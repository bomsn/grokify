#!/usr/bin/env node
// grokify-host - an MCP server that runs on the host machine.
//
// Why this exists: Claude Cowork executes shell commands inside a sandboxed
// Linux VM with a network allowlist it cannot reconfigure. The Grok CLI on the
// user's machine is not reachable from there, and neither is api.x.ai unless an
// organization owner opens the allowlist. Plugin MCP servers are the exception:
// they run natively on the device, outside that sandbox, with the host's own
// network and the user's own Grok login.
//
// So the sandbox builds the prompt and this process does the talking.
//
// Zero dependencies on purpose. The MCP stdio transport is newline-delimited
// JSON-RPC, which is small enough to implement directly, and requiring an npm
// install would defeat the point of a plugin that works the moment it is
// installed.

import { spawn } from 'node:child_process';
import { createInterface } from 'node:readline';
import { fileURLToPath } from 'node:url';
import { existsSync, mkdtempSync, readFileSync, writeFileSync, rmSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { tmpdir, platform, arch, hostname, homedir } from 'node:os';

const HERE = dirname(fileURLToPath(import.meta.url));
const PLUGIN_ROOT = process.env.CLAUDE_PLUGIN_ROOT || join(HERE, '..');
const SCRIPTS = join(PLUGIN_ROOT, 'skills', 'grokify', 'scripts');
const IS_WINDOWS = platform() === 'win32';
const PROTOCOL_FALLBACK = '2025-06-18';

// --- runner invocation -------------------------------------------------------

function runnerCommand(payloadPath, outPath, opts) {
  // Reuse the runner that already exists rather than reimplementing transport
  // selection, timeouts, marker extraction and encoding handling here. Those
  // took a long time to get right on Windows and there is no reason to have two
  // versions of them.
  const args = [];
  if (IS_WINDOWS) {
    const script = join(SCRIPTS, 'grokify.ps1');
    // -ExecutionPolicy Bypass because a downloaded, unsigned .ps1 is blocked
    // under the default machine policy, and a plugin cannot sign itself.
    args.push('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', script,
              '-Payload', payloadPath, '-Out', outPath);
    if (opts.model)     args.push('-Model', opts.model);
    if (opts.transport) args.push('-Transport', opts.transport);
    if (opts.timeoutSec) args.push('-TimeoutSec', String(opts.timeoutSec));
    return { command: process.env.GROKIFY_POWERSHELL || 'powershell.exe', args };
  }
  const script = join(SCRIPTS, 'grokify.sh');
  args.push(script, '--payload', payloadPath, '--out', outPath);
  if (opts.model)      args.push('--model', opts.model);
  if (opts.transport)  args.push('--transport', opts.transport);
  if (opts.timeoutSec) args.push('--timeout', String(opts.timeoutSec));
  return { command: process.env.GROKIFY_BASH || 'bash', args };
}

function runRunner(payloadText, opts) {
  return new Promise((resolve) => {
    const dir = mkdtempSync(join(tmpdir(), 'grokify-host-'));
    const payloadPath = join(dir, 'payload.md');
    const outPath = join(dir, 'result.txt');
    // Write UTF-8 without a BOM. A BOM at the top of the payload becomes the
    // first character of the prompt and shows up in the rewrite.
    writeFileSync(payloadPath, payloadText, { encoding: 'utf8' });

    const { command, args } = runnerCommand(payloadPath, outPath, opts);
    // The runner reports its transport, payload size and timeout on stderr and
    // writes only the rewrite to --out, so both streams are diagnostics here.
    let log = '';
    let child;
    try {
      child = spawn(command, args, {
        stdio: ['ignore', 'pipe', 'pipe'],
        windowsHide: true,
      });
    } catch (err) {
      rmSync(dir, { recursive: true, force: true });
      return resolve({ ok: false, error: `could not start ${command}: ${err.message}` });
    }

    child.stdout.on('data', (d) => { log += d.toString('utf8'); });
    child.stderr.on('data', (d) => { log += d.toString('utf8'); });

    child.on('error', (err) => {
      rmSync(dir, { recursive: true, force: true });
      resolve({ ok: false, error: `could not start ${command}: ${err.message}` });
    });

    child.on('close', (code) => {
      let text = '';
      try { if (existsSync(outPath)) text = readFileSync(outPath, 'utf8'); } catch {}
      rmSync(dir, { recursive: true, force: true });
      if (code === 0 && text.trim()) return resolve({ ok: true, text, log: log.trim() });
      resolve({
        ok: false,
        error: text.trim()
          ? `runner exited ${code} but produced output`
          : `runner exited ${code}`,
        log: log.trim(),
        text,
      });
    });
  });
}

// --- diagnostics -------------------------------------------------------------

function which(bin) {
  const exts = IS_WINDOWS ? ['.cmd', '.exe', '.bat', ''] : [''];
  const sep = IS_WINDOWS ? ';' : ':';
  const dirs = (process.env.PATH || '').split(sep).filter(Boolean);
  const extra = IS_WINDOWS
    ? [join(process.env.APPDATA || '', 'npm'),
       join(process.env.LOCALAPPDATA || '', 'Programs', 'grok'),
       join(homedir(), '.grok', 'bin')]
    : [join(homedir(), '.grok', 'bin'), join(homedir(), '.local', 'bin'),
       join(homedir(), '.bun', 'bin'), '/usr/local/bin', '/opt/homebrew/bin'];
  for (const d of [...dirs, ...extra]) {
    for (const ext of exts) {
      const p = join(d, bin + ext);
      try { if (existsSync(p)) return p; } catch {}
    }
  }
  return null;
}

function probeHost(host) {
  return new Promise((resolve) => {
    const req = { hostname: host, path: '/v1/models', method: 'GET', timeout: 12000 };
    import('node:https').then(({ request }) => {
      const r = request(req, (res) => {
        res.resume();
        // 401 is the good answer here: it proves the host answered. Only a
        // failure to connect at all means something is blocking the route.
        resolve(res.statusCode === 200 ? 'reachable' : `reachable (http ${res.statusCode})`);
      });
      r.on('timeout', () => { r.destroy(); resolve('no answer within 12s'); });
      r.on('error', (e) => {
        const code = e.code || e.message;
        // A substituted certificate means an intercepting proxy answered, which
        // is what a sandbox does and what the host does not. Worth naming,
        // because it says which side of the boundary this process is on.
        if (code === 'SELF_SIGNED_CERT_IN_CHAIN' || code === 'UNABLE_TO_VERIFY_LEAF_SIGNATURE') {
          return resolve(`intercepted by a TLS proxy (${code}) - this process is inside a sandbox, not on the host`);
        }
        if (code === 'ENOTFOUND' || code === 'EAI_AGAIN') {
          return resolve(`DNS did not resolve (${code}) - a sandbox allowlist is the usual cause`);
        }
        resolve(`unreachable (${code})`);
      });
      r.end();
    }).catch((e) => resolve(`unreachable (${e.message})`));
  });
}

async function envReport() {
  const grok = which('grok');
  const keyFiles = [process.env.GROKIFY_API_KEY_FILE, join(homedir(), '.grokify', 'api-key')]
    .filter(Boolean).filter((f) => { try { return existsSync(f); } catch { return false; } });
  return {
    running_on: {
      platform: platform(),
      arch: arch(),
      hostname: hostname(),
      node: process.version,
      home: homedir(),
    },
    // The line that answers the only question that matters: is this process on
    // the user's machine, or inside the sandbox?
    verdict: platform() === 'win32' || platform() === 'darwin'
      ? 'host machine (outside any Linux sandbox)'
      : 'linux - confirm hostname and home against the user\'s machine',
    plugin_root: PLUGIN_ROOT,
    runner_present: existsSync(join(SCRIPTS, IS_WINDOWS ? 'grokify.ps1' : 'grokify.sh')),
    grok_cli: grok || 'not found',
    api_key: (process.env.XAI_API_KEY || process.env.GROKIFY_API_KEY) ? 'set in environment'
             : keyFiles.length ? `file: ${keyFiles[0]}` : 'not set',
    api_x_ai: await probeHost('api.x.ai'),
  };
}

// --- MCP plumbing ------------------------------------------------------------

const TOOLS = [
  {
    name: 'grokify_env',
    description:
      'Report where this server is running and what routes to Grok are available from there: '
      + 'platform and hostname, whether the Grok CLI was found, whether an API key is set, and '
      + 'whether api.x.ai answers. Call this first when a Grokify run fails, to tell a missing '
      + 'CLI apart from a blocked network.',
    inputSchema: { type: 'object', properties: {}, additionalProperties: false },
  },
  {
    name: 'grokify_rewrite',
    description:
      'Send a fully built Grokify payload to Grok from the host machine and return the rewritten '
      + 'text verbatim. Takes the complete payload, already assembled from the Grokify skill\'s '
      + 'payload template - this tool does not build prompts. Runs outside any sandbox, so it '
      + 'reaches a locally installed Grok CLI and the host network.',
    inputSchema: {
      type: 'object',
      properties: {
        payload: { type: 'string', description: 'The complete assembled payload sent to Grok.' },
        model: { type: 'string', description: 'Optional model override, e.g. grok-4.6.' },
        transport: {
          type: 'string',
          enum: ['auto', 'api', 'inline', 'rules', 'file'],
          description: 'Optional transport override. Leave unset unless diagnosing.',
        },
        timeout_sec: { type: 'integer', description: 'Optional ceiling in seconds.' },
      },
      required: ['payload'],
      additionalProperties: false,
    },
  },
];

function send(msg) { process.stdout.write(JSON.stringify(msg) + '\n'); }
function reply(id, result) { send({ jsonrpc: '2.0', id, result }); }
function fail(id, code, message) { send({ jsonrpc: '2.0', id, error: { code, message } }); }
function textResult(id, text, isError = false) {
  reply(id, { content: [{ type: 'text', text }], isError });
}

async function handle(msg) {
  const { id, method, params } = msg;
  // Notifications carry no id and expect no response.
  if (id === undefined || id === null) return;

  switch (method) {
    case 'initialize':
      return reply(id, {
        protocolVersion: params?.protocolVersion || PROTOCOL_FALLBACK,
        capabilities: { tools: {} },
        serverInfo: { name: 'grokify-host', version: '1.0.0' },
      });

    case 'ping':
      return reply(id, {});

    case 'tools/list':
      return reply(id, { tools: TOOLS });

    case 'tools/call': {
      const name = params?.name;
      const args = params?.arguments || {};

      if (name === 'grokify_env') {
        try {
          return textResult(id, JSON.stringify(await envReport(), null, 2));
        } catch (err) {
          return textResult(id, `grokify_env failed: ${err.message}`, true);
        }
      }

      if (name === 'grokify_rewrite') {
        if (typeof args.payload !== 'string' || !args.payload.trim()) {
          return textResult(id, 'payload is required and must be a non-empty string', true);
        }
        const res = await runRunner(args.payload, {
          model: args.model,
          transport: args.transport,
          timeoutSec: args.timeout_sec,
        });
        if (res.ok) return textResult(id, res.text);
        const detail = res.log ? `\n\n${res.log}` : '';
        return textResult(id, `${res.error}${detail}`, true);
      }

      return fail(id, -32602, `unknown tool: ${name}`);
    }

    default:
      return fail(id, -32601, `unknown method: ${method}`);
  }
}

const rl = createInterface({ input: process.stdin });
rl.on('line', (line) => {
  const trimmed = line.trim();
  if (!trimmed) return;
  let msg;
  try { msg = JSON.parse(trimmed); } catch { return; }
  // A batch is legal JSON-RPC; handle each member independently.
  const batch = Array.isArray(msg) ? msg : [msg];
  for (const m of batch) {
    Promise.resolve(handle(m)).catch((err) => {
      if (m && m.id !== undefined && m.id !== null) fail(m.id, -32603, err.message);
    });
  }
});
rl.on('close', () => process.exit(0));

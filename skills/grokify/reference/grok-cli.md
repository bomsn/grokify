# Reaching Grok

Grokify calls one model: Grok. Not Gemini, not Codex, not Claude. The
whole point is routing writing to the model that writes like a person, so
the tool has exactly one engine and no menu.

There are two ways to reach it, and the runner takes whichever is
available.

## The host bridge

The plugin ships an MCP server, `servers/grokify-host.mjs`, which runs on the
machine rather than in a sandbox. Installing the plugin is the whole setup: the
server starts with it, finds the Grok CLI already installed and logged in
there, and exposes a tool ending in `grokify_rewrite`.

It runs on the device even when the session itself is executing in the cloud,
which is what makes Grokify work in Cowork at all. The tool then arrives
namespaced by the host, along the lines of
`mcp__remote-devices__plugin_grokify_grokify-host__grokify_rewrite`, so match
on the suffix rather than the bare name.

The bridge is asynchronous. A tool call has far less time than a CLI rewrite
needs, and that ceiling belongs to the transport, not to Grokify, so
`grokify_rewrite` starts the work and returns the text only if it finishes
quickly. Otherwise it returns a `job_id`, and `grokify_result` collects it.
Both calls wait up to 40 seconds by default, capped at 50, so a ten-minute
rewrite costs a handful of calls rather than constant polling. A returned
`job_id` is progress, not an error.

A finished job is dropped once collected, so collecting the same `job_id`
twice reports that it is gone. Jobs live in the server process and do not
survive a restart of the desktop app.

The server needs Node 18 or later on PATH. It also takes a few seconds to come
up after an install, so a tool that is missing immediately afterwards is
usually just early. `grokify_env` reports where it is running, whether it found
the CLI, and whether the network answered.

## The CLI

Everything below is the xAI Grok CLI's documented interface. Where a
detail matters, it is worth reading the source:
[headless and scripting](https://docs.x.ai/build/cli/headless-scripting),
[CLI reference](https://docs.x.ai/build/cli/reference),
[permissions](https://docs.x.ai/build/features/permissions).

## Install and sign in

```bash
curl -fsSL https://x.ai/cli/install.sh | bash          # Linux, macOS, WSL
```

```powershell
irm https://x.ai/cli/install.ps1 | iex                 # Windows
```

Then authenticate once:

```bash
grok login
grok login --device-auth      # headless or remote box, no browser
```

`grok version` prints the build. Grokify's `--check` calls that, not
`--version`.

## The one rule that governs everything else

**The prompt goes through `-p`, always.** `-p, --single <PROMPT>` is the
documented headless entry point, and it is the only one. Run `grok`
without it and you get the interactive interface, which under a
redirected stdout renders nowhere and waits for a keystroke that never
comes. There is no documented way to pipe a prompt in on stdin.

That is worth stating plainly because it is the failure everyone hits
once: a run that prints nothing and never returns is almost always a
`grok` invocation that never received `-p`.

## Flags Grokify sends on every run

```
--output-format plain     the answer, not a transcript
--no-alt-screen           never take over the terminal
--no-auto-update          no background update check mid-automation
```

`--no-alt-screen` is the one that matters most. Without it the CLI is
entitled to switch to the alternate screen buffer, and a full-screen
interface drawn into a pipe is a hang with extra steps.

Override the set with `GROKIFY_BASE_ARGS` if your build wants something
different.

## Flags the file transport adds

```
--always-approve          answer the tool approval nobody can see
--max-turns 6             bound the agent loop
--cwd <payload directory> keep the session scoped to one folder
```

The file transport is the only path that uses a tool at all, so it is the
only one that can meet an approval prompt. In headless mode that prompt
goes to a redirected stdout and waits on a closed stdin, so it has to be
answered in advance. `--always-approve` does that; the prompt itself asks
for one read and nothing else, and `--max-turns` caps the loop if the
model decides otherwise.

Those flags apply to the file transport only. Neither inline nor split
uses a tool, so neither can meet an approval prompt.

Override with `GROKIFY_FILE_ARGS`. To narrow it further, the CLI also
takes `--allow` and `--deny` rules per invocation; put them in
`GROKIFY_EXTRA_ARGS`.

## When a build rejects a flag

Flags come and go between releases. If `grok` exits complaining about an
unexpected or unknown argument, the runner retries once with nothing but
`-p` and the model flag, and says so on stderr. A missing flag degrades
the run; it does not fail it.

## How the payload reaches grok

A command line is the wrong place to put a brief, and the ceiling is far
lower than it looks. `Process.Start` documents a `Win32Exception` when
"the sum of the length of the arguments and the length of the full path to
the process exceeds 2080", surfacing as "The data area passed to a system
call is too small" or, more often, **"Access is denied"**. Two thousand
and eighty characters, not the 32767 that `CreateProcess` itself allows.
An 18 KB argument does not get truncated or refused on length; it comes
back as a permissions error, which sends you looking in the wrong place.

So the brief does not travel as an argument.

**rules** writes the whole brief to `AGENTS.md` in a scratch directory and
points `--cwd` at it. Project rules are loaded from disk for every session
in that directory, in full, with no size cap and no tool call, so the
command line carries only the task line: about 470 characters whatever the
brief weighs. This is the default for anything longer than a short message.

It is also the structure a single `-p` string cannot express. Role,
methodology, constraints, output format and the material all arrive as
system context; the task arrives as the prompt that follows them. Every
guide to prompt structure asks for that split, and this is the one way the
CLI offers it.

The brief ends where `<task>` begins, which is the line the runner splits
on. A payload without a `<task>` line cannot use this path.

**inline** passes the whole payload as one `-p` argument. Kept for short
payloads, where writing a file to save a few hundred characters is not
worth it. The PowerShell runner budgets its ceiling from 2080 minus the
binary path and the flags, and prints the number in `--check`; the bash
runner uses a flat 8000, well inside what it could pass, so that both
runners take the same path for anything of real size.

**file** hands grok a short prompt naming one file to read, and asks it to
reply with the rewritten text. It costs a tool call and a round trip
before any writing starts, which on a long document is minutes. Last
resort, for a payload with no `<task>` line to split on.

### Verifying the brief arrived

The rules path has one failure mode worth guarding: a build that does not
load project rules would rewrite from the task line alone, which reads as
a bad rewrite rather than a broken run.

The check that catches it is the output markers. The brief asks for them,
so a reply without them almost always means the brief never arrived, and
the runner says so. It is silent when the run is fine.

`GROKIFY_VERIFY_RULES=1` adds a preflight that runs `grok inspect` in the
scratch directory before the model call. It is off by default because not
every build's `inspect` reports rules for a directory it was pointed at,
so it warns on runs that are working perfectly well.


## Which runner for which shell

| You are in | Run | Why |
|---|---|---|
| Linux, macOS | `grokify.sh` | Native. |
| WSL | `grokify.sh` | Same as Linux. Install grok inside WSL, not on the Windows side. |
| Git Bash, MSYS, Cygwin | `grokify.sh` | Finds the extensionless npm launcher. |
| Windows PowerShell, pwsh | `grokify.ps1` | Resolves the `.cmd` shim and budgets the 2080-character ceiling. |
| Windows cmd | `grokify.ps1` via `powershell -File` | cmd has no runner of its own. |

Both runners take the same payload, apply the same cleanup, and return
the same exit codes. Nothing about a rewrite changes with the platform.

## When grok runs in your terminal but not here

This is the most common failure, and it is almost never a missing
install. The shell that launched the script inherited a different PATH
than the one you type in. On Windows this is routine: `%APPDATA%\npm` is
on the interactive PATH and absent nearly everywhere else.

Grokify checks PATH, then probes:

```
$HOME/.grok/bin        $HOME/.local/bin      $HOME/.bun/bin
$HOME/.npm-global/bin  $HOME/bin             %APPDATA%\npm
%LOCALAPPDATA%\Programs\grok                 /usr/local/bin
/opt/homebrew/bin
```

If it still comes up empty, get the real path from the terminal where
grok works:

```bash
which grok        # Linux, macOS, Git Bash, WSL
where.exe grok    # Windows cmd or PowerShell
```

Then pass it per run, or set it once in your shell profile:

```bash
export GROKIFY_BIN=/full/path/to/grok
```

```powershell
$env:GROKIFY_BIN = 'C:\Users\you\.grok\bin\grok.exe'
```

### The Windows launcher wrinkle

An npm install puts three launchers side by side: `grok` (a shell
script), `grok.cmd`, and `grok.ps1`. Bash can only execute the
extensionless one; cmd and PowerShell want the `.cmd`. That is the entire
reason there are two runners. The x.ai installer drops a real
`grok.exe` in `~/.grok/bin`, which both runners handle.

## Checking the wiring

```bash
bash scripts/grokify.sh --check
```

```powershell
.\scripts\grokify.ps1 -Check
```

Reports the platform, the resolved binary, `grok version`, the flag sets,
and the inline ceiling. The version probe runs with stdin closed on a
ten-second leash, so a CLI that would rather open its interface than
answer drops out instead of hanging.

Every run also prints one line to stderr before it starts:

```
grokify: transport=file payload=36989 chars binary=/home/you/.grok/bin/grok
```

It costs nothing and it is usually the whole diagnosis.

## Environment variables

| Variable | Effect |
|---|---|
| `GROKIFY_BIN` | Binary name or full path. Overrides discovery. |
| `GROKIFY_MODEL` | Default model, passed to `grok -m`. |
| `GROKIFY_TIMEOUT` | Seconds before a run is killed. Default scales with the payload: 300 plus one second per 50 characters, capped at 1800. |
| `GROKIFY_MAX_INLINE_CHARS` | Override the inline ceiling. |
| `GROKIFY_EFFORT` | Default reasoning effort, passed to `grok --effort`. |
| `GROKIFY_VERIFY_RULES` | Set to 1 to preflight project-rule discovery with `inspect`. Off by default: not every build's `inspect` accepts `--cwd`, so it reports nothing on a run that is working. |
| `GROKIFY_BASE_ARGS` | Replace the always-on automation flags. |
| `GROKIFY_FILE_ARGS` | Replace the file-transport flags. |
| `GROKIFY_EXTRA_ARGS` | Extra flags appended to every run, word-split. |

`GROKIFY_EXTRA_ARGS` is where per-build extras go: `--effort`, `--allow`
and `--deny` rules, `--sandbox`, `--disable-web-search`. Grokify sends
none of those by default, because a flag one release accepts is a fatal
error in another.

### If a rewrite is slow

Once the transport is `rules` or `inline`, nothing is left but generation,
and generation costs what it writes. A long document takes minutes and
there is no transport trick left to play.

Both levers are account-specific, which is why neither has a default here.
The vendor's own guidance is to discover them rather than look them up:
"Available effort levels vary by model. Check with `grok models` or
`/effort`."

`--check` runs `grok models` for you and prints what this account can
reach. Then:

```bash
grokify.sh --model <name> --payload p.md --out o.txt
grokify.sh --effort <level> --payload p.md --out o.txt
```

`GROKIFY_MODEL` and `GROKIFY_EFFORT` set either one for a whole shell.
A rewrite has little use for reasoning effort, so a lower level is usually
free speed, but only your account knows which levels exist.

Expect minutes for a long document either way. Once the transport is
`rules`, generation is all that is left, and generation costs what it
writes. Run-to-run variance is real: the same brief has taken four minutes
and ten on the same machine.

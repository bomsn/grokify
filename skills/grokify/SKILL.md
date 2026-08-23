---
name: grokify
description: Hand a draft to the Grok CLI for a rewrite and return Grok's output verbatim. Use when the user types /grokify, or asks to rewrite, rephrase, tighten, humanize, de-AI, or "say that in normal English" - for a blog post, email, client message, proposal, documentation page, social post, report, commit message, or the previous reply. Carries the whole brief across - the original request, any skills that governed the draft, reference files and folders, audience, tone, length, and language.
allowed-tools: Bash(${CLAUDE_SKILL_DIR}/scripts/grokify.sh *)
---

# Grokify

Grokify moves a finished draft out of this model and into the Grok CLI,
which returns the version that actually gets sent. Grok receives the same
brief the draft was written against - the original request, the skills
that governed it, the reference files, the audience - so it rewrites with
full context instead of guessing from prose alone.

Grok's output is printed verbatim. Editing it here reintroduces the exact
voice the user is paying Grok to remove.

## Requirements

A route to Grok. There are three, and the first one that exists wins.

**The host bridge.** Any available tool whose name ends in
`grokify_rewrite` means it is already there and nothing else is needed -
it runs on the user's machine and uses the Grok CLI already installed and
logged in there. Step 5 covers how to find and call it. Everything below
is for a session with no bridge, or a machine with no CLI.

The bridge takes a moment to start after the plugin is installed. If the
tool is not there yet, it will be shortly; nothing needs configuring.

**An API key.** `XAI_API_KEY` in the environment and nothing else. No
install, no login, no command-line limits, and it is the faster route: a
rewrite is one completion, where an agent CLI spends a session start-up, a
tool loop and a transcript on top of it.

A sandbox usually has no way to keep an exported variable between
commands, so write the key to a file instead and the runner will find it:
`$GROKIFY_API_KEY_FILE`, then `~/.grokify/api-key`, then `./.grokify-key`.
A key pasted into a chat also lives in that transcript; a file is the safer
place for it.

A sandbox with no host bridge also has to be allowed to reach `api.x.ai`.
If the request never connects, its egress allowlist does not include that
host; see `reference/troubleshooting.md`. Nothing in the skill can work
around a blocked host, so say so rather than retrying.

**Or the `grok` binary**, on PATH and authenticated. Either CLI works:

- xAI Grok CLI: `curl -fsSL https://x.ai/cli/install.sh | bash`
  (Windows: `irm https://x.ai/cli/install.ps1 | iex`)
- superagent-ai/grok-cli: `curl -fsSL https://raw.githubusercontent.com/superagent-ai/grok-cli/main/install.sh | bash`

Both expose `grok -p "<prompt>"`, the only documented headless entry
point, and the only CLI interface Grokify uses.

Grok is the only model Grokify ever calls, by either route. Never
substitute another CLI, and never fall back to rewriting the draft here.

Verify before the first run of a session:

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/grokify.sh" --check
```

This reports the resolved binary path, so a PATH problem shows up as a
path problem rather than as a failed rewrite. When the binary is not
found, do not guess a path and do not silently fall back to rewriting the
draft here. Read the script's error, which names every directory it
searched, and follow the two fixes it prints. The user knows where their
CLI is; ask them for `which grok` or `where.exe grok` output rather than
hunting.

## Invocation

```
/grokify [mode] [target] [instruction] [flags]
```

Every argument is optional. `/grokify` on its own rewrites the previous
reply in auto mode.

| Argument | Meaning |
|---|---|
| `mode` | One of the modes in `reference/modes.md`. Defaults to `auto`. |
| `target` | A file path, or quoted text. Defaults to the previous output. |
| `instruction` | Free-form text: `"warmer, and cut the last paragraph"`. |

| Flag | Effect |
|---|---|
| `--skill <ref>` | Include a skill's instructions as reference material. Repeatable. |
| `--context <path>` | Include a file or folder as reference material. Repeatable. |
| `--brief <text>` | The original request the draft answers, when it is not in this conversation. |
| `--audience <text>` | Who reads the result. |
| `--tone <text>` | Free-form tone direction that overrides the mode's default. |
| `--length keep\|tighter\|shorter\|longer\|<n> words` | Length target. Defaults to `keep`. |
| `--lang <language>` | Output language. Defaults to the draft's language. |
| `--model <name>` | Passed to `grok -m`. |
| `--effort <level>` | Passed to `grok --effort`. Levels vary by model; `--check` lists what the account reaches. |
| `--transport api` | Force the API route even where a binary exists. Faster, and immune to command-line limits. |
| `--bin <path>` | Full path to the grok binary, when PATH does not have it. |
| `--out <path>` | Also write the result to this file. |
| `--diff` | Print a short list of what changed after the result. |
| `--dry-run` | Build the payload, print its path, call nothing. |
| `--keep` | Keep the temp directory for inspection. |
| `--raw` | Skip output cleanup: print Grok's stdout byte for byte. |
| `--no-footer` | Omit the one-line footer. |

Grokify holds no state. It reads no history, writes no config, and caches
nothing. Every run resolves its inputs from the arguments and the current
conversation, then deletes its temp directory.

## Step 1 - Resolve the target

Resolve in this order and stop at the first match:

1. A quoted string in the arguments -> that text is the draft.
2. A path in the arguments -> read that file in full. For `.md`, `.mdx`,
   or `.html` with front matter, keep the front matter out of the draft
   and restore it around the result.
3. A file this session created or edited in the immediately preceding
   turn -> that file.
4. The previous assistant message in this conversation -> its text.

When rule 3 and rule 4 both apply, take the file: it is the deliverable.

Strip nothing from the draft before sending. Tool logs, task lists, and
progress narration are not part of a deliverable and never belonged in
the draft in the first place - if the previous message contains them,
send only the prose the user would keep.

## Step 2 - Resolve the brief

The rewrite is only as good as what Grok knows about the job. Fill these
from the conversation, from flags, or leave them out. Never invent them.

- **Original request** - the user's own words that produced the draft.
  Quote them. This is the single highest-value field in the payload.
- **Audience and channel** - who reads it, and where it lands: a company
  blog, a cold email, a reply to an angry client, a README, a Slack
  message, a pull request description, a landing page.
- **Medium** - what it looks like on screen, which is a separate question
  from how it sounds: a chat thread, an email, a message, a document, a
  post, a page. The same register takes a different shape in each, and
  the payload has a field for both.
- **Constraints already agreed** - word count, required sections, a CTA,
  a link that has to appear, a legal line, a brand term.
- **What the user disliked** - if this is a second pass, the complaint is
  the most useful sentence in the payload. Quote it.

If the conversation carries none of this and the draft alone is
ambiguous, ask one question, not three. Otherwise proceed.

## Step 3 - Resolve reference material

Reference material is what makes Grokify better than a generic rewrite.
Resolution rules are in `reference/context-resolution.md`. In short:

- `--skill <ref>` resolves plugin-qualified (`content-writing:blog-writing`)
  or bare (`blog-writing`) names against the project and user skill
  directories, and includes `SKILL.md` plus the reference files it points
  at, within budget.
- Any skill that governed the original draft is included automatically,
  whether or not the user repeats it in the flags. If the draft was
  written under `/content-writing:blog-writing`, Grok gets that skill.
- `--context <path>` includes a file, or the readable text files in a
  folder, capped and listed by name so nothing is silently dropped.
- An optional project style file (`.grokify.md`, `GROKIFY.md`, or
  `.claude/grokify.md`) is included when it exists. Nothing is inferred
  when it does not.
- Samples of the author's own writing outrank every style rule in the
  payload. When the conversation, the repo, or a `--context` path holds
  something the same author or publication wrote before, include one or
  two as `type="author-sample"`. A paragraph that demonstrates the voice
  beats a paragraph that describes it.

Never send credentials, `.env` files, key material, or customer personal
data as reference material. Exclude them even when a `--context` folder
contains them, and say which files were excluded.

## Step 4 - Build the payload

Fill `reference/payload-template.md` exactly. The template's ordering is
load-bearing: role and rules first, long reference material next, the
draft after that, and the task instruction last. Do not reorder it, and
do not add sections it does not define.

The rule blocks (`<preservation>`, `<voice>`, `<cuts>`, `<shape>`,
`<output_format>`) go through verbatim. They are the product. Trim
reference material when the budget is tight; never trim a rule block.

`Register:` takes the one mode contract that applies, as text.
`reference/modes.md` itself never goes into the payload.

Write the filled payload to a temp file:

```bash
PAYLOAD="$(mktemp -d)/payload.md"
```

Omit any block whose content is empty. An empty `<reference_material>`
tag teaches the model that reference material is optional and unimportant.

## Step 5 - Run Grok

Two ways to reach Grok. Check for the first before falling back to the
second; they take the same payload and produce the same result.

**A host tool, if one is present.** Look for a tool whose name ends in
`grokify_rewrite`. It arrives under different prefixes depending on how the
bridge was registered - bare as `grokify_rewrite` from the plugin itself,
or namespaced through the desktop bridge, as in
`mcp__remote-devices__grokify-host__grokify_rewrite`. Match on the suffix,
not on an exact string, and do not conclude the bridge is absent because
the bare name is missing.

Call it with the assembled payload. It runs on the user's own machine,
outside any sandbox, so it reaches a Grok CLI installed there and the
machine's own network, and it needs nothing configured beyond the user's
existing Grok login. Prefer it whenever it exists, including on a local
machine, where it saves a shell round trip.

**It may answer with a job instead of the text, and that is success.** A
rewrite through the CLI is an agent session that routinely runs for
minutes, far longer than one tool call is allowed to take, so the tool
hands back JSON like this rather than holding the call open:

```json
{ "status": "running", "job_id": "job-1", "elapsed_sec": 40 }
```

Collect it with the matching `grokify_result`, passing that `job_id`. That
call waits too, so it returns the moment the rewrite lands rather than
reporting `running` straight back. If it does report `running` again, call
it again, and keep going until it returns the text. Ten minutes is a
normal rewrite. Do not treat a job as a failure, do not start a second
rewrite over the top of one still running, and do not fall back to
rewriting the draft here because the first call did not return text.

If either call returns an actual error, call the matching `grokify_env`
once and report what it says. That distinguishes a missing CLI from a
blocked network, which need opposite fixes, and reports which side of the
sandbox boundary the tool is running on.

**Otherwise the runner**, which is what a plain skill install has. The
runner lives beside this file, and the shell's working directory is the
user's project, not the skill directory. `${CLAUDE_SKILL_DIR}` expands to
this skill's own directory wherever it is installed, so use it rather than
guessing a path.

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/grokify.sh" --payload "$PAYLOAD" --out "$OUT"
```

On Windows PowerShell:

```powershell
& "${CLAUDE_SKILL_DIR}\scripts\grokify.ps1" -Payload $Payload -Out $Out
```

Pick the runner by shell, not by operating system: `grokify.sh` for Linux,
macOS, Git Bash, and WSL; `grokify.ps1` for Windows PowerShell. Both take
the same payload and return the same exit codes.

The runner picks its own transport: inline for a short payload, and
otherwise the brief travels as project rules in a scratch `AGENTS.md`
reached with `--cwd`, leaving only the task line on the command line. A
file handoff is the last resort. Command lines are capped far lower than
they look, at 2080 characters including the binary path, and the overflow
is reported as "Access is denied" rather than as a length error. It always sends the prompt through
`grok -p`, along with the flags a headless run needs (`--output-format
plain`, `--no-alt-screen`, `--no-auto-update`). Running grok without `-p`
starts its interactive interface and hangs. `reference/grok-cli.md` has
the details.

The timeout scales with the payload rather than sitting at a flat number,
because a rewrite costs what it writes. Long runs print their elapsed time
every thirty seconds, so a working run never looks like a stalled one.

Add `--model <name>` to select a model and `--timeout <seconds>` to
change the 300-second default.

With `--dry-run`, print the payload path and stop here.

## Step 6 - Return the result

Print the contents of `$OUT` verbatim, as the response body, with no
preamble and no closing commentary. Restore any front matter that was
held back in step 1. Write the file when `--out` was given.

Then one footer line, unless `--no-footer`:

```
grokify - <mode> - <target> - <model or "default"> - <n> words
```

With `--diff`, follow the footer with up to five bullets naming what
changed: structural moves, cut sections, reordered arguments. Only what
actually changed. When the result came back close to the draft, say that
in one line instead of finding five things to list. Do not critique the
result and do not offer to improve it further.

A result that comes back close to the draft is not a failed run. A draft
already written in a human register leaves Grok little to do, and
returning it nearly unchanged is the correct outcome. Do not re-run it to
manufacture a bigger difference.

Two things never happen: rewording Grok's output, and blending it with a
version written here. If the result is wrong, the fix is another run with
a better brief.

## Failure handling

The script exits non-zero and prints the real error. Surface it.

| Exit | Meaning | Response |
|---|---|---|
| 127 | No route to Grok | Neither a binary nor an API key. In a sandbox the answer is `XAI_API_KEY`, since no binary can be installed there. On a workstation, ask for `which grok` or `where.exe grok` output rather than guessing a path. |
| 126 | Rejected credentials | An API key the endpoint refused, or a CLI that has not signed in. The message says which. |
| 124 | Timed out | Suggest a longer `--timeout`, or a shorter draft. |
| 3 | Empty output | Re-run once with `--keep` and report the payload path. |
| other | Grok returned an error | Print stderr as-is. |

When grok cannot be reached, the run fails and the user sees why. Do not
route to another CLI, and do not quietly rewrite the draft here: a
rewriter that rewrites the text itself is the problem it exists to solve.
A rewrite produced here is offered only when the user asks for it, and
labelled as this model's own.

## Modes

`auto`, `plain`, `blog`, `email`, `client`, `chat`, `docs`, `technical`,
`social`, `exec`, `marketing`, `academic`, `tighten`, `translate`.

Each mode's style contract is in `reference/modes.md`. `auto` reads the
draft and picks one; when the draft fits none of them cleanly, `auto`
falls back to `plain` and says so in the footer.

A free-form instruction always wins over the mode's defaults. `/grokify
blog "make it angrier"` sends the blog contract with the instruction
layered on top.

## What Grok must not change

The preservation contract is the difference between a rewrite and a
rewrite that has to be checked line by line. It ships in every payload:
facts, numbers, dates, names, quotes, code, commands, file paths, error
strings, URLs, placeholders, front matter, and the draft's language all
survive byte for byte.

Three rules in it matter more than the rest, and they are the ones to
check when a result comes back wrong:

- **Certainty is content.** A measured fact stays flat, an inference
  stays an inference, a guess stays a guess. Nothing gains a hedge it did
  not have, and nothing loses one it earned.
- **Nothing new arrives.** No tool, vendor, statistic, example, or name
  that was not already in the draft or the reference material. An
  invented specific is worse than the vague sentence it replaced.
- **A factual error stays.** Grok rewrites, it does not correct. Note the
  error in the footer instead.

The full contract, along with the cut list and the shape rules, is in
`reference/payload-template.md`.

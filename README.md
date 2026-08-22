# Grokify

**Claude writes the draft. Grok writes the thing you actually send.**

A Claude Code skill (`/grokify`) that hands your draft to the Grok CLI and
prints what comes back, verbatim.

## Ask Claude for a client email

> I wanted to reach out and touch base regarding the timeline for the
> deliverables we discussed. Moving forward, I'm confident we can leverage
> our learnings to ensure a successful outcome.

Your client wanted to know if it ships Thursday.

Run `/grokify client`:

> Quick update on the timeline. The API work took two days longer than I
> estimated, so the handover moves to Thursday. Everything else is on
> track, and I'll send the staging link tomorrow morning.

## Ask Claude why a test is flaky

> Here's where it gets interesting: the caching layer isn't just a
> performance optimization, it's the load-bearing assumption of the entire
> request pipeline. Three things stood out during the investigation, and
> the third is the most instructive of all.

Run `/grokify technical`:

> The request pipeline assumes the cache is warm. When it isn't, every
> request hits the database directly, and `sync.py:212` opens a new
> connection per record. A 400-record batch opens 400 connections.

## The tell

Claude is a strong writer with one habit it cannot suppress: it writes
like it is presenting its own work at a conference. Every list has three
items. Every other sentence has an em dash. Nothing is ever just a thing;
it is always not just a thing, but a bigger thing. There is always a
kicker. The third point is always the most instructive.

You can prompt against this. You will lose. The tell is in the weights,
not the instructions, and the ban list gets longer every month while the
output finds new ways to sound like a keynote.

So Grokify stops arguing and hands the draft to a different model. Grok
writes like someone typing to a colleague, which is the entire product
requirement.

This is [nobuzz](https://github.com/adnanakil/nobuzz)'s idea. Same
diagnosis, different second opinion, and a lot more context in the
handoff.

## Why not just ask Claude to rewrite it

Because the model that wrote it is the model you are trying to route
around. Ask it to fix its own voice and it produces the same voice with
shorter sentences.

Grokify never lets Claude touch the result. Grok's output is printed byte
for byte. If Grok errors, you see the real error and the exit code, not a
quiet fallback where the buzzer debuzzes itself.

## The part that makes it work

A rewrite briefed with nothing is a paraphrase.

Grokify sends Grok the same context Claude had: your original request,
the skills that governed the draft, your reference files, the audience,
the channel, and whatever you said you hated about the last version.

If you wrote the draft under a skill, that skill goes along for the ride:

```
/content-writing:blog-writing   write the launch post for the new release
/grokify
```

Grok gets the blog-writing skill, its reference files, your original
request, and the draft. It rewrites the post against the same rules
Claude was working from, which is why you get back a correctly structured
launch post instead of a paraphrase with the headings knocked out.

Skills that chain resolve parent-first, so a brand skill layered on a
craft skill reaches Grok in the order it was meant to be read. Point
`--context` at a style guide, a folder of past posts, or a competitor
page and that goes in too.

Credentials, `.env` files, keys, and personal data are excluded from the
payload even when they sit inside a folder you passed, and the skill
tells you what it left out.

If anything the same author wrote before is reachable, that goes in too,
tagged as a sample. A style guide describes a voice; a paragraph the
person actually wrote demonstrates it, and demonstration wins every
time.

## Install

```bash
git clone https://github.com/bomsn/grokify
```

**Claude Code, everywhere.** Copy the skill folder into your personal
skills directory and it becomes `/grokify` in every project.

```bash
mkdir -p ~/.claude/skills
cp -r grokify/skills/grokify ~/.claude/skills/
```

```powershell
mkdir "$env:USERPROFILE\.claude\skills" -Force
Copy-Item grokify\skills\grokify "$env:USERPROFILE\.claude\skills\" -Recurse
```

You should land at `~/.claude/skills/grokify/SKILL.md`. Claude Code watches
that directory and picks the skill up mid-session; restart only if
`~/.claude/skills` did not exist when you started. `/skills` confirms it.

**Claude Code, one project.** Copy it to that repo's `.claude/skills/`
instead and commit it.

**As an uploadable archive.** Build one, then upload it in the Claude
desktop app or on claude.ai:

```bash
bash grokify/tools/package.sh          # or: pwsh grokify/tools/package.ps1
```

That writes `dist/grokify.zip` and an identical `dist/grokify.skill`, each
holding a single `grokify/` folder with `SKILL.md` at its top, which is the
layout the uploader and the Skills API accept. The packager also checks the
frontmatter against the six fields the spec allows, since an extra field
fails an upload outright rather than being ignored.

**Where it actually runs.** Grokify calls the `grok` binary on your
machine, so it works wherever your own shell does: Claude Code sessions
running locally, and desktop scheduled tasks, which also run locally. It
does not work in Cowork or cloud sessions. Those execute in a sandbox with
no access to your machine, so `grok` is not there and the run fails with
exit 127. Uploading the skill does not change that: the skill loads, the
binary still is not there.

You need [Claude Code](https://claude.com/claude-code) and the Grok CLI,
authenticated. Either one works:

- xAI: `curl -fsSL https://x.ai/cli/install.sh | bash`
  (Windows: `irm https://x.ai/cli/install.ps1 | iex`)
- superagent: `curl -fsSL https://raw.githubusercontent.com/superagent-ai/grok-cli/main/install.sh | bash`

Run `grok` once and sign in, or set `XAI_API_KEY`. Then check the wiring:

```bash
bash ~/.claude/skills/grokify/scripts/grokify.sh --check
```

## Usage

```
/grokify [mode] [target] [instruction] [flags]
```

Everything is optional. `/grokify` on its own rewrites Claude's last
reply.

```
/grokify
/grokify client
/grokify blog draft.md
/grokify email "shorter, and drop the apology"
/grokify --skill content-writing:blog-writing --context ./brand
/grokify translate --lang French
```

### Modes

| Mode | For |
|---|---|
| `auto` | Default. Reads the draft and picks one of the below. |
| `plain` | Chat replies, explanations, anything that got a TED talk. |
| `blog` | Articles, guides, newsletters, launch posts. |
| `email` | Outreach, follow-ups, internal mail. |
| `client` | Project updates, delays, scope, replies to complaints. |
| `chat` | Slack, Teams, PR comments, DMs. |
| `docs` | Setup guides, how-tos, knowledge base, API docs. |
| `technical` | Bug reports, RFCs, PR descriptions, commit messages. |
| `social` | X, LinkedIn, Reddit, Discord. |
| `exec` | Status summaries, escalations, stakeholder updates. |
| `marketing` | Landing pages, ads, product pages, campaigns. |
| `academic` | Papers, abstracts, reports for regulated readers. |
| `tighten` | A draft that is right but long. |
| `translate` | Localizing a finished piece, with `--lang`. |

Each mode is a written contract, not a pile of adjectives. "Professional
and engaging" tells a model nothing. "The ask in its own sentence,
unhedged" tells it what to write. They live in
[`skills/grokify/reference/modes.md`](skills/grokify/reference/modes.md), and adding
your own is one paragraph.

### Flags

| Flag | Effect |
|---|---|
| `--skill <ref>` | Include a skill's instructions as reference material. Repeatable. |
| `--context <path>` | Include a file or folder as reference material. Repeatable. |
| `--brief <text>` | The original request, when it is not in the conversation. |
| `--audience <text>` | Who reads the result. |
| `--tone <text>` | Overrides the mode's default register. |
| `--length` | `keep`, `tighter`, `shorter`, `longer`, or `<n> words`. |
| `--lang <language>` | Output language. Defaults to the draft's. |
| `--model <name>` | Passed to `grok -m`. |
| `--bin <path>` | Full path to the grok binary, when PATH does not have it. |
| `--out <path>` | Also write the result to a file. |
| `--diff` | List what changed after the result. |
| `--dry-run` | Build the payload, print its path, call nothing. |
| `--keep` | Keep the temp directory. |
| `--raw` | Print Grok's stdout byte for byte. |

## Runs where you run

| You are in | Run |
|---|---|
| Linux, macOS | `grokify.sh` |
| WSL | `grokify.sh` |
| Git Bash, MSYS, Cygwin | `grokify.sh` |
| Windows PowerShell, pwsh | `grokify.ps1` |

Same payload, same cleanup, same exit codes. Two runners exist for one
reason: npm installs `grok`, `grok.cmd`, and `grok.ps1` side by side, bash
can only execute the extensionless one, and PowerShell wants the `.cmd`.

## "But grok works in my terminal"

Then the shell Claude Code spawned has a different PATH than the one you
type in. On Windows this is routine: `%APPDATA%\npm` is on your
interactive PATH and missing almost everywhere else.

Grokify checks PATH, then probes `~/.grok/bin`, `~/.local/bin`,
`~/.bun/bin`, `~/.npm-global/bin`, `%APPDATA%\npm`,
`%LOCALAPPDATA%\Programs\grok`, `/usr/local/bin`, and `/opt/homebrew/bin`.
When it still comes up empty it tells you every directory it looked in,
which beats "command not found" by a mile.

The fix is one line:

```bash
export GROKIFY_BIN="$(which grok)"            # bash, zsh, Git Bash, WSL
```

```powershell
$env:GROKIFY_BIN = (Get-Command grok).Source  # PowerShell
```

Payloads too big for the command line route around it on their own, so a
200 KB brief works the same as a 2 KB one. The timeout scales with the payload
instead of sitting at a flat number, because a rewrite costs what it
writes. Every run goes through
`grok -p` with the flags a headless session needs, including
`--no-alt-screen`, without which the CLI can draw its full-screen
interface into a pipe and wait there forever.

Install, auth, transports, and the per-shell notes:
[`skills/grokify/reference/grok-cli.md`](skills/grokify/reference/grok-cli.md).

## What survives a rewrite

Facts, numbers, dates, names, quotes, code blocks, commands, file paths,
error strings, URLs, placeholders like `{{name}}` and `[CLIENT]`, front
matter, required legal lines, and the draft's language. All byte for byte.

Hedges survive too. "Likely" does not become "is". A confident sentence
that overstates a tentative finding is a worse failure than a clumsy one
that gets it right.

If the draft contains a factual error, Grok keeps it and the skill notes
it in the footer. Correcting content is a different job.

## What's actually in the prompt

The payload is not "rewrite this, but human." Four rule blocks go to Grok
verbatim on every run.

**Preservation** locks the facts: numbers, names, quotes, code, paths,
URLs, placeholders, front matter. Plus the two that usually get missed.
Certainty is content, so a measured fact stays flat and an inference
stays an inference. And nothing new arrives, because an invented specific
is worse than the vague sentence it replaced.

**Voice** is the register, four before-and-after transformations, and a
redirect table of about thirty entries. Not a ban list. Every row says
what to write instead, because telling a model to avoid a word is mostly
a way of putting the word in front of it. The block also covers the thing
most rewriters skip: rhythm is a stronger tell than vocabulary. Uniform
sentence length, uniform paragraphs, symmetrical list items and parallel
section openers are what a reader recognises before they can say why.

**Cuts** is the deletion list, and it does most of the work. Openers that
delay the start. Restating the reader's question back at them. "Great
question." Reasoning scaffolding. Labels telling the reader how to feel
about a fact. Answers to objections nobody raised. Selling a point the
evidence already made. Trailing summaries. Any paragraph that advances
nothing.

**Shape** is what it looks like on screen, which is a separate question
from how it sounds. A chat reply is paragraphs, no headings, broken at
thought boundaries. A message gets one bullet list only when the reader
has to answer several things separately. A document gets headings that
say something, not "Overview" and "Key Points".

One deliberate omission: nothing in the prompt tells Grok to sand the
text smooth. Perfect parallelism and immaculate consistency are tells of
their own, so comma splices, fragments, and sentences opening with "and"
are left where they are.

## How it works

No magic. The skill assembles one structured payload: the rule blocks
first, reference material next, the draft after that, and the task
instruction last. That ordering is deliberate. Long input placed above
the instruction improves compliance, and the last thing in a context
window is the thing a model acts on.

The payload goes to a temp file. `scripts/grokify.sh` (or `grokify.ps1`)
picks a transport. A brief does not go on the command line: `Process.Start`
throws at 2080 characters of arguments plus binary path, and reports it as
"Access is denied" rather than as anything about length. So the brief is
written to `AGENTS.md` in a scratch directory and reached with `--cwd`,
which the CLI loads from disk in full, with no size cap and no tool call.
The command line carries the task line and nothing else, about 470
characters whatever the brief weighs.

That also happens to be the structure a single `-p` string can't express:
rules and material as system context, the task as the prompt after them.
Short payloads still go inline, and a file handoff is the last resort.

Every run prints which transport it took and its time budget, and long
runs print elapsed time every thirty seconds. A four-minute rewrite that
prints nothing is indistinguishable from a hang, and that is not a thing
you should have to guess about. The result comes back, gets its blank lines trimmed and a
whole-output code fence unwrapped, and gets printed.

Nothing else is touched.

Grokify holds no state. No history, no config, no cache. Every run builds
its payload from the arguments and the current conversation, then deletes
its temp directory.

## Layout

```
skills/grokify/                     copy this to ~/.claude/skills/
├── SKILL.md                        the skill Claude reads
├── reference/
│   ├── payload-template.md         the prompt Grok receives, block by block
│   ├── modes.md                    the style contracts
│   ├── grok-cli.md                 install, PATH, transports, per-shell notes
│   ├── context-resolution.md       skill and file resolution, budgets, exclusions
│   └── troubleshooting.md
└── scripts/
    ├── grokify.sh                  transport, timeouts, exit codes
    └── grokify.ps1                 the same, for Windows PowerShell

tools/
├── package.sh                      builds dist/grokify.zip and dist/grokify.skill
└── package.ps1
```

## When it goes wrong

Exit codes are specific on purpose: `127` no binary, `126` not
authenticated, `124` timed out, `3` empty output. Start with
`grokify.sh --check`, then
[`skills/grokify/reference/troubleshooting.md`](skills/grokify/reference/troubleshooting.md).

If a rewrite comes back worse than the draft, the payload was thin. Add
`--brief`, add the governing skill, or just tell it what was wrong with
the last attempt in your own words. That last one beats every flag in
this file.

## License

MIT

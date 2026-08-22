# Troubleshooting

## Binary not found (exit 127), but it works in my terminal

This is the most common failure and it is almost never a missing install.
The shell Claude Code spawned inherited a different PATH than the one you
type in. On Windows this is routine: `%APPDATA%\npm` is on the
interactive PATH and absent nearly everywhere else.

The script already probes the usual install directories and prints every
one it searched. Start there:

```bash
bash "$SKILL_DIR/scripts/grokify.sh" --check
```

If it still misses, get the real path from the terminal where the CLI
works and hand it over:

```bash
which grok        # macOS, Linux, Git Bash, WSL
where.exe grok    # Windows cmd or PowerShell
```

```bash
export GROKIFY_BIN=/full/path/to/grok
```

Do not guess a path, and do not fall back to rewriting the draft in
Claude. Both hide the one fact worth knowing: which binary is actually
being called.

`reference/grok-cli.md` covers the Windows launcher wrinkle, where npm
installs `grok`, `grok.cmd`, and `grok.ps1` and only one of the three is
executable from your shell.

## Not authenticated (exit 126)

Run `grok` once interactively and sign in, or export `XAI_API_KEY` in the
environment the skill runs in. An API key set only in a GUI shell will not
be visible to a CLI session started before it was set.

## It hangs and never comes back

One cause dominates: `grok` was started without `-p`.

`-p, --single` is the CLI's only documented headless entry. Without it the
interactive interface starts, draws itself into a redirected stdout where
nothing appears, and waits for a keystroke. Nothing on your terminal, no
error, no exit. Both runners always pass `-p`, so if you see this with a
current copy of the skill, check whether something in `GROKIFY_BASE_ARGS`
or `GROKIFY_EXTRA_ARGS` is displacing it.

Three others, in order:

1. **The terminal takeover.** Without `--no-alt-screen` the CLI may switch
   to the alternate screen buffer, which is the same hang wearing a
   different hat. Grokify sends the flag on every run.
2. **A tool approval nobody can answer.** Only the file transport uses a
   tool. `--always-approve` answers in advance; it is in the default
   file-transport flag set. If you replaced `GROKIFY_FILE_ARGS`, put it
   back.
3. **This build does not support `-p` at all.** Confirm in your own
   terminal with `grok -p "Reply with the word OK and nothing else."` If
   that does not print OK and exit, the runner cannot drive it headlessly.

Stdin is not a way in. The CLI documents no piped-prompt mode, and an
earlier version of this skill offered one; it started the interactive
interface every time. That option is gone.

Nothing hangs indefinitely in any case: `--timeout` caps every run at 300
seconds by default, and the timeout kills the whole process tree, not just
the launcher shim.

## Timed out (exit 124)

The default is no longer a flat number: it starts at 300 seconds and adds
a second per 50 characters of payload, capped at 1800. A rewrite costs what
it writes, and the draft is the only proxy for that available before the
run starts. `--timeout` still overrides it.

Long runs print their elapsed time every thirty seconds. A run printing
those lines is working, not stuck.

If a rewrite genuinely times out, check the transport on the first stderr
line before raising the ceiling:

- `transport=file` is the slow path. It spends a tool call and a round
  trip before writing anything. It is only chosen when the payload has no
  `<task>` line to split on, which usually means a hand-built payload that
  departed from the template.
- `transport=rules` or `inline` and still timing out means the piece is
  genuinely long, or the model is slow. Raise `--timeout`, or pass a
  faster model with `--model`.

Trimming the brief helps in every case, and reference material is where the
slack is. The mode catalogue in particular never belongs in a payload; only
the one contract that applies does.

## Empty output (exit 3)

Three causes, in order of likelihood:

1. The file transport was used and Grok could not write to the temp
   directory. Re-run with `--transport inline` if the payload fits, or
   with `--keep` to inspect what happened.
2. Grok answered the payload conversationally instead of rewriting -
   usually because `<draft>` was empty or the payload was truncated.
   Check the payload with `--dry-run`.
3. Output cleanup removed everything, which happens when Grok returned
   only a code fence. Re-run with `--raw`.

## The output has a preamble like "Here is the rewritten version"

The output contract in the payload prevents this, and cleanup does not
strip it because stripping model chatter heuristically also strips real
first lines. If it happens repeatedly:

- Confirm the `<output_format>` block made it into the payload intact.
- Check that `<draft>` is not empty. A model with nothing to rewrite
  narrates instead.
- On the file transport, confirm the short handoff prompt is being sent -
  its instruction is stricter than the inline one and rarely leaks.

## The rewrite changed a number, a name, or a code block

The `<preservation>` block is the defense, and it belongs near the top of
the payload where it governs everything after it. Verify it was included
and not trimmed by the budget rules. Reference material is trimmable;
preservation rules are not.

If it persists on a specific draft, the draft is probably mixing prose and
code without fences. Fence the code before sending.

## The result is in the wrong language

The preservation contract keeps the draft's language unless
`<style_contract>` names another. A draft that mixes languages gives the
model no default to hold. Pass `--lang` explicitly.

## Grok's stdout contains a banner or telemetry line

Some CLI versions print a startup banner to stdout. Cleanup trims blank
lines and unwraps a whole-output code fence, and deliberately does nothing
else - guessing which lines are chrome is how a real first paragraph gets
deleted. If a banner appears, switch to `--transport file`, where the
result comes from a file and stdout is ignored entirely.

## The rewrite is worse than the draft

Almost always a thin payload. In order of impact:

1. `<original_request>` is missing. Add `--brief "<what you asked for>"`.
2. The governing skill was not included. Add `--skill <ref>`.
3. The mode is wrong. `auto` guessed `plain` for something that needed
   `client`.
4. No prior feedback. On a second pass, say what was wrong with the first
   in your own words - that sentence outperforms every flag.

## Reference material is being trimmed

`--dry-run` prints the payload path; check what actually made it in. Trim
the input instead: point `--context` at the two files that matter rather
than the folder that contains them.

## "Access is denied" from Process.Start

Not a permissions problem. `Process.Start` throws a `Win32Exception` when
the arguments plus the executable path exceed 2080 characters, and "Access
is denied" is one of the two messages it uses for that. A long brief passed
as an argument fails this way, which is why the brief travels as project
rules instead and the command line stays around 470 characters.

If you see it, something forced a long payload onto the command line:
`--transport inline` on a large brief, or a `GROKIFY_MAX_INLINE_CHARS`
raised past what the platform allows. Drop both and let the runner choose.

## Accented text, CJK, or box-drawing characters come back as mojibake

Something in the chain decoded UTF-8 as a legacy code page. Both runners
now pin UTF-8 at every boundary: the payload is read through .NET rather
than `Get-Content`, which defaults to the ANSI code page on Windows
PowerShell 5.1, and the engine's stdout is decoded as UTF-8 rather than as
the console code page.

If it reappears, find which end is at fault. `--dry-run` prints the payload
path: open it and check the characters are intact there. If they are, the
payload is fine and the corruption is on the way back; if they are not,
whatever built the payload wrote it in the wrong encoding.

A directory tree turning into `Ã”Ã¶Â£` is the signature.

## Windows: quotes come through mangled

They should not. The PowerShell runner builds the command line itself and
escapes it by the CommandLineToArgvW rules rather than relying on
PowerShell's native-command invocation, which is the part that is unsafe
on Windows PowerShell 5.1. Quotes, backslash runs, shell metacharacters
and UTF-8 all pass through byte for byte on both 5.1 and pwsh 7.

If output still reads like grok saw a corrupted prompt, check what the
payload contains with `--dry-run`, then reproduce with `--transport file`,
which puts nothing but a path on the command line. A difference between
the two points at the argument layer; no difference points at the payload.

The limit that does bind is length, and it is 2080 characters through
`Process.Start`, not the 32767 `CreateProcess` allows. That is what the
rules transport exists for.


## grok opened its REPL and hung

A CLI handed a flag it does not recognise can drop into interactive mode
and wait forever on a terminal that is not there. The `--check` version
probe runs with stdin closed on a ten-second leash for exactly this
reason.

If a rewrite hangs instead, check what your build accepts with
`grok --help`, and put the working set in `GROKIFY_BASE_ARGS`. Every run
is capped by `--timeout`, so a hang costs 300 seconds, not your
afternoon.

## grok rejected one of the automation flags

Flags move between releases. The runner retries once with nothing but
`-p` and the model flag, and says so on stderr, so a flag mismatch
degrades the run rather than failing it. To make the change permanent,
set `GROKIFY_BASE_ARGS` to the flags your build does accept.

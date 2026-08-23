#!/usr/bin/env bash
#
# grokify.sh - send a rewriting payload to the Grok CLI and capture the result.
#
# Runs on Linux, macOS, Git Bash, WSL, and anywhere else bash runs. Windows
# PowerShell has its own runner, grokify.ps1, in this directory.
#
# The skill builds the payload; this script owns the transport: finding the
# grok binary, driving it headlessly, enforcing a timeout, and turning failures
# into exit codes the caller can act on.
#
# Usage:
#   grokify.sh --payload FILE --out FILE [options]
#   grokify.sh --check
#
# Options:
#   --payload FILE      Payload built from reference/payload-template.md (required)
#   --out FILE          Where to write the rewritten text (required)
#   --model NAME        Model passed to grok as -m
#   --effort LEVEL      Reasoning effort, passed to grok as --effort. Accepted
#                       levels vary by model; `grok models` lists them.
#   --timeout SECONDS   Default 300
#   --bin PATH          grok binary name or full path, when PATH does not have it
#   --transport MODE    auto | inline | rules | file (default auto)
#   --raw               Skip output cleanup; keep grok's output byte for byte
#   --keep              Keep the working directory and print its path
#   --check             Report binary, version, and platform defaults, then exit
#   -h, --help          This message
#
# Environment:
#   GROKIFY_BIN, GROKIFY_MODEL, GROKIFY_TIMEOUT, GROKIFY_MAX_INLINE_CHARS,
#   GROKIFY_BASE_ARGS, GROKIFY_FILE_ARGS, GROKIFY_EXTRA_ARGS
#
# Exit codes:
#   0    success
#   2    usage error
#   3    grok ran but produced no output
#   124  timed out
#   126  grok is installed but not authenticated
#   127  the grok binary was not found
#   1    grok returned an error (its stderr is on this script's stderr)

set -uo pipefail

E_USAGE=2
E_EMPTY=3
E_TIMEOUT=124
E_AUTH=126
E_NOBIN=127

PAYLOAD=""
OUT=""
MODEL="${GROKIFY_MODEL:-}"
EFFORT="${GROKIFY_EFFORT:-}"
TIMEOUT="${GROKIFY_TIMEOUT:-}"
BIN="${GROKIFY_BIN:-grok}"
TRANSPORT="auto"
RAW=0
KEEP=0
CHECK=0

die() { printf 'grokify: %s\n' "$1" >&2; exit "${2:-1}"; }
usage() { sed -n '3,38p' "$0" | sed 's/^# \{0,1\}//'; }

# Flags every headless run needs. Without --no-alt-screen the CLI can take over
# the terminal with its full-screen interface, which under a redirected stdout
# renders nowhere and waits forever. --output-format plain keeps the answer free
# of transcript framing, and --no-auto-update stops a background update check
# from stalling an automated run.
BASE_ARGS_DEFAULT="--output-format plain --no-alt-screen --no-auto-update"
# The file transport is the only path that uses a tool, so it is the only one
# that can meet an approval prompt. --always-approve answers it; --max-turns
# bounds the loop if the model decides to keep going.
FILE_ARGS_DEFAULT="--always-approve --max-turns 6"

PLATFORM="$(uname -s 2>/dev/null || echo unknown)"
# bash execs directly and could pass far more than this, but a short message is
# the only case where inline is worth the difference. Everything longer takes
# the rules path, which has no ceiling anywhere and puts the brief where a
# brief belongs. One number keeps both runners behaving the same.
MAX_INLINE="${GROKIFY_MAX_INLINE_CHARS:-8000}"

while [ $# -gt 0 ]; do
  case "$1" in
    --payload)   PAYLOAD="${2:-}"; shift 2 ;;
    --out)       OUT="${2:-}"; shift 2 ;;
    --model)     MODEL="${2:-}"; shift 2 ;;
    --effort)    EFFORT="${2:-}"; shift 2 ;;
    --timeout)   TIMEOUT="${2:-}"; shift 2 ;;
    --bin)       BIN="${2:-}"; shift 2 ;;
    --transport) TRANSPORT="${2:-}"; shift 2 ;;
    --raw)       RAW=1; shift ;;
    --keep)      KEEP=1; shift ;;
    --check)     CHECK=1; shift ;;
    -h|--help)   usage; exit 0 ;;
    *)           die "unknown argument: $1" "$E_USAGE" ;;
  esac
done

case "$TRANSPORT" in auto|inline|rules|file) ;; *) die "--transport must be auto, inline, rules, or file" "$E_USAGE" ;; esac

# --- find grok --------------------------------------------------------------
#
# PATH first. When that misses, probe where the Grok CLI installers write. The
# npm global bin on Windows is the usual culprit: on the interactive PATH and
# absent nearly everywhere else. Only extensionless launchers are probed here,
# because bash cannot exec a .cmd or .ps1 shim; grokify.ps1 handles those.

find_grok() {
  local name="$1" candidate
  if command -v "$name" >/dev/null 2>&1; then command -v "$name"; return 0; fi
  case "$name" in */*)
    [ -x "$name" ] && { printf '%s' "$name"; return 0; }
    return 1 ;;
  esac
  for candidate in \
    "$HOME/.grok/bin/$name" \
    "$HOME/.local/bin/$name" \
    "$HOME/.bun/bin/$name" \
    "$HOME/.npm-global/bin/$name" \
    "$HOME/.nvm/versions/node/current/bin/$name" \
    "${APPDATA:-$HOME/AppData/Roaming}/npm/$name" \
    "$HOME/AppData/Roaming/npm/$name" \
    "$HOME/bin/$name" \
    "/usr/local/bin/$name" \
    "/opt/homebrew/bin/$name"
  do
    [ -x "$candidate" ] && { printf '%s' "$candidate"; return 0; }
  done
  return 1
}

BIN_PATH="$(find_grok "$BIN")" || BIN_PATH=""

if [ -z "$BIN_PATH" ]; then
  cat >&2 <<MISSING
grokify: '$BIN' was not found on PATH, and is not in any of the directories the
Grok CLI normally installs to:

  \$HOME/.grok/bin         \$HOME/.local/bin       \$HOME/.bun/bin
  \$HOME/.npm-global/bin   \$APPDATA/npm          /usr/local/bin
  /opt/homebrew/bin

If grok runs in your normal terminal but not here, the shell that launched this
script has a different PATH. Get the real path from the terminal where it works:

  which grok        # Linux, macOS, Git Bash, WSL
  where.exe grok    # Windows cmd or PowerShell

Then pass it per run with --bin /full/path/to/grok, or set it once:

  export GROKIFY_BIN=/full/path/to/grok

Install the Grok CLI:
  curl -fsSL https://x.ai/cli/install.sh | bash
  Windows PowerShell: irm https://x.ai/cli/install.ps1 | iex
MISSING
  exit "$E_NOBIN"
fi

TIMEOUT_BIN=""
if command -v timeout >/dev/null 2>&1; then TIMEOUT_BIN="timeout"
elif command -v gtimeout >/dev/null 2>&1; then TIMEOUT_BIN="gtimeout"; fi

leash() {
  # Run a command with stdin closed and a short ceiling, so a CLI that would
  # rather open its interface than answer cannot sit there.
  if [ -n "$TIMEOUT_BIN" ]; then "$TIMEOUT_BIN" "$1" "${@:2}" </dev/null 2>&1
  else "${@:2}" </dev/null 2>&1; fi
}

if [ "$CHECK" -eq 1 ]; then
  VERSION="$(leash 10 "$BIN_PATH" version | head -n 1)"
  [ -n "$VERSION" ] || VERSION="$(leash 10 "$BIN_PATH" --version | head -n 1)"
  printf 'platform:     %s\n' "$PLATFORM"
  printf 'binary:       %s\n' "$BIN_PATH"
  printf 'version:      %s\n' "${VERSION:-unknown}"
  printf 'base flags:   %s\n' "${GROKIFY_BASE_ARGS:-$BASE_ARGS_DEFAULT}"
  printf 'file flags:   %s\n' "${GROKIFY_FILE_ARGS:-$FILE_ARGS_DEFAULT}"
  printf 'timeout:      %s\n' "${TIMEOUT_BIN:-none available, running unbounded}"
  printf 'inline limit: %s characters\n' "$MAX_INLINE"
  MODELS="$(leash 20 "$BIN_PATH" models | head -n 20)"
  if [ -n "$MODELS" ]; then
    printf 'models:\n%s\n' "$MODELS"
  else
    printf 'models:       could not list; run: %s models\n' "$BIN"
  fi
  exit 0
fi

[ -n "$PAYLOAD" ] || die "--payload is required" "$E_USAGE"
[ -n "$OUT" ]     || die "--out is required" "$E_USAGE"
[ -f "$PAYLOAD" ] || die "payload not found: $PAYLOAD" "$E_USAGE"

# --- working directory ------------------------------------------------------

WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/grokify.XXXXXX")" || die "could not create a temp directory"
ERRLOG="$WORKDIR/grok.stderr"
RESULT_ABS="$WORKDIR/result.txt"
# shellcheck disable=SC2317  # invoked by trap
cleanup() {
  if [ "$KEEP" -eq 1 ]; then
    printf 'grokify: kept %s\n' "$WORKDIR" >&2
  else
    rm -rf "$WORKDIR"
  fi
}
trap cleanup EXIT

mkdir -p "$(dirname "$OUT")" 2>/dev/null || true

PAYLOAD_DIR="$(cd "$(dirname "$PAYLOAD")" && pwd)"
PAYLOAD_ABS="$PAYLOAD_DIR/$(basename "$PAYLOAD")"
PAYLOAD_CHARS=$(wc -c < "$PAYLOAD" | tr -d '[:space:]')

# A command line is the wrong place for a brief. Windows caps the arguments
# plus the executable path at 2080 characters and reports the overflow as
# "Access is denied", and even where the limit is larger it is a limit.
#
# Project rules have no such ceiling: the CLI loads them from disk for every
# session in the working directory, with no size cap and no tool call. So the
# whole brief goes there and the command line carries only the task line. That
# is also the structure every prompt guide asks for and a single -p string
# cannot express: role, rules, format and data as system context, and the task
# as the prompt that follows them.
#
# The brief ends where <task> begins.
TASK_START=$(grep -n '^<task>$' "$PAYLOAD" | head -n 1 | cut -d: -f1)

if [ "$TRANSPORT" = "auto" ]; then
  if [ "$PAYLOAD_CHARS" -le "$MAX_INLINE" ]; then
    TRANSPORT="inline"
  elif [ -n "$TASK_START" ]; then
    TRANSPORT="rules"
  else
    TRANSPORT="file"
  fi
fi
[ "$TRANSPORT" = "rules" ] && [ -z "$TASK_START" ] && die "--transport rules needs a <task> line to split on" "$E_USAGE"

# A rewrite's cost is the length of what it writes, and the draft is the only
# proxy for that available before the run. A flat ceiling is wrong at both ends:
# too generous for a chat reply, too tight for a long document.
if [ -z "$TIMEOUT" ]; then
  TIMEOUT=$(( 300 + PAYLOAD_CHARS / 50 ))
  [ "$TIMEOUT" -gt 1800 ] && TIMEOUT=1800
fi

# --- assemble the command line ----------------------------------------------

read -r -a BASE_ARGS <<< "${GROKIFY_BASE_ARGS:-$BASE_ARGS_DEFAULT}"
ARGS=("${BASE_ARGS[@]}")
[ -n "$MODEL" ] && ARGS+=(-m "$MODEL")
[ -n "$EFFORT" ] && ARGS+=(--effort "$EFFORT")

if [ "$TRANSPORT" = "rules" ]; then
  RULES_DIR="$WORKDIR/rules"
  mkdir -p "$RULES_DIR"
  head -n "$((TASK_START - 1))" "$PAYLOAD" > "$RULES_DIR/AGENTS.md"
  ARGS+=(--cwd "$RULES_DIR")
  PROMPT="Your project rules contain a complete rewriting brief: the rules to follow, the reference material, and the text to rewrite inside a <draft> block.

$(tail -n +"$((TASK_START + 1))" "$PAYLOAD" | sed '/^<\/task>$/d')"
elif [ "$TRANSPORT" = "file" ]; then
  read -r -a FILE_ARGS <<< "${GROKIFY_FILE_ARGS:-$FILE_ARGS_DEFAULT}"
  ARGS+=("${FILE_ARGS[@]}" --cwd "$PAYLOAD_DIR")
  # Read only. Asking grok to write the result to a file trips a write approval
  # on a stdin nobody can answer; reading one file and replying with the text
  # needs no write permission and no second round trip.
  PROMPT="Read the file at this path. It is the only file you need and the only tool call you should make.

${PAYLOAD_ABS}

That file contains a complete rewriting brief: the rules, the reference material, and the text to rewrite inside a <draft> block. Follow it exactly.

Wrap your answer in these two markers, each on its own line:

<<<GROKIFY>>>
the rewritten text
<<<END>>>

Everything between them is the piece and only the piece: no preamble, no notes, no summary of what changed, no surrounding code fence. Anything outside the markers is discarded. Do not write any file, do not run any shell command, and do not search the web."
else
  PROMPT="$(cat "$PAYLOAD")"
fi

if [ -n "${GROKIFY_EXTRA_ARGS:-}" ]; then
  read -r -a _extra <<< "$GROKIFY_EXTRA_ARGS"
  ARGS+=("${_extra[@]}")
fi

printf 'grokify: transport=%s payload=%s chars prompt=%s chars timeout=%ss binary=%s\n' \
  "$TRANSPORT" "$PAYLOAD_CHARS" "${#PROMPT}" "$TIMEOUT" "$BIN_PATH" >&2

# On the rules path the brief reaches the model through project rules. A build
# that does not load them would rewrite from the task line alone, which reads
# as a bad rewrite rather than a broken run. `inspect` reports what was
# discovered, costs no model call, and turns that into a visible warning.
if [ "$TRANSPORT" = "rules" ] && [ "${GROKIFY_VERIFY_RULES:-0}" = "1" ]; then
  INSPECT_OUT="$( (cd "$RULES_DIR" && leash 20 "$BIN_PATH" inspect --cwd "$RULES_DIR") || true )"
  if [ -z "$INSPECT_OUT" ]; then
    printf 'grokify: could not verify project-rule loading; inspect gave nothing. Proceeding.\n' >&2
  elif ! printf '%s' "$INSPECT_OUT" | grep -qi 'AGENTS\.md'; then
    printf 'grokify: could not confirm project rules in %s; inspect did not name them. Proceeding.\n' "$RULES_DIR" >&2
  fi
fi

# A rewrite of a long document takes minutes. Silence for that long is
# indistinguishable from a hang, which is how the last one got killed by hand.
heartbeat() {
  # One-second slices, not thirty. A backgrounded `sleep 30` keeps holding the
  # inherited stderr after its parent is killed, which stalls anything reading
  # this script's output for up to half a minute after the run is over.
  local n=0
  while sleep 1; do
    n=$((n + 1))
    if [ $((n % 30)) -eq 0 ]; then
      printf 'grokify: still running, %ss elapsed of %ss\n' "$n" "$TIMEOUT" >&2
    fi
  done
}

run_grok() {
  # stdin is closed on every run. A CLI that asks a question writes it to the
  # redirected stdout where nobody sees it, then waits; with stdin closed it
  # gets EOF and exits, so a hang becomes an error.
  local rc
  heartbeat & HB_PID=$!
  if [ -n "$TIMEOUT_BIN" ]; then
    "$TIMEOUT_BIN" "$TIMEOUT" "$BIN_PATH" "$@" -p "$PROMPT" >"$RESULT_ABS" 2>"$ERRLOG" </dev/null
  else
    "$BIN_PATH" "$@" -p "$PROMPT" >"$RESULT_ABS" 2>"$ERRLOG" </dev/null
  fi
  rc=$?
  kill "$HB_PID" 2>/dev/null
  wait "$HB_PID" 2>/dev/null
  return $rc
}

run_grok "${ARGS[@]}"
RC=$?

# A build that does not carry one of the automation flags rejects the whole
# command line. Retry once with nothing but the prompt rather than reporting a
# flag error as a rewrite failure.
if [ "$RC" -ne 0 ] && [ "$RC" -ne "$E_TIMEOUT" ] \
   && grep -qiE 'unexpected argument|unknown (flag|option|argument)|invalid (flag|option)|unrecognized' "$ERRLOG" 2>/dev/null; then
  printf 'grokify: this build rejected one of the automation flags; retrying with -p only.\n' >&2
  MIN_ARGS=()
  [ -n "$MODEL" ] && MIN_ARGS=(-m "$MODEL")
  run_grok ${MIN_ARGS[@]+"${MIN_ARGS[@]}"}
  RC=$?
fi

# --- classify failures ------------------------------------------------------

if [ "$RC" -eq "$E_TIMEOUT" ]; then
  printf 'grokify: grok timed out after %s seconds.\n' "$TIMEOUT" >&2
  printf 'Raise it with --timeout, or shrink the brief: --dry-run prints the payload path.\n' >&2
  [ -s "$ERRLOG" ] && cat "$ERRLOG" >&2
  exit "$E_TIMEOUT"
fi

if [ "$RC" -ne 0 ]; then
  if grep -qiE 'unauthori|not authenticated|401|sign in|login required' "$ERRLOG" 2>/dev/null; then
    printf 'grokify: grok is installed but not authenticated.\n' >&2
    # shellcheck disable=SC2016  # backticks are literal here
    printf 'Run `grok login` and sign in, or `grok login --device-auth` on a headless box.\n\n' >&2
    cat "$ERRLOG" >&2
    exit "$E_AUTH"
  fi
  printf 'grokify: grok exited with status %s.\n\n' "$RC" >&2
  [ -s "$ERRLOG" ] && cat "$ERRLOG" >&2
  exit 1
fi

if [ ! -s "$RESULT_ABS" ]; then
  printf 'grokify: grok returned no output.\n' >&2
  [ -s "$ERRLOG" ] && { printf '\nstderr:\n' >&2; cat "$ERRLOG" >&2; }
  [ "$TRANSPORT" = "file" ] && printf '\nThe file handoff was used; grok may not be able to read %s.\n' "$PAYLOAD_ABS" >&2
  [ "$TRANSPORT" = "rules" ] && printf '\nThe brief travelled as project rules. Check this build loads them:\n  %s inspect\n' "$BIN_PATH" >&2
  exit "$E_EMPTY"
fi

# --- clean the output -------------------------------------------------------

if [ "$RAW" -eq 1 ]; then
  cp "$RESULT_ABS" "$OUT"
else
  # Strip a UTF-8 BOM. Some builds emit one, and a BOM in front of a markdown
  # heading stops it being a heading.
  sed '1s/^\xEF\xBB\xBF//' "$RESULT_ABS" > "$WORKDIR/nobom.out"

  # Take what is between the markers. An agent narrates before it calls a tool
  # ("I'll read that file now..."), and that narration lands in stdout glued to
  # the first line of the answer. Markers are exact where trimming heuristics
  # guess. The match is on characters, not lines, because a marker glued to the
  # text has content on the same line; and it takes the last opening marker and
  # the first closing one after it, so a model that mentions the markers before
  # using them cannot fool it.
  if [ "$TRANSPORT" = "rules" ] && ! grep -q '<<<GROKIFY>>>' "$WORKDIR/nobom.out"; then
    # The brief asks for markers. Their absence on this path usually means the
    # brief never arrived, so the model answered the bare task line.
    printf 'grokify: the reply carried no output markers, which usually means the project rules did not load.\n' >&2
    printf 'Compare with --transport file before trusting this.\n' >&2
  fi

  awk -v OPEN='<<<GROKIFY>>>' -v CLOSE='<<<END>>>' '
    BEGIN { RS = "\0"; ORS = "" }
    {
      s = $0; p = 0; o = 0
      while ((i = index(substr(s, p + 1), OPEN)) > 0) { p = p + i; o = p }
      if (o > 0) {
        rest = substr(s, o + length(OPEN))
        c = index(rest, CLOSE)
        if (c > 0) rest = substr(rest, 1, c - 1)
        print rest
      } else print s
    }' "$WORKDIR/nobom.out" > "$WORKDIR/clean.out"

  awk 'NF {found=1} found' "$WORKDIR/clean.out" \
    | awk '{lines[NR]=$0} END {last=NR; while (last>0 && lines[last] ~ /^[[:space:]]*$/) last--; for (i=1;i<=last;i++) print lines[i]}' \
    > "$WORKDIR/trim.out"

  # Unwrap the outer fence when the whole output is wrapped in one.
  # A prose answer wrapped in ```markdown may hold code fences of its own, so
  # the fence count only has to be even, not exactly two. An unlabelled or
  # code-labelled wrapper is unwrapped only when it is the sole fenced block:
  # a document that legitimately opens and closes on a code block must survive.
  FENCES=$(grep -c '^```' "$WORKDIR/trim.out" || true)
  FIRST=$(head -n 1 "$WORKDIR/trim.out")
  LAST=$(tail -n 1 "$WORKDIR/trim.out")
  FENCE_LANG=$(printf '%s' "$FIRST" | sed 's/^```//')
  UNWRAP=0
  if [ "$FENCES" -ge 2 ] && [ $((FENCES % 2)) -eq 0 ] \
     && printf '%s' "$FIRST" | grep -qE '^```[A-Za-z0-9_+-]*$' && [ "$LAST" = '```' ]; then
    case "$FENCE_LANG" in
      markdown|md|mdx|text|txt|plaintext|plain|html|rst|adoc|asciidoc) UNWRAP=1 ;;
      *) [ "$FENCES" -eq 2 ] && UNWRAP=1 ;;
    esac
  fi
  if [ "$UNWRAP" -eq 1 ]; then
    sed '1d;$d' "$WORKDIR/trim.out" > "$OUT"
  else
    cp "$WORKDIR/trim.out" "$OUT"
  fi
fi

if [ ! -s "$OUT" ]; then
  printf 'grokify: output was empty after cleanup; re-run with --raw to inspect it.\n' >&2
  exit "$E_EMPTY"
fi

exit 0

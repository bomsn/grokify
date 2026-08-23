<#
.SYNOPSIS
  Send a rewriting payload to the Grok CLI and capture the result.

.DESCRIPTION
  The Windows PowerShell runner. On Linux, macOS, Git Bash, and WSL, use
  grokify.sh in this directory instead; it is the same contract.

  The skill builds the payload; this script owns the transport: finding the
  grok binary, passing the prompt in a way that survives Windows, enforcing a
  timeout, and turning failures into exit codes the caller can act on.

  Three ways the payload can travel:

    rules   The whole brief is written to AGENTS.md in a scratch directory and
            reached with --cwd. The CLI loads project rules from disk with no
            size cap and no tool call, so the command line carries only the
            task line. The default for anything but a very short payload.
    inline  Passed as one -p argument. Only for a payload short enough to fit
            the command line; see the ceiling below.
    file    grok gets a short prompt naming one file to read, and replies with
            the rewritten text. Costs a tool call before any writing starts.
            Last resort, for a payload with no <task> line to split on.

  On the command-line ceiling: Process.Start documents a Win32Exception when
  "the sum of the length of the arguments and the length of the full path to
  the process exceeds 2080", reported as "The data area passed to a system
  call is too small" or "Access is denied". 2080, not the 32767 that
  CreateProcess itself allows. That is why the brief travels as project rules
  rather than as an argument.

  Argument escaping follows the CommandLineToArgvW rules and is done by this
  runner, so quotes, backslash runs and UTF-8 survive on Windows PowerShell
  5.1 as well as pwsh 7.

  The prompt always goes through -p. Running grok without it starts the
  interactive interface, which under a redirected stdout renders nowhere and
  waits forever.

.PARAMETER Payload
  Payload built from reference/payload-template.md. Required.

.PARAMETER Out
  Where to write the rewritten text. Required.

.PARAMETER Model
  Model passed to grok as -m.

.PARAMETER Effort
  Reasoning effort, passed to grok as --effort. Accepted levels vary by model;
  `grok models` lists them.

.PARAMETER TimeoutSec
  Seconds before the run is killed. Default 300.

.PARAMETER Bin
  grok binary name or full path, when PATH does not have it.

.PARAMETER Transport
  auto, inline, rules, or file. Default auto.

.PARAMETER Raw
  Skip output cleanup; keep grok's output byte for byte.

.PARAMETER Keep
  Keep the working directory and print its path.

.PARAMETER Check
  Report binary, version, and platform defaults, then exit.

.NOTES
  Exit codes: 0 success, 2 usage, 3 empty output, 124 timeout,
  126 not authenticated, 127 binary not found, 1 grok error.

  Environment: GROKIFY_BIN, GROKIFY_MODEL, GROKIFY_TIMEOUT,
  GROKIFY_MAX_INLINE_CHARS, GROKIFY_BASE_ARGS, GROKIFY_FILE_ARGS,
  GROKIFY_EXTRA_ARGS.
#>

[CmdletBinding()]
param(
    [string]$Payload,
    [string]$Out,
    [string]$Model,
    [string]$Effort,
    [int]$TimeoutSec = 0,
    [string]$Bin,
    [string]$Transport = 'auto',
    [switch]$Raw,
    [switch]$Keep,
    [switch]$Check
)

$ErrorActionPreference = 'Stop'

if (-not $Bin)        { $Bin        = if ($env:GROKIFY_BIN) { $env:GROKIFY_BIN } else { 'grok' } }
if (-not $Model)      { $Model      = $env:GROKIFY_MODEL }
if (-not $Effort)     { $Effort     = $env:GROKIFY_EFFORT }
if ($TimeoutSec -le 0 -and $env:GROKIFY_TIMEOUT) { $TimeoutSec = [int]$env:GROKIFY_TIMEOUT }

function Write-Err([string]$Message) { [Console]::Error.WriteLine("grokify: $Message") }

# Flags every headless run needs. Without --no-alt-screen the CLI can take over
# the terminal with its full-screen interface, which under a redirected stdout
# renders nowhere and waits forever. --output-format plain keeps the answer free
# of transcript framing, and --no-auto-update stops a background update check
# from stalling an automated run.
$baseArgsDefault = '--output-format plain --no-alt-screen --no-auto-update'
# The file transport is the only path that uses a tool, so it is the only one
# that can meet an approval prompt. --always-approve answers it; --max-turns
# bounds the loop if the model decides to keep going.
$fileArgsDefault = '--always-approve --max-turns 6'
$baseArgs = if ($env:GROKIFY_BASE_ARGS) { $env:GROKIFY_BASE_ARGS } else { $baseArgsDefault }
$fileArgs = if ($env:GROKIFY_FILE_ARGS) { $env:GROKIFY_FILE_ARGS } else { $fileArgsDefault }

if ($Transport -notin @('auto', 'inline', 'rules', 'file')) { Write-Err '-Transport must be auto, inline, rules, or file'; exit 2 }

function Split-Args([string]$Text) { @($Text -split '\s+' | Where-Object { $_ }) }

# --- find grok --------------------------------------------------------------
#
# Get-Command honours PATHEXT, so grok.cmd or grok.exe resolves on its own.
# When it misses, probe where the Grok CLI installers write. The npm global bin
# is the usual culprit: on the interactive PATH, absent nearly everywhere else.

function Find-Grok {
    param([string]$Name)

    if ($Name -match '[\\/]') {
        if (Test-Path -LiteralPath $Name) { return (Resolve-Path -LiteralPath $Name).Path }
        return $null
    }

    $cmd = Get-Command $Name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd) { return $cmd.Source }

    $dirs = @(
        (Join-Path $HOME '.grok\bin'),
        (Join-Path $HOME '.local\bin'),
        (Join-Path $HOME '.bun\bin'),
        (Join-Path $HOME '.npm-global\bin'),
        (Join-Path $HOME 'bin'),
        $(if ($env:APPDATA) { Join-Path $env:APPDATA 'npm' }),
        $(if ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA 'Programs\grok' }),
        '/usr/local/bin',
        '/opt/homebrew/bin'
    ) | Where-Object { $_ }

    foreach ($dir in $dirs) {
        foreach ($ext in @('.cmd', '.exe', '.bat', '')) {
            $candidate = Join-Path $dir ($Name + $ext)
            if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
        }
    }
    return $null
}

$binPath = Find-Grok -Name $Bin

if (-not $binPath) {
    Write-Err "'$Bin' was not found on PATH, and is not in any of the directories the Grok CLI normally installs to."
    [Console]::Error.WriteLine(@"

Searched: %APPDATA%\npm, `$HOME\.grok\bin, `$HOME\.local\bin, `$HOME\.bun\bin,
          `$HOME\.npm-global\bin, %LOCALAPPDATA%\Programs\grok, /usr/local/bin

If grok runs in your normal terminal but not here, the shell that launched this
script has a different PATH. Get the real path from the terminal where it works:

  where.exe grok

Then pass it per run with -Bin, or set it once:

  `$env:GROKIFY_BIN = 'C:\Users\you\AppData\Roaming\npm\grok.cmd'

Install the Grok CLI:
  irm https://x.ai/cli/install.ps1 | iex
"@)
    exit 127
}

# The inline ceiling is a property of the launcher, not the operating system.
# A .cmd or .bat shim runs through cmd.exe, which caps a command line at 8191
# characters; CreateProcess itself caps at 32767. Leave headroom for the flags.
# Which argument API .NET offers here. Informational only: the runner escapes
# the command line itself, by the CommandLineToArgvW rules, so both paths pass
# a payload through byte for byte. Verified against quotes, backslash runs,
# shell metacharacters, and UTF-8.
$hasArgumentList = ([System.Diagnostics.ProcessStartInfo]::new().PSObject.Properties.Name -contains 'ArgumentList')
# Process.Start throws when the arguments plus the executable path exceed
# 2080 characters, and reports it as "Access is denied". Budget from that,
# leaving room for the flags and the quoting the runner adds.
if ($env:GROKIFY_MAX_INLINE_CHARS) {
    $maxInline = [int]$env:GROKIFY_MAX_INLINE_CHARS
} else {
    $maxInline = 2080 - $binPath.Length - $baseArgs.Length - $fileArgs.Length - 128
    if ($maxInline -lt 256) { $maxInline = 256 }
}

if ($Check) {
    # Probe with stdin closed and a short leash: a CLI that does not recognise
    # --version may drop into its interactive REPL and wait forever.
    $version = 'unknown'
    try {
        $vpsi = New-Object System.Diagnostics.ProcessStartInfo
        $vpsi.FileName = $binPath
        $vpsi.UseShellExecute = $false
        $vpsi.RedirectStandardOutput = $true
        $vpsi.RedirectStandardError = $true
        $vpsi.RedirectStandardInput = $true
        if ($vpsi.PSObject.Properties.Name -contains 'ArgumentList') { $vpsi.ArgumentList.Add('version') }
        else { $vpsi.Arguments = 'version' }
        $vp = [System.Diagnostics.Process]::Start($vpsi)
        $vout = $vp.StandardOutput.ReadToEndAsync()
        $vp.StandardInput.Close()
        if ($vp.WaitForExit(10000)) {
            $first = ($vout.Result -split "`r?`n" | Where-Object { $_.Trim() } | Select-Object -First 1)
            if ($first) { $version = $first }
        } else { try { $vp.Kill() } catch { }; $version = 'no response to `grok version`' }
    } catch { $version = 'unknown' }
    Write-Output "platform:     $([System.Environment]::OSVersion.Platform)"
    Write-Output "binary:       $binPath"
    Write-Output "version:      $version"
    Write-Output "base flags:   $baseArgs"
    Write-Output "file flags:   $fileArgs"
    Write-Output "inline limit: $maxInline characters"
    Write-Output "argument api:  $(if ($hasArgumentList) { 'ArgumentList' } else { 'Arguments string, escaped by this runner' })"
    # The speed levers are account-specific, so show what this one can reach.
    try {
        $mp = New-Object System.Diagnostics.ProcessStartInfo
        $mp.FileName = $binPath; $mp.UseShellExecute = $false
        $mp.RedirectStandardOutput = $true; $mp.RedirectStandardError = $true; $mp.RedirectStandardInput = $true
        if ($mp.PSObject.Properties.Name -contains 'ArgumentList') { $mp.ArgumentList.Add('models') } else { $mp.Arguments = 'models' }
        $mproc = [System.Diagnostics.Process]::Start($mp)
        $mout = $mproc.StandardOutput.ReadToEndAsync()
        $mproc.StandardInput.Close()
        if ($mproc.WaitForExit(20000)) {
            $lines = ($mout.Result -split "`r?`n" | Where-Object { $_.Trim() } | Select-Object -First 20)
            if ($lines) { Write-Output 'models:'; $lines | ForEach-Object { Write-Output "  $_" } }
        } else { try { $mproc.Kill() } catch { } }
    } catch { Write-Output "models:       could not list; run '$Bin models' yourself" }
    exit 0
}

if (-not $Payload) { Write-Err '-Payload is required'; exit 2 }
if (-not $Out)     { Write-Err '-Out is required'; exit 2 }
if (-not (Test-Path -LiteralPath $Payload)) { Write-Err "payload not found: $Payload"; exit 2 }

$payloadAbs = (Resolve-Path -LiteralPath $Payload).Path
# Read through .NET rather than Get-Content: on Windows PowerShell 5.1
# Get-Content defaults to the ANSI code page, so a UTF-8 payload loses every
# non-ASCII character before it reaches the model. ReadAllText detects a BOM
# and falls back to UTF-8, identically on 5.1 and pwsh 7.
$payloadText = [System.IO.File]::ReadAllText($payloadAbs)
$payloadLines = $payloadText -split "`r?`n"
$payloadChars = $payloadText.Length

# --- working directory ------------------------------------------------------

$workDir = Join-Path ([System.IO.Path]::GetTempPath()) ("grokify-" + [System.Guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $workDir -Force | Out-Null
$resultAbs = Join-Path $workDir 'result.txt'

$outParent = Split-Path -Parent $Out
if ($outParent -and -not (Test-Path -LiteralPath $outParent)) {
    New-Item -ItemType Directory -Path $outParent -Force | Out-Null
}

function Remove-WorkDir {
    if ($Keep) { [Console]::Error.WriteLine("grokify: kept $workDir") }
    else { Remove-Item -LiteralPath $workDir -Recurse -Force -ErrorAction SilentlyContinue }
}

# --- choose how the payload travels -----------------------------------------

# The payload is two halves: standing rules, then the material for this one
# job. The rules end at </output_format>. Splitting there lets the rules travel
# as project rules, which the CLI reads off disk with no size cap, leaving only
# the job-specific half on the command line. That is both smaller and better
# structured: rules reach the model as system context and the data as the
# prompt, which is the split a single -p string cannot express.
# The brief ends where <task> begins.
$taskStart = -1
for ($i = 0; $i -lt $payloadLines.Count; $i++) {
    if ($payloadLines[$i] -eq '<task>') { $taskStart = $i; break }
}

$resolvedTransport = $Transport
if ($Transport -eq 'auto') {
    if ($payloadChars -le $maxInline) {
        $resolvedTransport = 'inline'
    } elseif ($taskStart -ge 0) {
        $resolvedTransport = 'rules'
    } else {
        $resolvedTransport = 'file'
    }
}
if ($resolvedTransport -eq 'rules' -and $taskStart -lt 0) {
    Write-Err '-Transport rules needs a <task> line to split on'; exit 2
}

# A rewrite's cost is the length of what it writes, and the draft is the only
# proxy for that available before the run. A flat ceiling is wrong at both ends:
# too generous for a chat reply, too tight for a long document.
if ($TimeoutSec -le 0) {
    $TimeoutSec = [Math]::Min(1800, 300 + [int]($payloadChars / 50))
}

# --- run --------------------------------------------------------------------

$script:runWorkingDir = $null

function Write-Utf8NoBom {
    # Set-Content -Encoding UTF8 writes a byte-order mark on Windows PowerShell
    # 5.1 and not on pwsh 7, so neither is portable. Write the bytes directly.
    param([string]$Path, [string]$Text)
    [System.IO.File]::WriteAllText($Path, $Text, (New-Object System.Text.UTF8Encoding($false)))
}

function Stop-ProcessTree {
    # A .cmd shim launches the real interpreter as a child. Killing the shim
    # leaves that child running and holding the pipes, so kill the tree.
    param([System.Diagnostics.Process]$Proc)
    try { $Proc.Kill($true); return } catch { }
    if ($env:OS -eq 'Windows_NT') {
        try { & taskkill.exe /T /F /PID $Proc.Id 2>&1 | Out-Null; return } catch { }
    }
    try { $Proc.Kill() } catch { }
}

function Invoke-Grok {
    param([string[]]$GrokArgs)

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $binPath
    $psi.UseShellExecute = $false
    if ($script:runWorkingDir) { $psi.WorkingDirectory = $script:runWorkingDir }
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    # Always redirect stdin, even when there is nothing to send. An agent CLI
    # that asks a question (approve this write? pick a model?) writes it to the
    # redirected stdout where nobody sees it, then waits on stdin forever. With
    # stdin closed it gets EOF instead and exits, so a hang becomes an error.
    $psi.RedirectStandardInput = $true
    # Decode the child's streams as UTF-8. The default is the console code
    # page, which turns box-drawing characters and accented text into mojibake.
    try {
        $utf8 = New-Object System.Text.UTF8Encoding($false)
        $psi.StandardOutputEncoding = $utf8
        $psi.StandardErrorEncoding = $utf8
    } catch { }

    if ($psi.PSObject.Properties.Name -contains 'ArgumentList') {
        foreach ($a in $GrokArgs) { $psi.ArgumentList.Add($a) }
    } else {
        $psi.Arguments = ($GrokArgs | ForEach-Object {
            $escaped = $_ -replace '(\\*)"', '$1$1\"'
            $escaped = $escaped -replace '(\\+)$', '$1$1'
            '"' + $escaped + '"'
        }) -join ' '
    }
    $proc = [System.Diagnostics.Process]::Start($psi)
    $stdoutTask = $proc.StandardOutput.ReadToEndAsync()
    $stderrTask = $proc.StandardError.ReadToEndAsync()

    $proc.StandardInput.Close()

    # A rewrite of a long document takes minutes. Silence for that long is
    # indistinguishable from a hang, which is how the last one got killed by
    # hand. Wait in slices and say so.
    $elapsed = 0
    while ($true) {
        $slice = [Math]::Min(30, $TimeoutSec - $elapsed)
        if ($slice -le 0) {
            Stop-ProcessTree -Proc $proc
            return @{ TimedOut = $true; Code = 124; Stdout = ''; Stderr = '' }
        }
        if ($proc.WaitForExit($slice * 1000)) { break }
        $elapsed += $slice
        if ($elapsed -lt $TimeoutSec) {
            [Console]::Error.WriteLine("grokify: still running, ${elapsed}s elapsed of ${TimeoutSec}s")
        }
    }

    return @{
        TimedOut = $false
        Code     = $proc.ExitCode
        Stdout   = $stdoutTask.Result
        Stderr   = $stderrTask.Result
    }
}

$grokArgs = @(Split-Args $baseArgs)
if ($Model)  { $grokArgs += @('-m', $Model) }
if ($Effort) { $grokArgs += @('--effort', $Effort) }

if ($resolvedTransport -eq 'rules') {
    $rulesDir = Join-Path $workDir 'rules'
    New-Item -ItemType Directory -Path $rulesDir -Force | Out-Null
    $briefText = ($payloadLines[0..($taskStart - 1)] -join [Environment]::NewLine)
    Write-Utf8NoBom -Path (Join-Path $rulesDir 'AGENTS.md') -Text $briefText
    $grokArgs += @('--cwd', $rulesDir)
    $script:runWorkingDir = $rulesDir
    $taskText = ($payloadLines[($taskStart + 1)..($payloadLines.Count - 1)] |
                 Where-Object { $_ -ne '</task>' }) -join [Environment]::NewLine
    $prompt = "Your project rules contain a complete rewriting brief: the rules to follow, the reference material, and the text to rewrite inside a <draft> block.`n`n" + $taskText.Trim()
} elseif ($resolvedTransport -eq 'file') {
    $grokArgs += Split-Args $fileArgs
    $grokArgs += @('--cwd', (Split-Path -Parent $payloadAbs))
    # Read only. Asking grok to write the result to a file trips a write
    # approval on a stdin nobody can answer; reading one file and replying with
    # the text needs no write permission and no second round trip.
    $template = @'
Read the file at this path. It is the only file you need and the only tool call you should make.

{0}

That file contains a complete rewriting brief: the rules, the reference material, and the text to rewrite inside a <draft> block. Follow it exactly.

Wrap your answer in these two markers, each on its own line:

<<<GROKIFY>>>
the rewritten text
<<<END>>>

Everything between them is the piece and only the piece: no preamble, no notes, no summary of what changed, no surrounding code fence. Anything outside the markers is discarded. Do not write any file, do not run any shell command, and do not search the web.
'@
    $prompt = $template -f $payloadAbs
} else {
    $prompt = $payloadText
}

if ($env:GROKIFY_EXTRA_ARGS) { $grokArgs += Split-Args $env:GROKIFY_EXTRA_ARGS }

[Console]::Error.WriteLine("grokify: transport=$resolvedTransport payload=$payloadChars chars prompt=$($prompt.Length) chars timeout=${TimeoutSec}s binary=$binPath")

# On the rules path the brief reaches the model through project rules. A build
# that does not load them would rewrite from the task line alone, which reads
# as a bad rewrite rather than a broken run. `inspect` reports what was
# discovered, costs no model call, and turns that into a visible warning.
if ($resolvedTransport -eq 'rules' -and $env:GROKIFY_VERIFY_RULES -eq '1') {
    $inspect = ''
    try {
        $ipsi = New-Object System.Diagnostics.ProcessStartInfo
        $ipsi.FileName = $binPath
        $ipsi.UseShellExecute = $false
        $ipsi.RedirectStandardOutput = $true
        $ipsi.RedirectStandardError = $true
        $ipsi.RedirectStandardInput = $true
        $ipsi.WorkingDirectory = $rulesDir
        try {
            $u8 = New-Object System.Text.UTF8Encoding($false)
            $ipsi.StandardOutputEncoding = $u8
            $ipsi.StandardErrorEncoding = $u8
        } catch { }
        foreach ($a in @('inspect', '--cwd', $rulesDir)) {
            if ($ipsi.PSObject.Properties.Name -contains 'ArgumentList') { $ipsi.ArgumentList.Add($a) }
        }
        if (-not ($ipsi.PSObject.Properties.Name -contains 'ArgumentList')) {
            $ipsi.Arguments = 'inspect --cwd "' + $rulesDir + '"'
        }
        $ip = [System.Diagnostics.Process]::Start($ipsi)
        $iout = $ip.StandardOutput.ReadToEndAsync()
        $ierr = $ip.StandardError.ReadToEndAsync()
        $ip.StandardInput.Close()
        if ($ip.WaitForExit(20000)) { $inspect = $iout.Result + $ierr.Result } else { try { $ip.Kill() } catch { } }
    } catch { $inspect = '' }

    if (-not $inspect) {
        [Console]::Error.WriteLine('grokify: could not verify project-rule loading (inspect gave nothing). Proceeding.')
    } elseif ($inspect -notmatch '(?i)AGENTS\.md') {
        [Console]::Error.WriteLine("grokify: could not confirm project rules in $rulesDir; inspect did not name them. Proceeding.")
    }
}

$run = Invoke-Grok -GrokArgs ($grokArgs + @('-p', $prompt))

# A build that does not carry one of the automation flags rejects the whole
# command line. Retry once with nothing but the prompt rather than reporting a
# flag error as a rewrite failure.
if (-not $run.TimedOut -and $run.Code -ne 0 -and
    $run.Stderr -match '(?i)unexpected argument|unknown (flag|option|argument)|invalid (flag|option)|unrecognized') {
    Write-Err 'this build rejected one of the automation flags; retrying with -p only.'
    $minArgs = @()
    if ($Model) { $minArgs += @('-m', $Model) }
    $run = Invoke-Grok -GrokArgs ($minArgs + @('-p', $prompt))
}

# --- classify failures ------------------------------------------------------

if ($run.TimedOut) {
    Write-Err "grok timed out after $TimeoutSec seconds."
    [Console]::Error.WriteLine('Raise it with -TimeoutSec, or shrink the brief.')
    Remove-WorkDir
    exit 124
}

if ($run.Code -ne 0) {
    if ($run.Stderr -match '(?i)unauthori|not authenticated|401|sign in|login required') {
        Write-Err 'grok is installed but not authenticated.'
        [Console]::Error.WriteLine("Run 'grok login' and sign in, or 'grok login --device-auth' on a headless box.")
        [Console]::Error.WriteLine($run.Stderr)
        Remove-WorkDir
        exit 126
    }
    Write-Err "grok exited with status $($run.Code)."

    [Console]::Error.WriteLine($run.Stderr)
    Remove-WorkDir
    exit 1
}

Write-Utf8NoBom -Path $resultAbs -Text $run.Stdout

if (-not (Test-Path -LiteralPath $resultAbs) -or (Get-Item -LiteralPath $resultAbs).Length -eq 0) {
    Write-Err 'grok returned no output.'
    [Console]::Error.WriteLine($run.Stderr)
    if ($resolvedTransport -eq 'file') {
        [Console]::Error.WriteLine("The file handoff was used; grok may not be able to read $payloadAbs.")
    }
    if ($resolvedTransport -eq 'rules') {
        [Console]::Error.WriteLine("The brief travelled as project rules. Check this build loads them: $binPath inspect")
    }
    Remove-WorkDir
    exit 3
}

$text = [System.IO.File]::ReadAllText($resultAbs)

# --- clean the output -------------------------------------------------------

if (-not $Raw) {
    # Strip a UTF-8 BOM. Some builds emit one, and a BOM in front of a markdown
    # heading stops it being a heading.
    $text = $text -replace "^\uFEFF", ''

    # Take what is between the markers. An agent narrates before it calls a tool
    # ("I'll read that file now..."), and that narration lands in stdout glued
    # to the first line of the answer. Markers are exact where trimming
    # heuristics guess. Take the last opening marker and the first closing one
    # after it, so a model that mentions the markers before using them cannot
    # fool it.
    $openIdx = $text.LastIndexOf('<<<GROKIFY>>>')
    if ($openIdx -lt 0 -and $resolvedTransport -eq 'rules') {
        # The brief asks for markers. Their absence on this path usually means
        # the brief never arrived, so the model answered the bare task line.
        [Console]::Error.WriteLine('grokify: the reply carried no output markers, which usually means the project rules did not load. Compare with -Transport file before trusting this.')
    }
    if ($openIdx -ge 0) {
        $text = $text.Substring($openIdx + '<<<GROKIFY>>>'.Length)
        $closeIdx = $text.IndexOf('<<<END>>>')
        if ($closeIdx -ge 0) { $text = $text.Substring(0, $closeIdx) }
    }

    $lines = $text -split "`r?`n"
    while ($lines.Count -gt 0 -and $lines[0].Trim() -eq '') { $lines = $lines[1..($lines.Count - 1)] }
    while ($lines.Count -gt 0 -and $lines[-1].Trim() -eq '') { $lines = $lines[0..($lines.Count - 2)] }

    # Unwrap the outer fence when the whole output is wrapped in one. A prose
    # answer wrapped in ```markdown may hold code fences of its own, so the
    # fence count only has to be even. An unlabelled or code-labelled wrapper
    # is unwrapped only when it is the sole fenced block.
    $fenceCount = ($lines | Where-Object { $_ -match '^```' }).Count
    if ($lines.Count -ge 2 -and $fenceCount -ge 2 -and ($fenceCount % 2) -eq 0 -and
        $lines[0] -match '^```([A-Za-z0-9_+-]*)$' -and $lines[-1].Trim() -eq '```') {
        $fenceLang = $Matches[1].ToLower()
        $docLangs = @('markdown', 'md', 'mdx', 'text', 'txt', 'plaintext', 'plain', 'html', 'rst', 'adoc', 'asciidoc')
        if ($docLangs -contains $fenceLang -or $fenceCount -eq 2) {
            $lines = $lines[1..($lines.Count - 2)]
        }
    }
    $text = ($lines -join [Environment]::NewLine)
}

if ($text -and -not $text.EndsWith("`n")) { $text += "`n" }
Write-Utf8NoBom -Path $Out -Text $text
Remove-WorkDir

if ((Get-Item -LiteralPath $Out).Length -eq 0) {
    Write-Err 'output was empty after cleanup; re-run with -Raw to inspect it.'
    exit 3
}

exit 0

<#
.SYNOPSIS
  Build the distributable archives.

.DESCRIPTION
  dist\grokify.zip     upload to claude.ai or the Claude desktop app
  dist\grokify.skill   the same archive, named for hosts that expect it

  Both hold a single top-level folder, grokify\, with SKILL.md at the top of
  it. That is the layout the Skills API and the claude.ai uploader accept.
#>

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$skillDir = Join-Path $root 'skills\grokify'
$dist = Join-Path $root 'dist'

if (-not (Test-Path (Join-Path $skillDir 'SKILL.md'))) {
    Write-Error "package: SKILL.md not found at $skillDir"
}

# The upload path accepts only the six Agent Skills frontmatter fields. A field
# outside that set fails the upload with a hard error rather than being ignored.
$allowed = @('name', 'description', 'license', 'compatibility', 'metadata', 'allowed-tools')
$lines = Get-Content -LiteralPath (Join-Path $skillDir 'SKILL.md')
$inFrontmatter = $false
foreach ($line in $lines) {
    if ($line -eq '---') {
        if ($inFrontmatter) { break }
        $inFrontmatter = $true
        continue
    }
    if ($inFrontmatter -and $line -match '^([A-Za-z][A-Za-z0-9_-]*):') {
        if ($allowed -notcontains $Matches[1]) {
            Write-Error "package: frontmatter key '$($Matches[1])' is not in the Agent Skills spec ($($allowed -join ', '))"
        }
    }
}

if (Test-Path $dist) { Remove-Item -LiteralPath $dist -Recurse -Force }
New-Item -ItemType Directory -Path $dist -Force | Out-Null

$stage = Join-Path ([System.IO.Path]::GetTempPath()) ("grokify-pkg-" + [System.Guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $stage -Force | Out-Null
try {
    Copy-Item -LiteralPath $skillDir -Destination (Join-Path $stage 'grokify') -Recurse
    Get-ChildItem -LiteralPath $stage -Recurse -Force -Filter '.DS_Store' | Remove-Item -Force -ErrorAction SilentlyContinue

    $zip = Join-Path $dist 'grokify.zip'
    Compress-Archive -Path (Join-Path $stage 'grokify') -DestinationPath $zip -Force
    Copy-Item -LiteralPath $zip -Destination (Join-Path $dist 'grokify.skill') -Force

    Write-Output "built $zip ($((Get-Item $zip).Length) bytes)"
    Write-Output "built $(Join-Path $dist 'grokify.skill')"
} finally {
    Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
}

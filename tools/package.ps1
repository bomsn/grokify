<#
.SYNOPSIS
  Build dist\grokify.plugin.

.DESCRIPTION
  One artifact, because there is only one thing to install. The repository is
  the plugin: .claude-plugin\plugin.json, .mcp.json, the host bridge under
  servers\, and the skill under skills\. Zipping it from its own root, with no
  enclosing folder, is the layout the plugin installer reads.

  A skill-only archive used to be built here too. It was removed on purpose. A
  skill archive cannot carry an MCP server, so uploading one to the desktop app
  installs something that loads and then cannot reach Grok at all - the exact
  failure this project exists to fix.
#>

$ErrorActionPreference = 'Stop'

$root     = Split-Path -Parent $PSScriptRoot
$dist     = Join-Path $root 'dist'
$skillDir = Join-Path $root 'skills\grokify'

$manifestPath = Join-Path $root '.claude-plugin\plugin.json'
$marketPath   = Join-Path $root '.claude-plugin\marketplace.json'
$mcpPath      = Join-Path $root '.mcp.json'
$serverPath   = Join-Path $root 'servers\grokify-host.mjs'
$skillMd      = Join-Path $skillDir 'SKILL.md'

foreach ($f in @($manifestPath, $mcpPath, $serverPath, $skillMd)) {
    if (-not (Test-Path $f)) { Write-Error "package: missing $f" }
}

# Keeping the skill's frontmatter inside the six fields the Agent Skills spec
# allows is not required by the plugin installer. It is kept so the skill folder
# stays valid on its own, for anyone who copies it into ~/.claude/skills.
$allowed = @('name', 'description', 'license', 'compatibility', 'metadata', 'allowed-tools')
$inFrontmatter = $false
foreach ($line in (Get-Content -LiteralPath $skillMd)) {
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

# Both manifests are read by the installer before anything runs, so a syntax
# error here is an install that fails with nothing useful to say.
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
if (-not $manifest.name) { Write-Error 'package: plugin.json needs a name' }

if (Test-Path $marketPath) {
    $market = Get-Content -LiteralPath $marketPath -Raw | ConvertFrom-Json
    if (@($market.plugins).name -notcontains $manifest.name) {
        Write-Error "package: marketplace.json does not list $($manifest.name)"
    }
}

$mcp = Get-Content -LiteralPath $mcpPath -Raw | ConvertFrom-Json
if (-not $mcp.mcpServers) { Write-Error 'package: .mcp.json declares no servers' }
foreach ($prop in $mcp.mcpServers.PSObject.Properties) {
    foreach ($arg in @($prop.Value.args)) {
        if ($arg -like '*.mjs') {
            # A hardcoded path works on the machine that built the archive and
            # nowhere else. ${CLAUDE_PLUGIN_ROOT} is what makes it portable.
            if ($arg -notlike '*${CLAUDE_PLUGIN_ROOT}*') {
                Write-Error "package: $($prop.Name) points at $arg without `${CLAUDE_PLUGIN_ROOT}"
            }
            $rel = $arg.Replace('${CLAUDE_PLUGIN_ROOT}/', '').Replace('/', '\')
            if (-not (Test-Path (Join-Path $root $rel))) {
                Write-Error "package: $($prop.Name) points at $rel, which is not in the archive"
            }
        }
    }
}

if (Get-Command node -ErrorAction SilentlyContinue) {
    & node --check $serverPath
    if ($LASTEXITCODE -ne 0) { Write-Error 'package: the host server does not parse' }
}

if (Test-Path $dist) { Remove-Item -LiteralPath $dist -Recurse -Force }
New-Item -ItemType Directory -Path $dist -Force | Out-Null

$stage = Join-Path ([System.IO.Path]::GetTempPath()) ("grokify-plg-" + [System.Guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $stage -Force | Out-Null
try {
    # Copy each item by name. Copy-Item -Recurse nests a directory inside an
    # existing one of the same name, so a wildcard pass is not safe here.
    New-Item -ItemType Directory -Path (Join-Path $stage '.claude-plugin') -Force | Out-Null
    Copy-Item -LiteralPath $manifestPath -Destination (Join-Path $stage '.claude-plugin\plugin.json') -Force
    Copy-Item -LiteralPath $mcpPath -Destination (Join-Path $stage '.mcp.json') -Force
    New-Item -ItemType Directory -Path (Join-Path $stage 'servers') -Force | Out-Null
    Copy-Item -LiteralPath $serverPath -Destination (Join-Path $stage 'servers\grokify-host.mjs') -Force
    New-Item -ItemType Directory -Path (Join-Path $stage 'skills') -Force | Out-Null
    Copy-Item -LiteralPath $skillDir -Destination (Join-Path $stage 'skills\grokify') -Recurse
    Copy-Item -LiteralPath (Join-Path $root 'README.md') -Destination $stage -Force
    Copy-Item -LiteralPath (Join-Path $root 'LICENSE') -Destination $stage -Force
    Get-ChildItem -LiteralPath $stage -Recurse -Force -Filter '.DS_Store' | Remove-Item -Force -ErrorAction SilentlyContinue

    # marketplace.json is deliberately not copied: it describes where to find
    # this plugin, which is of no use once you are holding it.
    $plugin = Join-Path $dist 'grokify.plugin'
    # Compress the staging directory's contents, not the directory: the archive
    # must have no enclosing folder, so the manifest sits at its root. A leading
    # dot is not a hidden attribute on Windows, so .claude-plugin and .mcp.json
    # are included by the wildcard.
    Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $plugin -Force
    Write-Output "built $plugin ($((Get-Item $plugin).Length) bytes)"
} finally {
    Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
}

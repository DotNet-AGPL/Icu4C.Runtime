<#
.SYNOPSIS
  Convert the WeChat article Markdown into WeChat-compatible HTML (inline styles).

.DESCRIPTION
  Uses tools/md-to-wechat (Node: marked + juice). WeChat strips <style> tags and class
  names, so all CSS is inlined. Open the generated HTML in a browser, select all, copy,
  and paste into the WeChat Official Account editor (then save as draft).

.PARAMETER Source
  Source Markdown (default: docs/wechat-article.md).

.PARAMETER Output
  Output HTML (default: docs/wechat-article.html).

.PARAMETER KeepTitle
  Keep the leading "# Title" in the body (by default it is removed; the title is
  entered separately in the WeChat editor).

.EXAMPLE
  ./scripts/md-to-wechat.ps1
#>
[CmdletBinding()]
param(
  [string]$Source = "docs/wechat-article.md",
  [string]$Output = "docs/wechat-article.html",
  [switch]$KeepTitle
)

$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$ToolDir  = Join-Path $RepoRoot "tools/md-to-wechat"

if (-not (Test-Path (Join-Path $ToolDir "node_modules"))) {
  Write-Host "Installing md-to-wechat dependencies ..."
  Push-Location $ToolDir
  try { npm install --registry https://registry.npmmirror.com --no-audit --no-fund } finally { Pop-Location }
}

$nodeArgs = @((Join-Path $RepoRoot $Source), (Join-Path $RepoRoot $Output))
if ($KeepTitle) { $nodeArgs += "--keep-title" }

& node (Join-Path $ToolDir "convert.js") @nodeArgs

<#
.SYNOPSIS
  Build ICU4C for a Windows RID and stage the DLLs under runtimes/<rid>/native/.

.DESCRIPTION
  Requires Visual Studio (MSBuild) with the C++ toolset. Downloads the ICU source,
  builds the allinone solution, and copies icuucNN.dll / icuinNN.dll / icudtNN.dll.

.PARAMETER IcuVersion
  ICU version, e.g. 77.1 (default).

.PARAMETER Rid
  win-x64 | win-arm64 (default: win-x64).

.EXAMPLE
  ./build-icu-windows.ps1 77.1 win-x64
#>
[CmdletBinding()]
param(
  [string]$IcuVersion = "77.1",
  [string]$Rid = "win-x64"
)

$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$OutDir   = Join-Path $RepoRoot "runtimes/$Rid/native"

$IcuMajor = ($IcuVersion -split '\.')[0]
$Tag      = "release-" + ($IcuVersion -replace '\.', '-')
$Asset    = "icu4c-" + ($IcuVersion -replace '\.', '_') + "-src.tgz"
$GhPath   = "unicode-org/icu/releases/download/$Tag/$Asset"

$Proxy = $env:ICU_GH_PROXY
if ([string]::IsNullOrEmpty($Proxy)) { $Proxy = "https://ghfast.top" }
if ($Proxy -in @("-", "none")) { $Url = "https://github.com/$GhPath" }
else { $Url = ($Proxy.TrimEnd('/')) + "/https://github.com/$GhPath" }

$Platform = switch ($Rid) {
  "win-x64"   { "x64"   }
  "win-arm64" { "ARM64" }
  default     { throw "Unsupported RID for build-icu-windows.ps1: $Rid" }
}

$WorkDir = Join-Path $env:TEMP ("icu-build-" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null

try {
  Write-Host "Downloading ICU $IcuVersion : $Url"
  $Tgz = Join-Path $WorkDir "icu.tgz"
  Invoke-WebRequest -Uri $Url -OutFile $Tgz

  Write-Host "Extracting..."
  tar xzf $Tgz -C $WorkDir
  $Source = Join-Path $WorkDir "icu/source"

  $Solution = Join-Path $Source "allinone/allinone.sln"
  Write-Host "Building $Solution ($Platform, Release) ..."

  # Locate MSBuild (from VS install) if not on PATH.
  $MSBuild = "msbuild"
  if (-not (Get-Command msbuild -ErrorAction SilentlyContinue)) {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio/Installer/vswhere.exe"
    if (Test-Path $vswhere) {
      $MSBuild = (& $vswhere -latest -requires Microsoft.Component.MSBuild -find "MSBuild/**/Bin/MSBuild.exe" | Select-Object -First 1)
    }
    if ([string]::IsNullOrEmpty($MSBuild)) { throw "MSBuild not found. Install Visual Studio with the C++ toolset." }
  }
  & $MSBuild $Solution /m /p:Configuration=Release /p:Platform=$Platform

  New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
  # Built output lands in <source>/bin64 or binARM64
  $BinDir = Get-ChildItem -Path $Source -Directory -Filter "bin*" |
            Where-Object { Get-ChildItem $_.FullName -Filter "icuuc$IcuMajor.dll" -ErrorAction SilentlyContinue } |
            Select-Object -First 1
  if (-not $BinDir) { throw "Could not locate built ICU DLLs under $Source" }

  foreach ($name in @("icuuc$IcuMajor.dll", "icuin$IcuMajor.dll", "icudt$IcuMajor.dll")) {
    $src = Join-Path $BinDir.FullName $name
    if (Test-Path $src) { Copy-Item $src $OutDir -Force }
    else { Write-Warning "Not found: $src" }
  }

  Write-Host "Result:"
  Get-ChildItem $OutDir | Format-Table Name, Length
}
finally {
  Remove-Item -Recurse -Force $WorkDir -ErrorAction SilentlyContinue
}

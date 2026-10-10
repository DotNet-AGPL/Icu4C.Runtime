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
  $CacheDir = $env:ICU_CACHE_DIR
  $Tgz = Join-Path $WorkDir "icu.tgz"
  if (-not [string]::IsNullOrEmpty($CacheDir)) {
    New-Item -ItemType Directory -Force -Path $CacheDir | Out-Null
    $Tgz = Join-Path $CacheDir $Asset
  }
  if (Test-Path $Tgz) {
    Write-Host "Using cached $Asset"
  } else {
    Write-Host "Downloading ICU $IcuVersion : $Url"
    Invoke-WebRequest -Uri $Url -OutFile $Tgz
  }

  Write-Host "Extracting..."
  tar xzf $Tgz -C $WorkDir
  $Source = Join-Path $WorkDir "icu/source"

  $Solution = Join-Path $Source "allinone/allinone.sln"

  # Locate MSBuild (from VS install) if not on PATH.
  $MSBuild = "msbuild"
  if (-not (Get-Command msbuild -ErrorAction SilentlyContinue)) {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio/Installer/vswhere.exe"
    if (Test-Path $vswhere) {
      $MSBuild = (& $vswhere -latest -requires Microsoft.Component.MSBuild -find "MSBuild/**/Bin/MSBuild.exe" | Select-Object -First 1)
    }
    if ([string]::IsNullOrEmpty($MSBuild)) { throw "MSBuild not found. Install Visual Studio with the C++ toolset." }
  }

  # For non-x64 targets ICU needs x64 host tools (pkgdata/genrb/...) to generate the data DLL,
  # so build the x64 tools first.
  if ($Platform -ne "x64") {
    Write-Host "Pass 1: building x64 host tools (Release|x64) ..."
    & $MSBuild $Solution /m /p:Configuration=Release /p:Platform=x64
    if ($LASTEXITCODE -ne 0) { throw "ICU host-tools build failed (exit $LASTEXITCODE)" }
  }

  Write-Host "Building $Solution ($Platform, Release) ..."
  & $MSBuild $Solution /m /p:Configuration=Release /p:Platform=$Platform
  if ($LASTEXITCODE -ne 0) { throw "ICU build failed (exit $LASTEXITCODE)" }

  New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
  # ICU's Windows build emits DLLs into <workdir>/icu/bin64 (x64), binARM64 (ARM64), bin (Win32).
  $BinDirName = switch ($Platform) {
    "x64"   { "bin64" }
    "ARM64" { "binARM64" }
    "Win32" { "bin" }
    default { "bin$Platform" }
  }
  $BinDir = Join-Path (Join-Path $WorkDir "icu") $BinDirName
  if (-not (Test-Path (Join-Path $BinDir "icuuc$IcuMajor.dll"))) {
    $found = Get-ChildItem -Path (Join-Path $WorkDir "icu") -Directory -Filter "bin*" -ErrorAction SilentlyContinue |
             Where-Object { $_.Name -notmatch 'uwp' } |
             Where-Object { Test-Path (Join-Path $_.FullName "icuuc$IcuMajor.dll") } |
             Select-Object -First 1
    if ($found) { $BinDir = $found.FullName }
  }
  if (-not (Test-Path (Join-Path $BinDir "icuuc$IcuMajor.dll"))) {
    throw "Could not locate built ICU DLLs under $WorkDir"
  }

  foreach ($name in @("icuuc$IcuMajor.dll", "icuin$IcuMajor.dll", "icudt$IcuMajor.dll")) {
    $src = Join-Path $BinDir $name
    if (Test-Path $src) { Copy-Item $src $OutDir -Force }
    else { Write-Warning "Not found: $src" }
  }

  Write-Host "Result:"
  Get-ChildItem $OutDir | Format-Table Name, Length
}
finally {
  Remove-Item -Recurse -Force $WorkDir -ErrorAction SilentlyContinue
}

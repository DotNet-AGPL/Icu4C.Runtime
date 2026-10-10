<#
.SYNOPSIS
  Verify the Icu4C.Runtime Windows packages locally.

.DESCRIPTION
  Publishes and runs the JIT test app in RID-specific and portable (no RID) modes,
  checks the app-local MSVC runtime closure of the output, and optionally runs the
  NativeAOT test (requires the MSVC toolset + Windows SDK).

  Prerequisites: the packages under verification must be available in the local
  "nupkg" feed (see nuget.config).

.PARAMETER Rid
  Windows RID to verify (default: win-x64).

.PARAMETER SkipAot
  Skip the NativeAOT test.

.PARAMETER PackageVersion
  Override the package version (default: Directory.Build.props / IcuPackageVersion).

.EXAMPLE
  ./verify-windows.ps1
  ./verify-windows.ps1 -Rid win-arm64 -SkipAot
#>
[CmdletBinding()]
param(
  [string]$Rid = "win-x64",
  [switch]$SkipAot,
  [string]$PackageVersion
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$PubRoot  = Join-Path $RepoRoot "pub"
$IcuMajor = "77"
$MsvcRuntime = @("msvcp140", "msvcp140_1", "msvcp140_2", "msvcp140_atomic_wait",
                 "msvcp140_codecvt_ids", "vcruntime140", "vcruntime140_1")

$publishArgs = @("-c", "Release")
if ($PackageVersion) { $publishArgs += "-p:IcuPackageVersion=$PackageVersion" }

function Assert-MsvcRuntimeClosure([string]$Dir) {
  $icuDlls = Get-ChildItem $Dir -Recurse -File -Filter "icu*$IcuMajor*.dll" -ErrorAction SilentlyContinue
  if (-not $icuDlls) { Write-Host "  (no ICU dlls under $Dir)"; return }
  $missing = @()
  foreach ($icu in $icuDlls) {
    $ascii = [System.Text.Encoding]::ASCII.GetString([System.IO.File]::ReadAllBytes($icu.FullName)).ToLowerInvariant()
    foreach ($b in $MsvcRuntime) {
      if ($ascii.Contains("$b.dll") -and -not (Test-Path (Join-Path $icu.DirectoryName "$b.dll"))) {
        $missing += "$($icu.Name) in $($icu.DirectoryName) needs $b.dll"
      }
    }
  }
  if ($missing.Count) { throw "MSVC runtime closure FAILED: $($missing -join '; ')" }
  Write-Host "  MSVC runtime closure OK ($($icuDlls.Count) ICU dll(s))"
}

function Invoke-TestApp([string]$Exe, [string]$WorkDir) {
  Write-Host "  running $Exe"
  $p = Start-Process -FilePath $Exe -WorkingDirectory $WorkDir -NoNewWindow -Wait -PassThru
  if ($p.ExitCode -ne 0) { throw "TEST FAILED (exit $($p.ExitCode)): $Exe" }
  Write-Host "  OK"
}

Write-Host "`n### JIT (RID $Rid) ###" -ForegroundColor Cyan
$jitRid = Join-Path $PubRoot "verify-jit-$Rid"
Remove-Item $jitRid -Recurse -Force -ErrorAction SilentlyContinue
& dotnet publish (Join-Path $RepoRoot "tests/IcuJitTest/IcuJitTest.csproj") @publishArgs -r $Rid -o $jitRid
Assert-MsvcRuntimeClosure $jitRid
Invoke-TestApp (Join-Path $jitRid "IcuJitTest.exe") $jitRid

Write-Host "`n### JIT (portable, no RID) ###" -ForegroundColor Cyan
$jitPortable = Join-Path $PubRoot "verify-jit-portable"
Remove-Item $jitPortable -Recurse -Force -ErrorAction SilentlyContinue
& dotnet publish (Join-Path $RepoRoot "tests/IcuJitTest/IcuJitTest.csproj") @publishArgs -o $jitPortable
Assert-MsvcRuntimeClosure $jitPortable
Invoke-TestApp (Join-Path $jitPortable "IcuJitTest.exe") $jitPortable

if (-not $SkipAot) {
  Write-Host "`n### AOT (RID $Rid) ###" -ForegroundColor Cyan
  $aot = Join-Path $PubRoot "verify-aot-$Rid"
  Remove-Item $aot -Recurse -Force -ErrorAction SilentlyContinue
  & dotnet publish (Join-Path $RepoRoot "tests/IcuAotTest/IcuAotTest.csproj") @publishArgs -r $Rid -o $aot
  Assert-MsvcRuntimeClosure $aot
  Invoke-TestApp (Join-Path $aot "IcuAotTest.exe") $aot
}

Write-Host "`nALL WINDOWS CHECKS PASSED" -ForegroundColor Green

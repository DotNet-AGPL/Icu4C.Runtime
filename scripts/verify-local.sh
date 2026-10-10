#!/usr/bin/env bash
#
# Local end-to-end verification using nerdctl (or docker).
#
# Usage: verify-local.sh [RID]
#   RID  linux-x64 (default) | linux-arm64 | ...
#
# Prerequisites: .NET 10 SDK, a container engine with the mcr.microsoft.com images
# available. Uses `nerdctl` if present, otherwise `docker`.
#
# Notes:
# - ICU is loaded at runtime via dlopen, so `ldd | grep icu` will NOT show it.
#   The real check is: (a) the app prints correct globalization output, and
#   (b) for AOT, `readelf -d` shows an $ORIGIN runpath.
# - Optionally hides the system ICU to prove the app-local copy is used.
#
set -euo pipefail

RID="${1:-linux-x64}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

if command -v nerdctl >/dev/null 2>&1; then ENGINE=nerdctl
elif command -v docker >/dev/null 2>&1; then ENGINE=docker
else echo "Need nerdctl or docker" >&2; exit 1; fi

RUNTIME_IMG="mcr.microsoft.com/dotnet/runtime:10.0"
RUNTIME_DEPS_IMG="mcr.microsoft.com/dotnet/runtime-deps:10.0"

echo "=== JIT verification (${RID}) ==="
dotnet publish "${REPO_ROOT}/tests/IcuJitTest/IcuJitTest.csproj" -c Release -r "${RID}" -o "${REPO_ROOT}/pub/jit" >/dev/null
"${ENGINE}" run --rm --entrypoint bash \
  -v "${REPO_ROOT}/pub/jit:/app" -w /app "${RUNTIME_IMG}" -c '
    mv /lib/x86_64-linux-gnu/libicu*.so* /root/ 2>/dev/null || true
    ldconfig 2>/dev/null || true
    ldconfig -p 2>/dev/null | grep -i icu || echo "(no system ICU)"
    ./IcuJitTest
  '

echo ""
echo "=== AOT verification (${RID}) ==="
dotnet publish "${REPO_ROOT}/tests/IcuAotTest/IcuAotTest.csproj" -c Release -r "${RID}" -o "${REPO_ROOT}/pub/aot" >/dev/null

echo "--- runpath check ---"
readelf -d "${REPO_ROOT}/pub/aot/IcuAotTest" | grep -Ei 'RUNPATH|RPATH' || true

echo "--- run (system ICU hidden) ---"
"${ENGINE}" run --rm --entrypoint bash \
  -v "${REPO_ROOT}/pub/aot:/app" -w /app "${RUNTIME_DEPS_IMG}" -c '
    mv /lib/x86_64-linux-gnu/libicu*.so* /root/ 2>/dev/null || true
    ldconfig 2>/dev/null || true
    ldconfig -p 2>/dev/null | grep -i icu || echo "(no system ICU)"
    ./IcuAotTest
  '

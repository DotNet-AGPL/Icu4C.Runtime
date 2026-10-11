#!/usr/bin/env bash
#
# Linux regression guard for Icu4C.Runtime. Run in CI after the 9 packages are built
# (the platform packages are expected under ./nupkg, and a Docker engine is available).
#
#   static : glibc floor (<= 2.28), no libstdc++/libgcc_s dependency, exact inter-library
#            NEEDED names, and an $ORIGIN runpath (the musl-loading fix)
#   native : dlopen the libraries on real distributions without .NET involved
#            (AlmaLinux 8 / glibc 2.28 = exactly the supported floor, Debian 12 / glibc 2.36,
#            Alpine 3.20 / musl)
#   runtime: JIT (linux-x64, linux-musl-x64) and AOT (linux-x64) in the official .NET images
#            with the system ICU hidden
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"
ENGINE="${ENGINE:-docker}"
NUPKG_DIR="${NUPKG_DIR:-nupkg}"
VER="$(sed -n 's/.*<IcuPackageVersion[^>]*>\([^<]*\)<.*/\1/p' Directory.Build.props | head -1)"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
say() { printf '\n=== %s ===\n' "$*"; }

say "unpack Linux packages (version ${VER})"
for rid in linux-x64 linux-arm64 linux-musl-x64 linux-musl-arm64; do
  unzip -oq "${NUPKG_DIR}"/Icu4C.Runtime."${rid}".*.nupkg -d "${STAGE}/${rid}"
done
ICUVER="$(ls "${STAGE}/linux-x64/runtimes/linux-x64/native"/libicuuc.so.* | sed 's/.*libicuuc\.so\.//')"

say "static checks (floor / NEEDED / rpath)"
fail=0
for rid in linux-x64 linux-arm64 linux-musl-x64 linux-musl-arm64; do
  nat="${STAGE}/${rid}/runtimes/${rid}/native"
  u="${nat}/libicuuc.so.${ICUVER}"; i="${nat}/libicui18n.so.${ICUVER}"; d="${nat}/libicudata.so.${ICUVER}"
  for f in "${u}" "${i}" "${d}"; do
    if readelf -d "${f}" | grep -qE 'NEEDED.*libstdc\+\+'; then echo "FAIL ${f} needs libstdc++"; fail=1; fi
    if readelf -d "${f}" | grep -qE 'NEEDED.*libgcc_s';    then echo "FAIL ${f} needs libgcc_s"; fail=1; fi
  done
  if ! readelf -d "${u}" | grep -q "libicudata.so.${ICUVER}"; then echo "FAIL ${u}: NEEDED != libicudata.so.${ICUVER}"; fail=1; fi
  if ! readelf -d "${i}" | grep -q "libicuuc.so.${ICUVER}";   then echo "FAIL ${i}: NEEDED != libicuuc.so.${ICUVER}";   fail=1; fi
  if ! readelf -d "${u}" | grep -qE 'RUNPATH.*\$ORIGIN';      then echo "FAIL ${u}: no \$ORIGIN runpath";                fail=1; fi
  case "${rid}" in linux-x64|linux-arm64)
    for f in "${u}" "${i}"; do
      max="$(readelf -V "${f}" | grep -oE 'GLIBC_2\.[0-9]+' | sort -uV | tail -1)"
      [ -z "${max}" ] && continue
      if [ "$(printf '%s\nGLIBC_2.28\n' "${max}" | sort -V | tail -1)" != "GLIBC_2.28" ]; then
        echo "FAIL ${f} requires ${max} (> GLIBC_2.28)"; fail=1
      fi
    done ;;
  esac
done
if [ "${fail}" -ne 0 ]; then echo "static checks FAILED"; exit 1; fi
echo "static checks OK (glibc <= 2.28, no C++ runtime deps, exact NEEDED + \$ORIGIN)"

say "native-distro dlopen checks (no .NET)"
dlopen_native() { # <image> <rid> <install-cmd>
  local image="$1" rid="$2" install="$3"
  printf -- '-- %s on %s\n' "${rid}" "${image}"
  "${ENGINE}" run --rm -v "${REPO_ROOT}:/repo:ro" -v "${STAGE}:/pkg:ro" "${image}" sh -c "
    ${install} >/dev/null 2>&1
    python3 /repo/scripts/dlopen-check.py /pkg/${rid}/runtimes/${rid}/native ${ICUVER}
  "
}
dlopen_native almalinux:8  linux-x64      "dnf install -y python3"
dlopen_native debian:12    linux-x64      "apt-get update -qq && apt-get install -y -qq python3"
dlopen_native alpine:3.20  linux-musl-x64 "apk add --no-cache python3"

hide_system_icu='for d in /usr/lib/x86_64-linux-gnu /usr/lib /lib/x86_64-linux-gnu; do [ -d "$d" ] && find "$d" -maxdepth 1 -name "libicu*.so*" -exec mv -t /root {} + 2>/dev/null; done; command -v ldconfig >/dev/null && ldconfig 2>/dev/null; echo "system icu: $(ldconfig -p 2>/dev/null | grep -ci icu) entries"'

say "JIT: linux-x64"
dotnet publish tests/IcuJitTest/IcuJitTest.csproj -c Release -r linux-x64 -p:IcuPackageVersion="${VER}" -o pub/ci-jit-x64 >/dev/null
"${ENGINE}" run --rm --entrypoint sh -v "${PWD}/pub/ci-jit-x64:/app" -w /app mcr.microsoft.com/dotnet/runtime:10.0 \
  -c "${hide_system_icu}; ./IcuJitTest"

say "JIT: linux-musl-x64"
dotnet publish tests/IcuJitTest/IcuJitTest.csproj -c Release -r linux-musl-x64 -p:IcuPackageVersion="${VER}" -o pub/ci-jit-musl >/dev/null
"${ENGINE}" run --rm -e DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=false --entrypoint sh \
  -v "${PWD}/pub/ci-jit-musl:/app" -w /app mcr.microsoft.com/dotnet/runtime:10.0-alpine -c './IcuJitTest'

say "AOT: linux-x64"
sudo apt-get update -qq
sudo apt-get install -y -qq clang zlib1g-dev
dotnet publish tests/IcuAotTest/IcuAotTest.csproj -c Release -r linux-x64 -p:IcuPackageVersion="${VER}" -o pub/ci-aot-x64 >/dev/null
"${ENGINE}" run --rm --entrypoint sh -v "${PWD}/pub/ci-aot-x64:/app" -w /app mcr.microsoft.com/dotnet/runtime-deps:10.0 \
  -c "${hide_system_icu}; ./IcuAotTest"

echo ""
echo "ALL LINUX CHECKS PASSED"

#!/usr/bin/env bash
#
# Build ICU4C for a macOS RID and stage the dylibs under runtimes/<rid>/native/.
# Must be run on macOS.
#
# Usage: build-icu-macos.sh [ICU_VERSION] [RID]
#   ICU_VERSION  e.g. 77.1    (default: 77.1)
#   RID          osx-x64 | osx-arm64  (default: osx-arm64)
#
# Environment:
#   ICU_GH_PROXY  GitHub proxy prefix (default: none on macOS runners)
#
# Notes:
# - .NET AppLocalIcu expects libicuuc.<version>.dylib / libicui18n.<version>.dylib /
#   libicudata.<version>.dylib (version in the middle of the name).
# - libicudata is NOT preloaded on macOS, so each dylib's dependency install-names
#   are rewritten to @loader_path/<basename> with install_name_tool.
#
set -euo pipefail

if [ "$(uname -s)" != "Darwin" ]; then
  echo "build-icu-macos.sh must run on macOS" >&2
  exit 1
fi

ICU_VERSION="${1:-77.1}"
RID="${2:-osx-arm64}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
OUT_DIR="${REPO_ROOT}/runtimes/${RID}/native"

ICU_GH_PROXY="${ICU_GH_PROXY:-}"
ICU_MAJOR="${ICU_VERSION%%.*}"
TAG="release-$(echo "${ICU_VERSION}" | tr '.' '-')"
ASSET="icu4c-$(echo "${ICU_VERSION}" | tr '.' '_')-src.tgz"
GH_PATH="unicode-org/icu/releases/download/${TAG}/${ASSET}"
if [ -z "${ICU_GH_PROXY}" ] || [ "${ICU_GH_PROXY}" = "-" ]; then
  URL="https://github.com/${GH_PATH}"
else
  URL="${ICU_GH_PROXY%/}/https://github.com/${GH_PATH}"
fi

case "${RID}" in
  osx-x64)   ARCH_FLAGS=(-arch x86_64) ;;
  osx-arm64) ARCH_FLAGS=(-arch arm64) ;;
  *) echo "Unsupported RID for build-icu-macos.sh: ${RID}" >&2; exit 1 ;;
esac

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "${WORK_DIR}"' EXIT

# Optional download cache (ICU_CACHE_DIR) to reuse the source tarball across runs.
CACHE_DIR="${ICU_CACHE_DIR:-}"
TGZ="${WORK_DIR}/icu.tgz"
if [ -n "${CACHE_DIR}" ]; then
  mkdir -p "${CACHE_DIR}"
  TGZ="${CACHE_DIR}/${ASSET}"
fi

if [ -f "${TGZ}" ]; then
  echo "Using cached ${ASSET}"
else
  echo "Downloading ICU ${ICU_VERSION}: ${URL}"
  curl -fsSL --retry 3 -o "${TGZ}" "${URL}"
fi
tar xzf "${TGZ}" -C "${WORK_DIR}"
cd "${WORK_DIR}/icu/source"

export CFLAGS="${CFLAGS:-} ${ARCH_FLAGS[*]}"
export CXXFLAGS="${CXXFLAGS:-} ${ARCH_FLAGS[*]}"
export LDFLAGS="${LDFLAGS:-} ${ARCH_FLAGS[*]}"

./runConfigureICU MacOSX --with-data-packaging=dll --disable-samples --disable-tests
make -j"$(sysctl -n hw.ncpu)"

mkdir -p "${OUT_DIR}"
for lib in libicuuc libicui18n libicudata; do
  # Real dylib is libicu<name>.<major>.<minor>.dylib
  cp -a lib/${lib}.${ICU_VERSION}.dylib "${OUT_DIR}/" 2>/dev/null || \
    cp -a lib/${lib}.${ICU_MAJOR}.*.dylib "${OUT_DIR}/"
done

# Rewrite inter-library dependencies to @loader_path so they resolve next to the app.
# On macOS AppLocalIcu does not preload libicudata, so install names must be self-contained.
shopt -s nullglob
for target in "${OUT_DIR}"/libicu*.dylib; do
  while IFS= read -r dylibpath; do
    dep="$(basename "${dylibpath}")"
    case "${dep}" in
      libicuuc.*.dylib|libicui18n.*.dylib|libicudata.*.dylib) ;;
      *) continue ;;
    esac
    if [ -e "${OUT_DIR}/${dep}" ]; then
      install_name_tool -change "${dylibpath}" "@loader_path/${dep}" "${target}"
    fi
  done < <(otool -L "${target}" | awk 'NR>1 {print $1}')
done
shopt -u nullglob

echo "Built ICU ${ICU_VERSION} for ${RID}:"
ls -lh "${OUT_DIR}"

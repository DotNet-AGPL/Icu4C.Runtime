#!/usr/bin/env bash
#
# Build ICU4C from source for a Linux RID (glibc or musl) and stage the shared
# libraries under runtimes/<rid>/native/.
#
# Usage: build-icu-linux.sh [ICU_VERSION] [RID]
#   ICU_VERSION  e.g. 77.1           (default: 77.1)
#   RID          linux-x64 | linux-arm64 | linux-musl-x64 | linux-musl-arm64
#
# Environment:
#   ICU_GH_PROXY  GitHub proxy prefix for downloading sources (default: https://ghfast.top)
#                 (set to "-" to download directly from github.com)
#
# Cross compilation: ICU requires a native build tree for its build tools, so for
# a non-native RID this script builds natively first and then configures the cross
# build with --with-cross-build. (On an arm64 host the arm64 targets build natively.)
#
set -euo pipefail

ICU_VERSION="${1:-77.1}"
RID="${2:-linux-x64}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
OUT_DIR="${REPO_ROOT}/runtimes/${RID}/native"

ICU_GH_PROXY="${ICU_GH_PROXY:-https://ghfast.top}"
ICU_MAJOR="${ICU_VERSION%%.*}"
TAG="release-$(echo "${ICU_VERSION}" | tr '.' '-')"
ASSET="icu4c-$(echo "${ICU_VERSION}" | tr '.' '_')-src.tgz"
GH_PATH="unicode-org/icu/releases/download/${TAG}/${ASSET}"

case "${ICU_GH_PROXY}" in
  ""|-|none) URL="https://github.com/${GH_PATH}" ;;
  *)         URL="${ICU_GH_PROXY%/}/https://github.com/${GH_PATH}" ;;
esac

case "${RID}" in
  linux-x64)        CROSS_TRIPLET="x86_64-linux-gnu" ;;
  linux-arm64)      CROSS_TRIPLET="aarch64-linux-gnu" ;;
  linux-musl-x64)   CROSS_TRIPLET="x86_64-linux-musl" ;;
  linux-musl-arm64) CROSS_TRIPLET="aarch64-linux-musl" ;;
  *) echo "Unsupported RID for build-icu-linux.sh: ${RID}" >&2; exit 1 ;;
esac

is_native() {
  case "${CROSS_TRIPLET}-$(uname -m)" in
    x86_64-linux-gnu-x86_64|x86_64-linux-musl-x86_64) return 0 ;;
    aarch64-linux-gnu-aarch64|aarch64-linux-musl-aarch64) return 0 ;;
    *) return 1 ;;
  esac
}

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
SOURCE="${WORK_DIR}/icu/source"

CONFIGURE_ARGS=(--with-data-packaging=dll --disable-samples --disable-tests)

# Statically link the C++ runtime so the shared libraries do not depend on the host's
# libstdc++.so.6 / libgcc_s.so.1 (the Linux analogue of bundling the VC++ runtime on
# Windows). Combined with building inside an older baseline container this keeps the
# glibc + GLIBCXX version floor low, so the libraries load on older distros too.
export LDFLAGS="${LDFLAGS:-} -static-libstdc++ -static-libgcc"

if is_native; then
  BUILD_DIR="${WORK_DIR}/build"
  mkdir -p "${BUILD_DIR}"
  cd "${BUILD_DIR}"
  "${SOURCE}/runConfigureICU" Linux "${CONFIGURE_ARGS[@]}"
  make -j"$(nproc)"
else
  # Stage 1: native build (provides the cross-build tools/data).
  NATIVE_BUILD="${WORK_DIR}/build-native"
  mkdir -p "${NATIVE_BUILD}"
  (
    cd "${NATIVE_BUILD}"
    "${SOURCE}/runConfigureICU" Linux --disable-samples --disable-tests
    make -j"$(nproc)"
  )

  # Stage 2: cross build.
  BUILD_DIR="${WORK_DIR}/build-cross"
  mkdir -p "${BUILD_DIR}"
  cd "${BUILD_DIR}"
  export CC="${CROSS_TRIPLET}-gcc"
  export CXX="${CROSS_TRIPLET}-g++"
  export AR="${CROSS_TRIPLET}-ar"
  export RANLIB="${CROSS_TRIPLET}-ranlib"
  "${SOURCE}/configure" --host="${CROSS_TRIPLET}" \
    --with-cross-build="${NATIVE_BUILD}" "${CONFIGURE_ARGS[@]}"
  make -j"$(nproc)"
fi

mkdir -p "${OUT_DIR}"
rm -f "${OUT_DIR}"/libicu*.so.* "${OUT_DIR}"/libicu*.dylib "${OUT_DIR}"/icu*.dll
for lib in libicuuc libicui18n libicudata; do
  cp -a "${BUILD_DIR}/lib/${lib}.so.${ICU_MAJOR}"* "${OUT_DIR}/" 2>/dev/null || \
    cp -a "${BUILD_DIR}/lib/${lib}.so."* "${OUT_DIR}/"
done

# Keep only real files (drop symlinks) and only the three runtime libraries.
find "${OUT_DIR}" -type l -delete
find "${OUT_DIR}" -maxdepth 1 -type f \
  ! -name 'libicuuc.so.*' ! -name 'libicui18n.so.*' ! -name 'libicudata.so.*' -delete

# Make the libraries self-contained within their own directory. AppLocalIcu loads the
# libraries by their exact file name (libicu*.so.<ver>), and some loaders (notably musl)
# do NOT resolve a NEEDED "libicudata.so.<major>" from an already-loaded
# "libicudata.so.<ver>". So reference siblings by the exact shipped file name and add an
# $ORIGIN rpath so they resolve next to each other (works on glibc and musl alike).
if ! command -v patchelf >/dev/null 2>&1; then
  echo "ERROR: patchelf is required to fix inter-library NEEDED names." >&2
  exit 1
fi
for lib in libicuuc libicui18n libicudata; do
  f="${OUT_DIR}/${lib}.so.${ICU_VERSION}"
  [ -f "${f}" ] || continue
  patchelf --set-soname "${lib}.so.${ICU_VERSION}" "${f}"
  patchelf --replace-needed "libicudata.so.${ICU_MAJOR}" "libicudata.so.${ICU_VERSION}" "${f}" || true
  patchelf --replace-needed "libicuuc.so.${ICU_MAJOR}"   "libicuuc.so.${ICU_VERSION}"   "${f}" || true
  patchelf --set-rpath '$ORIGIN' "${f}"
done

echo "Built ICU ${ICU_VERSION} for ${RID}:"
ls -lh "${OUT_DIR}"

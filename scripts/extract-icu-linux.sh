#!/usr/bin/env bash
#
# Quick extraction of ICU runtime libraries from an Ubuntu container image,
# for local validation only (not for release; use build-icu-linux.sh instead).
#
# Usage: extract-icu-linux.sh [RID] [UBUNTU_VERSION] [ICU_PACKAGE]
#   RID             linux-x64 | linux-arm64        (default: linux-x64)
#   UBUNTU_VERSION  24.04                          (default: 24.04)
#   ICU_PACKAGE     libicu74                       (default: libicu74)
#
# Notes:
# - Only libicuuc / libicui18n / libicudata are kept.
# - Symlinks are dropped; the real files (e.g. libicuuc.so.74.2) are kept.
# - Container apt uses the Tsinghua mirror (override with APT_MIRROR).
#
set -euo pipefail

RID="${1:-linux-x64}"
UBUNTU_VERSION="${2:-24.04}"
ICU_PKG="${3:-libicu74}"
APT_MIRROR="${APT_MIRROR:-mirrors.tuna.tsinghua.edu.cn}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
OUT_DIR="${REPO_ROOT}/runtimes/${RID}/native"
mkdir -p "${OUT_DIR}"

case "${RID}" in
  linux-x64)   ARCH_DIR="x86_64-linux-gnu"; CONTAINER_ARCH="" ;;
  linux-arm64) ARCH_DIR="aarch64-linux-gnu"; CONTAINER_ARCH="--platform linux/arm64" ;;
  *) echo "Unsupported RID for extract-icu-linux.sh: ${RID}" >&2; exit 1 ;;
esac

IMAGE="${ICU_BASE_IMAGE:-ubuntu:${UBUNTU_VERSION}}"

echo "Extracting ICU from ${IMAGE} (${ICU_PKG}) -> ${OUT_DIR}"
nerdctl run --rm ${CONTAINER_ARCH} -v "${OUT_DIR}:/out" "${IMAGE}" bash -c "
  set -e
  for f in /etc/apt/sources.list.d/ubuntu.sources /etc/apt/sources.list; do
    if [ -f \"\$f\" ]; then
      sed -i 's|https\\?://archive.ubuntu.com|http://${APT_MIRROR}|g; s|https\\?://security.ubuntu.com|http://${APT_MIRROR}|g' \"\$f\"
    fi
  done
  apt-get update -qq
  apt-get install -y -qq ${ICU_PKG}
  cp -a /usr/lib/${ARCH_DIR}/libicuuc.so*   /out/
  cp -a /usr/lib/${ARCH_DIR}/libicui18n.so* /out/
  cp -a /usr/lib/${ARCH_DIR}/libicudata.so* /out/
  find /out -type l -delete
  ls -l /out
"

echo "Result:"
ls -lh "${OUT_DIR}"

#!/usr/bin/env bash
# 02_setup_toolchain.sh — clang r596125 + kernel build-tools
set -euo pipefail
source "$(dirname "$0")/common.sh"

CLANG_VER="$(cfg toolchain.clang_version)"

if [ -x "$CLANG_DIR/bin/clang" ]; then
  log "clang already present: $CLANG_DIR"
else
  mkdir -p "$CLANG_DIR"
  log "fetching clang $CLANG_VER (android-17.0.0_r1)..."
  fetch_retry "https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/tags/android-17.0.0_r1/clang-r596125.tar.gz" \
    "$OUT_DIR/clang.tar.gz"
  tar -xzf "$OUT_DIR/clang.tar.gz" -C "$CLANG_DIR"
  log "clang extracted: $($CLANG_DIR/bin/clang --version | head -1)"
fi

if [ -d "$BUILD_TOOLS/bin" ]; then
  log "build-tools already present: $BUILD_TOOLS"
else
  log "fetching kernel build-tools (main-kernel-2025)..."
  fetch_retry "https://android.googlesource.com/kernel/prebuilts/build-tools/+archive/refs/heads/main-kernel-2025/linux-x86.tar.gz" \
    "$OUT_DIR/build-tools.tar.gz"
  mkdir -p "$BUILD_TOOLS"
  tar -xzf "$OUT_DIR/build-tools.tar.gz" -C "$BUILD_TOOLS"
  log "build-tools ready"
fi

env_put PATH "$CLANG_DIR/bin:$BUILD_TOOLS/bin:$PATH"

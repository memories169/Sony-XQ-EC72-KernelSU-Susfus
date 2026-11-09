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
  # large tarball (~1.1GB): fetch with retries, then VERIFY gzip integrity before extract
  local_ok=""
  for i in 1 2 3 4 5; do
    curl -fL --connect-timeout 30 --retry 3 --retry-delay 5 -C - \
      "https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/tags/android-17.0.0_r1/clang-r596125.tar.gz" \
      -o "$OUT_DIR/clang.tar.gz" && { log "download OK (attempt $i)"; local_ok=1; break; }
    warn "clang download attempt $i failed; retrying"
    sleep 10
  done
  [ -n "$local_ok" ] || die "clang download failed after retries"
  for i in 1 2 3; do
    if gzip -t "$OUT_DIR/clang.tar.gz" 2>/dev/null; then local_ok=1; break; fi
    warn "clang.tar.gz corrupt (attempt $i), re-downloading"
    rm -f "$OUT_DIR/clang.tar.gz"
    curl -fL --connect-timeout 30 --retry 3 \
      "https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/tags/android-17.0.0_r1/clang-r596125.tar.gz" \
      -o "$OUT_DIR/clang.tar.gz"
  done
  gzip -t "$OUT_DIR/clang.tar.gz" || die "clang.tar.gz still corrupt after re-fetch"
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

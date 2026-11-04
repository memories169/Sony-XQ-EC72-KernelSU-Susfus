#!/usr/bin/env bash
# Fetch the exact toolchain LineageOS used for this nightly:
#   clang-r596125  (from platform/prebuilts/clang/host/linux-x86, tag android-17.0.0_r1)
#   kernel-build-tools (kernel/prebuilts/build-tools, branch main-kernel-2025)
# Both are pulled as googlesource per-directory archives (no giant git clone).
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

[ -f "$ENV_FILE" ] && source "$ENV_FILE"

CLANG_REPO="$(cfg .toolchain.clang_repo)"
CLANG_REF="$(cfg .toolchain.clang_ref)"
CLANG_VER="$(cfg .toolchain.clang_version)"
BT_REPO="$(cfg .toolchain.build_tools_repo)"
BT_BRANCH="$(cfg .toolchain.build_tools_branch)"

CLANG_DIR="clang-$CLANG_VER"
CLANG_HOME="$PREBUILTS/clang/host/linux-x86/$CLANG_DIR"
BT_HOME="$PREBUILTS/kernel-build-tools/linux-x86"

mkdir -p "$PREBUILTS" "$OUT_DIR"

if [ ! -x "$CLANG_HOME/bin/clang" ]; then
  log "Downloading clang-$CLANG_VER archive (~150 MB compressed)"
  rm -rf "$PREBUILTS/clang"; mkdir -p "$PREBUILTS/clang/host/linux-x86"
  fetch_retry curl -fL --retry 3 --max-time 3600 \
    "$CLANG_REPO/+archive/$CLANG_REF/$CLANG_DIR.tar.gz" \
    -o "$PREBUILTS/clang-$CLANG_VER.tar.gz"
  mkdir -p "$CLANG_HOME"
  tar -xzf "$PREBUILTS/clang-$CLANG_VER.tar.gz" -C "$CLANG_HOME"
  rm -f "$PREBUILTS/clang-$CLANG_VER.tar.gz"
fi
chmod +x "$CLANG_HOME/bin/"* 2>/dev/null || true

if [ ! -x "$BT_HOME/bin/pahole" ] && [ ! -d "$BT_HOME/bin" ]; then
  log "Downloading kernel-build-tools archive"
  rm -rf "$PREBUILTS/kernel-build-tools"; mkdir -p "$PREBUILTS/kernel-build-tools"
  fetch_retry curl -fL --retry 3 --max-time 3600 \
    "$BT_REPO/+archive/refs/heads/$BT_BRANCH/linux-x86.tar.gz" \
    -o "$PREBUILTS/build-tools.tar.gz"
  mkdir -p "$BT_HOME"
  tar -xzf "$PREBUILTS/build-tools.tar.gz" -C "$BT_HOME"
  rm -f "$PREBUILTS/build-tools.tar.gz"
fi
chmod +x "$BT_HOME/bin/"* 2>/dev/null || true

"$CLANG_HOME/bin/clang" --version | head -1 | tee "$OUT_DIR/clang-version.txt"
case "$("$CLANG_HOME/bin/clang" --version)" in
  *"$CLANG_VER"*) log "clang matches $CLANG_VER ✔" ;;
  *) log "WARNING: clang version string does not mention $CLANG_VER" ;;
esac

export PATH="$CLANG_HOME/bin:$BT_HOME/bin:$PATH"
env_put CLANG_HOME "$CLANG_HOME"
env_put BT_HOME "$BT_HOME"
env_put PATH "$PATH"
log "toolchain ready"

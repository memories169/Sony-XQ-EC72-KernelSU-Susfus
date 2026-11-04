#!/usr/bin/env bash
# Shared helpers for Xm6_KernelSU_SUSFS build scripts.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

export WORKSPACE="${WORKSPACE:-$REPO_DIR}"
export DEVICE_CONFIG="${DEVICE_CONFIG:-$REPO_DIR/configs/pdx245.json}"

export DOWNLOADS="$WORKSPACE/downloads"
export OUT_DIR="$WORKSPACE/out"
export DIST_DIR="$WORKSPACE/dist"
export KERNEL_SRC="$WORKSPACE/kernel-src"
export KSU_DIR="$WORKSPACE/KernelSU"
export SUSFS_DIR="$WORKSPACE/susfs4ksu"
export AK3_DIR="$WORKSPACE/AnyKernel3"
export PREBUILTS="$WORKSPACE/prebuilts"
export ENV_FILE="${ENV_FILE:-$OUT_DIR/env.sh}"

cfg() {
  # cfg '.device.kernel_commit' [default]
  python3 - "$DEVICE_CONFIG" "$1" "${2:-}" <<'PY'
import json, sys
conf, path, default = sys.argv[1], sys.argv[2], sys.argv[3]
d = json.load(open(conf))
for part in path.lstrip('.').split('.'):
    if part == '':
        continue
    d = d[part]
if isinstance(d, (list, dict)):
    print(json.dumps(d))
else:
    print('' if d is None else d)
PY
}

log() { echo -e "\033[1;36m[Xm6]\033[0m $*"; }
die() { echo -e "\033[1;31m[Xm6][ERROR]\033[0m $*" >&2; exit 1; }

fetch_retry() {
  local n=0 max=5
  until "$@"; do
    n=$((n + 1))
    [ "$n" -ge "$max" ] && return 1
    log "retry $n/$max: $*"
    sleep 5
  done
}

# Write KEY=value into the shared env file (sourced by later stages / CI).
env_put() {
  local key="$1" val="$2"
  mkdir -p "$(dirname "$ENV_FILE")"
  grep -v "^export $key=" "$ENV_FILE" > "$ENV_FILE.tmp" 2>/dev/null || true
  echo "export $key='$val'" >> "$ENV_FILE.tmp"
  mv "$ENV_FILE.tmp" "$ENV_FILE"
  export "$key=$val"
}

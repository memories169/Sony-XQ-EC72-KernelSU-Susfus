#!/usr/bin/env bash
# common.sh — shared environment + logging for Xm6 build pipeline
set -euo pipefail

# Repo root = parent of scripts/
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

WORKSPACE="${XM6_WORKSPACE:-$REPO_ROOT}"
DOWNLOADS="$WORKSPACE/downloads"
OUT_DIR="$WORKSPACE/out"
DIST_DIR="$WORKSPACE/dist"
KERNEL_SRC="$WORKSPACE/kernel-src"
KSU_DIR="$WORKSPACE/KernelSU"
SUSFS_DIR="$WORKSPACE/susfs4ksu"
AK3_DIR="$WORKSPACE/AnyKernel3"
CLANG_DIR="$WORKSPACE/prebuilts/clang/host/linux-x86/clang-r596125"
BUILD_TOOLS="$WORKSPACE/prebuilts/build-tools"
ENV_FILE="$OUT_DIR/env.sh"

mkdir -p "$DOWNLOADS" "$OUT_DIR" "$DIST_DIR"

log()  { printf '\033[1;34m[xm6]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[xm6-warn]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[xm6-ERROR]\033[0m %s\n' "$*" >&2; exit 1; }

cfg() {
  # cfg <path.into.json> [file]
  local path="$1" file="${2:-$REPO_ROOT/configs/pdx245.json}"
  python3 -c "
import json,sys
d=json.load(open('$file'))
for k in '$path'.split('.'):
    d=d[k]
print(d if not isinstance(d,(list,dict)) else json.dumps(d))
" 2>/dev/null || die "cfg: cannot resolve '$path' in $file"
}

fetch_retry() {
  local url="$1" out="$2" tries="${3:-3}" code=0
  for i in $(seq 1 "$tries"); do
    if curl -sfL --connect-timeout 30 --retry 2 "$url" -o "$out"; then return 0; fi
    code=$?
    warn "fetch attempt $i/$tries failed (exit $code): $url"
    sleep $((i * 5))
  done
  die "failed to fetch after $tries attempts: $url"
}

env_put() {
  # persist a K=V into ENV_FILE for later steps + exports now
  # value-safe: single-quote with '\'' escaping so any content round-trips
  local k="$1" v="$2" q
  q="${v//\'/\'\\\'\'}"
  export "$k=$v"
  mkdir -p "$(dirname "$ENV_FILE")"
  grep -v "^export $k=" "$ENV_FILE" 2>/dev/null > "$ENV_FILE.tmp" || true
  printf "export %s='%s'\n" "$k" "$q" >> "$ENV_FILE.tmp"
  mv "$ENV_FILE.tmp" "$ENV_FILE"
  # GitHub Actions: propagate to subsequent steps
  if [ -n "${GITHUB_ENV:-}" ] && [ "$k" != "PATH" ]; then
    echo "$k=$v" >> "$GITHUB_ENV"
  fi
  if [ -n "${GITHUB_PATH:-}" ] && [ "$k" = "PATH" ]; then
    # GITHUB_PATH wants one directory per line; skip standard dirs
    local d
    IFS=':' read -ra DIRS <<< "$v"
    for d in "${DIRS[@]}"; do
      case "$d" in
        /usr/local/sbin|/usr/local/bin|/usr/sbin|/usr/bin|/sbin|/bin|/snap/bin) ;;
        '') ;;
        *) echo "$d" >> "$GITHUB_PATH" ;;
      esac
    done
  fi
}

# auto-load persisted env from previous steps (each CI step is a fresh shell)
if [ -f "$ENV_FILE" ]; then
  # shellcheck disable=SC1090
  . "$ENV_FILE"
fi

require_tools() {
  local t
  for t in "$@"; do
    command -v "$t" >/dev/null || die "missing tool: $t"
  done
}

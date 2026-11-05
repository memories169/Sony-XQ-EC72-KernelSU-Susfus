#!/usr/bin/env bash
# Fetch the newest LineageOS boot.img (+ build-manifest.xml) for the device,
# verify it, and record everything later stages need into $ENV_FILE:
#   NIGHTLY_VERSION, EXPECTED_RELEASE, STOCK_KERNEL_COMMIT, KERNEL_SRC_REPO...
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

API_URL="$(cfg .bootimg.api_url)"
SRC_REPO="$(cfg .device.kernel_source)"

mkdir -p "$DOWNLOADS" "$OUT_DIR"

log "Querying LineageOS API: $API_URL"
fetch_retry curl -fsSL --retry 3 --max-time 120 "$API_URL" -o "$DOWNLOADS/builds.json"

python3 - "$DOWNLOADS/builds.json" "$DOWNLOADS" <<'PY'
import json, os, sys, urllib.request
builds, outdir = json.load(open(sys.argv[1])), sys.argv[2]
if not isinstance(builds, list) or not builds:
    sys.exit("API returned no builds")
b = builds[0]
files = {f["filename"]: f for f in b["files"]}
need = []
for name in ("boot.img", "build-manifest.xml"):
    f = files.get(name)
    if not f:
        sys.exit(f"build has no {name}")
    need.append((name, f))
for name, f in need:
    url = f["url"]
    dst = os.path.join(outdir, name)
    print(f"downloading {url}")
    urllib.request.urlretrieve(url, dst)
    import hashlib
    h = hashlib.sha256(open(dst, 'rb').read()).hexdigest()
    assert h == f["sha256"], f"{name} sha256 mismatch: {h} != {f['sha256']}"
    print(f"  {name} ok sha256={h[:16]}...")
with open(os.path.join(outdir, "bootinfo.env"), "w") as o:
    o.write(f"NIGHTLY_VERSION=lineage-{b['version']}-{b['date']}-nightly\n")
    o.write(f"BOOT_SHA256={files['boot.img']['sha256']}\n")
PY

log "Resolving kernel source revision from build-manifest.xml"
python3 - "$DOWNLOADS/build-manifest.xml" "$SRC_REPO" > "$DOWNLOADS/kernelsrc.env" <<'PY'
import sys, xml.etree.ElementTree as ET
repo, want = sys.argv[1], sys.argv[2]
for p in ET.parse(repo).getroot().findall('project'):
    if p.get('name','').endswith(want.split('/')[-1]):
        print(f"MANIFEST_REV={p.get('revision')}")
        print(f"SRC_PROJECT={p.get('name')}")
        break
PY
source "$DOWNLOADS/kernelsrc.env"
[ -n "${MANIFEST_REV:-}" ] || die "kernel project $SRC_REPO not found in manifest"

log "Extracting kernel release + clang banner from stock boot.img"
EXPECTED_RELEASE=$(strings "$DOWNLOADS/boot.img" | grep -m1 -oE 'Linux version [0-9]+\.[0-9]+\.[0-9]+-g[0-9a-f]+[^ ]*' | awk '{print $3}')
CLANG_BANNER=$(strings "$DOWNLOADS/boot.img" | grep -m1 -oE 'Android \(Android 6156408[^)]*\) clang version [0-9.]+.*' | head -1) || true
[ -n "$EXPECTED_RELEASE" ] || die "could not extract 'Linux version' string from stock boot.img"
log "stock kernelrelease: $EXPECTED_RELEASE"

# The -g<hash> part must equal the first 12 chars of the source commit; assert it.
case "$EXPECTED_RELEASE" in
  *"g${MANIFEST_REV:0:12}"*) log "manifest revision matches boot.img scm hash ✔" ;;
  *)
    log "WARNING: boot.img release $EXPECTED_RELEASE != manifest rev ${MANIFEST_REV:0:12}; tracking boot.img"
    MANIFEST_REV=$(echo "$EXPECTED_RELEASE" | grep -oE 'g[0-9a-f]{12}' | cut -c2-)
    ;;
esac

env_put NIGHTLY_VERSION "$(grep NIGHTLY_VERSION "$DOWNLOADS"/bootinfo.env | cut -d= -f2)"
env_put BOOT_SHA256 "$(grep BOOT_SHA256 "$DOWNLOADS"/bootinfo.env | cut -d= -f2)"
env_put EXPECTED_RELEASE "$EXPECTED_RELEASE"
env_put STOCK_KERNEL_COMMIT "$MANIFEST_REV"
env_put KERNEL_SRC_REPO "$SRC_PROJECT"
env_put CLANG_BANNER "$CLANG_BANNER"

# unpack stock boot.img now: its embedded Image carries the EXACT LineageOS
# .config (IKCONFIG) which later stages reuse as build base
python3 "$REPO_DIR/tools/mkbootimg/unpack_bootimg.py" --boot_img "$DOWNLOADS/boot.img" \
  --out "$OUT_DIR/stock" --format mkbootimg > "$OUT_DIR/stock_mkbootimg_args.txt"
env_put STOCK_KERNEL "$OUT_DIR/stock/kernel"
log "stock kernel blob unpacked for config extraction"
log "boot.img ready ($NIGHTLY_VERSION, release $EXPECTED_RELEASE)"

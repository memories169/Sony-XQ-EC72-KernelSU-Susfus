#!/usr/bin/env bash
# 01_fetch_bootimg.sh — fetch latest LOS nightly boot.img, extract stock kernel
# + embedded AVB params (salt / rollback / props / key) for the re-sign step.
set -euo pipefail
source "$(dirname "$0")/common.sh"

require_tools curl python3 sha256sum

API_URL="$(cfg bootimg.api_url)"
WANT_NAME="$(cfg bootimg.filename)"

log "querying LOS API: $API_URL"
fetch_retry "$API_URL" "$OUT_DIR/los-builds.json"

python3 - "$OUT_DIR/los-builds.json" "$OUT_DIR/los-pick.json" <<'PY'
import json, sys
builds = json.load(open(sys.argv[1]))
pick = nightly = None
for b in builds:  # newest first
    for f in b.get('files', []):
        if f.get('filename') == 'boot.img':
            pick, nightly = f, b['files'][0]['filename']
            break
    if pick:
        break
if pick is None:
    sys.exit('no boot.img entry found in LOS API response')
pick['nightly_zip'] = nightly
json.dump(pick, open(sys.argv[2], 'w'), indent=2)
print('picked boot.img from nightly:', nightly)
PY

BOOT_URL=$(python3 -c "import json;print(json.load(open('$OUT_DIR/los-pick.json'))['url'])")
BOOT_SHA=$(python3 -c "import json;print(json.load(open('$OUT_DIR/los-pick.json'))['sha256'])")
NIGHTLY=$(python3 -c "import json;print(json.load(open('$OUT_DIR/los-pick.json'))['nightly_zip'])")

log "downloading boot.img from: $BOOT_URL"
fetch_retry "$BOOT_URL" "$DOWNLOADS/boot.img"

if [ -n "$BOOT_SHA" ]; then
  echo "$BOOT_SHA  $DOWNLOADS/boot.img" | sha256sum -c - \
    || die "boot.img sha256 mismatch (expected $BOOT_SHA)"
fi

log "boot.img sha256: $(sha256sum "$DOWNLOADS/boot.img" | cut -d' ' -f1)"
env_put XM6_NIGHTLY "$NIGHTLY"
env_put XM6_BOOT_SHA256 "$(sha256sum "$DOWNLOADS/boot.img" | cut -d' ' -f1)"

# unpack stock boot.img -> kernel blob + boot header info
mkdir -p "$OUT_DIR/stock"
python3 "$REPO_ROOT/tools/mkbootimg/unpack_bootimg.py" \
  --boot_img "$DOWNLOADS/boot.img" \
  --out "$OUT_DIR/stock" --format mkbootimg > "$OUT_DIR/stock/unpack.txt"
cp "$OUT_DIR/stock/boot.img-kernel" "$OUT_DIR/stock/kernel" 2>/dev/null || true
[ -s "$OUT_DIR/stock/kernel" ] || die "failed to extract stock kernel blob"

# expected kernel release string from the stock Image banner
strings "$OUT_DIR/stock/kernel" | grep -m1 -E '^Linux version [0-9]' > "$OUT_DIR/stock/banner.txt" || true
EXP_REL=$(sed -n 's/^Linux version \([0-9][^ ]*\).*/\1/p' "$OUT_DIR/stock/banner.txt" | head -1)
[ -n "$EXP_REL" ] || die "cannot read kernel release from stock Image"
log "stock kernel release: $EXP_REL"
env_put XM6_EXPECTED_RELEASE "$EXP_REL"

# extract embedded AVB params -> out/stock/avb.json (consumed by 05_repack)
python3 "$REPO_ROOT/tools/mkbootimg/avbtool.py" info_image \
  --image "$DOWNLOADS/boot.img" > "$OUT_DIR/stock/avb_info.txt"

python3 - "$OUT_DIR/stock/avb_info.txt" "$OUT_DIR/stock/avb.json" <<'PY'
import json, re, sys
txt = open(sys.argv[1]).read()

def grab(pat, cast=str):
    m = re.search(pat, txt, re.M)
    if not m:
        sys.exit(f'avb_info: pattern not found: {pat}')
    return cast(m.group(1))

salt   = grab(r'^\s*Salt:\s*([0-9a-f]+)')
digest = grab(r'^\s*Digest:\s*([0-9a-f]+)')
imgsz  = grab(r'^\s*Image Size:\s*(\d+)', int)
rbi    = grab(r'^\s*Rollback Index:\s*(\d+)', int)
algo   = grab(r'^\s*Algorithm:\s*(\S+)')
props  = dict(re.findall(r'^\s*Prop:\s+(\S+)\s+->\s+\'([^\']*)\'', txt, re.M))
vb_off = int(grab(r'(?i)^\s*vbmeta offset:\s*(\d+)')) if re.search(r'vbmeta offset', txt, re.I) else None

json.dump({'salt': salt, 'digest': digest, 'image_size': imgsz,
           'rollback_index': rbi, 'algorithm': algo, 'props': props,
           'vbmeta_offset': vb_off},
          open(sys.argv[2], 'w'), indent=2)
print('salt  :', salt[:16] + '...')
print('digest:', digest[:16] + '...')
print('rollback_index:', rbi, '| algorithm:', algo)
print('props :', props)
PY

log "step 01 done"

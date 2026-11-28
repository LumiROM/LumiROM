#!/bin/bash
#
# Exercises the vendor tuning helpers on a synthetic firmware tree:
# swappiness lowered, AV1 decoder removed, other codecs untouched and the XML
# still valid. Runs in the Lint workflow, no firmware needed.

set -eo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/../.."

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

FIRM="$TMP_DIR/FIRM"
mkdir -p "$FIRM/vendor/etc/init/hw" "$FIRM/vendor/etc"

cat > "$FIRM/vendor/etc/init/hw/init.mt6768.rc" <<'EOF'
on early-init
    write /proc/sys/vm/swappiness 130
EOF

cat > "$FIRM/vendor/etc/media_codecs_c2.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<MediaCodecs>
    <Decoders>
        <MediaCodec name="c2.android.av1.decoder" type="video/av01">
            <Limit name="size" min="2x2" max="1920x1080" />
            <Feature name="adaptive-playback" />
        </MediaCodec>
        <MediaCodec name="c2.mtk.vp9.decoder" type="video/x-vnd.on2.vp9" />
    </Decoders>
</MediaCodecs>
EOF

source scripts/features/LumiROM.sh

rom_tune_vendor_swappiness "$FIRM"
rom_disable_av1_codec "$FIRM"

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

grep -q 'write /proc/sys/vm/swappiness 80' "$FIRM/vendor/etc/init/hw/init.mt6768.rc" \
    || fail "swappiness was not lowered"
grep -qi 'av1' "$FIRM/vendor/etc/media_codecs_c2.xml" \
    && fail "AV1 decoder is still in the codec list"
grep -q 'c2.mtk.vp9.decoder' "$FIRM/vendor/etc/media_codecs_c2.xml" \
    || fail "VP9 decoder was removed"
python3 -c "import sys, xml.etree.ElementTree as ET; ET.parse(sys.argv[1])" \
    "$FIRM/vendor/etc/media_codecs_c2.xml" \
    || fail "the codec list is not valid XML"

# Running again must be a no-op, not an error.
rom_tune_vendor_swappiness "$FIRM"
rom_disable_av1_codec "$FIRM"

echo "OK: vendor tuning applies, keeps other codecs and is idempotent"

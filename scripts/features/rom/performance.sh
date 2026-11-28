#!/bin/bash
#
# LumiROM features: vendor tuning that used to be left at the vendor defaults.
# Part of scripts/features/LumiROM.sh (sourced by it); not meant to run alone.

# The MTK vendor init writes vm.swappiness 130 at boot (init.mt6768/6769t.rc).
# With a large zram on a 4-6 GB device that means constant compression churn,
# so the kernel spends time swapping instead of drawing the UI. 80 keeps zram
# in use without that pressure; the kernel default (60) is the fallback when
# the vendor tree has no such write.
rom_tune_vendor_swappiness() {
    if [ "$#" -ne 1 ]; then
        echo "Usage: ${FUNCNAME[0]} <EXTRACTED_FIRM_DIR>"
        return 1
    fi

    local FIRM_DIR="$1"
    local FILE FOUND=0 CHANGED=0

    for FILE in "$FIRM_DIR"/vendor/etc/init/hw/init.mt67*.rc; do
        [ -f "$FILE" ] || continue
        FOUND=1

        if grep -q 'write /proc/sys/vm/swappiness 130' "$FILE"; then
            sed -i 's|write /proc/sys/vm/swappiness 130|write /proc/sys/vm/swappiness 80|' "$FILE"
            echo "  - swappiness 130 -> 80 (${FILE#"$FIRM_DIR"/})"
            CHANGED=1
        fi
    done

    if [ "$FOUND" -eq 0 ]; then
        echo "  - no MTK init rc found, leaving the kernel default swappiness"
    elif [ "$CHANGED" -eq 0 ]; then
        echo "  - vendor init does not set swappiness, nothing to change"
    fi
}

# The A32/A22 SoCs have no AV1 hardware decoder, but the vendor codec list
# advertises the software one, so YouTube picks AV1 and drops frames. Removing
# it makes players fall back to VP9/HEVC, which is decoded in hardware.
rom_disable_av1_codec() {
    if [ "$#" -ne 1 ]; then
        echo "Usage: ${FUNCNAME[0]} <EXTRACTED_FIRM_DIR>"
        return 1
    fi

    local FIRM_DIR="$1"
    local FILE="$FIRM_DIR/vendor/etc/media_codecs_c2.xml"

    if [ ! -f "$FILE" ]; then
        echo "  - no media_codecs_c2.xml in the vendor tree, nothing to change"
        return 0
    fi

    if ! python3 scripts/utils/media_codecs.py --remove av1 "$FILE"; then
        echo "  - could not update the codec list" >&2
        return 1
    fi
}

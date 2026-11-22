#!/usr/bin/env bash

set -euo pipefail

source "$(pwd)/scripts/utils/bash_colors.sh"
source "$(pwd)/scripts/package/sign_ota.sh"

if [ "$#" -lt 3 ]; then
    echo "Usage: $0 <full_rom.zip> <output.zip> <partition> [partition...]"
    exit 1
fi

FULL_ZIP="$(realpath "$1")"
OUT_ZIP="$(realpath -m "$2")"
shift 2
PARTS=("$@")

[ -f "$FULL_ZIP" ] || { echo "${RED}Full ROM not found:${RESET} $FULL_ZIP"; exit 1; }
mkdir -p "$(dirname "$OUT_ZIP")"

WORK="$(pwd)/TMP/partial_ota_$$"
rm -rf "$WORK"
mkdir -p "$WORK"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

export UNZIP_DISABLE_ZIPBOMB_DETECTION=TRUE

echo "${YELLOW}Reading full ROM metadata...${RESET}"
unzip -o "$FULL_ZIP" build_info.txt dynamic_partitions_op_list \
    META-INF/com/google/android/update-binary -d "$WORK" >/dev/null

DEVICE_MODEL="$(grep '^device_model=' "$WORK/build_info.txt" | cut -d= -f2-)"
DEVICE_CODENAME="$(grep '^device=' "$WORK/build_info.txt" | cut -d= -f2-)"
BUILD_VERSION="$(grep '^version=' "$WORK/build_info.txt" | cut -d= -f2-)"
BUILD_DATE="$(grep '^build_date=' "$WORK/build_info.txt" | cut -d= -f2-)"
BUILD_STATUS="$(grep '^status=' "$WORK/build_info.txt" | cut -d= -f2-)"
ONEUI_VERSION="$(grep '^oneui_version=' "$WORK/build_info.txt" | cut -d= -f2-)"
BUILD_FINGERPRINT="$(grep '^build_fingerprint=' "$WORK/build_info.txt" | cut -d= -f2-)"
FULL_OP="$WORK/dynamic_partitions_op_list"
[ -n "$DEVICE_MODEL" ] || { echo "${RED}device_model missing in build_info${RESET}"; exit 1; }

# Same display names as zip_creation.sh, for the banner line
case "$DEVICE_MODEL" in
    SM-A325F|SM-A325M) DISPLAY_NAME="Galaxy A32 4G" ;;
    SM-A225F)          DISPLAY_NAME="Galaxy A22 4G" ;;
    SM-M325F)          DISPLAY_NAME="Galaxy M32 4G" ;;
    SM-E225F)          DISPLAY_NAME="Galaxy F22 4G" ;;
    *)                 DISPLAY_NAME="$DEVICE_CODENAME" ;;
esac

: > "$WORK/dynamic_partitions_op_list.partial"
for PART in "${PARTS[@]}"; do
    echo "${YELLOW}Extracting $PART...${RESET}"
    unzip -o "$FULL_ZIP" "$PART.new.dat.br" "$PART.transfer.list" "$PART.patch.dat" -d "$WORK" >/dev/null
    RESIZE_LINE="$(grep -E "^resize $PART " "$FULL_OP" || true)"
    ADD_LINE="$(grep -E "^add $PART " "$FULL_OP" || true)"
    GROUP="$(awk '{print $3}' <<< "$ADD_LINE")"
    if [ -z "$RESIZE_LINE" ] || [ -z "$GROUP" ]; then
        echo "${RED}Missing resize/add line for '$PART' in the full op list${RESET}"
        exit 1
    fi
    # Recreate the logical partition. A resize-only op list leaves the
    # existing dm device at its old size, so block_image_update fails at the
    # end when the image grows.
    echo "remove $PART" >> "$WORK/dynamic_partitions_op_list.partial"
    echo "add $PART $GROUP" >> "$WORK/dynamic_partitions_op_list.partial"
    echo "$RESIZE_LINE" >> "$WORK/dynamic_partitions_op_list.partial"
done
mv "$WORK/dynamic_partitions_op_list.partial" "$WORK/dynamic_partitions_op_list"

echo "${YELLOW}Generating updater-script...${RESET}"
# Same ANSI colours as the full ROM template. The escapes are written verbatim
# to the script; TWRP (twrp.console_ansi=1) strips them and colours the line,
# while any other recovery prints the plain text.
ANSI_COLOR() {
    printf 'ifelse(getprop("twrp.console_ansi") == "1", "\\x1b[%sm", "")' "$1"
}
# UIP <colour code or ""> <text>  -> one ui_print line, coloured when code != ""
UIP() {
    if [ -n "$1" ]; then
        printf 'ui_print(concat(%s, "%s"));\n' "$(ANSI_COLOR "$1")" "$2"
    else
        printf 'ui_print("%s");\n' "$2"
    fi
}
LOGO_LINES=(
'    __                    _ ____                 '
'   / /   __  ______ ___  (_) __ \____  ____ ___  '
'  / /   / / / / __ `__ \/ / /_/ / __ \/ __ `__ \ '
' / /___/ /_/ / / / / / / / _, _/ /_/ / / / / / / '
'/_____/\__,_/_/ /_/ /_/_/_/ |_|\____/_/ /_/ /_/  '
)
{
    echo "getprop(\"ro.boot.em.model\") == \"$DEVICE_MODEL\" || abort(concat(\"E3004: \", $(ANSI_COLOR 31), \"This package is for $DEVICE_CODENAME\"));"
    UIP "" " "
    UIP 36 "************************************************"
    for LINE in "${LOGO_LINES[@]}"; do
        UIP 34 "$LINE"
    done
    UIP "" " "
    UIP "" "   $BUILD_VERSION-$BUILD_DATE $BUILD_STATUS for $DISPLAY_NAME"
    UIP "" " "
    UIP 36 "************************************************"
    UIP "" "One UI version: $ONEUI_VERSION"
    UIP "" "Source: $BUILD_FINGERPRINT"
    UIP 36 "************************************************"
    UIP "" " "
    UIP 96 "LumiROM partial OTA: ${PARTS[*]}"
    UIP "" " "
    for PART in "${PARTS[@]}"; do
        echo "ifelse(is_mounted(\"/$PART\"), unmount(\"/$PART\"), \"\");"
        echo "unmap_partition(\"$PART\");"
    done
    echo "assert(update_dynamic_partitions(package_extract_file(\"dynamic_partitions_op_list\")));"
    for PART in "${PARTS[@]}"; do
        UIP 33 "Patching $PART image..."
        echo "show_progress(0.900000, 0);"
        echo "block_image_update(map_partition(\"$PART\"), package_extract_file(\"$PART.transfer.list\"), \"$PART.new.dat.br\", \"$PART.patch.dat\") || abort(concat(\"E1001: \", $(ANSI_COLOR 31), \"Failed to update $PART image.\"));"
    done
    # Framework changes leave stale ART/package caches in /data.
    echo "run_program(\"/sbin/sh\", \"-c\", \"grep -q ' /data ' /proc/mounts || mount -o rw /data 2>/dev/null; rm -rf /data/dalvik-cache/* /data/system/package_cache/* 2>/dev/null\");"
    UIP 32 "Partial OTA complete."
    UIP "" " "
    UIP 36 "************************************************"
    UIP "" " "
} > "$WORK/META-INF/com/google/android/updater-script"

echo "${YELLOW}Creating ZIP (${PARTS[*]})...${RESET}"
rm -f "$OUT_ZIP"
( cd "$WORK" && 7z a -tzip -mx=0 "$OUT_ZIP" ./* >/dev/null )

echo "${YELLOW}Signing partial OTA...${RESET}"
SIGN_OTA_ZIP "$OUT_ZIP"

echo "${GREEN}Partial OTA ready:${RESET} $OUT_ZIP"
ls -lh "$OUT_ZIP"
sha256sum "$OUT_ZIP"

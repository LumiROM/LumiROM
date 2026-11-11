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
FULL_OP="$WORK/dynamic_partitions_op_list"
[ -n "$DEVICE_MODEL" ] || { echo "${RED}device_model missing in build_info${RESET}"; exit 1; }

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
{
    echo "getprop(\"ro.boot.em.model\") == \"$DEVICE_MODEL\" || abort(\"E3004: This package is for $DEVICE_CODENAME\");"
    echo "ui_print(\" \");"
    echo "ui_print(\"LumiROM partial OTA: ${PARTS[*]}\");"
    for PART in "${PARTS[@]}"; do
        echo "ifelse(is_mounted(\"/$PART\"), unmount(\"/$PART\"), \"\");"
        echo "unmap_partition(\"$PART\");"
    done
    echo "assert(update_dynamic_partitions(package_extract_file(\"dynamic_partitions_op_list\")));"
    for PART in "${PARTS[@]}"; do
        echo "ui_print(\"Patching $PART image...\");"
        echo "show_progress(0.900000, 0);"
        echo "block_image_update(map_partition(\"$PART\"), package_extract_file(\"$PART.transfer.list\"), \"$PART.new.dat.br\", \"$PART.patch.dat\") || abort(\"E1001: Failed to update $PART image.\");"
    done
    # Framework changes leave stale ART/package caches in /data.
    echo "run_program(\"/sbin/sh\", \"-c\", \"grep -q ' /data ' /proc/mounts || mount -o rw /data 2>/dev/null; rm -rf /data/dalvik-cache/* /data/system/package_cache/* 2>/dev/null\");"
    echo "ui_print(\"Partial OTA complete.\");"
} > "$WORK/META-INF/com/google/android/updater-script"

echo "${YELLOW}Creating ZIP (${PARTS[*]})...${RESET}"
rm -f "$OUT_ZIP"
( cd "$WORK" && 7z a -tzip -mx=0 "$OUT_ZIP" ./* >/dev/null )

echo "${YELLOW}Signing partial OTA...${RESET}"
SIGN_OTA_ZIP "$OUT_ZIP"

echo "${GREEN}Partial OTA ready:${RESET} $OUT_ZIP"
ls -lh "$OUT_ZIP"
sha256sum "$OUT_ZIP"

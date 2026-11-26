#!/bin/bash

source scripts/utils/bash_colors.sh
source scripts/package/updater_script.sh

ota_image_size() {
    local FILE="$1"
    local MAGIC BLOCK_SIZE BLOCKS
    MAGIC="$(od -A n -t x1 -j 0 -N 4 "$FILE" 2>/dev/null | tr -d ' \n')"
    if [ "$MAGIC" = "3aff26ed" ]; then
        BLOCK_SIZE="$(od -A n -t u4 -j 12 -N 4 "$FILE" | tr -d ' ')"
        BLOCKS="$(od -A n -t u4 -j 16 -N 4 "$FILE" | tr -d ' ')"
        echo $((BLOCKS * BLOCK_SIZE))
    else
        stat -c "%s" "$FILE"
    fi
}

ota_display_name() {
    case "$1" in
        a32) echo "Galaxy A32 4G" ;;
        a32m) echo "Galaxy A32 4G" ;;
        a22) echo "Galaxy A22 4G" ;;
        m32) echo "Galaxy M32 4G" ;;
        f22) echo "Galaxy F22 4G" ;;
        *) echo "Galaxy Device" ;;
    esac
}

ota_codename() {
    case "$1" in
        SM-A325F) echo "a32" ;;
        SM-A325M) echo "a32m" ;;
        SM-A225F) echo "a22" ;;
        SM-M325F) echo "m32" ;;
        SM-E225F) echo "f22" ;;
        *) echo "unknown" ;;
    esac
}

# ota_generate_updater_script <template> <output> <incr_dir>
#                                   <install|skip|none> <partition...>
#
# Keeps the banner/prism block and the kernel/cache block from the rendered
# template and generates the partition section in between. `boot_mode`
# decides whether boot.img is flashed (install), reported as unchanged (skip)
# or omitted (none).
#
# Reads the build metadata from the caller's dynamically scoped variables:
# STOCK_DEVICE, DEVICE_CODENAME, DISPLAY_NAME, FINGERPRINT, LUMIROM_VERSION,
# BUILD_DATE, BUILD_STATUS, ONEUI_VERSION, SOURCE_VERSION.
ota_generate_updater_script() {
    if [ "$#" -lt 4 ]; then
        echo "Usage: ${FUNCNAME[0]} <template> <output> <incr_dir> <install|skip|none> <partition...>" >&2
        return 1
    fi

    local TEMPLATE="$1"
    local OUTPUT="$2"
    local INCR_DIR="$3"
    local BOOT_MODE="$4"
    shift 4
    local -a PARTITIONS=("$@")

    local BOOT_INSTALL=false BOOT_SKIP=false
    case "$BOOT_MODE" in
        install) BOOT_INSTALL=true ;;
        skip)    BOOT_SKIP=true ;;
        none)    ;;
        *)
            echo "${RED}Error:${RESET} invalid boot mode: $BOOT_MODE" >&2
            return 1
            ;;
    esac

    local RENDERED="$OUTPUT.rendered"
    if ! render_updater_script "$TEMPLATE" "$RENDERED" \
            "DEVICE_MODEL=$STOCK_DEVICE" \
            "DEVICE_CODENAME=$DEVICE_CODENAME" \
            "BUILD_TAG=$LUMIROM_VERSION-$BUILD_DATE $BUILD_STATUS" \
            "DISPLAY_NAME=$DISPLAY_NAME" \
            "ONEUI_VERSION=$ONEUI_VERSION" \
            "FINGERPRINT=$FINGERPRINT" \
            "BOOT_INSTALL=$BOOT_INSTALL" \
            "BOOT_SKIP=$BOOT_SKIP"; then
        rm -f "$RENDERED"
        return 1
    fi

    # Everything before the partition section (banner + prism cleanup) and
    # from the kernel section onwards (boot + cache wipe) comes verbatim from
    # the template; only the partition section is generated here.
    local SPLIT_LINE TAIL_LINE
    SPLIT_LINE="$(grep -n '^# --- Start patching dynamic partitions ---' "$RENDERED" | cut -d ":" -f 1)"
    TAIL_LINE="$(grep -n '^# --- Installing kernel ---' "$RENDERED" | cut -d ":" -f 1)"

    if [ -z "$SPLIT_LINE" ] || [ -z "$TAIL_LINE" ]; then
        echo "${RED}Error:${RESET} updater-script template is missing its section markers" >&2
        rm -f "$RENDERED"
        return 1
    fi

    head -n $((SPLIT_LINE - 1)) "$RENDERED" > "$OUTPUT"

    {
        echo "ui_print(\"Incremental update from $SOURCE_VERSION\");"
        echo "ui_print(\" \");"
    } >> "$OUTPUT"

    echo 'show_progress(0.400000, 45);' >> "$OUTPUT"

    local PARTITION RANGES_FILE SHA1_FILE RANGES SHA1
    for PARTITION in "${PARTITIONS[@]}"; do
        RANGES_FILE="$INCR_DIR/$PARTITION.touched_src_ranges"
        SHA1_FILE="$INCR_DIR/$PARTITION.touched_src_sha1"

        if [ -f "$SHA1_FILE" ] && [ -n "$(cat "$SHA1_FILE")" ]; then
            RANGES="$(cat "$RANGES_FILE")"
            SHA1="$(cat "$SHA1_FILE")"
            {
                echo "ui_print(\"Verifying $PARTITION image...\");"
                echo "if (range_sha1(map_partition(\"$PARTITION\"), \"$RANGES\") == \"$SHA1\" || block_image_verify(map_partition(\"$PARTITION\"), package_extract_file(\"$PARTITION.transfer.list\"), \"$PARTITION.new.dat.br\", \"$PARTITION.patch.dat\")) then"
                echo "ui_print(\"Verified $PARTITION image...\");"
                echo "else"
                echo "ifelse(block_image_recover(map_partition(\"$PARTITION\"), \"$RANGES\") && block_image_verify(map_partition(\"$PARTITION\"), package_extract_file(\"$PARTITION.transfer.list\"), \"$PARTITION.new.dat.br\", \"$PARTITION.patch.dat\"), ui_print(\"$PARTITION recovered successfully.\"), abort(\"E1004: $PARTITION partition fails to recover\"));"
                echo "endif;"
            } >> "$OUTPUT"
        else
            echo "ui_print(\"Patching $PARTITION image unconditionally...\");" >> "$OUTPUT"
        fi
    done

    {
        echo "# --- Start patching dynamic partitions ---"
        echo ""
        echo "# Update dynamic partition metadata"
        echo "assert(update_dynamic_partitions(package_extract_file(\"dynamic_partitions_op_list\")));"
        for PARTITION in "${PARTITIONS[@]}"; do
            echo ""
            echo "# Patch partition $PARTITION"
            echo "ui_print(\"Patching $PARTITION image...\");"
            echo "show_progress(0.100000, 0);"
            echo "block_image_update(map_partition(\"$PARTITION\"), package_extract_file(\"$PARTITION.transfer.list\"), \"$PARTITION.new.dat.br\", \"$PARTITION.patch.dat\") ||"
            echo "  abort(\"E1001: Failed to update $PARTITION image.\");"
        done
        echo ""
        echo "# --- End patching dynamic partitions ---"
        echo ""
    } >> "$OUTPUT"

    tail -n +"$TAIL_LINE" "$RENDERED" >> "$OUTPUT"
    rm -f "$RENDERED"
}

ota_build() {
    if [ "$#" -ne 2 ]; then
        echo "Usage: ${FUNCNAME[0]} <SOURCE_TARGET_FILES_ZIP> <IMG_DIR>"
        echo "       Outputs the incremental zip into ROM/\$FOLDER_NAME"
        return 1
    fi

    (
    local SOURCE_ZIP="$1"
    local IMG_DIR="$2"
    local IMG2SDAT_BIN
    IMG2SDAT_BIN="$(pwd)/bin/img2sdat/img2sdat"
    local TEMPLATE_DIR
    TEMPLATE_DIR="$(pwd)/template"

    for DEP in unzip zip 7z brotli sha1sum od date simg2img img2simg; do
        if ! command -v "$DEP" >/dev/null 2>&1; then
            echo "${RED}Error: missing dependency: $DEP${RESET}"
            exit 1
        fi
    done

    if [ ! -f "$SOURCE_ZIP" ]; then
        echo "${RED}Error: source target files not found: $SOURCE_ZIP${RESET}"
        exit 1
    fi

    if [ ! -f "$IMG_DIR/build_info.txt" ] || ! ls "$IMG_DIR"/*.img >/dev/null 2>&1; then
        echo "${RED}Error: current build images or build_info.txt not found in $IMG_DIR${RESET}"
        exit 1
    fi

    if [ ! -f "$IMG2SDAT_BIN" ] || [ ! -f "$TEMPLATE_DIR/META-INF/com/google/android/update-binary" ]; then
        echo "${RED}Error: img2sdat or template not found${RESET}"
        exit 1
    fi

    chmod +x "$IMG2SDAT_BIN"

    local WORK_DIR_INC TEMP_DIR
    mkdir -p "$(pwd)/TMP"
    WORK_DIR_INC="$(mktemp -d -p "$(pwd)/TMP")"
    TEMP_DIR="$(mktemp -d -p "$(pwd)/TMP")"
    trap 'rm -rf "$WORK_DIR_INC" "$TEMP_DIR"' EXIT

    export TMPDIR="$TEMP_DIR"

    echo "${BLUE}Extracting source target files...${RESET}"
    if ! unzip -q "$SOURCE_ZIP" -d "$WORK_DIR_INC/source"; then
        echo "${RED}Error: failed to extract $SOURCE_ZIP${RESET}"
        exit 1
    fi

    if [ ! -f "$WORK_DIR_INC/source/build_info.txt" ]; then
        echo "${RED}Error: build_info.txt not found inside source target files${RESET}"
        exit 1
    fi

    local SOURCE_BUILD_INFO TARGET_BUILD_INFO
    SOURCE_BUILD_INFO="$(cat "$WORK_DIR_INC/source/build_info.txt")"
    TARGET_BUILD_INFO="$(cat "$IMG_DIR/build_info.txt")"

    local SRC_DEVICE TGT_DEVICE SRC_SPL TGT_SPL SOURCE_VERSION
    SRC_DEVICE="$(grep "^device=" <<< "$SOURCE_BUILD_INFO" | cut -d "=" -f 2-)"
    TGT_DEVICE="$(grep "^device=" <<< "$TARGET_BUILD_INFO" | cut -d "=" -f 2-)"

    if [ "$SRC_DEVICE" != "$TGT_DEVICE" ]; then
        echo "${RED}Error: source device ($SRC_DEVICE) does not match target device ($TGT_DEVICE)${RESET}"
        exit 1
    fi

    SRC_SPL="$(grep "^security_patch=" <<< "$SOURCE_BUILD_INFO" | cut -d "=" -f 2-)"
    TGT_SPL="$(grep "^security_patch=" <<< "$TARGET_BUILD_INFO" | cut -d "=" -f 2-)"
    if [ -n "$SRC_SPL" ] && [ -n "$TGT_SPL" ]; then
        if [ "$(date -d "$SRC_SPL" +%s)" -gt "$(date -d "$TGT_SPL" +%s)" ]; then
            echo "${RED}Error: target security patch ($TGT_SPL) is older than source ($SRC_SPL)${RESET}"
            exit 1
        fi
    fi

    SOURCE_VERSION="$(grep "^version=" <<< "$SOURCE_BUILD_INFO" | cut -d "=" -f 2-)"
    local SOURCE_SHORT="${SOURCE_VERSION%%-*}"

    # shellcheck source=/dev/null
    source "$DEVICES_DIR/$STOCK_DEVICE/config" 2>/dev/null || true
    CACHE_PARTITION_SIZE="${CACHE_PARTITION_SIZE:-268435456}"

    local FINGERPRINT
    FINGERPRINT="$(grep "^build_fingerprint=" <<< "$TARGET_BUILD_INFO" | cut -d "=" -f 2-)"
    [ -n "$FINGERPRINT" ] || FINGERPRINT="$(grep "^ro.system.build.fingerprint=" "$FIRM_DIR/system/system/build.prop" 2>/dev/null | cut -d "=" -f 2)"
    [ -n "$FINGERPRINT" ] || FINGERPRINT="Unknown/Release-Keys"

    local DEVICE_CODENAME
    DEVICE_CODENAME="$(ota_codename "$STOCK_DEVICE")"

    local ONEUI_VERSION
    ONEUI_VERSION="$(grep "^ro.build.version.oneui=" "$FIRM_DIR/system/system/build.prop" 2>/dev/null | cut -d "=" -f 2)"
    ONEUI_VERSION="${ONEUI_VERSION:0:3}"
    ONEUI_VERSION="${ONEUI_VERSION/0/.}"

    local BUILD_DATE
    BUILD_DATE="$(date +'%d%m%Y')"

    local STAGE="$WORK_DIR_INC/stage"
    local INCR_DIR="$WORK_DIR_INC/incr"
    mkdir -p "$STAGE/META-INF/com/google/android" "$INCR_DIR"

    cp "$TEMPLATE_DIR/META-INF/com/google/android/update-binary" "$STAGE/META-INF/com/google/android/"
    cp "$TEMPLATE_DIR/META-INF/com/android/metadata" "$STAGE/META-INF/com/android/" 2>/dev/null || true
    cp "$TEMPLATE_DIR/META-INF/com/android/metadata.pb" "$STAGE/META-INF/com/android/" 2>/dev/null || true

    echo "${BLUE}Generating per-partition diffs...${RESET}"

    local CHANGED_PARTITIONS=()
    local PARTITION SRC_IMG SRC_MAP
    for f in "$IMG_DIR"/*.img; do
        PARTITION="$(basename "$f" .img)"
        SRC_IMG="$WORK_DIR_INC/source/$PARTITION.img"
        SRC_MAP="$WORK_DIR_INC/source/$PARTITION.map"

        local SRC_RAW="$WORK_DIR_INC/source/$PARTITION.raw"
        local TGT_RAW="$WORK_DIR_INC/$PARTITION.raw"
        if [ -f "$SRC_IMG" ] && [ "$(od -A n -t x1 -j 0 -N 4 "$SRC_IMG" | tr -d ' \n')" = "3aff26ed" ]; then
            simg2img "$SRC_IMG" "$SRC_RAW"
        elif [ -f "$SRC_IMG" ]; then
            cp "$SRC_IMG" "$SRC_RAW"
        fi
        if [ "$(od -A n -t x1 -j 0 -N 4 "$f" | tr -d ' \n')" = "3aff26ed" ]; then
            simg2img "$f" "$TGT_RAW"
        else
            cp "$f" "$TGT_RAW"
        fi

        if [ ! -f "$SRC_IMG" ]; then
            echo "${YELLOW}New partition $PARTITION, converting fully...${RESET}"
            if ! "$IMG2SDAT_BIN" -o "$INCR_DIR" "$f" 2> "$WORK_DIR_INC/$PARTITION.diff.log"; then
                echo "${RED}Full conversion failed for $PARTITION:${RESET}" >&2
                tail -n 5 "$WORK_DIR_INC/$PARTITION.diff.log" >&2
                exit 1
            fi
            mv "$INCR_DIR/$PARTITION.new.dat" "$STAGE/"
            mv "$INCR_DIR/$PARTITION.transfer.list" "$STAGE/"
            mv "$INCR_DIR/$PARTITION.patch.dat" "$STAGE/" 2>/dev/null || touch "$STAGE/$PARTITION.patch.dat"
        elif [ "$(sha1sum "$SRC_RAW" | cut -d " " -f 1)" = "$(sha1sum "$TGT_RAW" | cut -d " " -f 1)" ]; then
            echo "${GREEN}Skipping $PARTITION (unchanged)${RESET}"
            continue
        else
            echo "${YELLOW}Generating $PARTITION block diff...${RESET}"
            if [ ! -f "$SRC_MAP" ]; then
                echo "${RED}Error: block map missing for source partition $PARTITION${RESET}"
                exit 1
            fi
            if [ ! -f "$IMG_DIR/$PARTITION.map" ]; then
                echo "${RED}Error: block map missing for current $PARTITION build (expected $IMG_DIR/$PARTITION.map)${RESET}"
                exit 1
            fi
            mkdir -p "$INCR_DIR/$PARTITION"
            img2simg "$SRC_RAW" "$WORK_DIR_INC/source/$PARTITION.sparse"
            img2simg "$TGT_RAW" "$WORK_DIR_INC/$PARTITION.sparse"
            local DIFF_LOG="$WORK_DIR_INC/$PARTITION.diff.log"
            if "$IMG2SDAT_BIN" -o "$INCR_DIR/$PARTITION" -s "$WORK_DIR_INC/source/$PARTITION.sparse" --src-block-map "$SRC_MAP" -B "$IMG_DIR/$PARTITION.map" -c "$CACHE_PARTITION_SIZE" "$WORK_DIR_INC/$PARTITION.sparse" 2> "$DIFF_LOG"; then
                mv "$INCR_DIR/$PARTITION/$PARTITION.new.dat" "$STAGE/"
                mv "$INCR_DIR/$PARTITION/$PARTITION.transfer.list" "$STAGE/"
                mv "$INCR_DIR/$PARTITION/$PARTITION.patch.dat" "$STAGE/" 2>/dev/null || touch "$STAGE/$PARTITION.patch.dat"
                mv "$INCR_DIR/$PARTITION/$PARTITION.touched_src_ranges" "$INCR_DIR/" 2>/dev/null || true
                mv "$INCR_DIR/$PARTITION/$PARTITION.touched_src_sha1" "$INCR_DIR/" 2>/dev/null || true
            else
                echo "${RED}Block diff failed for $PARTITION:${RESET}" >&2
                tail -n 5 "$DIFF_LOG" >&2
                echo "${YELLOW}Block diff not possible for $PARTITION, falling back to full patch...${RESET}"
                rm -rf "${INCR_DIR:?}/${PARTITION:?}"
                if ! "$IMG2SDAT_BIN" -o "$INCR_DIR" "$f" 2> "$DIFF_LOG"; then
                    echo "${RED}Full conversion failed for $PARTITION:${RESET}" >&2
                    tail -n 5 "$DIFF_LOG" >&2
                    exit 1
                fi
                mv "$INCR_DIR/$PARTITION.new.dat" "$STAGE/"
                mv "$INCR_DIR/$PARTITION.transfer.list" "$STAGE/"
                mv "$INCR_DIR/$PARTITION.patch.dat" "$STAGE/" 2>/dev/null || touch "$STAGE/$PARTITION.patch.dat"
            fi
        fi

        CHANGED_PARTITIONS+=("$PARTITION")
    done

    if [ "${#CHANGED_PARTITIONS[@]}" -eq 0 ]; then
        echo "${RED}Error: no partition differences found, incremental OTA is not needed${RESET}"
        exit 1
    fi

    echo "${BLUE}Compressing .new.dat files with Brotli...${RESET}"
    local DAT
    for DAT in "$STAGE"/*.new.dat; do
        [[ -f "$DAT" ]] || continue
        brotli -f -q 1 --output="$DAT.br" "$DAT" && rm -f "$DAT"
    done

    echo "${BLUE}Generating dynamic_partitions_op_list...${RESET}"
    local OP_LIST="$STAGE/dynamic_partitions_op_list"
    local TOTAL_SIZE=0 PART_SIZE SRC_SIZE OP_LINES=""
    for PARTITION in "${CHANGED_PARTITIONS[@]}"; do
        PART_SIZE="$(ota_image_size "$IMG_DIR/$PARTITION.img")"
        TOTAL_SIZE=$((TOTAL_SIZE + PART_SIZE))
        SRC_SIZE="$(ota_image_size "$WORK_DIR_INC/source/$PARTITION.img" 2>/dev/null || echo 0)"
        if [ "$PART_SIZE" != "$SRC_SIZE" ]; then
            OP_LINES+="resize $PARTITION $PART_SIZE"$'\n'
        fi
    done

    if [ -n "${STOCK_SUPER_SIZE:-}" ] && [ "$TOTAL_SIZE" -gt "${STOCK_SUPER_SIZE:-0}" ]; then
        echo "${RED}Error: target partitions ($TOTAL_SIZE bytes) do not fit in the super partition (${STOCK_SUPER_SIZE:-0} bytes)${RESET}"
        exit 1
    fi

    {
        echo "# Incremental dynamic partitions update"
        if [ -n "$OP_LINES" ]; then
            printf "%s" "$OP_LINES"
        else
            echo "# No partition size changes"
        fi
    } > "$OP_LIST"

    echo "${BLUE}Generating updater-script...${RESET}"
    local TEMPLATE_SCRIPT="$TEMPLATE_DIR/META-INF/com/google/android/updater-script"
    local UPDATER_SCRIPT="$STAGE/META-INF/com/google/android/updater-script"
    local DISPLAY_NAME
    DISPLAY_NAME="$(ota_display_name "$DEVICE_CODENAME")"

    local SPECIFIC_BOOT="$PWD/LumiROM/Devices/$STOCK_DEVICE/boot.img"
    local SOURCE_BOOT="$WORK_DIR_INC/source/boot.img"
    local BOOT_MODE="none"

    if [ -f "$SPECIFIC_BOOT" ] && [ -f "$SOURCE_BOOT" ] && \
       [ "$(sha1sum "$SPECIFIC_BOOT" | cut -d " " -f 1)" = "$(sha1sum "$SOURCE_BOOT" | cut -d " " -f 1)" ]; then
        echo "${GREEN}Boot image unchanged, skipping it...${RESET}"
        BOOT_MODE="skip"
    elif [ -f "$SPECIFIC_BOOT" ]; then
        echo "${GREEN}Copying boot.img from $STOCK_DEVICE...${RESET}"
        cp "$SPECIFIC_BOOT" "$STAGE/boot.img"
        BOOT_MODE="install"
    else
        echo "${YELLOW}Warning: no boot.img found for $STOCK_DEVICE, it will not be included${RESET}"
    fi

    if ! ota_generate_updater_script \
            "$TEMPLATE_SCRIPT" "$UPDATER_SCRIPT" "$INCR_DIR" "$BOOT_MODE" \
            "${CHANGED_PARTITIONS[@]}"; then
        echo "${RED}Error: failed to generate the incremental updater-script${RESET}" >&2
        exit 1
    fi

    cp "$IMG_DIR/build_info.txt" "$STAGE/build_info.txt"
    {
        echo "incremental_from=$SOURCE_VERSION"
        echo "incremental_source_timestamp=$(grep "^timestamp=" <<< "$SOURCE_BUILD_INFO" | cut -d "=" -f 2-)"
    } >> "$STAGE/build_info.txt"

    local OUTPUT_ZIP="ROM/${FOLDER_NAME}/LumiROM_${LUMIROM_VERSION}-${BUILD_DATE}_${BUILD_STATUS}_${DEVICE_CODENAME}-INCREMENTAL_from_${SOURCE_SHORT}.zip"
    OUTPUT_ZIP="$(pwd)/$OUTPUT_ZIP"
    mkdir -p "$(dirname "$OUTPUT_ZIP")"
    rm -f "$OUTPUT_ZIP"

    echo "${BLUE}Creating incremental ZIP package...${RESET}"
    (
        cd "$STAGE" || exit 1
        7z a -tzip -mx=0 -mmt=4 "$OUTPUT_ZIP" ./*.new.dat.br ./*.patch.dat >/dev/null 2>&1 || true
        7z a -tzip -mx=3 -mmt=4 "$OUTPUT_ZIP" -r . -x!*.new.dat.br -x!*.patch.dat >/dev/null 2>&1
    ) || exit 1

    echo "${GREEN}Incremental OTA created: $OUTPUT_ZIP${RESET}"
    )
}

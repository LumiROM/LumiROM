#!/bin/bash

source scripts/utils/bash_colors.sh
source scripts/package/updater_script.sh

# Renders makerom/META-INF/com/google/android/updater-script with this build's
# metadata. The template lives in template/ and is never mutated in place.
pkg_render_updater_script() {
        if [ "$#" -ne 1 ]; then
            echo "Usage: ${FUNCNAME[0]} <extracted_firmware_dir>"
            return 1
        fi

        local EXTRACTED_FIRM_DIR="$1"
        local BUILD_PROP_PATH="$EXTRACTED_FIRM_DIR/system/system/build.prop"
        local TEMPLATE_SCRIPT="$PWD/template/META-INF/com/google/android/updater-script"
        local ONEUI_VERSION_RAW

        UPDATER_PATH="$PWD/makerom/META-INF/com/google/android/updater-script"
        BUILD_DATE=$(date +'%d%m%Y')
        DEVICE="$STOCK_DEVICE"
        BUILD_STATUS="${BUILD_STATUS:-UNOFFICIAL}"

        FINGERPRINT=$(grep -m 1 "ro.system.build.fingerprint=" "$BUILD_PROP_PATH" | cut -d'=' -f2)
        ONEUI_VERSION_RAW=$(grep -m 1 "ro.build.version.oneui=" "$BUILD_PROP_PATH" | cut -d'=' -f2)
        ONEUI_VERSION="${ONEUI_VERSION_RAW:0:3}"
        ONEUI_VERSION="${ONEUI_VERSION/0/.}"

        case "$DEVICE" in
            SM-A325F)          DEVICE_CODENAME="a32";  DISPLAY_NAME="Galaxy A32 4G" ;;
            SM-A325M)          DEVICE_CODENAME="a32m"; DISPLAY_NAME="Galaxy A32 4G" ;;
            SM-A225F)          DEVICE_CODENAME="a22";  DISPLAY_NAME="Galaxy A22 4G" ;;
            SM-M325F)          DEVICE_CODENAME="m32";  DISPLAY_NAME="Galaxy M32 4G" ;;
            SM-E225F)          DEVICE_CODENAME="f22";  DISPLAY_NAME="Galaxy F22 4G" ;;
            *)                 DEVICE_CODENAME="unknown"; DISPLAY_NAME="Unknown Device" ;;
        esac

        if [ -z "$FINGERPRINT" ]; then
            echo "${YELLOW}Warning: Fingerprint not found, using generic value.${RESET}"
            FINGERPRINT="Unknown/Release-Keys"
        fi

        echo "${GREEN}Detected Fingerprint:${RESET} $FINGERPRINT"
        echo "${GREEN}Updating device on updater-script for${RESET} $DISPLAY_NAME..."
        echo "${GREEN}Updating One UI version to${RESET} $ONEUI_VERSION ${GREEN}on updater-script...${RESET}"

        if ! render_updater_script "$TEMPLATE_SCRIPT" "$UPDATER_PATH" \
                "DEVICE_MODEL=$DEVICE" \
                "DEVICE_CODENAME=$DEVICE_CODENAME" \
                "BUILD_TAG=$LUMIROM_VERSION-$BUILD_DATE $BUILD_STATUS" \
                "DISPLAY_NAME=$DISPLAY_NAME" \
                "ONEUI_VERSION=$ONEUI_VERSION" \
                "FINGERPRINT=$FINGERPRINT" \
                "BOOT_INSTALL=true" \
                "BOOT_SKIP=false"; then
            echo "${RED}Error: failed to render the updater-script${RESET}" >&2
            return 1
        fi
}

pkg_create_flashable_zip() {
    
        BUILD_DATE=$(date +'%d%m%Y')
        TIMESTAMP=$(date +'%s')
        DEVICE="$STOCK_DEVICE"
        local cut_version_stock="${STOCK_DEVICE:3:3}"
        local cut_version_target="${TARGET_DEVICE:3:3}"
        FOLDER_NAME="${BUILD_DATE}-${TIMESTAMP}-${cut_version_stock}_to_${cut_version_target}/"
        MAKEROM_DIR="$(pwd)/makerom"
        export FOLDER_NAME

        # Persist FOLDER_NAME so the caller can find the output after this
        # function returns: $GITHUB_ENV in the workflows, or $LUMIROM_ENV_FILE
        # in local builds (where run() executes this in a subshell).
        if [ -n "${GITHUB_ENV:-}" ]; then
            echo "FOLDER_NAME=$FOLDER_NAME" >> "$GITHUB_ENV"
        elif [ -n "${LUMIROM_ENV_FILE:-}" ]; then
            echo "FOLDER_NAME=$FOLDER_NAME" >> "$LUMIROM_ENV_FILE"
        fi

        if [[ "$DEVICE" == "SM-A325F" ]]; then
            DEVICE_CODENAME="a32"
        elif [[ "$DEVICE" == "SM-A325M" ]]; then
            DEVICE_CODENAME="a32m"
        elif [[ "$DEVICE" == "SM-A225F" ]]; then
            DEVICE_CODENAME="a22"
        elif [[ "$DEVICE" == "SM-M325F" ]]; then
            DEVICE_CODENAME="m32"
        elif [[ "$DEVICE" == "SM-E225F" ]]; then
            DEVICE_CODENAME="f22"
        else
            DEVICE_CODENAME="unknown"
        fi

        echo "Generating build_info.txt..."
        if [ -n "${GITHUB_ENV:-}" ]; then
            echo "DEVICE_CODENAME=$DEVICE_CODENAME" >> "$GITHUB_ENV"
        fi

        if [ -f "$DEVICES_DIR/$STOCK_DEVICE/config" ]; then
            # shellcheck source=/dev/null
            source "$DEVICES_DIR/$STOCK_DEVICE/config"
        else
            echo "${YELLOW}Warning: no device config for $STOCK_DEVICE; super size and cache size may be wrong${RESET}"
        fi

        BUILD_PROP="$FIRM_DIR/system/system/build.prop"
        if [ -z "$FINGERPRINT" ]; then
            FINGERPRINT="$(grep "^ro.system.build.fingerprint=" "$BUILD_PROP" | cut -d "=" -f 2)"
        fi
        if [ -z "$ONEUI_VERSION" ]; then
            ONEUI_VERSION="$(grep "^ro.build.version.oneui=" "$BUILD_PROP" | cut -d "=" -f 2)"
            ONEUI_VERSION="${ONEUI_VERSION:0:3}"
            ONEUI_VERSION="${ONEUI_VERSION/0/.}"
        fi
        ONEUI_VERSION_UNCUT="$(grep "^ro.build.version.oneui=" "$BUILD_PROP" | cut -d "=" -f 2)"
        ANDROID_VERSION="$(grep "^ro.build.version.release=" "$BUILD_PROP" | cut -d "=" -f 2)"
        SECURITY_PATCH="$(grep "^ro.build.version.security_patch=" "$BUILD_PROP" | cut -d "=" -f 2)"

        # Kernel version of the boot image this device ships. The boot image is
        # authoritative; a stale KERNEL_VERSION from the device config or the
        # environment is only kept when the image cannot be read.
        local DETECTED_KERNEL_VERSION
        DETECTED_KERNEL_VERSION="$(python3 scripts/utils/kernel_version.py \
            "$(pwd)/LumiROM/Devices/$DEVICE/boot.img" 2>/dev/null || true)"
        if [ -n "$DETECTED_KERNEL_VERSION" ]; then
            KERNEL_VERSION="$DETECTED_KERNEL_VERSION"
        fi

        # Base (Galaxy A34) firmware the images were unpacked from, when known.
        # fw_prepare_partitions prunes IMGs/, so the marker lives in FIRM_DIR; the
        # IMGS_DIR lookup keeps builds made before that change working.
        BASE_FW_VERSION=""
        for BASE_FW_MARKER in "$FIRM_DIR/base_firmware_version.txt" "$IMGS_DIR/base_firmware_version.txt"; do
            if [ -f "$BASE_FW_MARKER" ]; then
                BASE_FW_VERSION="$(sed -n 's/^version=//p' "$BASE_FW_MARKER" | head -n 1)"
                break
            fi
        done
        # A build served from the IMGs cache never pulls from the bucket, so
        # fall back to the base firmware's own PDA (Samsung stores it there).
        if [ -z "$BASE_FW_VERSION" ]; then
            BASE_FW_VERSION="$(grep -m1 '^ro.build.PDA=' "$BUILD_PROP" | cut -d "=" -f 2)"
        fi

        echo "Kernel version: ${KERNEL_VERSION:-unknown}"

        {
            echo "device=$DEVICE_CODENAME"
            echo "device_model=$STOCK_DEVICE"
            echo "version=$LUMIROM_VERSION"
            echo "version_code=$LUMIROM_CODE"
            echo "build_date=$(date +%F)"
            echo "android_version=$ANDROID_VERSION"
            echo "oneui_version=$ONEUI_VERSION"
            echo "oneui_code=$ONEUI_VERSION_UNCUT"
            echo "security_patch=$SECURITY_PATCH"
            echo "build_fingerprint=$FINGERPRINT"
            echo "kernel_version=${KERNEL_VERSION:-}"
            echo "base_firmware_version=${BASE_FW_VERSION}"
            echo "partition_layout=a-only"
            echo "timestamp=$TIMESTAMP"
            echo "status=$BUILD_STATUS"
            if [ "${KEEP_STOCK_FRAMEWORK:-false}" = "true" ]; then
                echo "build_mode=stock-framework-diagnostic"
            fi
        } > "$MAKEROM_DIR/build_info.txt"

        cp "$MAKEROM_DIR/build_info.txt" "$OUT_DIR/build_info.txt" 2>/dev/null || true

        SPECIFIC_BOOT="$(pwd)/LumiROM/Devices/$DEVICE/boot.img"

        if [ -f "$SPECIFIC_BOOT" ]; then
            echo "${GREEN}-> Copying boot.img from${RESET} $DEVICE..."
            cp "$SPECIFIC_BOOT" "$MAKEROM_DIR/boot.img"
        else
            echo "${RED}There is no boot.img for${RESET} $DEVICE"
        fi

        echo "${GREEN}Moving compressed DAT files to ROM Folder...${RESET}"
        mv TMP/*.new.dat.br "$MAKEROM_DIR"/
        mv TMP/*.patch.dat "$MAKEROM_DIR"/
        mv TMP/*.transfer.list "$MAKEROM_DIR"/ 2>/dev/null || true

        echo "${GREEN}Creating ZIP package...${RESET}"
        ZIP_FILE="LumiROM_${LUMIROM_VERSION}-${BUILD_DATE}_${BUILD_STATUS}_${DEVICE_CODENAME}.zip"
        [ -f "$ZIP_FILE" ] && rm "$ZIP_FILE"

        cd "$MAKEROM_DIR" || return 1

        # ZIP the rom with mixed compression levels (Multithreaded 7z). A failure
        # here used to be ignored, which left a payload-less zip that still got
        # signed and published, so both calls are fatal and the result is checked.
        echo "${YELLOW}Adding large/compressed files (Store)...${RESET}"
        7z a -bso0 -bsp0 -mx=0 -mmt=4 "$ZIP_FILE" ./*.new.dat.br ./*.patch.dat || return 1

        echo "${YELLOW}Adding scripts and compressible data (Compress)...${RESET}"
        7z a -bso0 -bsp0 -mx=6 -mmt=4 "$ZIP_FILE" ./boot.img ./META-INF ./build_info.txt ./dynamic_partitions_op_list ./*.transfer.list || return 1

        local EXPECTED_DATS ACTUAL_DATS REQUIRED
        EXPECTED_DATS=$(find . -maxdepth 1 -name '*.new.dat.br' | wc -l)
        ACTUAL_DATS=$(7z l -ba "$ZIP_FILE" | awk '{print $NF}' | grep -c '\.new\.dat\.br$' || true)
        if [ "$EXPECTED_DATS" -ne "${ACTUAL_DATS:-0}" ]; then
            echo "${RED}Error: $ZIP_FILE has ${ACTUAL_DATS:-0}/$EXPECTED_DATS partition payloads${RESET}" >&2
            return 1
        fi
        for REQUIRED in boot.img build_info.txt dynamic_partitions_op_list; do
            if ! 7z l -ba "$ZIP_FILE" | awk '{print $NF}' | grep -qx "$REQUIRED"; then
                echo "${RED}Error: $ZIP_FILE is missing $REQUIRED${RESET}" >&2
                return 1
            fi
        done

        mkdir -p "../ROM/${FOLDER_NAME}"
        mv "$ZIP_FILE" "../ROM/${FOLDER_NAME}"

        echo "${GREEN}ZIP package created: $ZIP_FILE${RESET}"

        cd ..
        rm -rf "$MAKEROM_DIR"
}

pkg_zip_images() {
    if [ "$#" -ne 2 ]; then
        echo "Usage: ${FUNCNAME[0]} <IMG_DIR> <OUT_ZIP>"
        return 1
    fi

    local IMG_DIR="$1"
    local OUT_ZIP="$2"

    echo "${BLUE}=== Creating ZIP from IMG files ===${RESET}"

    if ! ls "$IMG_DIR"/*.img >/dev/null 2>&1; then
        echo "${RED}Error: No .img files found in $IMG_DIR${RESET}"
        return 1
    fi

    mkdir -p "$(dirname "$OUT_ZIP")"

    if zip -0 -j "$OUT_ZIP" "$IMG_DIR"/*.img; then
        echo "${GREEN}ZIP created successfully: $OUT_ZIP${RESET}"
    else
        echo "${RED}Error: Failed to create ZIP file${RESET}"
        return 1
    fi
}

pkg_create_image_zip() {
    if [ "$#" -ne 1 ]; then
        echo "Usage: ${FUNCNAME[0]} <OUT_DIR>"
        return 1
    fi

    local OUT_DIR="$1"

    BUILD_DATE=$(date +'%d%m%Y')
    TIMESTAMP=$(date +'%s')
    DEVICE="$STOCK_DEVICE"
    local cut_version_stock="${STOCK_DEVICE:3:3}"
    local cut_version_target="${TARGET_DEVICE:3:3}"
    FOLDER_NAME="${BUILD_DATE}-${TIMESTAMP}-${cut_version_stock}_to_${cut_version_target}/"
    export FOLDER_NAME

    if [ -n "${GITHUB_ENV:-}" ]; then
        echo "FOLDER_NAME=$FOLDER_NAME" >> "$GITHUB_ENV"
    elif [ -n "${LUMIROM_ENV_FILE:-}" ]; then
        echo "FOLDER_NAME=$FOLDER_NAME" >> "$LUMIROM_ENV_FILE"
    fi

    if [[ "$DEVICE" == "SM-A325F" ]]; then
        DEVICE_CODENAME="a32"
    elif [[ "$DEVICE" == "SM-A325M" ]]; then
        DEVICE_CODENAME="a32m"
    elif [[ "$DEVICE" == "SM-A225F" ]]; then
        DEVICE_CODENAME="a22"
    elif [[ "$DEVICE" == "SM-M325F" ]]; then
        DEVICE_CODENAME="m32"
    elif [[ "$DEVICE" == "SM-E225F" ]]; then
        DEVICE_CODENAME="f22"
    else
        DEVICE_CODENAME="unknown"
    fi

    local ZIP_FILE="LumiROM_${LUMIROM_VERSION}-${BUILD_DATE}_${BUILD_STATUS}_${DEVICE_CODENAME}_IMG.zip"

    pkg_zip_images "$OUT_DIR" "$(pwd)/ROM/${FOLDER_NAME}${ZIP_FILE}"
}
pkg_create_target_files() {
    if [ "$#" -ne 1 ]; then
        echo "Usage: ${FUNCNAME[0]} <OUTPUT_ZIP>"
        return 1
    fi

    local OUTPUT_ZIP="$1"

    if ! ls "$OUT_DIR"/*.img >/dev/null 2>&1; then
        echo "${RED}Error: No .img files found in $OUT_DIR${RESET}"
        return 1
    fi

    if [ ! -f "$OUT_DIR/build_info.txt" ]; then
        echo "${RED}Error: build_info.txt not found in $OUT_DIR${RESET}"
        return 1
    fi

    local WORK_DIR_TF
    mkdir -p "$(pwd)/TMP"
    WORK_DIR_TF="$(mktemp -d -p "$(pwd)/TMP")"

    cp "$OUT_DIR"/*.img "$WORK_DIR_TF"/
    if ! cp "$OUT_DIR"/*.map "$WORK_DIR_TF"/ 2>/dev/null; then
        echo "${YELLOW}Warning: no block maps in $OUT_DIR; this target-files zip cannot be used as the source of an incremental OTA${RESET}"
    fi
    cp "$OUT_DIR/build_info.txt" "$WORK_DIR_TF"/

    local SPECIFIC_BOOT
    SPECIFIC_BOOT="$(pwd)/LumiROM/Devices/$STOCK_DEVICE/boot.img"
    [ -f "$SPECIFIC_BOOT" ] && cp "$SPECIFIC_BOOT" "$WORK_DIR_TF"/

    mkdir -p "$(dirname "$OUTPUT_ZIP")"
    rm -f "$OUTPUT_ZIP"
    (cd "$WORK_DIR_TF" && zip -q -r "$OUTPUT_ZIP" .)
    rm -rf "$WORK_DIR_TF"

    echo "${GREEN}Target files created: $OUTPUT_ZIP${RESET}"
}

#!/bin/bash
#
# LumiROM features: stock config, iccc, otacerts and officialness helpers.
# Part of scripts/features/LumiROM.sh (sourced by it); not meant to run alone.

rom_is_official() {
    export BUILD_STATUS="UNOFFICIAL"
    export ROM_TAG="🛠️ LumiROM Unofficial Build"

    # A build is official only when it is signed with LumiROM's own platform
    # key (not the AOSP testkey).
    if key_is_custom; then
        export BUILD_STATUS="OFFICIAL"
        export ROM_TAG="✨ LumiROM Official Build"
    fi

    if [ -n "${GITHUB_ENV:-}" ]; then
        echo "BUILD_STATUS=$BUILD_STATUS" >> "$GITHUB_ENV"
        echo "ROM_TAG=$ROM_TAG" >> "$GITHUB_ENV"
    fi

    echo "${BLUE}--- $ROM_TAG detected (key: $(key_active_source)) ---${RESET}"
}

rom_check_file() {
    if [ ! -f "$1" ]; then
        echo "${RED}[!] File not found:${RESET} $1"
        echo "- Skipping..."
        return 1
    fi
    return 0
}

rom_delete_iccc() {
    local EXTRACTED_FIRM_DIR="$1"
    echo "${YELLOW}Starting wipe...${RESET}"
    # Delete iccc to prevent soft-bootloop

    local targets=(
        "$EXTRACTED_FIRM_DIR/vendor/bin/hw/vendor.samsung.hardware.tlc.iccc@1.0-service"
        "$EXTRACTED_FIRM_DIR/vendor/etc/init/vendor.samsung.hardware.tlc.iccc@1.0-service.rc"
        "$EXTRACTED_FIRM_DIR/vendor/etc/vintf/manifest/vendor.samsung.hardware.tlc.iccc@1.0-manifest.xml"
        "$EXTRACTED_FIRM_DIR/vendor/lib64/vendor.samsung.hardware.tlc.iccc@1.0-impl.so"
        "$EXTRACTED_FIRM_DIR/vendor/lib64/vendor.samsung.hardware.tlc.iccc@1.0.so"
    )

    for file in "${targets[@]}"; do
        if [ -e "$file" ] || [ -L "$file" ]; then
            sudo rm -rf "$file"
            echo "${GREEN}Deleted${RESET} $file"
        else
            echo "${RED}[Omitted]${RESET} $file ${RED}not found${RESET}"
        fi
    done

    echo "${GREEN}Wipe iccc completed${RESET}"
}

rom_apply_stock_config() {
    echo ""
	echo "${GREEN}Applying ${RESET}$STOCK_DEVICE ${GREEN}device config.${RESET}"
    if [ "$#" -ne 1 ]; then
        echo "Usage: ${FUNCNAME[0]} <EXTRACTED_FIRM_DIR>"
        return 1
    fi

    local EXTRACTED_FIRM_DIR="$1"

    if [ ! -f "$DEVICES_DIR/$STOCK_DEVICE/config" ]; then
        echo "${RED}[Omitted] Config file for $STOCK_DEVICE not found in $DEVICES_DIR${RESET}"
        return 1
	fi

    if [ -f "$DEVICES_DIR/$STOCK_DEVICE/config" ]; then
        echo "${GREEN}-${RESET} $STOCK_DEVICE ${GREEN}config found.${RESET}"
        STOCK_VNDK_VERSION="$(grep -m1 '^STOCK_VNDK_VERSION=' "$DEVICES_DIR/$STOCK_DEVICE/config" | cut -d= -f2 | tr -d '\r' || true)"
        export STOCK_VNDK_VERSION
        STOCK_HAS_SEPARATE_SYSTEM_EXT="$(grep -m1 '^STOCK_HAS_SEPARATE_SYSTEM_EXT=' "$DEVICES_DIR/$STOCK_DEVICE/config" | cut -d= -f2 | tr -d '\r' || true)"
        export STOCK_HAS_SEPARATE_SYSTEM_EXT
		STOCK_DVFS_FILENAME="$(grep -m1 '^STOCK_DVFS_FILENAME=' "$DEVICES_DIR/$STOCK_DEVICE/config" | cut -d= -f2 | tr -d '\r' || true)"
		export STOCK_DVFS_FILENAME
    fi

    export STOCK_FLOATING_FEATURE="$DEVICES_DIR/$STOCK_DEVICE/floating_feature.xml"
	export TARGET_FLOATING_FEATURE="$EXTRACTED_FIRM_DIR/system/system/etc/floating_feature.xml"
	STOCK_SIOP_FILENAME="$(awk -F'[<>]' '$2 == "SEC_FLOATING_FEATURE_SYSTEM_CONFIG_SIOP_POLICY_FILENAME" {print $3}' "$STOCK_FLOATING_FEATURE" | tr -d '\r' | xargs)"
	export STOCK_SIOP_FILENAME

	# FIX SYSTEM_EXT.
    rom_fix_system_ext "$EXTRACTED_FIRM_DIR"

	# FIX VNDK.
	rom_fix_vndk

    # Floating Feature.
    rom_apply_floating_feature

    # Fix unsupported BPF error for kernels lower than 5.10.
    if [ "$USE_UI_8_TETHERING_APEX" = "true" ]; then
        cp -rfa "$(pwd)/LumiROM/Mods/bpf_patch/." "$EXTRACTED_FIRM_DIR/"
    fi

	# Replace Stock Files.
	rm -rf $EXTRACTED_FIRM_DIR/product/overlay/framework-res*auto_generated_rro_product.apk
    cp -af "$DEVICES_DIR/$STOCK_DEVICE/Stock/." "$EXTRACTED_FIRM_DIR/"

    # Fix duplicate property-context prefixes (prevents init fatal bootloop).
    rom_fix_property_contexts "$EXTRACTED_FIRM_DIR"

}

rom_kick() {
    if [ "$#" -ne 1 ]; then
        echo "Usage: ${FUNCNAME[0]} <EXTRACTED_FIRM_DIR>"
        return 1
    fi
    
	local EXTRACTED_FIRM_DIR="$1"

    echo "${YELLOW}- Debloating apps.${RESET}"
    local APP_DIRS=(
        "$EXTRACTED_FIRM_DIR/system/system/app"
        "$EXTRACTED_FIRM_DIR/system/system/priv-app"
        "$EXTRACTED_FIRM_DIR/system/system_ext/app"
        "$EXTRACTED_FIRM_DIR/system/system_ext/priv-app"
        "$EXTRACTED_FIRM_DIR/system_ext/app"
        "$EXTRACTED_FIRM_DIR/system_ext/priv-app"
        "$EXTRACTED_FIRM_DIR/product/app"
        "$EXTRACTED_FIRM_DIR/product/priv-app"
    )

    for app in "${DEBLOAT_APPS[@]}"; do
        for dir in "${APP_DIRS[@]}"; do
            target="$dir/$app"

            if [[ -d "$target" ]]; then
                rm -rf "$target" || echo "[WARN] Failed to remove $target"
            fi
        done
    done
}

rom_replace_otacerts() {
    if [ "$#" -ne 1 ]; then
        echo "Usage: ${FUNCNAME[0]} <EXTRACTED_FIRM_DIR>"
        return 1
    fi

    local EXTRACTED_FIRM_DIR="$1"

    local CERT
    CERT="$(key_ota_cert)"
    if [ -z "$CERT" ]; then
        echo "${YELLOW}No OTA certificate available, keeping stock otacerts.zip.${RESET}"
        return 0
    fi

    local TMP_DIR
    TMP_DIR="$(mktemp -d)"

    local CERT_NAME
    CERT_NAME="$(printf '%s' "$CERT" | sed "/CERTIFICATE/d" | tr -d "\n" | base64 -d | sha256sum | cut -d ' ' -f 1)"
    CERT_NAME="lumirom_ota_${CERT_NAME:0:16}.x509.pem"

    printf '%s\n' "$CERT" > "$TMP_DIR/$CERT_NAME"

    local OUT_OTACERTS="$EXTRACTED_FIRM_DIR/system/system/etc/security/otacerts.zip"
    mkdir -p "$(dirname "$OUT_OTACERTS")"

    echo "${YELLOW}Building otacerts.zip with LumiROM OTA certificate only...${RESET}"
    rm -f "$OUT_OTACERTS"
    (cd "$TMP_DIR" && zip -q "$OUT_OTACERTS" "$CERT_NAME")

    rm -rf "$TMP_DIR"

    echo "${GREEN}otacerts.zip replaced at $OUT_OTACERTS${RESET}"
    unzip -l "$OUT_OTACERTS"
}

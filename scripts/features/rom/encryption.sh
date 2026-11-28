#!/bin/bash
#
# LumiROM features: encryption flags (FBE/FDE, metadata encryption).
# Part of scripts/features/LumiROM.sh (sourced by it); not meant to run alone.

rom_strip_data_encryption() {
    local EXTRACTED_FIRM_DIR="$1"
    local fstab

    for fstab in "$EXTRACTED_FIRM_DIR"/vendor/etc/fstab.mt*; do
        [ -f "$fstab" ] || continue

        echo "${YELLOW}Removing /data encryption flags from $(basename "$fstab")...${RESET}"
        sudo sed -i -E '/^[^#].*[[:space:]]\/data[[:space:]]/ {
            s/,?inlinecrypt//g
            s/,?(fileencryption|keydirectory|forceencrypt|encryptable)=[^,[:space:]]*//g
            s/,,+/,/g
        }' "$fstab"

        grep -n '[[:space:]]/data[[:space:]]' "$fstab" | sed 's/^/    /'
    done
}

rom_disable_fbe() {
    local EXTRACTED_FIRM_DIR="$1"
 	
	if [ "$#" -ne 1 ]; then
        echo "Usage: ${FUNCNAME[0]} <EXTRACTED_FIRM_DIRECTORY>"
        return 1
    fi

    # Android 17 removed FDE support, and this vendor's keymaster 4.0 cannot
    # provide the keys for FBE v2 (KM_TAG_ROLLBACK_RESISTANCE is missing).
    # Keep /data unencrypted on A17+.
    local ANDROID_RELEASE
    ANDROID_RELEASE="$(grep -m1 '^ro.build.version.release=' "$EXTRACTED_FIRM_DIR/system/system/build.prop" 2>/dev/null | cut -d= -f2 | tr -d '[:space:]')"
    if [ -n "$ANDROID_RELEASE" ] && [ "$ANDROID_RELEASE" -ge 17 ] 2>/dev/null; then
        echo "${YELLOW}Android $ANDROID_RELEASE: removing all /data encryption (FBE/FDE/metadata).${RESET}"
        rom_strip_data_encryption "$EXTRACTED_FIRM_DIR"
        return 0
    fi

    local i

    for i in "$EXTRACTED_FIRM_DIR"/vendor/etc/fstab.mt*; do
    if [ -f $i ]; then
      echo "${YELLOW}Disabling full-based encryption (FBE) for /data...${RESET}"
      echo "- Found $i."
      # If found file-encryption, comments it
      sudo sed -i -e 's/^\([^#].*\)fileencryption=[^,]*\(.*\)$/# &\n\1encryptable\2/g' $i
      echo "${GREEN}Disabled file-encryption on${RESET} $i"
    fi
  done
}

rom_disable_fde() {
    local EXTRACTED_FIRM_DIR="$1"
 	
	if [ "$#" -ne 1 ]; then
        echo "Usage: ${FUNCNAME[0]} <EXTRACTED_FIRM_DIRECTORY>"
        return 1
    fi

    # Android 17 has no FDE; rom_disable_fbe already removed all /data
    # encryption flags (including forceencrypt/encryptable). Keep this
    # function idempotent for CI callers.
    local ANDROID_RELEASE
    ANDROID_RELEASE="$(grep -m1 '^ro.build.version.release=' "$EXTRACTED_FIRM_DIR/system/system/build.prop" 2>/dev/null | cut -d= -f2 | tr -d '[:space:]')"
    if [ -n "$ANDROID_RELEASE" ] && [ "$ANDROID_RELEASE" -ge 17 ] 2>/dev/null; then
        echo "${YELLOW}Android $ANDROID_RELEASE: /data encryption already stripped by rom_disable_fbe.${RESET}"
        return 0
    fi

    local i

    for i in "$EXTRACTED_FIRM_DIR"/vendor/etc/fstab.mt*; do
    if [ -f $i ]; then
      echo "${YELLOW}Disabling full-disk encryption (FDE) for /data...${RESET}"
      echo "- Found $i."
      # If found force-encryption, comments it
      sudo sed -i -e 's/^\([^#].*\)forceencrypt=[^,]*\(.*\)$/# &\n\1encryptable\2/g' $i
      echo "${GREEN}Disabled force-encryption on${RESET} $i"
    fi
  done
}

rom_remove_fabric_crypto() {
    if [ "$#" -ne 1 ]; then
        echo "Usage: ${FUNCNAME[0]} <EXTRACTED_FIRM_DIR>"
        return 1
    fi

    # Yes, we dont need that, it spams logs
	local EXTRACTED_FIRM_DIR="$1"
    echo "${YELLOW}- Removing fabric crypto.${RESET}"
    rm -rf "$EXTRACTED_FIRM_DIR/system/system/bin/fabric_crypto"
    rm -rf "$EXTRACTED_FIRM_DIR/system/system/etc/init/fabric_crypto.rc"
    rm -rf "$EXTRACTED_FIRM_DIR/system/system/etc/permissions/FabricCryptoLib.xml"
    rm -rf "$EXTRACTED_FIRM_DIR/system/system/etc/vintf/manifest/fabric_crypto_manifest.xml"
    rm -rf "$EXTRACTED_FIRM_DIR/system/system/framework/FabricCryptoLib.jar"
    rm -rf "$EXTRACTED_FIRM_DIR/system/system/framework/oat/arm/FabricCryptoLib.odex"
	rm -rf "$EXTRACTED_FIRM_DIR/system/system/framework/oat/arm/FabricCryptoLib.vdex"
	rm -rf "$EXTRACTED_FIRM_DIR/system/system/framework/oat/arm64/FabricCryptoLib.odex"
	rm -rf "$EXTRACTED_FIRM_DIR/system/system/framework/oat/arm64/FabricCryptoLib.vdex"
    rm -rf "$EXTRACTED_FIRM_DIR/system/system/lib64/com.samsung.security.fabric.cryptod-V1-cpp.so"
    rm -rf "$EXTRACTED_FIRM_DIR/system/system/lib64/vendor.samsung.hardware.security.fkeymaster-V1-ndk.so"
    rm -rf "$EXTRACTED_FIRM_DIR/system/system/priv-app/KmxService"
}

#!/bin/bash

source scripts/utils/bash_colors.sh

source scripts/utils/platform_key.sh

fota_sign_with_platform_key() {
    echo "" >&2
    if [ "$#" -ne 1 ]; then
        echo "Usage: ${FUNCNAME[0]} <APK>" >&2
        return 1
    fi

    local APK="$1"
    local KEY_DIR
    local PK8
    local CERT

    if [ ! -f "$APK" ]; then
        echo "${RED}APK not found: $APK${RESET}" >&2
        return 1
    fi

    KEY_DIR="$(key_files)"
    PK8="$KEY_DIR/platform.pk8"
    CERT="$KEY_DIR/platform.x509.pem"

    if [ ! -f "$PK8" ] || [ ! -f "$CERT" ]; then
        echo "${RED}Platform key not found in $KEY_DIR${RESET}" >&2
        return 1
    fi

    local OUT="${TMPDIR:-/tmp}/lumifota_signed_$$.apk"

    echo "${YELLOW} - Re-signing $APK with platform key${RESET}" >&2
    if ! apksigner sign --key "$PK8" --cert "$CERT" --out "$OUT" "$APK" 2>/dev/null; then
        echo "${RED} - Failed to sign $APK${RESET}" >&2
        rm -f "$OUT"
        return 1
    fi

    echo "${GREEN} - Signed with platform key${RESET}" >&2
    echo "$OUT"
}

fota_add() {
    if [ "$#" -ne 1 ]; then
        echo "Usage: ${FUNCNAME[0]} <EXTRACTED_FIRM_DIR>"
        return 1
    fi

    local EXTRACTED_FIRM_DIR="$1"
    local UPDATER_DIR="./LumiROM/Mods/LumiFota"

    mkdir -p "$UPDATER_DIR/system/system/priv-app/LumiFota/"
    mkdir -p "$UPDATER_DIR/system/system/etc/permissions/"
    mkdir -p "$UPDATER_DIR/system/system/etc/default-permissions/"
    mkdir -p "$UPDATER_DIR/system/system/etc/init/"

    echo "${YELLOW} - Adding LumiFota${RESET}"
    sudo cp -rfa "$UPDATER_DIR/system/system/." "$EXTRACTED_FIRM_DIR/system/system/"
    local SIGNED_APK
    SIGNED_APK="$(fota_sign_with_platform_key "$UPDATER_DIR/system/system/priv-app/LumiFota/LumiFota.apk")" || return 1
    if [ -n "$SIGNED_APK" ] && [ -f "$SIGNED_APK" ]; then
        sudo cp -f "$SIGNED_APK" "$EXTRACTED_FIRM_DIR/system/system/priv-app/LumiFota/LumiFota.apk"
        rm -f "$SIGNED_APK"
    else
        echo "${RED} - LumiFota not re-signed, keeping bundled signature${RESET}"
    fi

    echo "${YELLOW} - Baking LumiFota SELinux rules (system_ext_sepolicy.cil)${RESET}"
    local SELINUX_CIL="$EXTRACTED_FIRM_DIR/system/system_ext/etc/selinux/system_ext_sepolicy.cil"
    if [ ! -f "$SELINUX_CIL" ]; then
        SELINUX_CIL="$EXTRACTED_FIRM_DIR/system_ext/etc/selinux/system_ext_sepolicy.cil"
    fi

    if [ -f "$SELINUX_CIL" ]; then
        if grep -q "LumiFota OTA staging" "$SELINUX_CIL"; then
            echo "${GREEN} - Rules already present, skipping${RESET}"
        else
            cat >> "$SELINUX_CIL" <<'LUMIFOTA_EOF'
; LumiFota OTA staging: RecoverySystem writes /cache/recovery/uncrypt_file and
; the package lives in /data/ota_package/lumi (ota_package_file) so uncrypt,
; which runs as root, can read it while the device is still decrypted.
(allow platform_app_all cache_recovery_file (dir (search write add_name remove_name create getattr open)))
(allow platform_app_all cache_recovery_file (file (create open write getattr setattr unlink)))
(allow platform_app_all ota_package_file (dir (search write add_name remove_name create getattr open)))
(allow platform_app_all ota_package_file (file (create open read write getattr setattr unlink rename map ioctl lock)))
; Same, in case the app is mapped to priv_app instead of platform_app.
(allow priv_app_all ota_package_file (dir (search write add_name remove_name create getattr open)))
(allow priv_app_all ota_package_file (file (create open read write getattr setattr unlink rename map ioctl lock)))
; uncrypt resolves /dev/block/platform/bootdevice/by-name/userdata before
; writing the block map; without lnk_file read it fails with EACCES
; ("Failed to get canonical ..." / uncrypt_error 119) and the framework
; aborts the "Preparing to update" reboot.
(allow uncrypt userdata_block_device (lnk_file (ioctl read getattr lock map open watch watch_reads)))
(allow uncrypt userdata_block_device (blk_file (write read getattr ioctl lock append map open)))
LUMIFOTA_EOF
        fi
    else
        echo "${RED}Warning: system_ext_sepolicy.cil not found at${RESET} $SELINUX_CIL"
    fi

    echo "${GREEN} - LumiFota OTA updater added${RESET}"
}

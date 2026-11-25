#!/bin/bash
#
# One subcommand per feature step of the workflows, so both the per-device
# and the single-device workflow run exactly the same code.
#
#   features.sh vendor-patches   FBE/FDE, iccc, vendor debloat, erofs fstab
#   features.sh stock-config     Stock config/fstab fixes
#   features.sh debloat          WSM and system debloat
#   features.sh props            Build prop features
#   features.sh mods             LumiROM mods
#   features.sh hotspot          Hotspot/APEX fix (skipped with USE_MODS=false)
#   features.sh lumifota         LumiFota OTA updater (skipped with USE_MODS=false)
#   features.sh ai               Galaxy AI add/remove
#   features.sh display-id       LumiROM display id
#   features.sh framework-res    Install the stock framework-res
#   features.sh knox             Knox and SecSettings patches
#
# Requires: FIRM_DIR, WORK_DIR, APKTOOL, USE_MODS, USE_GALAXY_AI.

set -eo pipefail

: "${FIRM_DIR:?FIRM_DIR is not set}"
: "${WORK_DIR:?WORK_DIR is not set}"

case "${1:-}" in
    vendor-patches)
        source scripts/features/LumiROM.sh
        DISABLE_FBE "$FIRM_DIR"
        DISABLE_FDE "$FIRM_DIR"
        DELETE_ICCC "$FIRM_DIR"
        DEBLOAT_VENDOR "$FIRM_DIR"
        PATCH_FSTAB_EROFS "$FIRM_DIR"
        ;;
    stock-config)
        source scripts/features/LumiROM.sh
        APPLY_STOCK_CONFIG "$FIRM_DIR"
        ;;
    debloat)
        source scripts/features/LumiROM.sh
        DEBLOAT_WSM "$FIRM_DIR"
        DEBLOAT "$FIRM_DIR"
        ;;
    props)
        source scripts/features/LumiROM.sh
        APPLY_PROP_FEATURES "$FIRM_DIR"
        ;;
    mods)
        source scripts/features/Mods.sh
        ADD_MODS "$FIRM_DIR"
        ;;
    hotspot)
        if [ "${USE_MODS:-true}" = "true" ]; then
            source scripts/features/HotspotFix.sh
            ADD_SOFTAP_FIX "$FIRM_DIR"
        else
            echo "Mods are disabled, skipping hotspot patch"
        fi
        ;;
    lumifota)
        if [ "${USE_MODS:-true}" = "true" ]; then
            source scripts/features/LumiFota.sh
            ADD_LUMIFOTA "$FIRM_DIR"
        else
            echo "Mods are disabled, skipping LumiFota OTA Updater"
        fi
        ;;
    ai)
        source scripts/features/Galaxy_AI.sh
        GALAXY_AI "$FIRM_DIR"
        ;;
    display-id)
        source scripts/features/LumiROM.sh
        APPENDING_DISPLAY_ID "$FIRM_DIR"
        ;;
    framework-res)
        source scripts/features/LumiROM.sh
        INSTALL_FRAMEWORK "FIRMWARE/system/system/framework/framework-res.apk"
        ;;
    knox)
        source scripts/features/Knox_script.sh
        source scripts/utils/platform_key.sh
        source scripts/features/LumiROM.sh
        PATCH_SSRM "$WORK_DIR/ssrm"
        PATCH_KNOX_GUARD "$WORK_DIR/services"
        PATCH_FLAG_SECURE "$WORK_DIR/services"
        PATCH_SECURE_FOLDER "$WORK_DIR/services"
        CUSTOM_PLATFORM_SIGNATURE "$WORK_DIR/services" "$(GET_ACTIVE_CERT_HEX)"
        DISABLE_SIGNATURE_VERIFICATION "$WORK_DIR/framework"
        PATCH_SECSETTINGS "$WORK_DIR/SecSettings"
        PATCH_SETUPWIZARD "$WORK_DIR/SecSetupWizard_Global"
        ADD_LUMISETTINGS "$WORK_DIR/SecSettings" "$WORK_DIR/framework" "$WORK_DIR/services" "$WORK_DIR/SecSettingsIntelligence"
        ADD_KNOXPATCH "$WORK_DIR/framework" "$WORK_DIR/knoxsdk" "$WORK_DIR/samsungkeystoreutils"
        ;;
    *)
        echo "Usage: $0 <vendor-patches|stock-config|debloat|props|mods|hotspot|lumifota|ai|display-id|framework-res|knox>" >&2
        exit 1
        ;;
esac

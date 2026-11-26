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

# Every feature library this dispatcher can run. The shared pieces (colors,
# platform keys, AppPatches) come in through LumiROM.sh and are guarded.
source scripts/features/LumiROM.sh
source scripts/features/Mods.sh
source scripts/features/HotspotFix.sh
source scripts/features/LumiFota.sh
source scripts/features/Galaxy_AI.sh
source scripts/features/Knox_script.sh

case "${1:-}" in
    vendor-patches)
        rom_disable_fbe "$FIRM_DIR"
        rom_disable_fde "$FIRM_DIR"
        rom_delete_iccc "$FIRM_DIR"
        rom_debloat_vendor "$FIRM_DIR"
        rom_patch_fstab_erofs "$FIRM_DIR"
        ;;
    stock-config)
        rom_apply_stock_config "$FIRM_DIR"
        ;;
    debloat)
        rom_debloat_wsm "$FIRM_DIR"
        rom_debloat "$FIRM_DIR"
        ;;
    props)
        rom_apply_prop_features "$FIRM_DIR"
        ;;
    mods)
        mods_add "$FIRM_DIR"
        ;;
    hotspot)
        if [ "${USE_MODS:-true}" = "true" ]; then
            hotspot_add_fix "$FIRM_DIR"
        else
            echo "Mods are disabled, skipping hotspot patch"
        fi
        ;;
    lumifota)
        if [ "${USE_MODS:-true}" = "true" ]; then
            fota_add "$FIRM_DIR"
        else
            echo "Mods are disabled, skipping LumiFota OTA Updater"
        fi
        ;;
    ai)
        ai_apply "$FIRM_DIR"
        ;;
    display-id)
        rom_set_display_id "$FIRM_DIR"
        ;;
    framework-res)
        rom_install_framework "$FIRM_DIR/system/system/framework/framework-res.apk"
        ;;
    knox)
        knox_patch_ssrm "$WORK_DIR/ssrm"
        knox_patch_knox_guard "$WORK_DIR/services"
        knox_patch_flag_secure "$WORK_DIR/services"
        knox_patch_secure_folder "$WORK_DIR/services"
        knox_custom_platform_signature "$WORK_DIR/services" "$(key_cert_hex)"
        knox_disable_signature_verification "$WORK_DIR/framework"
        apps_patch_secsettings "$WORK_DIR/SecSettings"
        apps_patch_setupwizard "$WORK_DIR/SecSetupWizard_Global"
        apps_add_lumisettings "$WORK_DIR/SecSettings" "$WORK_DIR/framework" "$WORK_DIR/services" "$WORK_DIR/SecSettingsIntelligence"
        apps_add_knoxpatch "$WORK_DIR/framework" "$WORK_DIR/knoxsdk" "$WORK_DIR/samsungkeystoreutils"
        ;;
    *)
        echo "Usage: $0 <vendor-patches|stock-config|debloat|props|mods|hotspot|lumifota|ai|display-id|framework-res|knox>" >&2
        exit 1
        ;;
esac

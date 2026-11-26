#!/bin/bash

# =====================================================================
#  LumiROM local builder
# =====================================================================
#
# Shell options:
#   -u           Fail on unset variables, so typos and a missing .env value
#                stop the build instead of producing a broken ROM.
#   -o pipefail  A pipeline fails if any command in it fails.
#
# `set -e` is intentionally not enabled: every build step goes through run(),
# which aborts on failure with a clear message, while other helpers rely on
# non-zero returns for control flow.
set -uo pipefail

START_TIME=$(date +%s)

# Load local overrides (LUMIROM_VERSION, signing keys...). Forks may not have a .env.
if [ -f .env ]; then
    source .env
fi

# =====================================================================
#  Default configuration
# =====================================================================
set_defaults() {
    STOCK_DEVICE=""
    TARGET_DEVICE=""
    TARGET_CSC=""
    TARGET_IMEI=""
    USE_MODS="true"
    USE_GALAXY_AI="false"
    USE_UI_8_TETHERING_APEX="false"
    ZIP_IMG="false"
    INCREMENTAL_FROM=""
    SKIP_TARGET_FILES="false"
    KEEP_STOCK_FRAMEWORK="false"
    LUMIROM_MAINTAINER="$(git config user.name 2>/dev/null)"
}

# =====================================================================
#  Helpers
# =====================================================================

# die <message>: print the error, record it in the error log and abort.
# Works before the logging system is loaded (setup_environment).
die() {
    local message="$*"
    printf '\n%sERROR:%s %s\n' "${RED:-}" "${RESET:-}" "$message" >&2
    if [ -n "${ERROR_LOG:-}" ]; then
        printf '[%s] ERROR: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$message" >> "$ERROR_LOG" 2>/dev/null || true
    fi
    exit 1
}

# Runs a command piping its output to the log. Aborts the build on failure:
# piping to tee hides the real exit status, so it is read from PIPESTATUS.
run() {
    local status
    "$@" 2>&1 | tee -a "${LOG_FILE:-/dev/null}"
    status=${PIPESTATUS[0]}
    [ "$status" -eq 0 ] || die "command failed (exit $status): $*"
    return 0
}

# Like `run`, but without aborting on failure (optional/cleanup steps).
try() {
    "$@" 2>&1 | tee -a "${LOG_FILE:-/dev/null}"
    return "${PIPESTATUS[0]}"
}

# Like `run`, but in the background (for parallel jobs).
# Collect the jobs with wait_jobs before using their output.
PAR_PIDS=()
par() {
    run "$@" &
    PAR_PIDS+=("$!")
}

# Waits for every job started with par(), then aborts if any of them failed.
wait_jobs() {
    local pid failed=0
    for pid in "${PAR_PIDS[@]}"; do
        wait "$pid" || failed=1
    done
    PAR_PIDS=()
    [ "$failed" -eq 0 ] || die "one or more parallel jobs failed (see the log above)"
}

usage() {
    echo "LumiROM local builder"
    echo ""
    echo "Usage: bash build_local.sh -s <STOCK_DEVICE> -c <CSC> -i <IMEI> [options]"
    echo ""
    echo "Required:"
    echo "  -s, --stock <SM-XXXXX>     Your phone model (must be supported)"
    echo "  -c, --csc <XXX>            Region code of the base firmware (3 letters)"
    echo "  -i, --imei <15 digits>     Valid IMEI of the base device"
    echo ""
    echo "Optional:"
    echo "  -t, --target <SM-XXXXX>    Base device to port from (auto-derived from stock if omitted)"
    echo "  -m, --maintainer <name>    Maintainer name (default: git config user.name)"
    echo "      --no-mods              Exclude mods (LumiFota app, Vulkan fix, VoLTE fix, tweaks, wallpapers)"
    echo "      --ai                   Enable Galaxy AI (disabled by default)"
    echo "      --no-ai                Explicitly disable Galaxy AI (default)"
    echo "      --bpf-legacy           Enable if your kernel BPF version is lower than 5.10"
    echo "      --img-zip              Deliver the partition images (.img) in a ZIP instead of a flashable ROM"
    echo "      --no-target-files      Skip generating the TARGET_FILES zip (useful for test builds)"
    echo "      --stock-framework      Diagnostic build: keep the stock framework.jar (no LumiSettings/KnoxPatch framework changes)"
    echo "      --incremental-from <ver>"
    echo "                             Build an incremental OTA from a previous version saved in TARGET_FILES"
    echo "  -h, --help                 Show this help"
    echo ""
    echo "Supported devices:"
    ls LumiROM/Devices 2>/dev/null || echo "  (run this script from the repository root)"
    echo ""
    echo "Examples:"
    echo "  bash build_local.sh -s SM-A325F -c EUX -i 353117555323497"
    echo "  bash build_local.sh -s SM-A225F -c INS -i 358212589089183 --ai --img-zip"
}

# =====================================================================
#  Argument parsing
# =====================================================================
parse_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            -s|--stock)   STOCK_DEVICE="${2:?Option $1 requires a value}"; shift 2 ;;
            -t|--target)  TARGET_DEVICE="${2:?Option $1 requires a value}"; shift 2 ;;
            -c|--csc)     TARGET_CSC="${2:?Option $1 requires a value}"; shift 2 ;;
            -i|--imei)    TARGET_IMEI="${2:?Option $1 requires a value}"; shift 2 ;;
            -m|--maintainer) LUMIROM_MAINTAINER="${2:?Option $1 requires a value}"; shift 2 ;;
            --no-mods)    USE_MODS="false"; shift ;;
            --ai)         USE_GALAXY_AI="true"; shift ;;
            --no-ai)      USE_GALAXY_AI="false"; shift ;;
            --bpf-legacy) USE_UI_8_TETHERING_APEX="true"; shift ;;
            --img-zip)    ZIP_IMG="true"; shift ;;
            --no-target-files) SKIP_TARGET_FILES="true"; shift ;;
            --stock-framework) KEEP_STOCK_FRAMEWORK="true"; shift ;;
            --incremental-from) INCREMENTAL_FROM="${2:?Option $1 requires a value}"; shift 2 ;;
            -h|--help)    usage; exit 0 ;;
            *) echo "Unknown option: $1"; echo ""; usage; exit 1 ;;
        esac
    done
}

# =====================================================================
#  Interactive wizard for missing values
#  A346B imei = 353117555323497
# =====================================================================
run_wizard() {
    if [ -z "$STOCK_DEVICE" ]; then
        echo "Supported devices:"
        ls LumiROM/Devices
        read -rp "Stock device (SM-XXXXX): " STOCK_DEVICE
    fi

    if [ -z "$TARGET_CSC" ]; then
        read -rp "CSC/Region (3 letters, e.g. DBT): " TARGET_CSC
    fi

    if [ -z "$TARGET_IMEI" ]; then
        echo "Tip: example IMEIs for each base device are listed above."
        read -rp "IMEI of the base device (15 digits): " TARGET_IMEI
    fi

    if [ -z "$LUMIROM_MAINTAINER" ]; then
        read -rp "Maintainer name (GitHub or Telegram username): " LUMIROM_MAINTAINER
    fi
}

# =====================================================================
#  Device resolution and validation
# =====================================================================
resolve_target_device() {
    if [ -z "$TARGET_DEVICE" ]; then
        TARGET_DEVICE=$(fw_get_base_device "$STOCK_DEVICE") || die "no base device for $STOCK_DEVICE"
    fi

    validate_inputs

    # Device config (STOCK_SUPER_SIZE, CACHE_PARTITION_SIZE, ...), loaded once
    # the inputs are known to be valid.
    source "$DEVICES_DIR/$STOCK_DEVICE/config"
}

# =====================================================================
#  System environment variables
# =====================================================================

# Loads every library the pipeline needs. Doing it once here means a step can
# never pull a module in halfway through a build, and it documents the
# dependencies at the top of the file.
load_modules() {
    source scripts/firmware/FW.sh
    source scripts/utils/validation.sh
    source scripts/utils/install_packages.sh
    source scripts/firmware/local_official.sh
    source scripts/features/LumiROM.sh
    source scripts/features/Mods.sh
    source scripts/features/HotspotFix.sh
    source scripts/features/LumiFota.sh
    source scripts/features/Galaxy_AI.sh
    source scripts/features/Knox_script.sh
    source scripts/package/zip_creation.sh
    source scripts/package/sign_ota.sh
    source scripts/package/build_incremental_ota.sh
}

# Paths and flags. Must run before load_modules (DEVICES_DIR) and before the
# modules that read these variables at load time.
setup_paths() {
    if [ -z "${LUMIROM_VERSION:-}" ]; then
        die "LUMIROM_VERSION is not set. Add it to .env (LUMIROM_VERSION=<version>) or export it before running this script."
    fi

    export OUTPUT_FILESYSTEM="erofs"
    export LUMIROM_CODE="${LUMIROM_VERSION//./0}"
    export OUT_DIR="$PWD/OUT"
    export WORK_DIR="$PWD/TMP/LumiWORK"
    export FIRM_DIR="$PWD/FIRMWARE"
    export IMGS_DIR="$PWD/IMGs"
    export DEVICES_DIR="$PWD/LumiROM/Devices"
    export APKTOOL="$PWD/bin/apktool/apktool.jar"
    export VNDKS_COLLECTION="$PWD/LumiROM/vndks"
    export BUILD_PARTITIONS="product,vendor,odm,system_ext,system"
    export SKIP_TARGET_FILES
    export KEEP_STOCK_FRAMEWORK

    # Mirror the workflows' $GITHUB_ENV: a file where functions invoked through
    # run() (which pipes them into a subshell) can persist globals such as
    # FOLDER_NAME so the caller still sees them after they return.
    LUMIROM_ENV_FILE="$(mktemp)"
    export LUMIROM_ENV_FILE

    # Android build-tools (zipalign/apksigner) needed by apps_rebuild_and_sign_apk.
    # Ubuntu ships them under /usr/lib/android-sdk/build-tools/debian/ (not in PATH).
    if [ -d "$HOME/Android/Sdk/build-tools" ]; then
        BT_DIR=$(ls -d "$HOME"/Android/Sdk/build-tools/*/ 2>/dev/null | sort -V | tail -1)
        export PATH="$BT_DIR:$PATH"
    fi
    if [ -d /usr/lib/android-sdk/build-tools/debian ]; then
        export PATH="/usr/lib/android-sdk/build-tools/debian:$PATH"
    fi
}

setup_logging() {
    initialize_logs "$STOCK_DEVICE" "$TARGET_DEVICE" "$TARGET_CSC" "$TARGET_IMEI" "$LUMIROM_VERSION" "$USE_MODS" "$USE_GALAXY_AI" "$USE_UI_8_TETHERING_APEX" "$OUTPUT_FILESYSTEM" "$LUMIROM_MAINTAINER"
}

# =====================================================================
#  Environment preparation
# =====================================================================
setup_permissions() {
    log_section "Setting up permissions"
    find scripts -name "*.sh" -exec chmod +x {} +
    chmod +x bin/MergeOTA/MergeAll.sh
    chmod +x bin/erofs-utils/extract.erofs
    chmod +x bin/erofs-utils/mkfs.erofs
    chmod +x bin/lp/*
    log_message "Permissions set successfully"
}

install_packages() {
    log_section "Installing required packages"
    run deps_install
}

setup_directories() {
    log_section "Setting up directories"
    mkdir -p "$WORK_DIR"
    run bash scripts/utils/setup_directories.sh FIRMWARE WORK OUT ROM TMP IMGs TARGET_FILES LOGS
}

check_environment() {
    log_section "Checking the environment"
    # Runs in the current shell: is_local_official exports BUILD_STATUS, which
    # the packaging steps need. Process substitution keeps stdout visible while
    # still writing it to the log.
    if ! is_local_official > >(tee -a "$LOG_FILE") 2>&1; then
        die "environment check failed (is_local_official)"
    fi
}

# =====================================================================
#  Firmware download and preparation
# =====================================================================
download_firmware() {
    log_section "Downloading Firmware"

    # Check if firmware images are already cached
    log_message "Checking firmware cache..."
    if fw_check_firmware_images "$IMGS_DIR" "$BUILD_PARTITIONS"; then
        log_message "✓ Firmware cache found. Skipping download..."
    elif try bash scripts/firmware/fw_bucket.sh pull; then
        log_message "✓ Base images pulled from the FW bucket."
    else
        log_message "✗ No firmware cache found. Proceeding with download..."
        run fw_download_firmware "$TARGET_DEVICE" "$TARGET_CSC" "$TARGET_IMEI" "$FIRM_DIR"
    fi

    if [[ -f "IMGs/${TARGET_DEVICE}.zip" ]]; then
        log_section "Extracting $TARGET_DEVICE images"
        run fw_extract_firmware "$IMGS_DIR"
        run fw_extract_super_image "$IMGS_DIR"
    fi
}

download_vendor() {
    log_message "Checking vendor cache..."
    if fw_check_vendor_image "$IMGS_DIR"; then
        log_message "✓ Vendor cache found. Skipping download..."
        sleep 1
    else
        log_message "✗ No vendor cache found. Proceeding with download..."
        run fw_download_vendor "$IMGS_DIR"
    fi
}

prepare_partitions() {
    log_section "Preparing partitions"
    run fw_prepare_partitions "$IMGS_DIR"
    run fw_extract_partitions "$IMGS_DIR" "$FIRM_DIR"
}

# =====================================================================
#  LumiROM features applied to the firmware
# =====================================================================
apply_rom_features() {
    log_message "Applying LumiROM features..."
    run rom_disable_fbe "$FIRM_DIR"
    run rom_disable_fde "$FIRM_DIR"
    run rom_delete_iccc "$FIRM_DIR"
    run rom_debloat_vendor "$FIRM_DIR"
    run rom_debloat_wsm "$FIRM_DIR"
    run rom_patch_fstab_erofs "$FIRM_DIR"
    run rom_apply_stock_config "$FIRM_DIR"
    run rom_debloat "$FIRM_DIR"
    run rom_apply_prop_features "$FIRM_DIR"
    #run rom_enable_zygote_stdio "$FIRM_DIR"
    #run rom_enable_logcat_persist "$FIRM_DIR"
}

add_mods() {
    log_section "Adding Mods"
    run mods_add "$FIRM_DIR"

    log_section "Patching hotspot"
    run hotspot_add_fix "$FIRM_DIR"

    log_section "Adding LumiFota OTA Updater"
    run fota_add "$FIRM_DIR"
}

add_galaxy_ai() {
    if [ "$USE_GALAXY_AI" = "true" ]; then
        log_section "Adding Galaxy AI"
    else
        log_section "Removing Galaxy AI"
    fi
    run ai_apply "$FIRM_DIR"
}

apply_display_id() {
    log_section "Appending Display ID"
    run rom_set_display_id "$FIRM_DIR"
    run rom_install_framework "FIRMWARE/system/system/framework/framework-res.apk"
}

# =====================================================================
#  Knox & Framework patching
# =====================================================================
decompile_framework() {
    log_section "Patching Knox and Framework"
    par rom_decompile "$APKTOOL" "FIRMWARE/system/system/framework/ssrm.jar" "$WORK_DIR"
    par rom_decompile "$APKTOOL" "FIRMWARE/system/system/framework/services.jar" "$WORK_DIR"
    par rom_decompile "$APKTOOL" "FIRMWARE/system/system/framework/framework.jar" "$WORK_DIR"
    par rom_decompile "$APKTOOL" "FIRMWARE/system/system/framework/knoxsdk.jar" "$WORK_DIR"
    par rom_decompile "$APKTOOL" "FIRMWARE/system/system/framework/samsungkeystoreutils.jar" "$WORK_DIR"
    par rom_decompile "$APKTOOL" "FIRMWARE/system/system/priv-app/SecSettings/SecSettings.apk" "$WORK_DIR"
    par rom_decompile "$APKTOOL" "FIRMWARE/system/system/priv-app/SecSettingsIntelligence/SecSettingsIntelligence.apk" "$WORK_DIR"
    par rom_decompile "$APKTOOL" "FIRMWARE/system/system/priv-app/SecSetupWizard_Global/SecSetupWizard_Global.apk" "$WORK_DIR"
    wait_jobs
}

apply_knox_patches() {
    log_section "Applying Knox and Framework patches"
    run knox_patch_ssrm "$WORK_DIR/ssrm"
    run knox_patch_knox_guard "$WORK_DIR/services"
    run knox_patch_flag_secure "$WORK_DIR/services"
    run knox_patch_secure_folder "$WORK_DIR/services"
    run knox_custom_platform_signature "$WORK_DIR/services" "$(key_cert_hex)"
    if [ "$KEEP_STOCK_FRAMEWORK" != "true" ]; then
        run knox_disable_signature_verification "$WORK_DIR/framework"
    else
        log_message "Diagnostic build: skipping knox_disable_signature_verification (stock framework.jar)"
    fi
    run apps_patch_secsettings "$WORK_DIR/SecSettings"
    run apps_patch_setupwizard "$WORK_DIR/SecSetupWizard_Global"
    run apps_add_lumisettings "$WORK_DIR/SecSettings" "$WORK_DIR/framework" "$WORK_DIR/services" "$WORK_DIR/SecSettingsIntelligence"
    if [ "$KEEP_STOCK_FRAMEWORK" = "true" ]; then
        log_message "Diagnostic build: skipping apps_add_knoxpatch (stock framework.jar)"
    else
        run apps_add_knoxpatch "$WORK_DIR/framework" "$WORK_DIR/knoxsdk" "$WORK_DIR/samsungkeystoreutils"
    fi
}

recompile_framework() {
    log_section "Recompiling Knox and Framework"
    par rom_recompile "$APKTOOL" "$WORK_DIR/ssrm" "FIRMWARE/system/system/framework" "$WORK_DIR"
    par rom_recompile "$APKTOOL" "$WORK_DIR/services" "FIRMWARE/system/system/framework" "$WORK_DIR"
    if [ "$KEEP_STOCK_FRAMEWORK" = "true" ]; then
        log_message "Diagnostic build: using stock framework.jar, knoxsdk.jar and samsungkeystoreutils.jar"
        cp -f "FIRMWARE/system/system/framework/framework.jar" "$WORK_DIR/framework.jar"
        cp -f "FIRMWARE/system/system/framework/knoxsdk.jar" "$WORK_DIR/knoxsdk.jar"
        cp -f "FIRMWARE/system/system/framework/samsungkeystoreutils.jar" "$WORK_DIR/samsungkeystoreutils.jar"
    else
        par rom_recompile "$APKTOOL" "$WORK_DIR/framework" "FIRMWARE/system/system/framework" "$WORK_DIR"
        par rom_recompile "$APKTOOL" "$WORK_DIR/knoxsdk" "FIRMWARE/system/system/framework" "$WORK_DIR"
        par rom_recompile "$APKTOOL" "$WORK_DIR/samsungkeystoreutils" "FIRMWARE/system/system/framework" "$WORK_DIR"
    fi
    par apps_rebuild_and_sign_apk "$APKTOOL" "$WORK_DIR/SecSettings" "$HOME/.local/share/apktool/framework" "$WORK_DIR/SecSettings_rebuilt.apk"
    par apps_rebuild_and_sign_apk "$APKTOOL" "$WORK_DIR/SecSettingsIntelligence" "$HOME/.local/share/apktool/framework" "$WORK_DIR/SecSettingsIntelligence_rebuilt.apk"
    par apps_rebuild_and_sign_apk "$APKTOOL" "$WORK_DIR/SecSetupWizard_Global" "$HOME/.local/share/apktool/framework" "$WORK_DIR/SecSetupWizard_Global_rebuilt.apk"
    wait_jobs

    if [ ! -f "$WORK_DIR/SecSettings_rebuilt.apk" ] || \
            [ ! -f "$WORK_DIR/SecSettingsIntelligence_rebuilt.apk" ] || \
            [ ! -f "$WORK_DIR/SecSetupWizard_Global_rebuilt.apk" ] || \
            [ ! -f "$WORK_DIR/framework.jar" ] || \
            [ ! -f "$WORK_DIR/services.jar" ] || \
            [ ! -f "$WORK_DIR/knoxsdk.jar" ] || \
            [ ! -f "$WORK_DIR/samsungkeystoreutils.jar" ]; then
        die "a decompiled artifact failed to recompile (see the log above)"
    fi

    run rom_fix_framework_mime "FIRMWARE/system/system/framework/framework.jar" "$WORK_DIR/framework.jar"

    run cp -fv "$WORK_DIR"/*.jar "FIRMWARE/system/system/framework/"
    if [ "$KEEP_STOCK_FRAMEWORK" != "true" ]; then
        log_message "Removing stale boot-framework artifacts (framework.jar changed)"
        rm -f "FIRMWARE/system/system/framework/boot-framework.vdex"
        local ARCH
        for ARCH in arm arm64; do
            rm -f "FIRMWARE/system/system/framework/$ARCH/boot-framework.art" \
                  "FIRMWARE/system/system/framework/$ARCH/boot-framework.oat" \
                  "FIRMWARE/system/system/framework/$ARCH/boot-framework.vdex"
        done
    fi
    if [ -f "$WORK_DIR/SecSettings_rebuilt.apk" ]; then
        run cp -fv "$WORK_DIR/SecSettings_rebuilt.apk" "FIRMWARE/system/system/priv-app/SecSettings/SecSettings.apk"
    fi
    if [ -f "$WORK_DIR/SecSettingsIntelligence_rebuilt.apk" ]; then
        run cp -fv "$WORK_DIR/SecSettingsIntelligence_rebuilt.apk" "FIRMWARE/system/system/priv-app/SecSettingsIntelligence/SecSettingsIntelligence.apk"
    fi
    if [ -f "$WORK_DIR/SecSetupWizard_Global_rebuilt.apk" ]; then
        run cp -fv "$WORK_DIR/SecSetupWizard_Global_rebuilt.apk" "FIRMWARE/system/system/priv-app/SecSetupWizard_Global/SecSetupWizard_Global.apk"
    fi
}

# =====================================================================
#  ROM build and packaging
# =====================================================================
build_rom() {
    log_section "Building ROM"
    run rom_replace_otacerts "$FIRM_DIR"
    run fw_build_images "$FIRM_DIR" "$OUTPUT_FILESYSTEM" "$OUT_DIR"
}

package_output() {
    if [ "$ZIP_IMG" = "true" ]; then
        log_section "Creating IMG ZIP"
        run pkg_create_image_zip "$OUT_DIR"
    else
        run fw_images_to_brotli "$OUT_DIR" "TMP"

        log_section "Creating flashable ZIP"
        run pkg_render_updater_script "$FIRM_DIR"
        inject_camera_cleanup_file "$(pwd)/makerom/META-INF/com/google/android/updater-script"
        run pkg_create_flashable_zip

        if [ -s "$LUMIROM_ENV_FILE" ]; then
            . "$LUMIROM_ENV_FILE"
            export FOLDER_NAME
        fi

        log_section "Signing OTA package"
        OTA_ZIP=$(find ./ROM/"$FOLDER_NAME" -type f -name "*.zip" ! -name "*INCREMENTAL*" 2>/dev/null | head -n 1)
        if [ -n "$OTA_ZIP" ]; then
            run ota_sign_zip "$OTA_ZIP"
        else
            log_message "No flashable zip found to sign, skipping."
        fi

        log_section "Saving target files"
        if [ "$SKIP_TARGET_FILES" != "true" ]; then
            run pkg_create_target_files "$PWD/TARGET_FILES/LumiROM_TARGET_${LUMIROM_VERSION}_${STOCK_DEVICE}.zip"
        else
            log_message "Skipping target files (--no-target-files)"
        fi

        if [ -n "$INCREMENTAL_FROM" ]; then
            if [ "$SKIP_TARGET_FILES" = "true" ]; then
                log_message "[!] Target files skipped: this version won't be available as a base for a future incremental OTA."
            fi
            log_section "Building incremental OTA"
            run ota_build "$PWD/TARGET_FILES/LumiROM_TARGET_${INCREMENTAL_FROM}_${STOCK_DEVICE}.zip" "$OUT_DIR"
            INCREMENTAL_ZIP="$(find ./ROM/"$FOLDER_NAME" -type f -name "*INCREMENTAL*.zip" 2>/dev/null | head -n 1)"
            if [ -n "$INCREMENTAL_ZIP" ]; then
                inject_camera_cleanup_zip "$INCREMENTAL_ZIP"

                log_section "Signing incremental OTA"
                run ota_sign_zip "$INCREMENTAL_ZIP"
            fi
        fi
    fi
}

# =====================================================================
#  Cleanup and closure
# =====================================================================
cleanup() {
    log_message "Cleaning up temporary directories..."
    if ! try sudo rm -rf ./OUT/ ./TMP/ ./WORK/ ./FIRMWARE/ ./makerom/; then
        log_message "Warning: could not remove some temporary directories (continuing)"
    fi
    if [ -n "${LUMIROM_ENV_FILE:-}" ]; then
        rm -f "$LUMIROM_ENV_FILE"
    fi

    log_message "✓ LumiROM $LUMIROM_VERSION for $STOCK_DEVICE is ready!"
    log_message "✓ You can find it in the ROM folder"
}

finalize() {
    # Generate build summary and finalize logs
    finalize_logs "$START_TIME"
}

# =====================================================================
#  Entry point
# =====================================================================
main() {
    set_defaults
    parse_args "$@"
    run_wizard
    setup_paths
    load_modules
    resolve_target_device
    setup_logging
    setup_permissions
    install_packages
    setup_directories
    check_environment
    download_firmware
    download_vendor
    prepare_partitions
    apply_rom_features
    if [ "$USE_MODS" = "true" ]; then
        add_mods
    fi
    # ai_apply() handles both paths: it adds the mod when USE_GALAXY_AI=true
    # and removes the stock AI apps when it is false, so it must always run.
    add_galaxy_ai
    apply_display_id
    decompile_framework
    apply_knox_patches
    recompile_framework
    build_rom
    package_output
    cleanup
    finalize
}

main "$@"
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

source scripts/utils/config.sh

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
    # shellcheck source=/dev/null
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
    export BUILD_PARTITIONS="$LUMIROM_BUILD_PARTITIONS"
    export LUMIROM_VERSION LUMIROM_MAINTAINER
    export STOCK_DEVICE TARGET_DEVICE TARGET_CSC TARGET_IMEI
    export USE_MODS USE_GALAXY_AI USE_UI_8_TETHERING_APEX ZIP_IMG INCREMENTAL_FROM
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
# =====================================================================
#  Pipeline
# =====================================================================
# One step = one script under scripts/ci. The order lives in
# scripts/ci/steps.sh, which the workflows walk too, so both paths run the
# same steps in the same order.
run_step() {
    run bash scripts/ci/steps.sh "$1"
}

fetch_firmware() {
    log_section "Downloading Firmware"
    log_message "Checking firmware cache..."
    if fw_check_firmware_images "$IMGS_DIR" "$BUILD_PARTITIONS"; then
        log_message "✓ Firmware cache found. Skipping download..."
    else
        log_message "✗ No firmware cache found. Fetching the base firmware..."
        run_step firmware-base
    fi
}

fetch_vendor() {
    log_message "Checking vendor cache..."
    if fw_check_vendor_image "$IMGS_DIR"; then
        log_message "✓ Vendor cache found. Skipping download..."
    else
        log_message "✗ No vendor cache found. Proceeding with download..."
        run_step firmware-vendor
    fi
}

prepare_partitions() {
    log_section "Preparing partitions"
    run_step firmware-partitions
}

# Features, framework patches and image build, in the shared order.
run_pipeline() {
    local STEP
    for STEP in \
        features-vendor features-stock features-debloat features-props \
        features-mods features-hotspot features-fota features-ai \
        features-display features-framework-res \
        framework-decompile features-knox framework-recompile \
        rom-build; do
        log_section "$STEP"
        run_step "$STEP"
    done
}

# =====================================================================
#  ROM packaging
# =====================================================================
package_output() {
    if [ "$ZIP_IMG" = "true" ]; then
        log_section "Creating IMG ZIP"
        run_step rom-img-zip
        return 0
    fi

    log_section "Creating flashable ZIP"
    run_step rom-updater-script
    run_step rom-inject-cleanup
    run_step rom-flashable

    if [ -s "$LUMIROM_ENV_FILE" ]; then
        # shellcheck source=/dev/null
        . "$LUMIROM_ENV_FILE"
        export FOLDER_NAME
    fi

    log_section "Signing OTA package"
    run_step rom-sign

    log_section "Saving target files"
    if [ "$SKIP_TARGET_FILES" != "true" ]; then
        # Local builds keep the target files in TARGET_FILES/ (no upload).
        HF_TOKEN="" HF_USER="" run_step rom-target-files
    else
        log_message "Skipping target files (--no-target-files)"
    fi

    if [ -n "$INCREMENTAL_FROM" ]; then
        if [ "$SKIP_TARGET_FILES" = "true" ]; then
            log_message "[!] Target files skipped: this version won't be available as a base for a future incremental OTA."
        fi
        log_section "Building incremental OTA"
        INCREMENTAL_SOURCE_ZIP="$PWD/TARGET_FILES/LumiROM_TARGET_${INCREMENTAL_FROM}_${STOCK_DEVICE}.zip"
        export INCREMENTAL_SOURCE_ZIP
        run_step ota-build
        run_step ota-inject-cleanup
        log_section "Signing incremental OTA"
        run_step ota-sign
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
    fetch_firmware
    fetch_vendor
    prepare_partitions
    run_pipeline
    package_output
    cleanup
    finalize
}

main "$@"

#!/bin/bash
#
# ROM build and packaging steps:
#
#   rom.sh build                Replace otacerts, build every partition image
#                               and (unless ZIP_IMG=true) convert them to SDAT.
#   rom.sh updater-script       Render makerom's updater-script for this build.
#   rom.sh inject-camera-cleanup Inject the SamsungCamera dirty-flash cleanup
#                               into the full OTA's updater-script.
#   rom.sh flashable-zip        Build the flashable ROM zip.
#   rom.sh img-zip              Build the .img ZIP (ZIP_IMG=true).
#   rom.sh sign                 Sign the flashable ROM.
#   rom.sh target-files         Create and upload the target-files zip.
#
# Requires: FIRM_DIR, OUT_DIR, OUTPUT_FILESYSTEM, ZIP_IMG, STOCK_DEVICE,
#           LUMIROM_VERSION, GITHUB_ENV.

set -eo pipefail

: "${STOCK_DEVICE:?STOCK_DEVICE is not set}"
: "${FIRM_DIR:?FIRM_DIR is not set}"
: "${OUT_DIR:?OUT_DIR is not set}"
if [ -z "${GITHUB_ENV:-}" ] && [ -z "${LUMIROM_ENV_FILE:-}" ]; then
    echo "ERROR: neither GITHUB_ENV nor LUMIROM_ENV_FILE is set" >&2
    exit 1
fi

source scripts/firmware/FW.sh
source scripts/features/LumiROM.sh
source scripts/package/zip_creation.sh
source scripts/package/sign_ota.sh

ACTION="${1:-}"

case "$ACTION" in
    build)
        rom_replace_otacerts "$FIRM_DIR"
        fw_build_images "$FIRM_DIR" "${OUTPUT_FILESYSTEM:-erofs}" "$OUT_DIR"
        if [ "${ZIP_IMG:-false}" != "true" ]; then
            fw_images_to_brotli "$OUT_DIR" "TMP"
        fi
        ;;
    updater-script)
        pkg_render_updater_script "$FIRM_DIR"
        ;;
    inject-camera-cleanup)
        SCRIPT="$PWD/makerom/META-INF/com/google/android/updater-script"
        if inject_camera_cleanup_file "$SCRIPT"; then
            echo "SamsungCamera cleanup present in the full OTA updater-script."
        fi
        ;;
    flashable-zip)
        pkg_create_flashable_zip
        ;;
    img-zip)
        pkg_create_image_zip "$OUT_DIR"
        ;;
    sign)
        OTA_ZIP=$(find ./ROM/"$FOLDER_NAME" -type f -name "*.zip" ! -name "*INCREMENTAL*" | head -n 1)
        if [ -n "$OTA_ZIP" ]; then
            ota_sign_zip "$OTA_ZIP"
        else
            echo "No flashable zip found to sign, skipping."
        fi
        ;;
    target-files)
        : "${LUMIROM_VERSION:?LUMIROM_VERSION is not set}"
        TARGET_NAME="LumiROM_TARGET_${LUMIROM_VERSION}_${STOCK_DEVICE}.zip"
        pkg_create_target_files "$PWD/$TARGET_NAME"
        if [ -n "${HF_TOKEN:-}" ] && [ -n "${HF_USER:-}" ]; then
            python3 scripts/package/upload_hf.py "$PWD/$TARGET_NAME" \
                "$LUMIROM_VERSION/$STOCK_DEVICE/$TARGET_NAME" \
                --bucket "${HF_USER}/target-files"
        else
            echo "HF credentials not set, target files saved locally only."
        fi
        ;;
    *)
        echo "Usage: $0 <build|updater-script|inject-camera-cleanup|flashable-zip|img-zip|sign|target-files>" >&2
        exit 1
        ;;
esac

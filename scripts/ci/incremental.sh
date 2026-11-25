#!/bin/bash
#
# Incremental OTA steps:
#
#   incremental.sh fetch-source   Download the target-files zip of INCREMENTAL_FROM.
#                                 Sets INCREMENTAL_SOURCE_AVAILABLE=false when
#                                 it is not published, so the next steps skip.
#   incremental.sh build          Build the incremental OTA from prev-target-files.zip.
#   incremental.sh inject-cleanup Re-zip it with the SamsungCamera cleanup.
#   incremental.sh sign           Sign it (must be the last step that touches the zip).
#
# Requires: OUT_DIR, FOLDER_NAME, INCREMENTAL_FROM, STOCK_DEVICE, HF_USER,
#           GITHUB_ENV.

set -eo pipefail

: "${GITHUB_ENV:?GITHUB_ENV is not set; run this from GitHub Actions}"

ACTION="${1:-}"

case "$ACTION" in
    fetch-source)
        : "${INCREMENTAL_FROM:?INCREMENTAL_FROM is not set}"
        : "${STOCK_DEVICE:?STOCK_DEVICE is not set}"
        URL="https://huggingface.co/buckets/${HF_USER:-}/target-files/resolve/${INCREMENTAL_FROM}/${STOCK_DEVICE}/LumiROM_TARGET_${INCREMENTAL_FROM}_${STOCK_DEVICE}.zip?download=true"
        if curl -sfL -o prev-target-files.zip "$URL"; then
            echo "Previous target files downloaded."
        else
            echo "Previous target files not found for ${INCREMENTAL_FROM}, skipping incremental OTA."
            echo "INCREMENTAL_SOURCE_AVAILABLE=false" >> "$GITHUB_ENV"
        fi
        ;;
    build)
        : "${OUT_DIR:?OUT_DIR is not set}"
        source scripts/package/build_incremental_ota.sh
        BUILD_INCREMENTAL_OTA "$PWD/prev-target-files.zip" "$OUT_DIR"
        ;;
    inject-cleanup)
        : "${FOLDER_NAME:?FOLDER_NAME is not set}"
        source scripts/package/updater_script.sh
        INC_ZIP=$(find ./ROM/"$FOLDER_NAME" -type f -name "*INCREMENTAL*.zip" | head -n 1)
        if [ -z "$INC_ZIP" ]; then
            echo "No incremental zip found, skipping."
            exit 0
        fi
        inject_camera_cleanup_zip "$INC_ZIP"
        echo "SamsungCamera cleanup present in the incremental OTA."
        ;;
    sign)
        source scripts/package/sign_ota.sh
        SIGN_INCREMENTAL_OTA
        ;;
    *)
        echo "Usage: $0 <fetch-source|build|inject-cleanup|sign>" >&2
        exit 1
        ;;
esac

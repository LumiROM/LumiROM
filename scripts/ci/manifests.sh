#!/bin/bash
#
# OTA manifest steps:
#
#   manifests.sh generate  Build OTA_MANIFESTS/<codename>.json (full ROM, keeps
#                          history) and OTA_MANIFESTS/<codename>_ota.json (only
#                          when an incremental OTA exists).
#   manifests.sh publish   Copy the manifests into a clone of LumiROM/updater
#                          and push them (release job).
#
# generate requires: FOLDER_NAME, DOWNLOAD_URL, OTA_CHANGELOG, and optionally
#                    DOWNLOAD_URL_INCREMENTAL.
# publish requires:  UPDATER_TOKEN.

set -eo pipefail

ACTION="${1:-}"

generate() {
    : "${FOLDER_NAME:?FOLDER_NAME is not set}"

    local ZIP_PATH
    ZIP_PATH=$(find ./ROM/"$FOLDER_NAME" -type f -name "*.zip" ! -name "*INCREMENTAL*" | head -n 1)
    if [ -z "$ZIP_PATH" ]; then
        echo "No ROM zip found, skipping OTA manifest generation."
        mkdir -p OTA_MANIFESTS
        return 0
    fi
    if [ -z "${DOWNLOAD_URL:-}" ]; then
        echo "No download URL available, skipping OTA manifest generation."
        mkdir -p OTA_MANIFESTS
        return 0
    fi

    # The codename lives in build_info.txt inside the zip; it is not an env var.
    local DEVICE_CODENAME
    DEVICE_CODENAME="$(unzip -p "$ZIP_PATH" build_info.txt | sed -n 's/^device=//p' | head -n 1)"
    if [ -z "$DEVICE_CODENAME" ]; then
        echo "No device codename in build_info, skipping OTA manifest generation."
        mkdir -p OTA_MANIFESTS
        return 0
    fi

    source scripts/package/generate_ota_manifest.sh
    mkdir -p OTA_MANIFESTS

    # Full-ROM manifest (updater/{device}.json) - keeps release history.
    local CURRENT_JSON="/tmp/ota_current.json"
    curl -sf -o "$CURRENT_JSON" "https://raw.githubusercontent.com/LumiROM/updater/main/${DEVICE_CODENAME}.json" || CURRENT_JSON=""
    ota_generate_manifest "$ZIP_PATH" "$DOWNLOAD_URL" "${OTA_CHANGELOG:-}" "$CURRENT_JSON" \
        > "OTA_MANIFESTS/${DEVICE_CODENAME}.json"
    echo "Full-ROM manifest generated for ${DEVICE_CODENAME}."

    # OTA-only manifest (updater/ota/{device}.json) - only when an incremental exists.
    local INCREMENTAL_ZIP=""
    local INC_URL=""
    if [ -n "${DOWNLOAD_URL_INCREMENTAL:-}" ]; then
        INCREMENTAL_ZIP=$(find ./ROM/"$FOLDER_NAME" -type f -name "*INCREMENTAL*.zip" | head -n 1)
        INC_URL="$DOWNLOAD_URL_INCREMENTAL"
    fi
    if [ -n "$INCREMENTAL_ZIP" ] && [ -f "$INCREMENTAL_ZIP" ]; then
        ota_generate_incremental_manifest "$INCREMENTAL_ZIP" "$INC_URL" "${OTA_CHANGELOG:-}" \
            > "OTA_MANIFESTS/${DEVICE_CODENAME}_ota.json"
        echo "OTA-only manifest generated for ${DEVICE_CODENAME}."
    else
        echo "No incremental OTA found, skipping OTA-only manifest for ${DEVICE_CODENAME}."
    fi
}

publish() {
    if [ -z "${UPDATER_TOKEN:-}" ]; then
        echo "UPDATER_TOKEN not set, skipping OTA manifest update."
        return 0
    fi

    find OTA_MANIFESTS/ -type f -name "*.json" | sort > /tmp/found_manifests.txt
    if [ ! -s /tmp/found_manifests.txt ]; then
        echo "No ROM manifests generated, skipping OTA manifest update."
        return 0
    fi

    local REPO_DIR="/tmp/updater"
    rm -rf "$REPO_DIR"
    git clone --depth 1 "https://x-access-token:${UPDATER_TOKEN}@github.com/LumiROM/updater.git" "$REPO_DIR"
    mkdir -p "$REPO_DIR/ota"

    local MANIFEST FILENAME CODENAME
    while IFS= read -r MANIFEST; do
        FILENAME=$(basename "$MANIFEST")
        if [[ "$FILENAME" == *_ota.json ]]; then
            CODENAME="${FILENAME%_ota.json}"
            cp "$MANIFEST" "$REPO_DIR/ota/${CODENAME}.json"
            echo "OTA manifest updated for ${CODENAME}."
        else
            CODENAME="${FILENAME%.json}"
            cp "$MANIFEST" "$REPO_DIR/${CODENAME}.json"
            echo "Full-ROM manifest updated for ${CODENAME}."
        fi
    done < /tmp/found_manifests.txt

    cd "$REPO_DIR"
    git config user.name "LumiROM Bot"
    git config user.email "noreply@github.com"
    if find "$REPO_DIR/ota" -type f -name "*.json" | grep -q .; then
        git add -- "*.json" ota
    else
        # `git add ota` fails when the directory is still empty (first release).
        git add -- "*.json"
    fi
    if git diff --cached --quiet; then
        echo "Manifest unchanged, nothing to push."
        return 0
    fi
    git commit -m "OTA: publish manifests"
    git push
}

case "$ACTION" in
    generate) generate ;;
    publish)  publish ;;
    *)
        echo "Usage: $0 <generate|publish>" >&2
        exit 1
        ;;
esac

#!/bin/bash

# Re-signs the incremental OTAs that were published WITHOUT a signature (they
# lack the signapk -w whole-file footer, so Cloudy/RecoverySystem fails with
# "no signature in file (no footer)") and re-uploads them to the same Hugging
# Face OTAs bucket. Also regenerates the OTA-only manifest JSON for each
# device (updater/ota/{device}.json in the cloudy repo) with the new size /
# sha256 of the signed file.
#
# Requirements:
#   - The OTA private key: $OTA_PK8/$OTA_CERT or ~/.lumi/keys/ota.{pk8,x509.pem}
#   - signapk installed (/usr/share/signapk/signapk.jar)
#   - For uploads: $HF_TOKEN and $HF_USER (owner of the buckets)
#
# Usage:
#   scripts/package/resign_published_ota.sh [-n] [--no-upload] [-o OUT_DIR] [device ...]
#
#   -n, --dry-run   Sign and regenerate manifests, but do not upload.
#   --no-upload     Same as --dry-run (kept for clarity).
#   -o, --out DIR   Where to write the regenerated manifests (default: ./OTA_MANIFESTS).
#
#   device          One or more codenames (default: a32 a22 m32 f22).
#
# Example:
#   HF_USER=LuminousJD418 HF_TOKEN=hf_xxx \
#     scripts/package/resign_published_ota.sh a32 a22 m32 f22

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT" || exit 1

source scripts/utils/bash_colors.sh
source scripts/package/sign_ota.sh
source scripts/package/generate_ota_manifest.sh

MANIFEST_BASE="${OTA_MANIFEST_BASE:-https://raw.githubusercontent.com/Luminous418/cloudy/main/updater/ota}"
WORK_DIR="${OTA_WORK_DIR:-/tmp/lumi-resign-ota}"
OUT_DIR="$ROOT/OTA_MANIFESTS"
UPLOAD="true"

usage() {
    sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'
}

while [ $# -gt 0 ]; do
    case "$1" in
        -n|--dry-run|--no-upload) UPLOAD="false"; shift ;;
        -o|--out) OUT_DIR="${2:?Option $1 requires a value}"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        --) shift; break ;;
        -*) echo "Unknown option: $1" >&2; usage; exit 1 ;;
        *) break ;;
    esac
done

DEVICES=("$@")
if [ "${#DEVICES[@]}" -eq 0 ]; then
    DEVICES=(a32 a22 m32 f22)
fi

mkdir -p "$WORK_DIR" "$OUT_DIR"

FAILED=()
for DEVICE in "${DEVICES[@]}"; do
    echo "${BLUE}=== ${DEVICE} ===${RESET}"

    MANIFEST_URL="${MANIFEST_BASE}/${DEVICE}.json"
    MANIFEST="$(curl -sf "$MANIFEST_URL" 2>/dev/null)" || {
        echo "${YELLOW}No OTA manifest at ${MANIFEST_URL}, skipping.${RESET}"
        continue
    }

    URL="$(jq -r '.releases[0].download.url // empty' <<< "$MANIFEST")"
    FILE_NAME="$(jq -r '.releases[0].download.filename // empty' <<< "$MANIFEST")"
    VERSION="$(jq -r '.releases[0].version // empty' <<< "$MANIFEST")"
    DEVICE_MODEL="$(jq -r '.releases[0].device_model // empty' <<< "$MANIFEST")"
    CHANGELOG="$(jq -r '[.releases[0].changelog[]?] | join(";")' <<< "$MANIFEST")"
    LOCAL="$WORK_DIR/$FILE_NAME"

    if [ -z "$URL" ] || [ -z "$FILE_NAME" ] || [ -z "$VERSION" ] || [ -z "$DEVICE_MODEL" ]; then
        echo "${RED}Manifest is missing download/version/device_model fields, skipping.${RESET}"
        FAILED+=("$DEVICE")
        continue
    fi

    if [ ! -f "$LOCAL" ] || [ "$(stat -c '%s' "$LOCAL")" != "$(jq -r '.releases[0].download.size_bytes' <<< "$MANIFEST")" ]; then
        echo "${YELLOW} - Downloading $(basename "$FILE_NAME")...${RESET}"
        if ! curl -sfL -o "$LOCAL" "$URL"; then
            echo "${RED} - Download failed, skipping.${RESET}"
            FAILED+=("$DEVICE")
            rm -f "$LOCAL"
            continue
        fi
    else
        echo "${GREEN} - Reusing downloaded file (size matches manifest).${RESET}"
    fi

    echo "${YELLOW} - Signing ${FILE_NAME}${RESET}"
    if ! SIGN_OTA_ZIP "$LOCAL"; then
        echo "${RED} - Signing failed, skipping.${RESET}"
        FAILED+=("$DEVICE")
        continue
    fi

    OUT_JSON="$OUT_DIR/${DEVICE}_ota.json"
    GENERATE_OTA_INCREMENTAL_MANIFEST "$LOCAL" "$URL" "$CHANGELOG" > "$OUT_JSON" || {
        echo "${RED} - Manifest generation failed, skipping.${RESET}"
        FAILED+=("$DEVICE")
        continue
    }
    NEW_SHA="$(jq -r '.releases[0].download.sha256' "$OUT_JSON")"
    NEW_SIZE="$(jq -r '.releases[0].download.size_bytes' "$OUT_JSON")"
    echo "${GREEN} - Manifest written to ${OUT_JSON} (sha256=${NEW_SHA}, size=${NEW_SIZE})${RESET}"

    REMOTE_PATH="${VERSION}/${DEVICE_MODEL}/${FILE_NAME}"
    if [ "$UPLOAD" = "true" ]; then
        if [ -z "${HF_TOKEN:-}" ] || [ -z "${HF_USER:-}" ]; then
            echo "${RED} - HF_TOKEN/HF_USER not set: signed file left at ${LOCAL}, not uploaded.${RESET}"
            FAILED+=("$DEVICE")
            continue
        fi
        echo "${YELLOW} - Uploading to ${HF_USER}/OTAs/${REMOTE_PATH}${RESET}"
        if ! python3 scripts/package/upload_hf.py "$LOCAL" "$REMOTE_PATH" --bucket "${HF_USER}/OTAs"; then
            echo "${RED} - Upload failed.${RESET}"
            FAILED+=("$DEVICE")
            continue
        fi
        echo "${GREEN} - Uploaded.${RESET}"
    else
        echo "${YELLOW} - Dry run: signed file left at ${LOCAL}${RESET}"
    fi
done

echo
if [ "${#FAILED[@]}" -eq 0 ]; then
    echo "${GREEN}All requested OTAs re-signed successfully.${RESET}"
else
    echo "${RED}Failed/review: ${FAILED[*]}${RESET}"
    exit 1
fi

if [ "$UPLOAD" = "true" ]; then
    echo "${YELLOW}Remember to commit the regenerated manifests from ${OUT_DIR} to the cloudy repo (updater/ota/{device}.json).${RESET}"
fi

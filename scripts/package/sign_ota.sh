#!/usr/bin/env bash

source "$(pwd)/scripts/utils/bash_colors.sh"
source "$(pwd)/scripts/utils/platform_key.sh"

# Signs a flashable zip as an OTA package using signapk with the -w flag, which
# embeds META-INF/com/android/otacert (the certificate that Recovery will later
# accept for this package). The signed zip replaces the original file.
# Usage: SIGN_OTA_ZIP <OTA_ZIP>
SIGN_OTA_ZIP() {
    if [ "$#" -ne 1 ]; then
        echo "Usage: ${FUNCNAME[0]} <OTA_ZIP>"
        return 1
    fi

    local OTA_ZIP="$1"

    if [ ! -f "$OTA_ZIP" ]; then
        echo "${RED}OTA zip not found:${RESET} $OTA_ZIP"
        return 1
    fi

    local SIGNER="/usr/share/signapk/signapk.jar"
    if [ ! -f "$SIGNER" ]; then
        echo "${RED}signapk not found at $SIGNER. Install it first.${RESET}"
        return 1
    fi

    local KEY_DIR
    KEY_DIR="$(GET_ACTIVE_OTA_KEY_FILES)"
    if [ -z "$KEY_DIR" ] || [ ! -f "$KEY_DIR/ota.pk8" ] || [ ! -f "$KEY_DIR/ota.x509.pem" ]; then
        echo "${RED}No OTA signing key available, skipping signature.${RESET}"
        return 1
    fi

    local CERT="$KEY_DIR/ota.x509.pem"
    local PK8="$KEY_DIR/ota.pk8"
    local SIGNED="${OTA_ZIP%.zip}.signed.zip"

    echo "${YELLOW}Signing OTA package with signapk (-w otacert)...${RESET}"
    java -jar "$SIGNER" -w "$CERT" "$PK8" "$OTA_ZIP" "$SIGNED" || {
        echo "${RED}signapk failed.${RESET}"
        return 1
    }

    if ! unzip -l "$SIGNED" 2>/dev/null | grep -q "META-INF/com/android/otacert"; then
        echo "${RED}Signed zip is missing META-INF/com/android/otacert. Aborting.${RESET}"
        rm -f "$SIGNED"
        return 1
    fi

    mv -f "$SIGNED" "$OTA_ZIP"
    echo "${GREEN}OTA package signed (otacert embedded): $OTA_ZIP${RESET}"
}

# Signs the incremental OTA zip found under a directory (defaults to
# ./ROM/$FOLDER_NAME). Must run AFTER any post-processing that re-zips the
# package (e.g. the SamsungCamera cleanup injection), because re-zipping
# rewrites the EOCD and strips the whole-file signature footer, otherwise
# RecoverySystem/Cloudy fails with "no signature in file (no footer)".
# Usage: SIGN_INCREMENTAL_OTA [DIR]
SIGN_INCREMENTAL_OTA() {
    local DIR="${1:-./ROM/$FOLDER_NAME}"
    local INC_ZIP

    INC_ZIP=$(find "$DIR" -type f -name "*INCREMENTAL*.zip" 2>/dev/null | head -n 1)
    if [ -z "$INC_ZIP" ] || [ ! -f "$INC_ZIP" ]; then
        echo "${RED}No incremental OTA zip found in $DIR, nothing to sign.${RESET}"
        return 1
    fi

    SIGN_OTA_ZIP "$INC_ZIP"
}

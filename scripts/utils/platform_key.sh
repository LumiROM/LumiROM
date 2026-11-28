#!/bin/bash

# Loaded from several entry points; the guard keeps the side effects
# (colors, log files, exports) to the first source.
[ -n "${LUMIROM_PLATFORM_KEY_LOADED:-}" ] && return 0
LUMIROM_PLATFORM_KEY_LOADED=1

source "$(pwd)/scripts/utils/bash_colors.sh"

key_active_cert() {
    if [ -n "${PLATFORM_CERT:-}" ]; then
        printf '%s' "${PLATFORM_CERT:-}"
    elif [ -f "$HOME/.lumi/keys/platform.x509.pem" ]; then
        cat "$HOME/.lumi/keys/platform.x509.pem"
    else
        cat "$(pwd)/scripts/keys/testkey.x509.pem"
    fi
}

key_active_source() {
    if [ -n "${PLATFORM_CERT:-}" ]; then
        echo "PLATFORM_CERT (env/secret)"
    elif [ -f "$HOME/.lumi/keys/platform.x509.pem" ]; then
        echo "$HOME/.lumi/keys"
    else
        echo "AOSP testkey (unofficial)"
    fi
}

key_cert_hash() {
    key_active_cert | sed "/CERTIFICATE/d" | tr -d "\n" | base64 -d | sha256sum | cut -d ' ' -f 1
}

key_is_custom() {
    local TESTKEY_HASH
    TESTKEY_HASH="$(sed "/CERTIFICATE/d" "$(pwd)/scripts/keys/testkey.x509.pem" | tr -d "\n" | base64 -d | sha256sum | cut -d ' ' -f 1)"

    local ACTIVE_HASH
    ACTIVE_HASH="$(key_cert_hash)"

    if [ -n "$ACTIVE_HASH" ] && [ "$ACTIVE_HASH" != "$TESTKEY_HASH" ]; then
        return 0
    fi

    return 1
}
key_cert_hex() {
    key_active_cert | sed "/CERTIFICATE/d" | tr -d "\n" | base64 -d | xxd -p -c 0
}

key_files() {
    local KEY_DIR

    if [ -n "${PLATFORM_PK8:-}" ] && [ -n "${PLATFORM_CERT:-}" ]; then
        KEY_DIR="$(mktemp -d)"
        printf '%s' "${PLATFORM_PK8:-}" | base64 -d > "$KEY_DIR/platform.pk8"
        printf '%s' "${PLATFORM_CERT:-}" > "$KEY_DIR/platform.x509.pem"
    elif [ -f "$HOME/.lumi/keys/platform.pk8" ] && [ -f "$HOME/.lumi/keys/platform.x509.pem" ]; then
        KEY_DIR="$HOME/.lumi/keys"
    else
        KEY_DIR="$(mktemp -d)"
        cp "$(pwd)/scripts/keys/testkey.pk8" "$KEY_DIR/platform.pk8"
        cp "$(pwd)/scripts/keys/testkey.x509.pem" "$KEY_DIR/platform.x509.pem"
    fi

    echo "$KEY_DIR"
}

key_ota_files() {
    local KEY_DIR=""

    if [ -n "${OTA_PK8:-}" ] && [ -n "${OTA_CERT:-}" ]; then
        KEY_DIR="$(mktemp -d)"
        printf '%s' "${OTA_PK8:-}" | base64 -d > "$KEY_DIR/ota.pk8"
        printf '%s' "${OTA_CERT:-}" > "$KEY_DIR/ota.x509.pem"
    elif [ -f "$HOME/.lumi/keys/ota.pk8" ] && [ -f "$HOME/.lumi/keys/ota.x509.pem" ]; then
        KEY_DIR="$HOME/.lumi/keys"
    else
        echo "${YELLOW}No OTA signing key found (secrets or ~/.lumi/keys/ota.*). Skipping OTA signature.${RESET}" >&2
    fi

    echo "$KEY_DIR"
}

key_ota_cert() {
    if [ -n "${OTA_CERT:-}" ]; then
        printf '%s' "${OTA_CERT:-}"
    elif [ -f "$HOME/.lumi/keys/ota.x509.pem" ]; then
        cat "$HOME/.lumi/keys/ota.x509.pem"
    fi
}

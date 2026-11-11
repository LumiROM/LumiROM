#!/bin/bash

source "$(pwd)/scripts/utils/bash_colors.sh"

GET_ACTIVE_PLATFORM_CERT() {
    if [ -n "${PLATFORM_CERT:-}" ]; then
        printf '%s' "${PLATFORM_CERT:-}"
    elif [ -f "$HOME/.lumi/keys/platform.x509.pem" ]; then
        cat "$HOME/.lumi/keys/platform.x509.pem"
    else
        cat "$(pwd)/scripts/keys/testkey.x509.pem"
    fi
}

GET_ACTIVE_PLATFORM_KEY_SOURCE() {
    if [ -n "${PLATFORM_CERT:-}" ]; then
        echo "PLATFORM_CERT (env/secret)"
    elif [ -f "$HOME/.lumi/keys/platform.x509.pem" ]; then
        echo "$HOME/.lumi/keys"
    else
        echo "AOSP testkey (unofficial)"
    fi
}

GET_ACTIVE_CERT_HASH() {
    GET_ACTIVE_PLATFORM_CERT | sed "/CERTIFICATE/d" | tr -d "\n" | base64 -d | sha256sum | cut -d ' ' -f 1
}

IS_CUSTOM_PLATFORM_KEY() {
    local TESTKEY_HASH
    TESTKEY_HASH="$(sed "/CERTIFICATE/d" "$(pwd)/scripts/keys/testkey.x509.pem" | tr -d "\n" | base64 -d | sha256sum | cut -d ' ' -f 1)"

    local ACTIVE_HASH
    ACTIVE_HASH="$(GET_ACTIVE_CERT_HASH)"

    if [ -n "$ACTIVE_HASH" ] && [ "$ACTIVE_HASH" != "$TESTKEY_HASH" ]; then
        return 0
    fi

    return 1
}
GET_ACTIVE_CERT_HEX() {
    GET_ACTIVE_PLATFORM_CERT | sed "/CERTIFICATE/d" | tr -d "\n" | base64 -d | xxd -p -c 0
}

GET_ACTIVE_KEY_FILES() {
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

GET_ACTIVE_OTA_KEY_FILES() {
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

GET_ACTIVE_OTA_CERT() {
    if [ -n "${OTA_CERT:-}" ]; then
        printf '%s' "${OTA_CERT:-}"
    elif [ -f "$HOME/.lumi/keys/ota.x509.pem" ]; then
        cat "$HOME/.lumi/keys/ota.x509.pem"
    fi
}
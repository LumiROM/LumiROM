#!/bin/bash
#
# Framework (de)compilation, one subcommand per workflow step:
#
#   framework.sh decompile  apktool-decompile the jars and apps that get patched.
#   framework.sh recompile  Recompile them, verify every artifact exists and
#                           copy the results back into FIRMWARE/.
#
# Requires: FIRM_DIR, WORK_DIR, APKTOOL.

set -eo pipefail

: "${FIRM_DIR:?FIRM_DIR is not set}"
: "${WORK_DIR:?WORK_DIR is not set}"
: "${APKTOOL:?APKTOOL is not set}"

source scripts/features/LumiROM.sh

FW_DIR="FIRMWARE/system/system/framework"
# Runs the pending background jobs and fails if any of them failed.
wait_jobs() {
    local pid failed=0
    for pid in "$@"; do
        wait "$pid" || failed=1
    done
    [ "$failed" -eq 0 ]
}

decompile() {
    local -a PIDS=()

    rom_decompile "$APKTOOL" "$FW_DIR/ssrm.jar" "$WORK_DIR" & PIDS+=("$!")
    rom_decompile "$APKTOOL" "$FW_DIR/services.jar" "$WORK_DIR" & PIDS+=("$!")
    rom_decompile "$APKTOOL" "$FW_DIR/framework.jar" "$WORK_DIR" & PIDS+=("$!")
    rom_decompile "$APKTOOL" "$FW_DIR/knoxsdk.jar" "$WORK_DIR" & PIDS+=("$!")
    rom_decompile "$APKTOOL" "$FW_DIR/samsungkeystoreutils.jar" "$WORK_DIR" & PIDS+=("$!")
    rom_decompile "$APKTOOL" "FIRMWARE/system/system/priv-app/SecSettings/SecSettings.apk" "$WORK_DIR" & PIDS+=("$!")
    rom_decompile "$APKTOOL" "FIRMWARE/system/system/priv-app/SecSettingsIntelligence/SecSettingsIntelligence.apk" "$WORK_DIR" & PIDS+=("$!")
    rom_decompile "$APKTOOL" "FIRMWARE/system/system/priv-app/SecSetupWizard_Global/SecSetupWizard_Global.apk" "$WORK_DIR" & PIDS+=("$!")

    if ! wait_jobs "${PIDS[@]}"; then
        echo "ERROR: one or more apktool decompiles failed" >&2
        exit 1
    fi
}

recompile() {
    local APKTOOL_FRAMEWORK="$HOME/.local/share/apktool/framework"
    local -a PIDS=()

    rom_recompile "$APKTOOL" "$WORK_DIR/ssrm" "$FW_DIR" "$WORK_DIR" & PIDS+=("$!")
    rom_recompile "$APKTOOL" "$WORK_DIR/services" "$FW_DIR" "$WORK_DIR" & PIDS+=("$!")
    rom_recompile "$APKTOOL" "$WORK_DIR/framework" "$FW_DIR" "$WORK_DIR" & PIDS+=("$!")
    rom_recompile "$APKTOOL" "$WORK_DIR/knoxsdk" "$FW_DIR" "$WORK_DIR" & PIDS+=("$!")
    rom_recompile "$APKTOOL" "$WORK_DIR/samsungkeystoreutils" "$FW_DIR" "$WORK_DIR" & PIDS+=("$!")
    apps_rebuild_and_sign_apk "$APKTOOL" "$WORK_DIR/SecSettings" "$APKTOOL_FRAMEWORK" "$WORK_DIR/SecSettings_rebuilt.apk" & PIDS+=("$!")
    apps_rebuild_and_sign_apk "$APKTOOL" "$WORK_DIR/SecSettingsIntelligence" "$APKTOOL_FRAMEWORK" "$WORK_DIR/SecSettingsIntelligence_rebuilt.apk" & PIDS+=("$!")
    apps_rebuild_and_sign_apk "$APKTOOL" "$WORK_DIR/SecSetupWizard_Global" "$APKTOOL_FRAMEWORK" "$WORK_DIR/SecSetupWizard_Global_rebuilt.apk" & PIDS+=("$!")

    if ! wait_jobs "${PIDS[@]}"; then
        echo "ERROR: one or more apktool builds failed (see the log above). Aborting." >&2
        exit 1
    fi

    local MISSING=0 ARTIFACT
    for ARTIFACT in \
            "$WORK_DIR/SecSettings_rebuilt.apk" \
            "$WORK_DIR/SecSettingsIntelligence_rebuilt.apk" \
            "$WORK_DIR/SecSetupWizard_Global_rebuilt.apk" \
            "$WORK_DIR/framework.jar" \
            "$WORK_DIR/services.jar" \
            "$WORK_DIR/knoxsdk.jar" \
            "$WORK_DIR/samsungkeystoreutils.jar"; do
        if [ ! -f "$ARTIFACT" ]; then
            echo "ERROR: missing artifact: $ARTIFACT" >&2
            MISSING=1
        fi
    done
    if [ "$MISSING" -ne 0 ]; then
        echo "ERROR: a decompiled artifact failed to recompile. Aborting." >&2
        exit 1
    fi

    rom_fix_framework_mime "$FW_DIR/framework.jar" "$WORK_DIR/framework.jar"

    cp -fv "$WORK_DIR"/*.jar "$FW_DIR/"

    echo "Removing stale boot-framework artifacts (framework.jar changed)"
    rm -f "$FW_DIR/boot-framework.vdex"
    local ARCH
    for ARCH in arm arm64; do
        rm -f "$FW_DIR/$ARCH/boot-framework.art" \
              "$FW_DIR/$ARCH/boot-framework.oat" \
              "$FW_DIR/$ARCH/boot-framework.vdex"
    done

    if [ -f "$WORK_DIR/SecSettings_rebuilt.apk" ]; then
        cp -fv "$WORK_DIR/SecSettings_rebuilt.apk" \
            "FIRMWARE/system/system/priv-app/SecSettings/SecSettings.apk"
    fi
    if [ -f "$WORK_DIR/SecSettingsIntelligence_rebuilt.apk" ]; then
        cp -fv "$WORK_DIR/SecSettingsIntelligence_rebuilt.apk" \
            "FIRMWARE/system/system/priv-app/SecSettingsIntelligence/SecSettingsIntelligence.apk"
    fi
    if [ -f "$WORK_DIR/SecSetupWizard_Global_rebuilt.apk" ]; then
        cp -fv "$WORK_DIR/SecSetupWizard_Global_rebuilt.apk" \
            "FIRMWARE/system/system/priv-app/SecSetupWizard_Global/SecSetupWizard_Global.apk"
    fi
}

case "${1:-}" in
    decompile) decompile ;;
    recompile) recompile ;;
    *)
        echo "Usage: $0 <decompile|recompile>" >&2
        exit 1
        ;;
esac

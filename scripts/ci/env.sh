#!/bin/bash
#
# Writes the build configuration to $GITHUB_ENV so the following workflow
# steps see it. Only the values that change per run are passed in; everything
# else is derived here.
#
# Required environment:
#   GITHUB_ENV         Set by GitHub Actions.
#   STOCK_DEVICE       Device to build (matrix.device or the workflow input).
#   LUMIROM_VERSION    Read from the repository variable by the workflow.
#
# Optional (workflow inputs, with the same defaults as the workflows):
#   USE_MODS, USE_GALAXY_AI, USE_UI_8_TETHERING_APEX, ZIP_IMG, DESTINATION,
#   LUMIROM_MAINTAINER

set -eo pipefail

: "${GITHUB_ENV:?GITHUB_ENV is not set; run this from GitHub Actions}"
: "${STOCK_DEVICE:?STOCK_DEVICE is not set}"
: "${LUMIROM_VERSION:?LUMIROM_VERSION is not set (repository variable)}"

{
    echo "STOCK_DEVICE=$STOCK_DEVICE"
    echo "TARGET_DEVICE=${TARGET_DEVICE:-}"
    echo "TARGET_CSC=${TARGET_CSC:-}"
    echo "TARGET_IMEI=${TARGET_IMEI:-}"
    echo "USE_MODS=${USE_MODS:-true}"
    echo "USE_GALAXY_AI=${USE_GALAXY_AI:-false}"
    echo "USE_UI_8_TETHERING_APEX=${USE_UI_8_TETHERING_APEX:-false}"
    echo "ZIP_IMG=${ZIP_IMG:-false}"
    echo "DESTINATION=${DESTINATION:-gofile}"
    echo "OUTPUT_FILESYSTEM=erofs"

    echo "LUMIROM_VERSION=$LUMIROM_VERSION"
    echo "LUMIROM_CODE=${LUMIROM_VERSION//./0}"
    echo "LUMIROM_MAINTAINER=${LUMIROM_MAINTAINER:-${GITHUB_ACTOR:-github-actions}}"

    echo "OUT_DIR=$PWD/OUT"
    echo "WORK_DIR=$PWD/TMP/LumiWORK"
    echo "FIRM_DIR=$PWD/FIRMWARE"
    echo "IMGS_DIR=$PWD/IMGs"
    echo "DEVICES_DIR=$PWD/LumiROM/Devices"
    echo "APKTOOL=$PWD/bin/apktool/apktool.jar"
    echo "VNDKS_COLLECTION=$PWD/LumiROM/vndks"
    echo "BUILD_PARTITIONS=product,vendor,odm,system_ext,system"
} >> "$GITHUB_ENV"

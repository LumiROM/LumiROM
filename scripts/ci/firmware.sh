#!/bin/bash
#
# Firmware steps, one subcommand per workflow step so the Actions log keeps
# the same granularity:
#
#   firmware.sh download    Download the base (target) firmware for this CSC/IMEI.
#   firmware.sh extract     Extract super.img and the partition images.
#   firmware.sh vendor      Download the vendor image for STOCK_DEVICE.
#   firmware.sh partitions  Create the per-partition images and extract them.
#
# Requires: STOCK_DEVICE, TARGET_DEVICE, TARGET_CSC, TARGET_IMEI, DEVICES_DIR,
#           FIRM_DIR, IMGS_DIR.

set -eo pipefail

: "${STOCK_DEVICE:?STOCK_DEVICE is not set}"
: "${FIRM_DIR:?FIRM_DIR is not set}"
: "${IMGS_DIR:?IMGS_DIR is not set}"
: "${DEVICES_DIR:?DEVICES_DIR is not set}"

source scripts/firmware/FW.sh
source "$DEVICES_DIR/$STOCK_DEVICE/config"

case "${1:-}" in
    download)
        : "${TARGET_DEVICE:?TARGET_DEVICE is not set}"
        : "${TARGET_CSC:?TARGET_CSC is not set}"
        : "${TARGET_IMEI:?TARGET_IMEI is not set}"
        DOWNLOAD_FIRMWARE "$TARGET_DEVICE" "$TARGET_CSC" "$TARGET_IMEI" "$FIRM_DIR"
        ;;
    extract)
        EXTRACT_FIRMWARE "$IMGS_DIR"
        EXTRACT_SUPER_IMG "$IMGS_DIR"
        ;;
    vendor)
        DOWNLOAD_VENDOR "$IMGS_DIR"
        ;;
    partitions)
        PREPARE_PARTITIONS "$IMGS_DIR"
        EXTRACT_FIRMWARE_IMG "$IMGS_DIR" "$FIRM_DIR"
        ;;
    *)
        echo "Usage: $0 <download|extract|vendor|partitions>" >&2
        exit 1
        ;;
esac

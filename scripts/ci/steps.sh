#!/bin/bash
#
# The build pipeline, in order.
#
# This is the single definition of "which steps, in which order". build_local.sh
# walks it in-process and the workflows call it one step per job step, so the
# two paths cannot drift. Commands live in scripts/ci/*.sh; this file only maps
# names to them.
#
#   steps.sh list        Print the ordered step names.
#   steps.sh <step>      Run one step.
#
# Conditions (ZIP_IMG, INCREMENTAL_FROM, TARGET_FILES, USE_MODS...) stay in the
# caller: local checks them in build_local.sh, CI in the workflow `if:`s.

set -eo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/../.."

PIPELINE_STEPS=(
    firmware-base
    firmware-vendor
    firmware-partitions
    features-vendor
    features-stock
    features-debloat
    features-props
    features-mods
    features-hotspot
    features-fota
    features-ai
    features-display
    features-framework-res
    framework-decompile
    features-knox
    framework-recompile
    rom-build
    rom-updater-script
    rom-inject-cleanup
    rom-flashable
    rom-sign
    rom-img-zip
    rom-target-files
    ota-fetch-source
    ota-build
    ota-inject-cleanup
    ota-sign
)

run_step() {
    case "$1" in
        firmware-base)        bash scripts/ci/firmware.sh base ;;
        firmware-vendor)      bash scripts/ci/firmware.sh vendor ;;
        firmware-partitions)  bash scripts/ci/firmware.sh partitions ;;

        features-vendor)      bash scripts/ci/features.sh vendor-patches ;;
        features-stock)       bash scripts/ci/features.sh stock-config ;;
        features-debloat)     bash scripts/ci/features.sh debloat ;;
        features-props)       bash scripts/ci/features.sh props ;;
        features-mods)        bash scripts/ci/features.sh mods ;;
        features-hotspot)     bash scripts/ci/features.sh hotspot ;;
        features-fota)        bash scripts/ci/features.sh lumifota ;;
        features-ai)          bash scripts/ci/features.sh ai ;;
        features-display)     bash scripts/ci/features.sh display-id ;;
        features-framework-res) bash scripts/ci/features.sh framework-res ;;
        features-knox)        bash scripts/ci/features.sh knox ;;

        framework-decompile)  bash scripts/ci/framework.sh decompile ;;
        framework-recompile)  bash scripts/ci/framework.sh recompile ;;

        rom-build)            bash scripts/ci/rom.sh build ;;
        rom-updater-script)   bash scripts/ci/rom.sh updater-script ;;
        rom-inject-cleanup)   bash scripts/ci/rom.sh inject-camera-cleanup ;;
        rom-flashable)        bash scripts/ci/rom.sh flashable-zip ;;
        rom-img-zip)          bash scripts/ci/rom.sh img-zip ;;
        rom-sign)             bash scripts/ci/rom.sh sign ;;
        rom-target-files)     bash scripts/ci/rom.sh target-files ;;

        ota-fetch-source)     bash scripts/ci/incremental.sh fetch-source ;;
        ota-build)            bash scripts/ci/incremental.sh build ;;
        ota-inject-cleanup)   bash scripts/ci/incremental.sh inject-cleanup ;;
        ota-sign)             bash scripts/ci/incremental.sh sign ;;

        *)
            echo "Unknown step: $1" >&2
            echo "Known steps: $(printf '%s ' "${PIPELINE_STEPS[@]}")" >&2
            return 1
            ;;
    esac
}

if [ "${1:-}" = "list" ]; then
    printf '%s\n' "${PIPELINE_STEPS[@]}"
    exit 0
fi

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <list|step>" >&2
    exit 1
fi

run_step "$1"

#!/bin/bash
#
# Shared defaults for every build entry point (build_local.sh and scripts/ci).
# Keep values that more than one place needs here, so they cannot drift.

# shellcheck disable=SC2034  # consumed by the scripts that source this file

# Guard: this file is sourced from build_local.sh, the CI scripts and the
# cache manager.
[ -n "${LUMIROM_CONFIG_LOADED:-}" ] && return 0
LUMIROM_CONFIG_LOADED=1

# Partitions that end up in the ROM, in the order they are written.
LUMIROM_BUILD_PARTITIONS="${LUMIROM_BUILD_PARTITIONS:-product,vendor,odm,system_ext,system}"

#!/bin/bash

# LumiROM feature set.
#
# The implementation lives in scripts/features/rom/*.sh; this file is the facade
# that build_local.sh and the workflows source, so call sites stay unchanged.

export LC_ALL=C

source scripts/utils/bash_colors.sh
source scripts/utils/platform_key.sh
source scripts/features/AppPatches.sh

for _rom_part in encryption fstab props debloat framework display misc; do
    source "scripts/features/rom/${_rom_part}.sh"
done
unset _rom_part

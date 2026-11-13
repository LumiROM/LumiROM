#!/bin/bash

source scripts/utils/bash_colors.sh
source scripts/utils/mod_utils.sh

ADD_MODS() {
    echo ""
    if [ "$#" -ne 1 ]; then
        echo "Usage: ${FUNCNAME[0]} <EXTRACTED_FIRM_DIR>"
        return 1
    fi

    EXTRACTED_FIRM_DIR="$1"
    export EXTRACTED_FIRM_DIR

    if [ "$USE_MODS" != "true" ]; then
        echo "${RED}The use of mods for this build have been disabled by the user${RESET}"
        return 0
    fi

    echo "${BLUE}============ Mods Installation ============${RESET}"

    local MODS_DIR="$(pwd)/LumiROM/Mods"
    local MOD_ORDER
    local MOD_DIR
    local MOD_COUNT=0

    while IFS=$'\t' read -r MOD_ORDER MOD_DIR; do
        [ -z "$MOD_DIR" ] && continue
        MOD_APPLY "$MOD_DIR" || return 1
        MOD_COUNT=$((MOD_COUNT + 1))
    done < <(MOD_LIST "$MODS_DIR")

    echo "${GREEN} - ${MOD_COUNT} mods added${RESET}"
}

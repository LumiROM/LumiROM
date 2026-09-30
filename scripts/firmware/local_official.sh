#!/bin/bash

source scripts/utils/bash_colors.sh

if [ -f .env ]; then
    source .env
fi

IS_LOCAL_OFFICIAL() {

    if [ -z "$LUMIROM_BUILD" ] || [ -z "$OFFICIAL_HASH" ]; then
        echo "${BLUE}[!] Missing environment variables. Using default values.${RESET}"
    fi

    export BUILD_STATUS="UNOFFICIAL"
    export ROM_TAG="🛠️ LumiROM Unofficial Build"

    echo "${BLUE}--- $ROM_TAG detected ---${RESET}"
}

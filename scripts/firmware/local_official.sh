#!/bin/bash

source scripts/utils/bash_colors.sh

if [ -f .env ]; then
    source .env
fi

source scripts/utils/platform_key.sh

IS_LOCAL_OFFICIAL() {

    export BUILD_STATUS="UNOFFICIAL"
    export ROM_TAG="🛠️ LumiROM Unofficial Build"

    # A build is official only when it is signed with LumiROM's own platform
    # key (not the AOSP testkey).
    if IS_CUSTOM_PLATFORM_KEY; then
        export BUILD_STATUS="OFFICIAL"
        export ROM_TAG="✨ LumiROM Official Build"
    fi

    echo "${BLUE}--- $ROM_TAG detected (key: $(GET_ACTIVE_PLATFORM_KEY_SOURCE)) ---${RESET}"
}
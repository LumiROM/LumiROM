#!/bin/bash

source scripts/utils/bash_colors.sh

if [ -f .env ]; then
    source .env
fi

source scripts/utils/platform_key.sh

is_local_official() {

    export BUILD_STATUS="UNOFFICIAL"
    export ROM_TAG="🛠️ LumiROM Unofficial Build"

    # A build is official only when it is signed with LumiROM's own platform
    # key (not the AOSP testkey).
    if key_is_custom; then
        export BUILD_STATUS="OFFICIAL"
        export ROM_TAG="✨ LumiROM Official Build"
    fi

    echo "${BLUE}--- $ROM_TAG detected (key: $(key_active_source)) ---${RESET}"
}
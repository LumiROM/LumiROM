#!/bin/bash
#
# LumiROM features: framework-res install and display id.
# Part of scripts/features/LumiROM.sh (sourced by it); not meant to run alone.

rom_install_framework() {
    if [ "$#" -ne 1 ]; then
        echo "Usage: ${FUNCNAME[0]} <framework-res.apk>"
        return 1
    fi

    local framework_res_apk="$1"

    # Installing stock overlay
    echo "${YELLOW}Installing Framework...${RESET}"
    java -jar "$APKTOOL" install-framework "$framework_res_apk"
}

rom_append_display_id() {
    local EXTRACTED_FIRM_DIR="$1"
    local SUFFIX="$2"

    if [ -z "$EXTRACTED_FIRM_DIR" ] || [ -z "$SUFFIX" ]; then
        echo "Usage: rom_append_display_id <EXTRACTED_FIRM_DIR> <text_to_append>"
        return 1
    fi

    local PROP_FILES=(
        "$EXTRACTED_FIRM_DIR/product/etc/build.prop"
        "$EXTRACTED_FIRM_DIR/system/system/build.prop"
    )

    for PROP in "${PROP_FILES[@]}"; do
        [ -f "$PROP" ] || continue

        if grep -q "^ro.build.display.id=" "$PROP"; then
            local CURRENT
            CURRENT=$(grep "^ro.build.display.id=" "$PROP" | cut -d= -f2-)

            # Try to not update it, if it was already there
            if [[ "$CURRENT" != *"$SUFFIX"* ]]; then
                sed -i "s|^ro.build.display.id=.*|ro.build.display.id=${CURRENT} - ${SUFFIX}|" "$PROP"
                echo "${GREEN}Updated ${RESET}ro.build.display.id${GREEN} in ${RESET}$PROP"
            fi
        fi
    done
}

rom_set_display_id() {
    if [ -z "$1" ]; then
        echo "Usage: rom_set_display_id <EXTRACTED_FIRM_DIR>"
        return 1
    fi

    # Add a name to build ID, doesnt delete the line, it adds at the end
	local EXTRACTED_FIRM_DIR="$1"

    rom_append_display_id "$1" "LumiROM $LUMIROM_VERSION $BUILD_STATUS Stable"
}

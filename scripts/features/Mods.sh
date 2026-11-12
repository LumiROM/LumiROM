#!/bin/bash

source scripts/utils/bash_colors.sh

ADD_MODS() {
    echo ""
    if [ "$#" -ne 1 ]; then
        echo "Usage: ${FUNCNAME[0]} <EXTRACTED_FIRM_DIR>"
        return 1
    fi

	local EXTRACTED_FIRM_DIR="$1"

    if [ "$USE_MODS" = "true" ]; then
        # For every new mod, add it with all route, until I remake the script
        echo "${BLUE}============ Mods Installation ============${RESET}"
        
        echo "${YELLOW} - Adding misc system files${RESET}"
        sudo cp -rfan "$(pwd)/LumiROM/Mods/Files/system/system/bin/"* "$EXTRACTED_FIRM_DIR/system/system/bin/"
        sudo cp -rfan "$(pwd)/LumiROM/Mods/Files/system/system/etc/"* "$EXTRACTED_FIRM_DIR/system/system/etc/"

        echo "${YELLOW} - Adding SDHMS SIOP warning fix${RESET}"
        sudo mkdir -p "$EXTRACTED_FIRM_DIR/system/system/priv-app/SamsungDeviceHealthManagerService"
        sudo cp -rfa "$(pwd)/LumiROM/Mods/SDHMSFix/system/system/priv-app/SamsungDeviceHealthManagerService/"* "$EXTRACTED_FIRM_DIR/system/system/priv-app/SamsungDeviceHealthManagerService/"

        echo "${YELLOW} - Adding FluidMotion settings app${RESET}"
        sudo mkdir -p "$EXTRACTED_FIRM_DIR/system/system/priv-app/FluidMotion"
        sudo cp -rfa "$(pwd)/LumiROM/Mods/FluidMotion/system/system/priv-app/FluidMotion/"* "$EXTRACTED_FIRM_DIR/system/system/priv-app/FluidMotion/"

        echo "${YELLOW} - Adding FluidMotion SystemUI${RESET}"
        local SYSTEMUI_DST="$EXTRACTED_FIRM_DIR/system_ext/priv-app/SystemUI"
        if [ -d "$EXTRACTED_FIRM_DIR/system/system_ext/priv-app/SystemUI" ]; then
            SYSTEMUI_DST="$EXTRACTED_FIRM_DIR/system/system_ext/priv-app/SystemUI"
        fi
        sudo mkdir -p "$SYSTEMUI_DST"
        sudo cp -rfa "$(pwd)/LumiROM/Mods/FluidMotion/system_ext/priv-app/SystemUI/"* "$SYSTEMUI_DST/"

        echo "${YELLOW} - Adding FluidMotion Launcher${RESET}"
        sudo mkdir -p "$EXTRACTED_FIRM_DIR/system/system/priv-app/TouchWizHome_2017"
        sudo cp -rfa "$(pwd)/LumiROM/Mods/FluidMotion/system/system/priv-app/TouchWizHome_2017/"* "$EXTRACTED_FIRM_DIR/system/system/priv-app/TouchWizHome_2017/"

        echo "${YELLOW} - Adding volte fix${RESET}"
        sudo cp -rfa "$(pwd)/LumiROM/Mods/volte_fix/vendor/lib64/"* "$EXTRACTED_FIRM_DIR/vendor/lib64/"

        echo "${YELLOW} - Adding init tweaks${RESET}"
        sudo cp -rfa "$(pwd)/LumiROM/Mods/tweaks/system/system/etc/init/"* "$EXTRACTED_FIRM_DIR/system/system/etc/init/"

        echo "${YELLOW} - Adding custom wallpapers${RESET}"
        sudo cp -rfa "$(pwd)/LumiROM/Mods/wallpaper/system/system/priv-app/wallpaper-res/"* "$EXTRACTED_FIRM_DIR/system/system/priv-app/wallpaper-res/"

        echo "${YELLOW} - Adding modded SamsungCamera${RESET}"
        sudo cp -rfa "$(pwd)/LumiROM/Mods/SamsungCameraFix/system/system/priv-app/SamsungCamera/"* "$EXTRACTED_FIRM_DIR/system/system/priv-app/SamsungCamera/"

        echo "${GREEN} - Mods added${RESET}"
    else
        echo "${RED}The use of mods for this build have been disabled by the user${RESET}"
    fi

}
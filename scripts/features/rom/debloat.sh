#!/bin/bash
#
# LumiROM features: system/vendor debloat and deodex.
# Part of scripts/features/LumiROM.sh (sourced by it); not meant to run alone.

# shellcheck disable=SC2034  # consumed by rom_debloat in rom/misc.sh
DEBLOAT_APPS=("FactoryCameraFB" "HybridRadio" "CIDManager" "SBrowser" "Facebook_stub_TFN" "FBAppManager_TFN" "SamsungTTSVoice_es_US_l01 " "SamsungCalendar" "KTAuth_Stub" "GameTools_Dream" "Gmail2" "Maps" "Duo" "Velvet" "CarrierDefaultApp" "ccinfo" "Chrome" "ChromeCustomizations" "GameHome" "GameOptimizingService" "WlanTest" "AssistantShell" "HotwordEnrollmentOKGoogleEx4CORTEXM55" "HotwordEnrollmentXGoogleEx4CORTEXM55" "BardShell" "DuoStub" "GoogleCalendarSyncAdapter" "AndroidDeveloperVerifier" "AndroidGlassesCore" "SOAgent77" "YourPhone_Stub" "AndroidAutoStub" "SingleTakeService" "SamsungBilling" "AndroidSystemIntelligence" "GoogleRestore" "SamsungMessages" "SamsungPositioning" "YouTube"  "SearchSelector" "AirGlance" "AirReadingGlass" "SamsungTTS" "WlanTest" "ARCore" "ARDrawing" "ARZone" "BGMProvider" "BixbyWakeup" "BlockchainBasicKit" "Cameralyzer" "DictDiotekForSec" "EasymodeContactsWidget81" "Fast" "FBAppManager_NS" "FunModeSDK" "GearManagerStub" "KidsHome_Installer" "LinkSharing_v11" "LiveDrawing" "MAPSAgent" "MdecService" "MoccaMobile" "Netflix_stub" "Notes40" "ParentalCare" "PhotoTable" "PlayAutoInstallConfig" "SamsungPassAutofill_v1" "SamsungTTSVoice_de_DE_f00" "SamsungTTSVoice_el_GR_f00" "SamsungTTSVoice_en_GB_f00" "SamsungTTSVoice_en_US_f00" "SamsungTTSVoice_en_US_l03" "SamsungTTSVoice_es_ES_f00" "SamsungTTSVoice_es_MX_f00" "SamsungTTSVoice_es_US_f00" "SamsungTTSVoice_fr_FR_f00" "SamsungTTSVoice_hi_IN_f00" "SamsungTTSVoice_it_IT_f00" "SamsungTTSVoice_pl_PL_f00" "SamsungTTSVoice_pt_BR_f00" "SamsungTTSVoice_ru_RU_f00" "SamsungTTSVoice_th_TH_f00" "SamsungTTSVoice_vi_VN_f00" "SamsungTTSVoice_en_IN_f00" "SmartReminder" "SmartSwitchStub" "UnifiedWFC" "UniversalMDMClient" "VideoEditorLite_Dream_N" "VisionIntelligence3.7" "VoiceAccess" "VTCameraSetting" "WebManual" "WifiGuider" "KTAuth" "KTCustomerService" "KTUsimManager" "LGUMiniCustomerCenter" "LGUplusTsmProxy" "SamsungTTSVoice_ko_KR_r00" "SketchBook" "SKTMemberShip_new" "SktUsimService" "TWorld" "AirCommand" "AppUpdateCenter" "AREmoji" "AREmojiEditor" "AuthFramework" "AutoDoodle" "AvatarEmojiSticker" "AvatarEmojiSticker_S" "Bixby" "BixbyInterpreter" "BixbyVisionFramework3.5" "DevGPUDriver-EX2200" "DigitalKey" "Discover" "DiscoverSEP" "EarphoneTypeC" "EasySetup" "FBInstaller_NS" "FBServices" "FotaAgent" "GalleryWidget" "GameDriver-EX2100" "GameDriver-EX2200" "GameDriver-SM8150" "HashTagService" "MultiControlVP6" "LedCoverService" "LinkToWindowsService" "LiveStickers" "MemorySaver_O_Refresh" "MultiControl" "OMCAgent5" "OneDrive_Samsung_v3" "OneStoreService" "SamsungCarKeyFw" "SamsungPass" "SettingsBixby" "SetupIndiaServicesTnC" "SKTFindLostPhone" "SKTHiddenMenu" "SKTMemberShip" "SKTOneStore" "SktUsimService" "SmartEye" "SmartPush" "SmartThingsKit" "SmartTouchCall" "SOAgent7" "SOAgent75" "SolarAudio-service" "SPPPushClient" "sticker" "StickerFaceARAvatar" "StoryService" "SumeNNService" "SVoiceIME" "SwiftkeyIme" "SwiftkeySetting" "SystemUpdate" "TADownloader" "TalkbackSE" "TaPackAuthFw" "TPhoneOnePackage" "TPhoneSetup" "TWorld" "UltraDataSaving_O" "Upday" "UsimRegistrationKOR" "YourPhone_P1_5" "AvatarPicker" "KT114Provider2" "KTHiddenMenu" "KTOneStore" "KTServiceAgent" "KTServiceMenu" "LGUGPSnWPS" "LGUHiddenMenu" "LGUOZStore" "SKTFindLostPhoneApp" "SmartPush_64" "SOAgent76" "TService" "vexfwk_service" "VexScanner" "LiveEffectService" "YourPhone_P1_5" "vexfwk_service" "AutoHotspotMDE" "ShareLive" "RubinVersion38" "SCPMAgent" "IPService")

rom_debloat() {
    echo ""
    if [ "$#" -ne 1 ]; then
        echo "Usage: ${FUNCNAME[0]} <EXTRACTED_FIRM_DIR>"
        return 1
    fi

	local EXTRACTED_FIRM_DIR="$1"

    rom_kick "$EXTRACTED_FIRM_DIR"
    rom_remove_esim_files "$EXTRACTED_FIRM_DIR"
	rom_remove_fabric_crypto "$EXTRACTED_FIRM_DIR"
    rom_jdm_debloat "$EXTRACTED_FIRM_DIR"
    rom_deodex "$EXTRACTED_FIRM_DIR"
    
	echo "${YELLOW}- Deleting unnecessary files and folders.${RESET}"
    rm -rf "$EXTRACTED_FIRM_DIR/system/system/etc/init/boot-image.bprof"
    rm -rf "$EXTRACTED_FIRM_DIR/system/system/etc/init/boot-image.prof"
    rm -rf "$EXTRACTED_FIRM_DIR/system/system/hidden"
    rm -rf "$EXTRACTED_FIRM_DIR/system/system/preload"
    rm -rf "$EXTRACTED_FIRM_DIR/system/system/tts"
    rm -rf "$EXTRACTED_FIRM_DIR/system/system/etc/mediasearch"
	rm -rf "$EXTRACTED_FIRM_DIR/system/system/priv-app/MediaSearch"


    if [[ "$STOCK_DEVICE" == "SM-A225F" ]]; then
        rm -rf "$EXTRACTED_FIRM_DIR/system/system/lib64/libnfc-sec.so"
        rm -rf "$EXTRACTED_FIRM_DIR/system/system/lib64/libnfc_sec_jni.so"
        rm -rf "$EXTRACTED_FIRM_DIR/system/system/lib/libnfc_sec_jni.so"
        echo "${GREEN}Removed NFC from stock image${RESET}"
    fi
    
}

rom_debloat_vendor() {
    local EXTRACTED_FIRM_DIR="$1"
    echo "${YELLOW}Starting Debloat...${RESET}"

    local targets=(
        "$EXTRACTED_FIRM_DIR/vendor/bin/create_factory_efs_file"
        "$EXTRACTED_FIRM_DIR/vendor/bin/factory"
        "$EXTRACTED_FIRM_DIR/vendor/bin/install-recovery.sh"
        "$EXTRACTED_FIRM_DIR/vendor/etc/factory.ini"
        "$EXTRACTED_FIRM_DIR/vendor/etc/init/vendor_flash_recovery.rc"
        "$EXTRACTED_FIRM_DIR/vendor/etc/mmigroup"
        "$EXTRACTED_FIRM_DIR/vendor/etc/recovery-resource.dat"
        "$EXTRACTED_FIRM_DIR/vendor/lib/modules"
        "$EXTRACTED_FIRM_DIR/vendor/lost+found"
        "$EXTRACTED_FIRM_DIR/vendor/recovery-from-boot.p"
        "$EXTRACTED_FIRM_DIR/vendor/res"
    )

    for file in "${targets[@]}"; do
        if [ -e "$file" ] || [ -L "$file" ]; then
            sudo rm -rf "$file"
            echo "${GREEN}Deleted${RESET} $file"
        else
            echo "${RED}[Omitted]${RESET} $file ${RED}not found${RESET}"
        fi
    done

    echo "${GREEN}Vendor debloat completed${RESET}"
}

rom_debloat_wsm() {
    local EXTRACTED_FIRM_DIR="$1"
    echo "${YELLOW}Starting WSM Debloat...${RESET}"

    local targets=(
        "$EXTRACTED_FIRM_DIR/system/system/etc/public.libraries-wsm.samsung.txt"
        "$EXTRACTED_FIRM_DIR/system/system/lib/libhal.wsm.samsung.so"
        "$EXTRACTED_FIRM_DIR/system/system/lib/vendor.samsung.hardware.security.wsm.service-V1-ndk.so"
        "$EXTRACTED_FIRM_DIR/system/system/lib64/libhal.wsm.samsung.so"
        "$EXTRACTED_FIRM_DIR/system/system/lib64/vendor.samsung.hardware.security.wsm.service-V1-ndk.so"
    )

    for file in "${targets[@]}"; do
        if [ -e "$file" ] || [ -L "$file" ]; then
            sudo rm -rf "$file"
            echo "${GREEN}Deleted${RESET} $file"
        else
            echo "${RED}[Omitted]${RESET} $file ${RED}not found${RESET}"
        fi
    done

    echo "${GREEN}WSM Debloat completed${RESET}"
}

rom_jdm_debloat() {
    if [ "$#" -ne 1 ]; then
        echo "Usage: ${FUNCNAME[0]} <EXTRACTED_FIRM_DIR>"
        return 1
    fi

    # I added JDM Debloat separately from Debloat to have better control over it 
    local EXTRACTED_FIRM_DIR="$1"
    local STOCK_FLOATING_FEATURE="$DEVICES_DIR/$STOCK_DEVICE/floating_feature.xml"
    local MANUF_TYPE
    MANUF_TYPE=$(awk -F'[<>]' '$2 == "SEC_FLOATING_FEATURE_COMMON_CONFIG_DEVICE_MANUFACTURING_TYPE" {print $3}' "$STOCK_FLOATING_FEATURE" | xargs)

    shopt -s nocasematch

    if [[ "$MANUF_TYPE" == *jdm* ]]; then
        echo "${GREEN}JDM detected → debloating unnecessary files${RESET}"
        rm -rf -- "$EXTRACTED_FIRM_DIR/system/system/app/BluetoothAgent"
        rm -rf -- "$EXTRACTED_FIRM_DIR/system/system/app/BluetoothMidiService"
        rm -rf -- "$EXTRACTED_FIRM_DIR/system/system/priv-app/SamsungCamera"
    else
        echo "${RED}[Omitted] Device is not JDM → skipping JDM debloating${RESET}"
    fi

    shopt -u nocasematch
}

rom_deodex() {
    echo "${YELLOW}- Deodexing ROM (removing oat folders)...${RESET}"
    echo "${YELLOW}- OAT folders to remove:${RESET}"

    local SEARCH_DIRS=(
        "$EXTRACTED_FIRM_DIR/system/system_ext/priv-app"
        "$EXTRACTED_FIRM_DIR/system/system_ext/app"
        "$EXTRACTED_FIRM_DIR/system_ext/priv-app"
        "$EXTRACTED_FIRM_DIR/system_ext/app"
        "$EXTRACTED_FIRM_DIR/system/system/priv-app"
        "$EXTRACTED_FIRM_DIR/system/system/app"
        "$EXTRACTED_FIRM_DIR/product/priv-app"
        "$EXTRACTED_FIRM_DIR/product/app"
    )

    for dir in "${SEARCH_DIRS[@]}"; do
        if [ -d "$dir" ]; then
            find "$dir" -type d -name "oat" | sed "s|$EXTRACTED_FIRM_DIR/|    - |"
            sudo find "$dir" -type d -name "oat" -exec rm -rf {} +
        else
            echo "${RED}[Omitted]${RESET} $dir ${RED}not found, skipping.${RESET}"
        fi
    done

    echo "${GREEN}Deodex complete${RESET}"
}

rom_remove_esim_files() {
    if [ "$#" -ne 1 ]; then
        echo "Usage: ${FUNCNAME[0]} <EXTRACTED_FIRM_DIR>"
        return 1
    fi

    # Remove ESIM files as we dont need it
	local EXTRACTED_FIRM_DIR="$1"
    echo "${YELLOW}- Removing ESIM files.${RESET}"
    rm -rf "$EXTRACTED_FIRM_DIR/system/system/priv-app/EsimClient"
    rm -rf "$EXTRACTED_FIRM_DIR/system/system/priv-app/EsimKeyString"
    rm -rf "$EXTRACTED_FIRM_DIR/system/system/priv-app/EuiccService"
	rm -rf "$EXTRACTED_FIRM_DIR/system/system/etc/permissions/privapp-permissions-com.samsung.euicc.xml"
	rm -rf "$EXTRACTED_FIRM_DIR/system/system/etc/sysconfig/preinstalled-packages-com.samsung.euicc.xml"
	rm -rf "$EXTRACTED_FIRM_DIR/system/system/etc/privapp-permissions-com.samsung.android.app.telephonyui.esimclient.xml"
	rm -rf "$EXTRACTED_FIRM_DIR/system/system/etc/permissions/privapp-permissions-com.samsung.android.app.telephonyui.esimclient.xml"
	rm -rf "$EXTRACTED_FIRM_DIR/system/system/etc/sysconfig/preinstalled-packages-com.samsung.android.app.telephonyui.esimclient.xml"
    rm -rf "$EXTRACTED_FIRM_DIR/system/system/etc/permissions/privapp-permissions-com.samsung.android.app.esimkeystring.xml"
    rm -rf "$EXTRACTED_FIRM_DIR/system/system/etc/sysconfig/preinstalled-packages-com.samsung.android.app.esimkeystring.xml"
}

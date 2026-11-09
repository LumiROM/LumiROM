#!/bin/bash

source scripts/utils/bash_colors.sh

GET_APK_VERSION_CODE() {
    local APK="$1"
    local VC=""

    if command -v aapt2 >/dev/null 2>&1; then
        VC=$(aapt2 dump badging "$APK" 2>/dev/null \
            | sed -n "s/^package:.*versionCode='\([0-9]*\)'.*/\1/p" | head -n1)
    fi
    if [ -z "$VC" ] && command -v aapt >/dev/null 2>&1; then
        VC=$(aapt dump badging "$APK" 2>/dev/null \
            | sed -n "s/^package:.*versionCode='\([0-9]*\)'.*/\1/p" | head -n1)
    fi

    echo "$VC"
}

GALAXY_AI() {
    echo ""
    if [ "$#" -ne 1 ]; then
        echo "Usage: ${FUNCNAME[0]} <EXTRACTED_FIRM_DIR>"
        return 1
    fi

    source "scripts/features/LumiROM.sh"

    local EXTRACTED_FIRM_DIR="$1"
    local AI_DIR="./LumiROM/Mods/Galaxy_AI"
    local STOCK_FLOATING_FEATURE="$DEVICES_DIR/$STOCK_DEVICE/floating_feature.xml"
    local TARGET_FLOATING_FEATURE="$EXTRACTED_FIRM_DIR/system/system/etc/floating_feature.xml"

    if [ "$USE_GALAXY_AI" = "true" ]; then
    	echo "${YELLOW}Adding Galaxy AI${RESET}"

        sed -i '/SEC_FLOATING_FEATURE_COMMON_DISABLE_NATIVE_AI/d' "$TARGET_FLOATING_FEATURE"
        # Adding the Galaxy AI versioning
        UPDATE_FLOATING_FEATURE "SEC_FLOATING_FEATURE_SIP_CONFIG_ONEUI_VERSION" "90000"
        # One UI 9 (S23 S918BXXUAGZIF) does not define AI_PHASE; keep the
        # 8.5-only value commented so it is not injected on Android 17.
        #UPDATE_FLOATING_FEATURE "SEC_FLOATING_FEATURE_COMMON_CONFIG_AI_PHASE" "20260201"
        UPDATE_FLOATING_FEATURE "SEC_FLOATING_FEATURE_COMMON_CONFIG_AI_VERSION" "20253"
        UPDATE_FLOATING_FEATURE "SEC_FLOATING_FEATURE_COMMON_SUPPORT_AI_AGENT" "TRUE"
        UPDATE_FLOATING_FEATURE "SEC_FLOATING_FEATURE_COMMON_SUPPORT_GENERATIVE_AI" "TRUE"
        UPDATE_FLOATING_FEATURE "SEC_FLOATING_FEATURE_GENAI_CONFIG_FOUNDATION_MODEL" "3B"
        UPDATE_FLOATING_FEATURE "SEC_FLOATING_FEATURE_GENAI_CONFIG_LLM_VERSION" "0.70"
        BUILD_PROP "$EXTRACTED_FIRM_DIR" "persist.sys.composition.type" "gpu"
        BUILD_PROP "$EXTRACTED_FIRM_DIR" "persist.sys.purgeable_assets" "1"
        BUILD_PROP "$EXTRACTED_FIRM_DIR" "ro.config.fha_enable" "true"
        BUILD_PROP "$EXTRACTED_FIRM_DIR" "ro.vendor.mtk_tflite_support" "1"
        BUILD_PROP "$EXTRACTED_FIRM_DIR" "debug.mtk_tflite.target_gpu" "1"
        BUILD_PROP "$EXTRACTED_FIRM_DIR" "persist.sys.storage_manager.enabled" "1"
        BUILD_PROP "$EXTRACTED_FIRM_DIR" "debug.vpp.enable" "1"
        BUILD_PROP "$EXTRACTED_FIRM_DIR" "persist.sys.videoplayer.vpp" "0"
        BUILD_PROP "$EXTRACTED_FIRM_DIR" "persist.sys.aicp.enable" "true"
        BUILD_PROP "$EXTRACTED_FIRM_DIR" "persist.sys.vsw.enable" "true"
        BUILD_PROP "$EXTRACTED_FIRM_DIR" "debug.hwui.render_dirty_regions" "false"
        BUILD_PROP "$EXTRACTED_FIRM_DIR" "ro.videoeditor.support_audio_eraser" "1"
        BUILD_PROP "$EXTRACTED_FIRM_DIR" "ro.videoeditor.support_object_eraser" "1"
        BUILD_PROP "$EXTRACTED_FIRM_DIR" "com.samsung.android.media.contextanalyzer.core" "cpu"
        BUILD_PROP "$EXTRACTED_FIRM_DIR" "ro.hwui.texture_cache_size" "72"
        BUILD_PROP "$EXTRACTED_FIRM_DIR" "ro.hwui.layer_cache_size" "48"
        BUILD_PROP "$EXTRACTED_FIRM_DIR" "persist.vendor.camera.hal3.enabled" "1"
        BUILD_PROP "$EXTRACTED_FIRM_DIR" "vendor.camera.hal3.enabled" "1"
        BUILD_PROP "$EXTRACTED_FIRM_DIR" "persist.vendor.camera.raw.enabled" "1"
        BUILD_PROP "$EXTRACTED_FIRM_DIR" "persist.sys.camera.raw" "1"

        # Adding AI dependencies
        UPDATE_FLOATING_FEATURE "SEC_FLOATING_FEATURE_GENAI_SUPPORT_OFFLINE_LANGUAGEMODEL" "TRUE"
        UPDATE_FLOATING_FEATURE "SEC_FLOATING_FEATURE_FRAMEWORK_SUPPORT_PERSONALIZED_DATA_CORE" "TRUE"
        UPDATE_FLOATING_FEATURE "SEC_FLOATING_FEATURE_SAIV_SUPPORT_AI_REVITAL" "TRUE"
        UPDATE_FLOATING_FEATURE "SEC_FLOATING_FEATURE_SAIV_CONFIG_AI_REVITAL_VERSION" "1.9,4"
        UPDATE_FLOATING_FEATURE "SEC_FLOATING_FEATURE_GENAI_SUPPORT_C2PA" "FALSE"

        # Misc AI things
        UPDATE_FLOATING_FEATURE "SEC_FLOATING_FEATURE_VISION_SUPPORT_AI_MY_FAVORITE_CONTENTS" "TRUE"
        UPDATE_FLOATING_FEATURE "SEC_FLOATING_FEATURE_GENAI_SUPPORT_IMAGE_CLIPPER" "TRUE"
        UPDATE_FLOATING_FEATURE "SEC_FLOATING_FEATURE_GENAI_SUPPORT_OBJECT_ERASER" "TRUE"
        UPDATE_FLOATING_FEATURE "SEC_FLOATING_FEATURE_GENAI_SUPPORT_REFLECTION_ERASER" "TRUE"
        UPDATE_FLOATING_FEATURE "SEC_FLOATING_FEATURE_GENAI_SUPPORT_SHADOW_ERASER" "TRUE"
        UPDATE_FLOATING_FEATURE "SEC_FLOATING_FEATURE_GENAI_SUPPORT_SMART_LASSO" "TRUE"
        UPDATE_FLOATING_FEATURE "SEC_FLOATING_FEATURE_GENAI_SUPPORT_SPOT_FIXER" "TRUE"
        UPDATE_FLOATING_FEATURE "SEC_FLOATING_FEATURE_GENAI_SUPPORT_STYLE_TRANSFER" "TRUE"
        UPDATE_FLOATING_FEATURE "SEC_FLOATING_FEATURE_SYSTEMUI_SUPPORT_BRIEF_NOTIFICATION" "TRUE"
        UPDATE_FLOATING_FEATURE "SEC_FLOATING_FEATURE_MMFW_SUPPORT_MEDIA_CONTEXT_ANALYZER" "TRUE"
        UPDATE_FLOATING_FEATURE "SEC_FLOATING_FEATURE_MMFW_SUPPORT_TARGET_TRACKING" "TRUE"
        UPDATE_FLOATING_FEATURE "SEC_FLOATING_FEATURE_MMFW_SUPPORT_MUSIC_ALBUMART_3DAUDIO" "TRUE"

        local AI_SYS="$AI_DIR/system/system"
        local AI_ENTRY AI_APP_NAME

        for AI_ENTRY in "$AI_SYS/app/"*; do
            [ -e "$AI_ENTRY" ] || continue
            AI_APP_NAME="$(basename "$AI_ENTRY")"
            if [ -d "$EXTRACTED_FIRM_DIR/system/system/app/$AI_APP_NAME" ]; then
                echo "${GREEN}Keeping stock app/$AI_APP_NAME${RESET}"
            else
                sudo cp -rfa "$AI_ENTRY" "$EXTRACTED_FIRM_DIR/system/system/app/"
            fi
        done

        for AI_ENTRY in "$AI_SYS/priv-app/"*; do
            [ -e "$AI_ENTRY" ] || continue
            AI_APP_NAME="$(basename "$AI_ENTRY")"
            [ "$AI_APP_NAME" = "SamsungSmartSuggestions" ] && continue
            if [ -d "$EXTRACTED_FIRM_DIR/system/system/priv-app/$AI_APP_NAME" ]; then
                echo "${GREEN}Keeping stock priv-app/$AI_APP_NAME${RESET}"
            else
                sudo cp -rfa "$AI_ENTRY" "$EXTRACTED_FIRM_DIR/system/system/priv-app/"
            fi
        done

        for AI_ENTRY in "$AI_SYS"/*; do
            [ -e "$AI_ENTRY" ] || continue
            case "$(basename "$AI_ENTRY")" in
                app|priv-app) continue ;;
            esac
            # -n: keep existing files, copy only missing ones.
            sudo cp -rfan "$AI_ENTRY" "$EXTRACTED_FIRM_DIR/system/system/"
        done
        sudo cp -rfa "$(pwd)/LumiROM/Mods/Galaxy_AI/vendor/"* "$EXTRACTED_FIRM_DIR/vendor/"


        # Adding Wallpaper AI
        if [ ! -d "$EXTRACTED_FIRM_DIR/product/priv-app/AiWallpaper" ]; then
        	echo "${YELLOW}Adding Wallpaper AI${RESET}"
            mkdir -p "$EXTRACTED_FIRM_DIR/product/priv-app/AiWallpaper"
            cp -rfa "$(pwd)/LumiROM/Mods/Apps/AiWallpaper/"* "$EXTRACTED_FIRM_DIR/product/priv-app/AiWallpaper/"

            UPDATE_FLOATING_FEATURE "SEC_FLOATING_FEATURE_GENAI_SUPPORT_TIME_WEATHER_WALLPAPER" "V7"
            UPDATE_FLOATING_FEATURE "SEC_FLOATING_FEATURE_LOCKSCREEN_CONFIG_WALLPAPER_STYLE" "VIDEO,GENWEATHER,FLIPSUIT_LOCK"
        fi

        # Adding Now Brief
        echo "${YELLOW}Adding Now Brief${RESET}"
        mkdir -p "$AI_DIR/system/system/priv-app/SamsungSmartSuggestions/"
        mkdir -p "$EXTRACTED_FIRM_DIR/system/system/priv-app/SamsungSmartSuggestions/"

        local SS_MOD_APK="$AI_DIR/system/system/priv-app/SamsungSmartSuggestions/SamsungSmartSuggestions.apk"
        local SS_TARGET_APK="$EXTRACTED_FIRM_DIR/system/system/priv-app/SamsungSmartSuggestions/SamsungSmartSuggestions.apk"
        local SS_STOCK_VC=""
        local SS_MOD_VC=""
        [ -f "$SS_TARGET_APK" ] && SS_STOCK_VC="$(GET_APK_VERSION_CODE "$SS_TARGET_APK")"

        if [ ! -f "$SS_MOD_APK" ]; then
            aria2c -x 1 -d "$AI_DIR/system/system/priv-app/SamsungSmartSuggestions/" -o "SamsungSmartSuggestions.apk" --allow-overwrite=true --auto-file-renaming=false --console-log-level=error "https://huggingface.co/buckets/LuminousJD418/LumiROM/resolve/OneUi9/SamsungSmartSuggestions.apk?download=true" || return 1
        fi

        if [ -f "$SS_MOD_APK" ]; then
            SS_MOD_VC="$(GET_APK_VERSION_CODE "$SS_MOD_APK")"
            echo "${YELLOW}Replacing SamsungSmartSuggestions (stock ${SS_STOCK_VC:-none} -> mod ${SS_MOD_VC:-unknown})${RESET}"
            rm -f "$SS_TARGET_APK"
            cp -rfa "$AI_DIR/system/system/priv-app/SamsungSmartSuggestions/"* "$EXTRACTED_FIRM_DIR/system/system/priv-app/SamsungSmartSuggestions/"
        else
            echo "${RED}No SamsungSmartSuggestions APK available; keeping stock${RESET}"
        fi

        # Cleanup any leftover .aria2 control files
        wait
        find "$AI_DIR/system/system/priv-app/SamsungSmartSuggestions/" -name "*.aria2" -exec rm -f {} +
    else
    	echo
        echo "${RED}The use of Galaxy AI for this build have been disabled by the user${RESET}"
        UPDATE_FLOATING_FEATURE "SEC_FLOATING_FEATURE_COMMON_DISABLE_NATIVE_AI" "TRUE"
    fi
}
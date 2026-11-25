#!/bin/bash
#
# LumiROM features: build props and floating features.
# Part of scripts/features/LumiROM.sh (sourced by it); not meant to run alone.

rom_update_floating_feature() {
    local key="$1"
    local value="$2"
    if [[ -z "$value" ]]; then
        echo "${RED}[Omitted]${RESET} $key ${RED}— no value found.${RESET}"
        return
    fi

    if grep -q "<${key}>.*</${key}>" "$TARGET_FLOATING_FEATURE"; then
        local current_line
        current_line=$(grep "<${key}>.*</${key}>" "$TARGET_FLOATING_FEATURE")
        local current_value
        current_value=$(echo "$current_line" | sed -E "s/.*<${key}>(.*)<\/${key}>.*/\1/")

        if [[ "$current_value" == "$value" ]]; then
            return
        fi

        local indent
        indent=$(echo "$current_line" | sed -E "s/(<${key}>.*<\/${key}>).*//")
        local line="${indent}<${key}>${value}</${key}>"
        sed -i "s|${indent}<${key}>.*</${key}>|$line|" "$TARGET_FLOATING_FEATURE"
        echo "${GREEN}Updated ${RESET}$key${GREEN} with => ${RESET}$value"
    else
        local line="    <$key>$value</$key>"
        sed -i "3i\\$line" "$TARGET_FLOATING_FEATURE"
        echo "${GREEN}Added ${RESET}$key${GREEN} with value => ${RESET}$value"
    fi
}

rom_apply_floating_feature() {
    echo ""
	echo "${BLUE}============ Floating Feature ============${RESET}"
    #========== COMMON ==========#
    rom_update_floating_feature "SEC_FLOATING_FEATURE_COMMON_CONFIG_SEP_CATEGORY" "sep_basic"

    #========== EDGE ==========#
    rom_update_floating_feature "SEC_FLOATING_FEATURE_COMMON_CONFIG_EDGE" "panel"
    rom_update_floating_feature "SEC_FLOATING_FEATURE_SYSTEMUI_CONFIG_EDGELIGHTING_FRAME_EFFECT" "frame_effect"

    #========== SCREEN RECORDER ==========#
    rom_update_floating_feature "SEC_FLOATING_FEATURE_FRAMEWORK_SUPPORT_SCREEN_RECORDER" "TRUE"
	
	#========== VOICE RECORDER ==========#
    rom_update_floating_feature "SEC_FLOATING_FEATURE_VOICERECORDER_CONFIG_DEF_MODE" "normal,interview,voicememo"

    #========== AUDIO ==========#
    rom_update_floating_feature "SEC_FLOATING_FEATURE_AUDIO_SUPPORT_BT_RECORDING" "TRUE"
    rom_update_floating_feature "SEC_FLOATING_FEATURE_AUDIO_CONFIG_VOLUMEMONITOR_STAGE" "$(awk -F'[<>]' '$2 == "SEC_FLOATING_FEATURE_AUDIO_CONFIG_VOLUMEMONITOR_STAGE" {print $3}' "$STOCK_FLOATING_FEATURE")"
    rom_update_floating_feature "SEC_FLOATING_FEATURE_AUDIO_SUPPORT_VOLUME_MONITOR" "$(awk -F'[<>]' '$2 == "SEC_FLOATING_FEATURE_AUDIO_SUPPORT_VOLUME_MONITOR" {print $3}' "$STOCK_FLOATING_FEATURE")"
    rom_update_floating_feature "SEC_FLOATING_FEATURE_AUDIO_CONFIG_REMOTE_MIC" "$(awk -F'[<>]' '$2 == "SEC_FLOATING_FEATURE_AUDIO_CONFIG_REMOTE_MIC" {print $3}' "$STOCK_FLOATING_FEATURE")"
    rom_update_floating_feature "SEC_FLOATING_FEATURE_AUDIO_CONFIG_SOUNDALIVE_VERSION" "$(awk -F'[<>]' '$2 == "SEC_FLOATING_FEATURE_AUDIO_CONFIG_SOUNDALIVE_VERSION" {print $3}' "$STOCK_FLOATING_FEATURE")"
    rom_update_floating_feature "SEC_FLOATING_FEATURE_AUDIO_CONFIG_VOLUMEMONITOR_GAIN" "$(awk -F'[<>]' '$2 == "SEC_FLOATING_FEATURE_AUDIO_CONFIG_VOLUMEMONITOR_GAIN" {print $3}' "$STOCK_FLOATING_FEATURE")"

    #========== SETTINGS ==========#
    rom_update_floating_feature "SEC_FLOATING_FEATURE_SETTINGS_SUPPORT_DEFAULT_DOUBLE_TAP_TO_WAKE" "TRUE"
    rom_update_floating_feature "SEC_FLOATING_FEATURE_SETTINGS_SUPPORT_FUNCTION_KEY_MENU" "TRUE"
    rom_update_floating_feature "SEC_FLOATING_FEATURE_SETTINGS_CONFIG_ELECTRIC_RATED_VALUE" "$(awk -F'[<>]' '$2 == "SEC_FLOATING_FEATURE_SETTINGS_CONFIG_ELECTRIC_RATED_VALUE" {print $3}' "$STOCK_FLOATING_FEATURE")"
    rom_update_floating_feature "SEC_FLOATING_FEATURE_SETTINGS_CONFIG_BRAND_NAME" "$(awk -F'[<>]' '$2 == "SEC_FLOATING_FEATURE_SETTINGS_CONFIG_BRAND_NAME" {print $3}' "$STOCK_FLOATING_FEATURE")"
    rom_update_floating_feature "SEC_FLOATING_FEATURE_SETTINGS_CONFIG_DEFAULT_FONT_SIZE" "$(awk -F'[<>]' '$2 == "SEC_FLOATING_FEATURE_SETTINGS_CONFIG_DEFAULT_FONT_SIZE" {print $3}' "$STOCK_FLOATING_FEATURE")"

    #========== REFRESH RATE ==========#
    rom_update_floating_feature "SEC_FLOATING_FEATURE_LCD_CONFIG_HFR_SUPPORTED_REFRESH_RATE" "$(awk -F'[<>]' '$2 == "SEC_FLOATING_FEATURE_LCD_CONFIG_HFR_SUPPORTED_REFRESH_RATE" {print $3}' "$STOCK_FLOATING_FEATURE")"
    rom_update_floating_feature "SEC_FLOATING_FEATURE_LCD_CONFIG_HFR_MODE" "$(awk -F'[<>]' '$2 == "SEC_FLOATING_FEATURE_LCD_CONFIG_HFR_MODE" {print $3}' "$STOCK_FLOATING_FEATURE")"
    rom_update_floating_feature "SEC_FLOATING_FEATURE_LCD_CONFIG_HFR_DEFAULT_REFRESH_RATE" "$(awk -F'[<>]' '$2 == "SEC_FLOATING_FEATURE_LCD_CONFIG_HFR_DEFAULT_REFRESH_RATE" {print $3}' "$STOCK_FLOATING_FEATURE")"

    #========== SYSTEM ==========#
    rom_update_floating_feature "SEC_FLOATING_FEATURE_SYSTEM_SUPPORT_ENHANCED_CPU_RESPONSIVENESS" "TRUE"
    rom_update_floating_feature "SEC_FLOATING_FEATURE_SYSTEM_SUPPORT_ENHANCED_PROCESSING" "TRUE"
    rom_update_floating_feature "SEC_FLOATING_FEATURE_SYSTEM_CONFIG_SIOP_POLICY_FILENAME" "$(awk -F'[<>]' '$2 == "SEC_FLOATING_FEATURE_SYSTEM_CONFIG_SIOP_POLICY_FILENAME" {print $3}' "$STOCK_FLOATING_FEATURE")"

    #========== LAUNCHER ==========#
    rom_update_floating_feature "SEC_FLOATING_FEATURE_LAUNCHER_SUPPORT_CLOCK_LIVE_ICON" "TRUE"
    rom_update_floating_feature "SEC_FLOATING_FEATURE_LAUNCHER_CONFIG_ANIMATION_TYPE" "HighEnd"

    #========== DISPLAY ==========#
    rom_update_floating_feature "SEC_FLOATING_FEATURE_LCD_CONFIG_CONTROL_AUTO_BRIGHTNESS" "$(awk -F'[<>]' '$2 == "SEC_FLOATING_FEATURE_LCD_CONFIG_CONTROL_AUTO_BRIGHTNESS" {print $3}' "$STOCK_FLOATING_FEATURE")"
    rom_update_floating_feature "SEC_FLOATING_FEATURE_LCD_CONFIG_DEFAULT_SCREEN_MODE" "$(awk -F'[<>]' '$2 == "SEC_FLOATING_FEATURE_LCD_CONFIG_DEFAULT_SCREEN_MODE" {print $3}' "$STOCK_FLOATING_FEATURE")"
    rom_update_floating_feature "SEC_FLOATING_FEATURE_LCD_SUPPORT_NATURAL_SCREEN_MODE" "$(awk -F'[<>]' '$2 == "SEC_FLOATING_FEATURE_LCD_SUPPORT_NATURAL_SCREEN_MODE" {print $3}' "$STOCK_FLOATING_FEATURE")"
    rom_update_floating_feature "SEC_FLOATING_FEATURE_LCD_SUPPORT_SCREEN_MODE_TYPE" "$(awk -F'[<>]' '$2 == "SEC_FLOATING_FEATURE_LCD_SUPPORT_SCREEN_MODE_TYPE" {print $3}' "$STOCK_FLOATING_FEATURE")"

    #========== CAMERA ==========#
    rom_update_floating_feature "SEC_FLOATING_FEATURE_CAMERA_CONFIG_STRIDE_OCR_VERSION" "V1"
    rom_update_floating_feature "SEC_FLOATING_FEATURE_CAMERA_SUPPORT_PRIVACY_TOGGLE" "TRUE"
    rom_update_floating_feature "SEC_FLOATING_FEATURE_CAMERA_CONFIG_CAMID_TELE_BINNING" "$(awk -F'[<>]' '$2 == "SEC_FLOATING_FEATURE_CAMERA_CONFIG_CAMID_TELE_BINNING" {print $3}' "$STOCK_FLOATING_FEATURE")"
    rom_update_floating_feature "SEC_FLOATING_FEATURE_CAMERA_CONFIG_MEMORY_USAGE_LEVEL" "$(awk -F'[<>]' '$2 == "SEC_FLOATING_FEATURE_CAMERA_CONFIG_MEMORY_USAGE_LEVEL" {print $3}' "$STOCK_FLOATING_FEATURE")"
    rom_update_floating_feature "SEC_FLOATING_FEATURE_CAMERA_CONFIG_QRCODE_INTERVAL" "$(awk -F'[<>]' '$2 == "SEC_FLOATING_FEATURE_CAMERA_CONFIG_QRCODE_INTERVAL" {print $3}' "$STOCK_FLOATING_FEATURE")"
    rom_update_floating_feature "SEC_FLOATING_FEATURE_CAMERA_CONFIG_UW_DISTORTION_CORRECTION" "$(awk -F'[<>]' '$2 == "SEC_FLOATING_FEATURE_CAMERA_CONFIG_UW_DISTORTION_CORRECTION" {print $3}' "$STOCK_FLOATING_FEATURE")"
    rom_update_floating_feature "SEC_FLOATING_FEATURE_CAMERA_CONFIG_AVATAR_MAX_FACE_NUM" "$(awk -F'[<>]' '$2 == "SEC_FLOATING_FEATURE_CAMERA_CONFIG_AVATAR_MAX_FACE_NUM" {print $3}' "$STOCK_FLOATING_FEATURE")"
    rom_update_floating_feature "SEC_FLOATING_FEATURE_CAMERA_CONFIG_CAMID_TELE_STANDARD_CROP" "$(awk -F'[<>]' '$2 == "SEC_FLOATING_FEATURE_CAMERA_CONFIG_CAMID_TELE_STANDARD_CROP" {print $3}' "$STOCK_FLOATING_FEATURE")"
    rom_update_floating_feature "SEC_FLOATING_FEATURE_CAMERA_CONFIG_HIGH_RESOLUTION_MAX_CAPTURE" "$(awk -F'[<>]' '$2 == "SEC_FLOATING_FEATURE_CAMERA_CONFIG_HIGH_RESOLUTION_MAX_CAPTURE" {print $3}' "$STOCK_FLOATING_FEATURE")"
    rom_update_floating_feature "SEC_FLOATING_FEATURE_CAMERA_CONFIG_NIGHT_FRONT_DISPLAY_FLASH_TRANSPARENT" "$(awk -F'[<>]' '$2 == "SEC_FLOATING_FEATURE_CAMERA_CONFIG_NIGHT_FRONT_DISPLAY_FLASH_TRANSPARENT" {print $3}' "$STOCK_FLOATING_FEATURE")"

    #========== BIOAUTH ==========#
    rom_update_floating_feature "SEC_FLOATING_FEATURE_BIOAUTH_CONFIG_FINGERPRINT_FEATURES" "$(awk -F'[<>]' '$2 == "SEC_FLOATING_FEATURE_BIOAUTH_CONFIG_FINGERPRINT_FEATURES" {print $3}' "$STOCK_FLOATING_FEATURE")"

    #========== LOCKSCREEN ==========#
    rom_update_floating_feature "SEC_FLOATING_FEATURE_LOCKSCREEN_CONFIG_PUNCHHOLE_VI" "$(awk -F'[<>]' '$2 == "SEC_FLOATING_FEATURE_LOCKSCREEN_CONFIG_PUNCHHOLE_VI" {print $3}' "$STOCK_FLOATING_FEATURE")"

	#========== MANUFACTUREER TYPE ==========#
	rom_update_floating_feature "SEC_FLOATING_FEATURE_COMMON_CONFIG_DEVICE_MANUFACTURING_TYPE" "$(awk -F'[<>]' '$2 == "SEC_FLOATING_FEATURE_COMMON_CONFIG_DEVICE_MANUFACTURING_TYPE" {print $3}' "$STOCK_FLOATING_FEATURE")"

}

rom_build_prop() {
    local EXTRACTED_FIRM_DIR="$1"
    local KEY="$2"
    local VALUE="${3:-}"

    if [ -z "$EXTRACTED_FIRM_DIR" ] || [ -z "$KEY" ]; then
        echo "Usage: BUILD_PROP <EXTRACTED_FIRM_DIR> <key> [value]"
        return 1
    fi

    local PROP_FILES=(
        "$EXTRACTED_FIRM_DIR/system/system/build.prop"
    )
    for PROP in "${PROP_FILES[@]}"; do
        [ -f "$PROP" ] || continue

        if [ -z "$VALUE" ]; then
            sudo sed -i "/^${KEY}=.*/d" "$PROP"
            echo "${RED}Removed ${RESET}$KEY"
        else
            if sudo grep -q "^${KEY}=" "$PROP"; then
                sudo sed -i "s|^${KEY}=.*|${KEY}=${VALUE}|" "$PROP"
                echo "${GREEN}Updated ${RESET}$KEY${GREEN} with value => ${RESET}$VALUE${RESET}"
            else
                echo "${KEY}=${VALUE}" | sudo tee -a "$PROP" > /dev/null
                echo "${GREEN}Added ${RESET}$KEY${GREEN} with value => ${RESET}$VALUE${RESET}"
            fi
        fi
    done
}

rom_disable_encryption_props() {
    local EXTRACTED_FIRM_DIR="$1"
    local PROP

    for PROP in "$EXTRACTED_FIRM_DIR/system/system/build.prop" "$EXTRACTED_FIRM_DIR/vendor/build.prop"; do
        [ -f "$PROP" ] || continue
        sudo sed -i '/^ro.crypto.state=/d; /^ro.crypto.type=/d' "$PROP"
        printf 'ro.crypto.state=unencrypted\nro.crypto.type=none\n' | sudo tee -a "$PROP" >/dev/null
        echo "${GREEN}Set ro.crypto.state=unencrypted / ro.crypto.type=none in ${PROP#$EXTRACTED_FIRM_DIR/}${RESET}"
    done
}

rom_enable_zygote_stdio() {
    local EXTRACTED_FIRM_DIR="$1"
    [ "${ZYGOTE_STDIO_KMSG:-false}" = "true" ] || return 0

    local RC
    for RC in \
        "$EXTRACTED_FIRM_DIR/system/system/etc/init/hw/init.zygote64.rc" \
        "$EXTRACTED_FIRM_DIR/system/system/etc/init/hw/init.zygote64_32.rc" \
        "$EXTRACTED_FIRM_DIR/system/system/etc/init/hw/init.zygote32.rc"; do
        [ -f "$RC" ] || continue
        if ! grep -q '^[[:space:]]*stdio_to_kmsg' "$RC"; then
            awk '
                /^service zygote( |_secondary )/ { in_svc=1 }
                in_svc && /^[[:space:]]*user / { print; print "    stdio_to_kmsg"; next }
                /^$/ { in_svc=0 }
                { print }
            ' "$RC" > "$RC.tmp" && mv "$RC.tmp" "$RC"
            echo "${GREEN}Enabled zygote stdio_to_kmsg in $(basename "$RC")${RESET}"
        fi
    done
}

rom_enable_logcat_persist() {
    local EXTRACTED_FIRM_DIR="$1"
    [ "${LOGCAT_PERSIST:-false}" = "true" ] || return 0

    local RC="$EXTRACTED_FIRM_DIR/system/system/etc/init/lumi_logcat.rc"
    local WRAP="$EXTRACTED_FIRM_DIR/system/system/bin/lumi_logcat.sh"
    local WRAP_INIT="$EXTRACTED_FIRM_DIR/system/system/bin/lumi_logcat_init.sh"

    cat > "$WRAP" <<'EOF'
#!/system/bin/sh
exec /system/bin/logcat -b main,system,crash,events -v threadtime -f /data/local/tmp/lumi_boot.log 2>/data/local/tmp/lumi_logcat_err.txt
EOF
    cat > "$WRAP_INIT" <<'EOF'
#!/system/bin/sh
exec /system/bin/logcat -b main,system,crash,events -v threadtime -f /data/lumi_boot_init.log 2>/data/local/tmp/lumi_logcat_init_err.txt
EOF
    chmod 0755 "$WRAP" "$WRAP_INIT"

    {
        cat <<'EOF'
service lumi_logcat /system/bin/sh /system/bin/lumi_logcat.sh
    class late_start
    user root
    group root log
    seclabel u:r:shell:s0
    oneshot

service lumi_logcat_init /system/bin/sh /system/bin/lumi_logcat_init.sh
    class late_start
    user root
    group root log
    oneshot

on post-fs-data
EOF
        if [ "${SELINUX_PERMISSIVE:-false}" = "true" ]; then
            echo "    write /sys/fs/selinux/enforce 0"
        fi
        cat <<'EOF'
    mkdir /data/local/tmp 0771 shell shell
    symlink /data/local/tmp/lumi_boot.log /data/lumi_boot.log
    start lumi_logcat
    start lumi_logcat_init
EOF
    } > "$RC"
    echo "${GREEN}Enabled persistent logcat via sh wrapper (/data/lumi_boot.log)${RESET}"
}

rom_apply_prop_features() {
    echo ""
    if [ "$#" -ne 1 ]; then
        echo "Usage: ${FUNCNAME[0]} <EXTRACTED_FIRM_DIR>"
        return 1
    fi

	local EXTRACTED_FIRM_DIR="$1"

    # Add build.prop features
    rom_build_prop "$EXTRACTED_FIRM_DIR" "wifi.interface" "wlan0"
    rom_build_prop "$EXTRACTED_FIRM_DIR" "wlan.wfd.hdcp" "disabled"
    rom_build_prop "$EXTRACTED_FIRM_DIR" "debug.hwui.renderer" "opengl"
    rom_build_prop "$EXTRACTED_FIRM_DIR" "debug.hwui.skia_atrace_enabled" "false"
    rom_build_prop "$EXTRACTED_FIRM_DIR" "debug.renderengine.backend" "skiaglthreaded"
	rom_build_prop "$EXTRACTED_FIRM_DIR" "ro.telephony.sim_slots.count" "2"
    rom_build_prop "$EXTRACTED_FIRM_DIR" "ro.factory.model" "$STOCK_DEVICE"
    rom_build_prop "$EXTRACTED_FIRM_DIR" "ro.surface_flinger.protected_contents" "false"
    rom_build_prop "$EXTRACTED_FIRM_DIR" "persist.audio.voip.enabled" "true"
    rom_build_prop "$EXTRACTED_FIRM_DIR" "persist.vendor.audio.voip" "true"
    rom_build_prop "$EXTRACTED_FIRM_DIR" "persist.audio.recording.voip" "true"
    rom_build_prop "$EXTRACTED_FIRM_DIR" "ro.config.iccc_version" "Disabled"
    rom_build_prop "$EXTRACTED_FIRM_DIR" "dalvik.vm.systemuicompilerfilter" "speed"
    rom_build_prop "$EXTRACTED_FIRM_DIR" "persist.adb.notify" "0"
    rom_build_prop "$EXTRACTED_FIRM_DIR" "ro.surface_flinger.max_frame_buffer_acquired_buffers" "4"
    rom_build_prop "$EXTRACTED_FIRM_DIR" "debug.hwui.use_triple_buffering" "true"
    rom_build_prop "$EXTRACTED_FIRM_DIR" "debug.sf.enable_gl_backpressure" "0"
    rom_build_prop "$EXTRACTED_FIRM_DIR" "debug.sf.disable_backpressure" "1"
    rom_build_prop "$EXTRACTED_FIRM_DIR" "audio.safemedia.bypass" "true"
    rom_build_prop "$EXTRACTED_FIRM_DIR" "persist.vendor.camera.expose.aux" "1"
    rom_build_prop "$EXTRACTED_FIRM_DIR" "vendor.camera.aux.packagelist" "com.sec.android.app.camera,com.samsung.android.scan3d"
	rom_build_prop "$EXTRACTED_FIRM_DIR" "fw.show_multiuserui" "1"
	rom_build_prop "$EXTRACTED_FIRM_DIR" "fw.max_users" "5"

    # Build identity
    rom_build_prop "$EXTRACTED_FIRM_DIR" "ro.build.user" "Luminous418"
    rom_build_prop "$EXTRACTED_FIRM_DIR" "ro.build.host" "Luminous418"

    # Related to LumiSettings
    rom_build_prop "$EXTRACTED_FIRM_DIR" "ro.lumi.version" "$LUMIROM_VERSION"
    

    # Related to Updater App
    # LumiFota reads ro.lumi.rom.ver / ro.lumi.rom.ver.code and falls back to
    # the old ro.cloudy.* names, so write both: the new ones for LumiFota and
    # the legacy pair for older updater builds that may still be installed.
    if [ "$USE_MODS" = "true" ]; then
        rom_build_prop "$EXTRACTED_FIRM_DIR" "ro.lumi.rom.ver" "$LUMIROM_VERSION"
        rom_build_prop "$EXTRACTED_FIRM_DIR" "ro.lumi.rom.ver.code" "$LUMIROM_CODE"
        rom_build_prop "$EXTRACTED_FIRM_DIR" "ro.cloudy.rom.ver" "$LUMIROM_VERSION"
        rom_build_prop "$EXTRACTED_FIRM_DIR" "ro.cloudy.rom.ver.code" "$LUMIROM_CODE"
        rom_build_prop "$EXTRACTED_FIRM_DIR" "ro.cloudy.maintainer" "$LUMIROM_MAINTAINER"
    fi

    # The vendor build.prop overrides the system one at boot, so patch it here
    # to ensure the threaded Skia renderengine backend is actually used.
    local VENDOR_BUILD_PROP="$EXTRACTED_FIRM_DIR/vendor/build.prop"
    if [ -f "$VENDOR_BUILD_PROP" ]; then
        sudo sed -i 's|^debug.renderengine.backend=.*|debug.renderengine.backend=skiaglthreaded|' "$VENDOR_BUILD_PROP"
        echo "${GREEN}Patched ${RESET}vendor/build.prop debug.renderengine.backend => skiaglthreaded${RESET}"
    fi

    rom_disable_encryption_props "$EXTRACTED_FIRM_DIR"
}

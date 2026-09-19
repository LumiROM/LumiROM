#!/bin/bash
source scripts/utils/bash_colors.sh
[ -f scripts/utils/platform_key.sh ] && source scripts/utils/platform_key.sh
export AVBTOOL_BIN="${AVBTOOL:-$PWD/bin/avb/avbtool}"
export APEX_WIFI_FIX_KEY="$PWD/scripts/keys/apex-wifi-fix.pem"
export APEX_WIFI_FIX_PUB="$PWD/scripts/keys/apex-wifi-fix.avbpubkey"

# =====================================================================
#  Wifi teardown fix, baked into the com.android.wifi apex.
#
#  Root cause on MediaTek devices ported to an A34/A24 base:
#  WifiNative.stopHalAndWificondIfNecessary() -> WifiVendorHal.stopVendorHal()
#  -> HalDeviceManager.stopWifi() -> IWifi.stop() HIDL call into the legacy
#  1.0 wifi HAL (android.hardware.wifi@1.0-service-lazy), which never answers
#  while the HAL is running wifi_cleanup. The WifiHandlerThread blocks
#  forever. Via onSoftApInterfaceDestroyed that leaves the hotspot tile on
#  "turning off"; via onClientInterfaceForConnectivityDestroyed (wifi OFF)
#  it wedges wifi entirely, so the hotspot can no longer be started. The
#  same call is also reached from the NAN/P2P teardown paths.
#
#  Fix: patch WifiNative inside the service-wifi.jar that lives in the
#  com.android.wifi apex, then rewrite the apex *in the ROM itself*
#  (capex repack at build time). No bind-mounts, no SELinux service, no
#  Magisk, no post-fs-data hooks — the patch is baked into the apex
#  payload image itself. Because apexd compares the payload's embedded
#  AVB hashtree root digest with the one inside the capex's
#  apex_manifest.pb (originalApexDigest), we regenerate the dm-verity
#  hash tree with avbtool (LumiROM's own apex key) and update both the
#  apex digest and its apex_pubkey to keep apexd's verification happy.
# =====================================================================

HotspotFix_BUILD_PATCHED_JAR() {
    if [ "$#" -ne 3 ]; then
        echo "Usage: ${FUNCNAME[0]} <WORK_DIR_SOFTAP> <APKTOOL_JAR> <SRC_JAR>"
        return 1
    fi
    local SOFTAP_DIR="$1"
    local APKTOOL_JAR="$2"
    local SRC_JAR="$3"
    local SMALI_OUT="$SOFTAP_DIR/services"

    rm -rf "$SMALI_OUT"
    java -jar "$APKTOOL_JAR" d -f "$SRC_JAR" -o "$SMALI_OUT" >/dev/null 2>&1 || {
        echo "${RED} - apktool decompile failed for service-wifi.jar${RESET}"
        return 1
    }

    local SMALI
    SMALI="$(ls "$SMALI_OUT"/smali*/com/android/server/wifi/WifiNative.smali 2>/dev/null | grep -v '\$' | head -1)"
    if [ -z "$SMALI" ]; then
        echo "${RED} - WifiNative.smali not found inside apex${RESET}"
        return 1
    fi

    echo "${YELLOW} - Patching WifiNative in service-wifi.jar${RESET}"
    python3 scripts/utils/softap_fix.py "$SMALI" || {
        echo "${RED} - softap smali edit failed${RESET}"
        return 1
    }

    java -jar "$APKTOOL_JAR" b "$SMALI_OUT" -o "$SOFTAP_DIR/patched/service-wifi.jar" >/dev/null 2>&1 || {
        echo "${RED} - apktool build failed for service-wifi.jar${RESET}"
        return 1
    }
    return 0
}

# ---------------------------------------------------------------
# Extract the raw ext4 region from a payload with an existing AVB footer
# ---------------------------------------------------------------
HotspotFix_STRIP_AVB_FOOTER() {
    if [ "$#" -ne 2 ]; then
        echo "Usage: ${FUNCNAME[0]} <APEX_PAYLOAD_IMG> <OUTPUT_RAW_IMG>"
        return 1
    fi
    local SRC="$1"
    local OUT="$2"
    local FS_BYTES
    FS_BYTES=$("${AVBTOOL_BIN:-$PWD/bin/avb/avbtool}" info_image --image "$SRC" 2>/dev/null | awk '/Original image size:/ {print $4}')
    if [ -z "$FS_BYTES" ]; then
        echo "${RED} - failed to read the ext4 size from payload${RESET}"
        return 1
    fi
    dd if="$SRC" of="$OUT" bs="$FS_BYTES" count=1 status=none
    return 0
}

# ---------------------------------------------------------------
# Rebuild the dm-verity hashtree + vbmeta of the patched payload
# ---------------------------------------------------------------
HotspotFix_SIGN_PAYLOAD() {
    if [ "$#" -ne 2 ]; then
        echo "Usage: ${FUNCNAME[0]} <RAW_FS_IMG> <NEW_PAYLOAD_IMG>"
        return 1
    fi
    local RAW="$1"
    local OUT="$2"
    mkdir -p "$(dirname "$OUT")"

    local FS_BYTES
    FS_BYTES=$(stat -c%s "$RAW")

    local SALT
    SALT=$("${AVBTOOL_BIN:-$PWD/bin/avb/avbtool}" info_image --image "$APEX_WIFI_PREVIOUS_PAYLOAD" 2>/dev/null | awk '/Salt:/ {print $2}')
    if [ -z "$SALT" ]; then
        SALT="2be4f352b93bda691f7e4a725dd39e328148bd3ce46838ad5e0e81db16eb56fa"
    fi

    # avbtool appends the hashtree + vbmeta and pads up to partition_size; a
    # ~100 KiB hashtree needs a little headroom over the raw ext4 size.
    local PART_SIZE=$((FS_BYTES + FS_BYTES / 64 + 262144))
    PART_SIZE=$(((PART_SIZE + 4095) / 4096 * 4096))

    "${AVBTOOL_BIN:-$PWD/bin/avb/avbtool}" add_hashtree_footer \
        --image "$RAW" \
        --partition_size "$PART_SIZE" \
        --partition_name "" \
        --hash_algorithm sha256 \
        --salt "$SALT" \
        --key "$APEX_WIFI_FIX_KEY" \
        --algorithm SHA256_RSA4096 \
        --prop apex.key:com.android.wifi \
        --do_not_generate_fec || {
        echo "${RED} - avbtool add_hashtree_footer failed${RESET}"
        return 1
    }
    mv -f "$RAW" "$OUT"
    return 0
}

# ---------------------------------------------------------------
# Extract the new payload root digest
# ---------------------------------------------------------------
HotspotFix_GET_ROOT_DIGEST() {
    if [ "$#" -ne 1 ]; then
        echo "Usage: ${FUNCNAME[0]} <APEX_PAYLOAD_IMG>"
        return 1
    fi
    "${AVBTOOL_BIN:-$PWD/bin/avb/avbtool}" info_image --image "$1" 2>/dev/null | awk '/Root Digest:/ {print $3}'
}

# ---------------------------------------------------------------
# Locate the Android SDK's zipalign (preferred) for APEX page alignment
# ---------------------------------------------------------------
HotspotFix_FIND_ZIPALIGN() {
    if [ -n "$ZIPALIGN" ] && [ -x "$ZIPALIGN" ]; then
        echo "$ZIPALIGN"
        return 0
    fi
    if command -v zipalign >/dev/null 2>&1; then
        command -v zipalign
        return 0
    fi
    local root cand roots
    roots="$ANDROID_HOME $ANDROID_SDK_ROOT $HOME/Android/Sdk $HOME/android-sdk ${ANDROID_HOME:-/nonexistent}"
    for root in $roots; do
        [ -d "$root/build-tools" ] || continue
        cand=$(ls -1 "$root"/build-tools/*/zipalign 2>/dev/null | sort -V | tail -1)
        if [ -n "$cand" ]; then
            echo "$cand"
            return 0
        fi
    done
    return 1
}

# ---------------------------------------------------------------
# Locate the Android SDK's apksigner
# ---------------------------------------------------------------
HotspotFix_FIND_APKSIGNER() {
    if [ -n "$APKSIGNER" ] && [ -x "$APKSIGNER" ]; then
        echo "$APKSIGNER"
        return 0
    fi
    if command -v apksigner >/dev/null 2>&1; then
        command -v apksigner
        return 0
    fi
    local root cand roots
    roots="$ANDROID_HOME $ANDROID_SDK_ROOT $HOME/Android/Sdk $HOME/android-sdk"
    for root in $roots; do
        [ -d "$root/build-tools" ] || continue
        cand=$(ls -1 "$root"/build-tools/*/apksigner 2>/dev/null | sort -V | tail -1)
        if [ -n "$cand" ]; then
            echo "$cand"
            return 0
        fi
    done
    return 1
}

# ---------------------------------------------------------------
# Rebuild the APEX zip with a valid APK signature and page alignment
# ---------------------------------------------------------------
# The inner APEX is a signed zip: system_server's PackageParser verifies
# its APK signature. Re-zipping drops the v2/v3 signing block and breaks
# the v1 digests, so the package is rejected and system_server reboots to
# recovery (recoveryDecompressedApex). zipalign also strips the signing
# block, so the order must be: rebuild (no directory entries) -> zipalign
# -> apksigner with --alignment-preserved, which keeps the 4096-byte
# apex_payload.img offset dm-verity needs.
HotspotFix_REPACK_SIGN_APEX() {
    if [ "$#" -ne 2 ]; then
        echo "Usage: ${FUNCNAME[0]} <STAGING_DIR> <OUT_APEX>"
        return 1
    fi
    local STAGE="$1"
    local OUT="$2"

    local ZIPALIGN_BIN APKSIGNER_BIN KEY_DIR
    ZIPALIGN_BIN=$(HotspotFix_FIND_ZIPALIGN) || {
        echo "${RED} - zipalign not found (needed to page-align the APEX)${RESET}"
        return 1
    }
    APKSIGNER_BIN=$(HotspotFix_FIND_APKSIGNER) || {
        echo "${RED} - apksigner not found (needed to sign the APEX)${RESET}"
        return 1
    }
    KEY_DIR="$(GET_ACTIVE_KEY_FILES)"
    if [ -z "$KEY_DIR" ] || [ ! -f "$KEY_DIR/platform.pk8" ]; then
        echo "${RED} - no platform signing key available for the APEX${RESET}"
        return 1
    fi

    local FILES
    FILES=$(cd "$STAGE" && find . -type f ! -path './META-INF/*' -printf '%P\n' | sort)
    if ! printf '%s\n' "$FILES" | grep -qx 'apex_payload.img'; then
        echo "${RED} - apex_payload.img missing from staging dir${RESET}"
        return 1
    fi
    # payload/pubkey first (matches AOSP's APEX layout)
    FILES=$(printf '%s\n' "$FILES" | grep -vx 'apex_payload.img' | grep -vx 'apex_pubkey' | tr '\n' ' ')
    FILES="apex_payload.img apex_pubkey $FILES"

    rm -f "$OUT" "$OUT.zip" "$OUT.aligned"
    ( cd "$STAGE" && zip -q -0 -X "$OUT.zip" $FILES ) || {
        echo "${RED} - failed to rebuild the APEX zip${RESET}"
        return 1
    }
    mv -f "$OUT.zip" "$OUT"
    "$ZIPALIGN_BIN" -f 4096 "$OUT" "$OUT.aligned" || {
        echo "${RED} - zipalign failed${RESET}"
        return 1
    }
    "$APKSIGNER_BIN" sign \
        --key "$KEY_DIR/platform.pk8" --cert "$KEY_DIR/platform.x509.pem" \
        --alignment-preserved true \
        --out "$OUT" "$OUT.aligned" || {
        echo "${RED} - apksigner failed${RESET}"
        return 1
    }
    rm -f "$OUT.aligned"
    return 0
}

# ---------------------------------------------------------------
# Replace the service-wifi.jar inside the ext4 payload
# ---------------------------------------------------------------
HotspotFix_PATCH_PAYLOAD() {
    if [ "$#" -ne 2 ]; then
        echo "Usage: ${FUNCNAME[0]} <PAYLOAD_IMG> <PATCHED_JAR>"
        return 1
    fi
    local PAYLOAD_IMG="$1"
    local PATCHED_JAR="$2"

    debugfs -w -R "rm /javalib/service-wifi.jar" "$PAYLOAD_IMG" >/dev/null 2>&1
    debugfs -w -R "write $PATCHED_JAR /javalib/service-wifi.jar" "$PAYLOAD_IMG" >/dev/null 2>&1

    # debugfs rm+write allocates a new inode, so the stock ownership and the
    # security.selinux xattr are lost. Without the label system_server and
    # odrefresh cannot open the jar (Permission denied), the class loader ends
    # up empty and WifiService fails to load.
    debugfs -w -R "sif /javalib/service-wifi.jar uid 1000" "$PAYLOAD_IMG" >/dev/null 2>&1
    debugfs -w -R "sif /javalib/service-wifi.jar gid 1000" "$PAYLOAD_IMG" >/dev/null 2>&1

    local LABEL_FILE="$(dirname "$PATCHED_JAR")/selinux.label"
    printf 'u:object_r:system_file:s0\0' > "$LABEL_FILE"
    debugfs -w -R "ea_set -f $LABEL_FILE /javalib/service-wifi.jar security.selinux" \
        "$PAYLOAD_IMG" >/dev/null 2>&1

    local OWNER LABEL
    OWNER=$(debugfs -R "stat /javalib/service-wifi.jar" "$PAYLOAD_IMG" 2>/dev/null \
        | awk '/User:/ {print $2"/"$4}')
    LABEL=$(debugfs -R "ea_list /javalib/service-wifi.jar" "$PAYLOAD_IMG" 2>/dev/null \
        | grep -a 'security.selinux')
    case "$LABEL" in
        *system_file*) LABEL="system_file" ;;
        *) LABEL="" ;;
    esac
    if [ "$OWNER" != "1000/1000" ] || [ "$LABEL" != "system_file" ]; then
        echo "${RED} - service-wifi.jar metadata wrong (owner=$OWNER label=$LABEL)${RESET}"
        return 1
    fi
    echo "${GREEN} - payload patched${RESET}"
    return 0
}

ADD_SOFTAP_FIX() {
    echo ""
    if [ "$#" -ne 1 ]; then
        echo "Usage: ${FUNCNAME[0]} <EXTRACTED_FIRM_DIR>"
        return 1
    fi

    local EXTRACTED_FIRM_DIR="$1"

    case "$STOCK_DEVICE" in
        SM-A325F|SM-A325M|SM-M325F) ;;
        *)
            echo "${YELLOW}Hotspot fix skipped (not needed for $STOCK_DEVICE)${RESET}"
            return 0
            ;;
    esac

    echo "${YELLOW}Patching Hotspot...${RESET}"

    local CAPEX=""
    local cand
    for cand in \
        "$EXTRACTED_FIRM_DIR/system/system/apex/com.android.wifi.capex" \
        "$EXTRACTED_FIRM_DIR/system/apex/com.android.wifi.capex" \
        "$EXTRACTED_FIRM_DIR/system/system/apex/com.android.wifi.apex" \
        "$EXTRACTED_FIRM_DIR/system/apex/com.android.wifi.apex"; do
        if [ -f "$cand" ]; then
            CAPEX="$cand"
            break
        fi
    done
    if [ -z "$CAPEX" ]; then
        echo "${RED}Warning: com.android.wifi apex not found, skipping SoftAp fix${RESET}"
        return 0
    fi

    local SOFTAP_DIR="$WORK_DIR/softapfix"
    rm -rf "$SOFTAP_DIR"
    mkdir -p "$SOFTAP_DIR/pit" "$SOFTAP_DIR/patched" "$SOFTAP_DIR/apexzip"

    {
        cp -f "$CAPEX" "$SOFTAP_DIR/pit/original.capex"
        unzip -qq "$SOFTAP_DIR/pit/original.capex" -d "$SOFTAP_DIR/pit" &&
        unzip -qq "$SOFTAP_DIR/pit/original_apex" -d "$SOFTAP_DIR/apexzip"
    } >/dev/null 2>&1 || {
        echo "${RED} - failed to unzip capex${RESET}"
        return 1
    }

    local PAYLOAD="$SOFTAP_DIR/apexzip/apex_payload.img"
    if [ ! -f "$PAYLOAD" ]; then
        echo "${RED} - apex_payload.img missing${RESET}"
        return 1
    fi

    export APEX_WIFI_PREVIOUS_PAYLOAD="$PAYLOAD"

    debugfs -R "dump /javalib/service-wifi.jar $SOFTAP_DIR/patched/service-wifi.jar" \
        "$PAYLOAD" >/dev/null 2>&1

    HotspotFix_BUILD_PATCHED_JAR "$SOFTAP_DIR" "$APKTOOL" "$SOFTAP_DIR/patched/service-wifi.jar" || {
        echo "${RED} - SoftAp teardown patch aborted${RESET}"
        return 1
    }

    HotspotFix_PATCH_PAYLOAD "$PAYLOAD" "$SOFTAP_DIR/patched/service-wifi.jar" || {
        echo "${RED} - patching service-wifi.jar into payload failed${RESET}"
        return 1
    }

    HotspotFix_STRIP_AVB_FOOTER "$PAYLOAD" "$SOFTAP_DIR/patched/payload_raw.img" || {
        echo "${RED} - failed to strip avb footer${RESET}"
        return 1
    }

    HotspotFix_SIGN_PAYLOAD "$SOFTAP_DIR/patched/payload_raw.img" "$SOFTAP_DIR/patched/payload_rebuilt.img" || {
        echo "${RED} - failed to re-sign payload${RESET}"
        return 1
    }

    cp -f "$SOFTAP_DIR/patched/payload_rebuilt.img" "$PAYLOAD"
    cp -f "$APEX_WIFI_FIX_PUB" "$SOFTAP_DIR/apexzip/apex_pubkey"
    cp -f "$APEX_WIFI_FIX_PUB"  "$SOFTAP_DIR/pit/apex_pubkey"

    local ROOT_DIGEST
    ROOT_DIGEST=$(HotspotFix_GET_ROOT_DIGEST "$PAYLOAD") || ROOT_DIGEST=""
    if [ -z "$ROOT_DIGEST" ]; then
        echo "${RED} - failed to compute the new root digest${RESET}"
        return 1
    fi

    python3 scripts/utils/softap_fix.py --digest \
        "$SOFTAP_DIR/pit/apex_manifest.pb" "$ROOT_DIGEST" || {
        echo "${RED} - failed to update the apex manifest digest${RESET}"
        return 1
    }

    echo "${YELLOW} - Rebuilding and signing the inner APEX${RESET}"
    HotspotFix_REPACK_SIGN_APEX "$SOFTAP_DIR/apexzip" "$SOFTAP_DIR/pit/original_apex" || {
        echo "${RED} - APEX repack/sign failed${RESET}"
        return 1
    }

    ( cd "$SOFTAP_DIR/pit" && rm -f "$CAPEX" "$CAPEX.zip" \
        && zip -q -r -X "$CAPEX.zip" AndroidManifest.xml \
            apex_build_info.pb apex_manifest.pb apex_pubkey \
            original_apex META-INF \
        && mv "$CAPEX.zip" "$CAPEX" )

    echo "${GREEN} - Hotspot fix baked into $CAPEX${RESET}"
    return 0
}

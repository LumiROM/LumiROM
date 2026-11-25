#!/bin/bash
#
# LumiROM features: framework.jar helpers (decompile, patches, VNDK).
# Part of scripts/features/LumiROM.sh (sourced by it); not meant to run alone.

rom_decompile() {
    echo ""
    if [ "$#" -ne 3 ]; then
        echo "Usage: rom_decompile <APKTOOL_JAR_DIR> <FILE> <DECOMPILE_DIR>"
        return 1
    fi

    local APKTOOL="$1"
    local FILE="$2"
    local DECOMPILE_DIR="$3"
    local BASENAME="$(basename "${FILE%.*}")"
    local OUT="$DECOMPILE_DIR/$BASENAME"

    echo "${YELLOW}Decompiling:${RESET} $FILE"
	rm -rf "$OUT"
    java -jar "$APKTOOL" d -f "$FILE" -o "$OUT"
}

rom_recompile() {
    echo ""
	if [ "$#" -ne 4 ]; then
        echo "Usage: ${FUNCNAME[0]} <APKTOOL_JAR_DIR> <FRAMEWORK_DIR> <DECOMPILED_DIR> <RECOMPILE_DIR>"
        return 1
    fi

	local APKTOOL="$1"
	local DECOMPILED_DIR="$2"
    local FRAMEWORK_DIR="$3"
    local RECOMPILE_DIR="$4"

    local org_file_name
    org_file_name=$(awk '/^apkFileName:/ {print $2}' "$DECOMPILED_DIR/apktool.yml")
    local name="${org_file_name%.*}"
    local ext="${org_file_name##*.}"
    local built_file="$WORK_DIR/${name}_unsigned.$ext"
    local final_file="$WORK_DIR/$org_file_name"

    echo "${YELLOW}Recompiling:${RESET} $DECOMPILED_DIR"
    java -jar "$APKTOOL" b "$DECOMPILED_DIR" --copy-original -p "$FRAMEWORK_DIR" -o "$built_file"

    # Zipalign
	echo ""
	if [[ "$ext" == "jar" ]]; then
	    echo "Zipaligning: $built_file to $final_file"
        zipalign -v 4 "$built_file" "$final_file" >/dev/null 2>&1
		rm -rf "$built_file" "$DECOMPILED_DIR"
    fi
}

rom_fix_framework_mime() {
    echo ""
    if [ "$#" -ne 2 ]; then
        echo "Usage: ${FUNCNAME[0]} <STOCK_FRAMEWORK_JAR> <BUILT_FRAMEWORK_JAR>"
        echo "  Restores the raw res/*.mime.types resources that apktool drops"
        echo "  when recompiling framework.jar (otherwise MimeMap/media provider crash)."
        return 1
    fi

    local STOCK="$1"
    local BUILT="$2"

    if [ ! -f "$STOCK" ] || [ ! -f "$BUILT" ]; then
        echo "${RED}rom_fix_framework_mime: missing jar ($STOCK / $BUILT)${RESET}"
        return 1
    fi

    if unzip -l "$BUILT" | grep -q "res/debian.mime.types"; then
        echo "${GREEN} - framework.jar already keeps res/*.mime.types${RESET}"
        return 0
    fi

    local BUILT_ABS
    BUILT_ABS="$(realpath "$BUILT")"

    local TMP
    TMP="$(mktemp -d)"
    if unzip -o "$STOCK" "res/*.mime.types" -d "$TMP" >/dev/null 2>&1 && [ -d "$TMP/res" ]; then
        ( cd "$TMP" && zip -q "$BUILT_ABS" res/*.mime.types )
        echo "${GREEN} - Restored res/*.mime.types in $(basename "$BUILT")${RESET}"
        unzip -l "$BUILT_ABS" | grep -E "res/.*mime.types" | awk '{print "   - " $4}'
    else
        echo "${YELLOW} - [!] res/*.mime.types not found in stock framework.jar${RESET}"
    fi
    rm -rf "$TMP"
}

rom_hex_patch() {
    echo ""
	if [ "$#" -ne 3 ]; then
        echo "Usage: ${FUNCNAME[0]} <FILE> <TARGET_VALUE> <REPLACE_VALUE>"
        return 1
    fi

    local FILE="$1"
    local FROM="$(echo "$2" | tr '[:upper:]' '[:lower:]')"
    local TO="$(echo "$3" | tr '[:upper:]' '[:lower:]')"

    [ ! -f "$FILE" ] && { echo "File not found: $FILE"; return 1; }

    xxd -p -c 0 "$FILE" | grep -q "$FROM" || {
        echo "- ${RED}Pattern not found${RESET}: $FROM"
        return 1
    }

    echo "${YELLOW}Patching:${RESET} $FILE"
    echo "- From $FROM to $TO"
    [ -f "$FILE.bak" ] || cp "$FILE" "$FILE.bak"

    xxd -p -c 0 "$FILE" | sed "s/$FROM/$TO/" | xxd -r -p > "$FILE.tmp" &&
    mv "$FILE.tmp" "$FILE"

    xxd -p -c 0 "$FILE" | grep -q "$TO" && {
        echo "- Patch success"
        rm -rf "$FILE.bak"        
        return 0
    }

    echo "${RED}Patch failed, restoring backup${RESET}"
    mv "$FILE.bak" "$FILE"
    return 1
}

rom_patch_bt_lib() {
    echo ""
	if [ "$#" -ne 2 ]; then
        echo "Usage: ${FUNCNAME[0]} <EXTRACTED_FIRM_DIRECTORY> <WORK_DIR>"
        return 1
    fi

	local EXTRACTED_FIRM_DIR="$1"
	local WORK_DIR="$2"
	local BT_LIB_FILE="$WORK_DIR/libbluetooth_jni.so"

    echo "${YELLOW}Patching Bluetooth library...${RESET}"
    # Get libbluetooth_jni.so
    unzip "$EXTRACTED_FIRM_DIR/system/system/apex/com.android.bt.apex" "apex_payload.img" -d "$WORK_DIR"
	debugfs -R "dump /lib64/libbluetooth_jni.so $WORK_DIR/libbluetooth_jni.so" "$WORK_DIR/apex_payload.img"  >/dev/null 2>&1
	rm -rf "$WORK_DIR/apex_payload.img"

    # local associative array (function-scoped)
    declare -A hex=(
        [136]=00122a0140395f01086b00020054 [1136]=00122a0140395f01086bde030014
        [135]=480500352800805228 [1135]=530100142800805228
        [134]=6804003528008052 [1134]=2b00001428008052
        [133]=6804003528008052 [1133]=2a00001428008052
        [132]=........f9031f2af3031f2a41 [1132]=1f2003d5f9031f2af3031f2a48
        [131]=........f9031f2af3031f2a41 [1131]=1f2003d5f9031f2af3031f2a48
        [130]=........f3031f2af4031f2a3e [1130]=1f2003d5f3031f2af4031f2a3e
        [129]=........f4031f2af3031f2ae8030032 [1129]=1f2003d5f4031f2af3031f2ae8031f2a
        [128]=88000034e8030032 [1128]=1f2003d5e8031f2a
        [127]=88000034e8030032 [1127]=1f2003d5e8031f2a
        [126]=88000034e8030032 [1126]=1f2003d5e8031f2a
        [234]=4e7e4448bb [1234]=4e7e4437e0
        [233]=4e7e4440bb [1233]=4e7e4432e0
        [231]=20b14ff000084ff000095ae0 [1231]=00bf4ff000084ff0000964e0
        [230]=18b14ff0000b00254a [1230]=00204ff0000b002554
        [229]=..b100250120 [1229]=00bf00250020
        [228]=..b101200028 [1228]=00bf00200028
        [227]=09b1012032e0 [1227]=00bf002032e0
        [226]=08b1012031e0 [1226]=00bf002031e0
        [225]=087850bbb548 [1225]=08785ae1b548
        [224]=007840bb6a48 [1224]=0078c4e06a48
        [330]=88000054691180522925c81a69000037 [1330]=1f2003d5691180522925c81a1f2003d5
        [329]=88000054691180522925c81a69000037 [1329]=1f2003d5691180522925c81a1f2003d5
        [328]=7f1d0071e91700f9e83c0054 [1328]=7f1d0071e91700f9e7010014
        [429]=....0034f3031f2af4031f2a....0014 [1429]=1f2003d5f3031f2af4031f2a47000014
        [531]=10b1002500244ce0 [1531]=00bf0025002456e0
        [530]=18b100244ff0000b4d [1530]=002000244ff0000b57
        [529]=44387810b1002400254a [1529]=44387800200024002556
        [629]=90387810b1002400254a [1629]=90387800200024002558
    )

    local HEXDATA
    HEXDATA="$(xxd -p -c 0 "$BT_LIB_FILE")" || return 1

    local PATCHED=0

    for idx in "${!hex[@]}"; do
        (( idx >= 1000 )) && continue

        local from="${hex[$idx]}"
        local to="${hex[$((idx + 1000))]}"

        [ -z "$to" ] && continue

        # convert wildcard .... → regex
        local from_regex="${from//./[0-9a-f]}"

        if echo "$HEXDATA" | grep -qiE "$from_regex"; then
            echo "- Found Bluetooth patch pattern [$idx]"
            rom_hex_patch "$BT_LIB_FILE" "$from" "$to" || return 1
            PATCHED=1
			cp -rfa "$WORK_DIR/libbluetooth_jni.so" "$EXTRACTED_FIRM_DIR/system/system/lib64/"
            break
        fi
    done

    if [ "$PATCHED" -eq 0 ]; then
        echo "${RED}- No known Bluetooth patch pattern matched.${RESET}"
		rm -rf "$BT_LIB_FILE"
        return 1
    fi

    return 0
}

rom_fix_vndk() {
    echo "${YELLOW}- Checking ${RESET}$STOCK_DEVICE ${YELLOW}and${RESET} $TARGET_DEVICE ${YELLOW}vndk version.${RESET}"
    if [ -f "$TARGET_ROM_SYSTEM_EXT_DIR/apex/com.android.vndk.v${STOCK_VNDK_VERSION}.apex" ]; then
        echo "${GREEN}- VNDK matched.${RESET}"
    else
        echo "${RED}- VNDK mismatch or missing.${RESET}"
        echo "${YELLOW}- Extracting VNDK from $STOCK_DEVICE${RESET}"
        rm -f "$TARGET_ROM_SYSTEM_EXT_DIR/apex/com.android.vndk"*.apex
        mkdir -p "$TARGET_ROM_SYSTEM_EXT_DIR/apex/"
        cp -rfa "$VNDKS_COLLECTION/vndk31-a16/com.android.vndk.v${STOCK_VNDK_VERSION}.apex" "$TARGET_ROM_SYSTEM_EXT_DIR/apex/"
        sed -i "/<vendor-ndk>/,/<\/vendor-ndk>/ s|<version>[0-9]\+</version>|<version>${STOCK_VNDK_VERSION}</version>|" "$TARGET_ROM_SYSTEM_EXT_DIR/etc/vintf/manifest.xml"
    fi
}

rom_fix_system_ext() {
    if [ "$#" -ne 1 ]; then
        echo "Usage: ${FUNCNAME[0]} <EXTRACTED_FIRM_DIR>"
        return 1
    fi

    local EXTRACTED_FIRM_DIR="$1"

	if [[ ! -d "$EXTRACTED_FIRM_DIR/system_ext" ]]; then
        if [[ -d "$EXTRACTED_FIRM_DIR/system/system_ext" ]]; then
            export TARGET_ROM_SYSTEM_EXT_DIR="$EXTRACTED_FIRM_DIR/system/system_ext"
        else
            export TARGET_ROM_SYSTEM_EXT_DIR="$EXTRACTED_FIRM_DIR/system/system/system_ext"
        fi
	fi

    # Make system_ext merged with system
    if [[ "$STOCK_HAS_SEPARATE_SYSTEM_EXT" == FALSE && -d "$EXTRACTED_FIRM_DIR/system_ext" ]]; then
	    echo "${YELLOW}Fixing system_ext according to ${RESET}$STOCK_DEVICE"
        echo "${YELLOW}Copying system_ext content into system root${RESET}"
		rm -rf "$EXTRACTED_FIRM_DIR/system/system_ext"
        cp -a --preserve=all "$EXTRACTED_FIRM_DIR/system_ext" "$EXTRACTED_FIRM_DIR/system"

        echo "${YELLOW}Cleaning and merging system_ext file contexts and configs${RESET}"
        # File paths
        SYSTEM_EXT_CONFIG_FILE="$EXTRACTED_FIRM_DIR/config/system_ext_fs_config"
        SYSTEM_EXT_CONTEXTS_FILE="$EXTRACTED_FIRM_DIR/config/system_ext_file_contexts"

        SYSTEM_CONFIG_FILE="$EXTRACTED_FIRM_DIR/config/system_fs_config"
        SYSTEM_CONTEXTS_FILE="$EXTRACTED_FIRM_DIR/config/system_file_contexts"

        SYSTEM_EXT_TEMP_CONFIG="${SYSTEM_EXT_CONFIG_FILE}.tmp"
        SYSTEM_EXT_TEMP_CONTEXTS="${SYSTEM_EXT_CONTEXTS_FILE}.tmp"

        # Clean system_ext contexts
        grep -v '^/ u:object_r:system_file:s0$' "$SYSTEM_EXT_CONTEXTS_FILE" \
        | grep -v '^/system_ext u:object_r:system_file:s0$' \
        | grep -v '^/system_ext(.*)? u:object_r:system_file:s0$' \
        | grep -v '^/system_ext/ u:object_r:system_file:s0$' \
        > "$SYSTEM_EXT_TEMP_CONTEXTS" && mv "$SYSTEM_EXT_TEMP_CONTEXTS" "$SYSTEM_EXT_CONTEXTS_FILE"

        # Clean system_ext config
        grep -v '^/ 0 0 0755$' "$SYSTEM_EXT_CONFIG_FILE" \
        | grep -v '^system_ext/ 0 0 0755$' \
        | grep -v '^system_ext/lost+found 0 0 0755$' \
        > "$SYSTEM_EXT_TEMP_CONFIG" && mv "$SYSTEM_EXT_TEMP_CONFIG" "$SYSTEM_EXT_CONFIG_FILE"

        # Fix system_ext config
        awk '{print "system/" $0}' "$SYSTEM_EXT_CONFIG_FILE" \
        > "$SYSTEM_EXT_TEMP_CONFIG" && mv "$SYSTEM_EXT_TEMP_CONFIG" "$SYSTEM_EXT_CONFIG_FILE"

        # Fix system_ext contexts
        awk '{print "/system" $0}' "$SYSTEM_EXT_CONTEXTS_FILE" \
        > "$SYSTEM_EXT_TEMP_CONTEXTS" && mv "$SYSTEM_EXT_TEMP_CONTEXTS" "$SYSTEM_EXT_CONTEXTS_FILE"

        # Append cleaned system_ext config into system config
        cat "$SYSTEM_EXT_CONFIG_FILE" >> "$SYSTEM_CONFIG_FILE"

        # Append cleaned system_ext contexts into system contexts
        cat "$SYSTEM_EXT_CONTEXTS_FILE" >> "$SYSTEM_CONTEXTS_FILE"

		export TARGET_ROM_SYSTEM_EXT_DIR="$EXTRACTED_FIRM_DIR/system/system_ext"

	    rm -rf "$EXTRACTED_FIRM_DIR/system_ext"
		rm -rf "$EXTRACTED_FIRM_DIR/config/system_ext_fs_config"
		rm -rf "$EXTRACTED_FIRM_DIR/config/system_ext_file_contexts"
    elif [[ -d "$EXTRACTED_FIRM_DIR/system_ext" ]]; then
        export TARGET_ROM_SYSTEM_EXT_DIR="$EXTRACTED_FIRM_DIR/system_ext"
    fi
}

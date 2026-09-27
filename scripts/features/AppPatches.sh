#!/bin/bash

export LC_ALL=C

source scripts/utils/bash_colors.sh
source scripts/utils/platform_key.sh


PATCH_SECSETTINGS() {
    echo ""
    if [ "$#" -ne 1 ]; then
        echo "Usage: ${FUNCNAME[0]} <DECOMPILED_SECSETTINGS_DIR>"
        echo "  Applies the SecSettings patches (Cloudy entry + ROM logo)."
        return 1
    fi

    local SECSETTINGS_DIR="$1"

    if [ ! -d "$SECSETTINGS_DIR" ]; then
        echo "${RED}SecSettings decompiled directory not found: $SECSETTINGS_DIR${RESET}"
        return 1
    fi

    local PATCHES=(
        "0002-Open-Cloudy-from-Software-update-in-settings.patch"
        "0003-Add-LumiROM-Logo.patch"
    )

    for PATCH in "${PATCHES[@]}"; do
        local PATCH_FILE="$(pwd)/scripts/patches/$PATCH"
        if [ ! -f "$PATCH_FILE" ]; then
            echo "${RED}Patch not found: $PATCH_FILE${RESET}"
            return 1
        fi
        echo "${YELLOW}Applying SecSettings patch: $PATCH${RESET}"
        if ! patch -p1 -d "$SECSETTINGS_DIR" < "$PATCH_FILE" >/dev/null 2>&1; then
            echo "${RED}Failed to apply $PATCH${RESET}"
            return 1
        fi
    done

    # Copy the ROM logo into the decompiled SecSettings tree.
    local LOGO_SRC="$(pwd)/LumiROM/Mods/SecSettings/res/drawable/logo.png"
    if [ -f "$LOGO_SRC" ]; then
        mkdir -p "$SECSETTINGS_DIR/res/drawable"
        cp -f "$LOGO_SRC" "$SECSETTINGS_DIR/res/drawable/logo.png"
        echo "${GREEN}ROM logo copied into SecSettings.${RESET}"
    else
        echo "${RED}ROM logo not found: $LOGO_SRC${RESET}"
        return 1
    fi

    echo "${GREEN}SecSettings patched.${RESET}"
}


REBUILD_AND_SIGN_APK() {
    echo ""
    if [ "$#" -ne 4 ]; then
        echo "Usage: ${FUNCNAME[0]} <APKTOOL> <DECOMPILED_DIR> <FRAMEWORK_DIR> <OUT_APK>"
        echo "  Recompiles a decompiled APK, zipaligns and re-signs it with"
        echo "  the active platform key."
        return 1
    fi

    local APKTOOL="$1"
    local DECOMPILED_DIR="$2"
    local FRAMEWORK_DIR="$3"
    local OUT_APK="$4"

    if [ ! -d "$DECOMPILED_DIR" ]; then
        echo "${RED}Decompiled directory not found: $DECOMPILED_DIR${RESET}"
        return 1
    fi

    echo "${YELLOW}Recompiling:${RESET} $DECOMPILED_DIR"
    java -jar "$APKTOOL" b "$DECOMPILED_DIR" --copy-original -p "$FRAMEWORK_DIR" -o "$OUT_APK" || {
        echo "${RED}Failed to recompile $DECOMPILED_DIR${RESET}"
        return 1
    }

    local ALIGNED="${OUT_APK%.apk}.aligned.apk"
    zipalign -f 4 "$OUT_APK" "$ALIGNED" || return 1
    rm -f "$OUT_APK"

    local KEY_DIR
    KEY_DIR="$(GET_ACTIVE_KEY_FILES)"
    echo "${YELLOW}Re-signing with platform key from $KEY_DIR${RESET}"
    apksigner sign --key "$KEY_DIR/platform.pk8" --cert "$KEY_DIR/platform.x509.pem" \
        --out "$OUT_APK" "$ALIGNED" || return 1
    rm -f "$ALIGNED"

    echo "${GREEN}Rebuilt and signed: $OUT_APK${RESET}"
}


PATCH_SETUPWIZARD() {
    echo ""
    if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
        echo "Usage: ${FUNCNAME[0]} <DECOMPILED_SETUPWIZARD_DIR> [LOGO_PNG]"
        echo "  Applies the SetupWizard patches (LumiROM disclaimer + navbar step)."
        return 1
    fi

    local SW_DIR="$1"
    local LOGO_SRC="${2:-$(pwd)/LumiROM/Mods/SecSettings/res/drawable/logo.png}"

    if [ ! -d "$SW_DIR" ]; then
        echo "${RED}SetupWizard decompiled directory not found: $SW_DIR${RESET}"
        return 1
    fi

    # Copy the banner logo into the decompiled tree (binary, not part of the patches).
    mkdir -p "$SW_DIR/res/drawable-xxhdpi"
    if [ -f "$LOGO_SRC" ]; then
        cp -f "$LOGO_SRC" "$SW_DIR/res/drawable-xxhdpi/lumirom_logo.png"
        echo "${GREEN}LumiROM banner logo copied into SetupWizard.${RESET}"
    else
        echo "${YELLOW}  [!] Logo not found: $LOGO_SRC${RESET}"
    fi

    local PATCHES=(
        "0004-Add-LumiROM-Disclaimer.patch"
        "0005-Add-LumiROM-Disclaimer-Strings.patch"
        "0006-SetupWizard-Steps.patch"
    )

    for PATCH in "${PATCHES[@]}"; do
        local PATCH_FILE="$(pwd)/scripts/patches/$PATCH"
        if [ ! -f "$PATCH_FILE" ]; then
            echo "${RED}Patch not found: $PATCH_FILE${RESET}"
            return 1
        fi
        echo "${YELLOW}Applying SetupWizard patch: $PATCH${RESET}"
        if ! patch -p1 -d "$SW_DIR" < "$PATCH_FILE" >/dev/null 2>&1; then
            echo "${RED}Failed to apply $PATCH${RESET}"
            return 1
        fi
    done

    echo "${GREEN}SetupWizard patched.${RESET}"
}


LUMISETTINGS_SEARCH_PATCH() {
    if [ "$#" -ne 2 ]; then
        echo "Usage: ${FUNCNAME[0]} <SECSETTINGS_DIR> <SECSETTINGSINTELLIGENCE_DIR>"
        return 1
    fi

    local SECSETTINGS_DIR="$1"
    local INTELLIGENCE_DIR="$2"

    echo "${YELLOW} - Registering LumiSettings in search${RESET}"

    # Allow extending the stock search indexable resources.
    local SIRM="$SECSETTINGS_DIR/smali_classes2/com/android/settingslib/search/SearchIndexableResourcesMobile.smali"
    if [ -f "$SIRM" ]; then
        sed -i 's#^\.class public final Lcom/android/settingslib/search/SearchIndexableResourcesMobile;#.class public Lcom/android/settingslib/search/SearchIndexableResourcesMobile;#' "$SIRM"
    else
        echo "${YELLOW}   [!] SearchIndexableResourcesMobile.smali not found, search may not work${RESET}"
    fi

    # Point the search provider to the LumiSettings resources.
    local LAMBDA="$SECSETTINGS_DIR/smali_classes2/com/android/settings/search/SearchFeatureProviderImpl\$\$ExternalSyntheticLambda0.smali"
    if [ -f "$LAMBDA" ]; then
        sed -i 's#Lcom/android/settingslib/search/SearchIndexableResourcesMobile;#Lio/buizel/lumi/search/LumiSearchIndexableResources;#g' "$LAMBDA"
        sed -i 's#Lcom/android/settingslib/search/SearchIndexableResourcesBase;#Lio/buizel/lumi/search/LumiSearchIndexableResources;#g' "$LAMBDA"
    else
        echo "${YELLOW}   [!] SearchFeatureProviderImpl lambda not found, search may not work${RESET}"
    fi

    # Add the LumiSettings top level key to the search collector.
    local TLC="$INTELLIGENCE_DIR/smali_classes2/com/samsung/android/settings/intelligence/search/categorizing/TopLevelKeysCollector.smali"
    if [ -f "$TLC" ] && ! grep -q "top_level_lumi" "$TLC"; then
        sed -i 's#\.locals 36#.locals 37#' "$TLC"
        sed -i 's#filled-new-array/range {v1 .. v35}, \[Ljava/lang/String;#const-string v36, "top_level_lumi"\n\n    filled-new-array/range {v1 .. v36}, [Ljava/lang/String;#' "$TLC"
    else
        echo "${YELLOW}   [!] TopLevelKeysCollector.smali not patched, search may not work${RESET}"
    fi
}


ADD_LUMISETTINGS() {
    echo ""
    if [ "$#" -ne 4 ]; then
        echo "Usage: ${FUNCNAME[0]} <SECSETTINGS_DIR> <FRAMEWORK_DIR> <SERVICES_DIR> <SECSETTINGSINTELLIGENCE_DIR>"
        echo "  Applies the LumiSettings integration (UN1CA-based, rebranded)."
        return 1
    fi

    local SECSETTINGS_DIR="$1"
    local FRAMEWORK_DIR="$2"
    local SERVICES_DIR="$3"
    local INTELLIGENCE_DIR="$4"
    local MOD_DIR="$(pwd)/LumiROM/Mods/LumiSettings"

    local DIR
    for DIR in "$SECSETTINGS_DIR" "$FRAMEWORK_DIR" "$SERVICES_DIR" "$INTELLIGENCE_DIR"; do
        if [ ! -d "$DIR" ]; then
            echo "${RED}LumiSettings: directory not found: $DIR${RESET}"
            return 1
        fi
    done

    echo "${BLUE}============ LumiSettings ============${RESET}"

    echo "${YELLOW} - Patching SecSettings${RESET}"
    while IFS= read -r f; do
        local REL="${f#"$MOD_DIR"/SecSettings/}"
        local TARGET="$SECSETTINGS_DIR/$REL"

        if [ ! -f "$TARGET" ] || [[ "$REL" != *".xml" ]]; then
            mkdir -p "$(dirname "$TARGET")"
            cp -a "$f" "$TARGET"
        elif [[ "$REL" == *"res/values"* ]]; then
            # Merge values literally (preserves \' escapes) before </resources>.
            local TMPC
            TMPC="$(mktemp)"
            sed -e "/?xml/d" -e "/<resources>/d" -e "/<\/resources>/d" "$f" > "$TMPC"
            awk -v extra="$TMPC" '
                BEGIN { while ((getline l < extra) > 0) buf = buf l "\n" }
                /<\/resources>/ && !ins { printf "%s", buf; ins=1 }
                { print }
            ' "$TARGET" > "$TARGET.lumi_tmp" && mv "$TARGET.lumi_tmp" "$TARGET"
            rm -f "$TMPC"
        else
            local PATCH_INST CONTENT
            PATCH_INST="$(head -n 1 "$f")"
            CONTENT="$(tail -n +2 "$f")"
            CONTENT="$(sed -e "s/\"/\\\\\"/g" -e "s/\\$/\\\\$/g" -e "s/ /\\\ /g" -e "s/\\\\n/\\\\\\\\\n/g" <<< "$CONTENT")"
            CONTENT="$(sed -E ':a;N;$!ba;s/\r{0,1}\n/\\n/g' <<< "$CONTENT")"
            eval "sed -i \"$PATCH_INST $CONTENT\" \"$TARGET\""
        fi
    done < <(find "$MOD_DIR/SecSettings" -type f)

    echo "${YELLOW} - Patching framework.jar${RESET}"
    local PATCH
    while IFS= read -r PATCH; do
        echo "   - $(basename "$PATCH")"
        if ! patch -p1 --no-backup-if-mismatch -d "$FRAMEWORK_DIR" < "$PATCH" >/dev/null 2>&1; then
            echo "${RED}LumiSettings: failed to apply $(basename "$PATCH")${RESET}"
            return 1
        fi
    done < <(find "$MOD_DIR/patches/framework.jar" -name '*.patch' | sort -n)
    # Overlay the trimmed FloatingFeatureHooks (launcher animation only).
    cp -rfa "$MOD_DIR/framework/." "$FRAMEWORK_DIR/"

    echo "${YELLOW} - Patching services.jar${RESET}"
    while IFS= read -r PATCH; do
        echo "   - $(basename "$PATCH")"
        if ! patch -p1 --no-backup-if-mismatch -d "$SERVICES_DIR" < "$PATCH" >/dev/null 2>&1; then
            echo "${RED}LumiSettings: failed to apply $(basename "$PATCH")${RESET}"
            return 1
        fi
    done < <(find "$MOD_DIR/patches/services.jar" -name '*.patch' | sort -n)

    LUMISETTINGS_SEARCH_PATCH "$SECSETTINGS_DIR" "$INTELLIGENCE_DIR"

    echo "${GREEN} - LumiSettings applied${RESET}"
}

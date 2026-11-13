#!/bin/bash

# Utilities for the LumiROM auto-mod system.
#
# A mod is a directory with a module.prop file and, optionally, a set of
# partition trees (system/, system_ext/, product/, vendor/, odm/) and a
# customize.sh script. Only directories with module.prop are auto-applied;
# feature-specific folders handled by other scripts are ignored.

MOD_PROP_GET() {
    local PROP_FILE="$1"
    local KEY="$2"

    [ -f "$PROP_FILE" ] || return 0
    grep -m1 "^${KEY}=" "$PROP_FILE" 2>/dev/null | cut -d= -f2- | tr -d '\r'
}

MOD_IS_DISABLED() {
    local MOD_DIR="$1"
    local DISABLED

    [ -f "$MOD_DIR/disable" ] && return 0

    DISABLED="$(MOD_PROP_GET "$MOD_DIR/module.prop" disabled)"
    [ "$DISABLED" = "true" ] || [ "$DISABLED" = "1" ] || [ "$DISABLED" = "yes" ]
}

MOD_DEVICE_MATCH() {
    local MOD_DIR="$1"
    local DEVICES
    local DEV

    DEVICES="$(MOD_PROP_GET "$MOD_DIR/module.prop" devices)"
    [ -z "$DEVICES" ] && return 0

    IFS=', ' read -r -a DEV_LIST <<< "$DEVICES"
    for DEV in "${DEV_LIST[@]}"; do
        [ -z "$DEV" ] && continue
        [ "$DEV" = "*" ] && return 0
        [ "$DEV" = "$STOCK_DEVICE" ] && return 0
        [ "$DEV" = "$TARGET_DEVICE" ] && return 0
    done

    return 1
}

# MOD_PARTITION_DIR <partition>
# Prints the destination directory in the extracted firmware tree.
MOD_PARTITION_DIR() {
    local PARTITION="$1"

    case "$PARTITION" in
        system)
            # Samsung's system.img contains a top-level system/ directory.
            if [ -d "$EXTRACTED_FIRM_DIR/system/system" ]; then
                echo "$EXTRACTED_FIRM_DIR/system/system"
            else
                echo "$EXTRACTED_FIRM_DIR/system"
            fi
            ;;
        system_ext)
            # FIX_SYSTEM_EXT merges system_ext into system when the device has
            # no separate system_ext partition. Prefer the separate partition
            # only when the device config says it is actually separate.
            if [ "$STOCK_HAS_SEPARATE_SYSTEM_EXT" = "TRUE" ] && [ -d "$EXTRACTED_FIRM_DIR/system_ext" ]; then
                echo "$EXTRACTED_FIRM_DIR/system_ext"
            elif [ -d "$EXTRACTED_FIRM_DIR/system/system_ext" ]; then
                echo "$EXTRACTED_FIRM_DIR/system/system_ext"
            elif [ -d "$EXTRACTED_FIRM_DIR/system_ext" ]; then
                echo "$EXTRACTED_FIRM_DIR/system_ext"
            else
                echo "$EXTRACTED_FIRM_DIR/system/system_ext"
            fi
            ;;
        product|vendor|odm|system_dlkm|vendor_dlkm|odm_dlkm)
            echo "$EXTRACTED_FIRM_DIR/$PARTITION"
            ;;
        *)
            return 1
            ;;
    esac
}

# MOD_COPY_TREE <mod_dir> <partition>
# Copies the whole partition tree from the mod to the firmware.
MOD_COPY_TREE() {
    local MOD_DIR="$1"
    local PARTITION="$2"
    local SRC="$MOD_DIR/$PARTITION"
    local DST

    [ -d "$SRC" ] || return 0

    # Catch the old double-partition layout before it creates /system/system
    # or /odm/odm entries inside the partition.
    if [ "$PARTITION" = "system" ] && [ -d "$SRC/system" ]; then
        echo "Legacy system/system layout in $MOD_DIR; move files to system/"
        return 1
    fi
    if [ "$PARTITION" = "odm" ] && [ -d "$SRC/odm" ]; then
        echo "Legacy odm/odm layout in $MOD_DIR; move files to odm/"
        return 1
    fi

    DST="$(MOD_PARTITION_DIR "$PARTITION")" || {
        echo "Unknown partition: $PARTITION"
        return 1
    }

    local CP_FLAGS="-rfa"
    if [ "$(MOD_PROP_GET "$MOD_DIR/module.prop" overwrite)" = "false" ]; then
        CP_FLAGS="-rfan"
    fi

    sudo mkdir -p "$DST" || return 1
    sudo cp $CP_FLAGS "$SRC/." "$DST/" || return 1
}

# MOD_COPY_FILE <mod_dir> <partition> <source> <destination>
# Copies a single file or directory from the mod to the firmware.
# Paths are relative to the partition root.
MOD_COPY_FILE() {
    local MOD_DIR="$1"
    local PARTITION="$2"
    local SRC_REL="$3"
    local DST_REL="$4"
    local SRC="$MOD_DIR/$PARTITION/$SRC_REL"
    local DST_ROOT
    local DST

    if [ ! -e "$SRC" ]; then
        echo "File not found: $SRC"
        return 1
    fi

    if [ -z "$DST_REL" ]; then
        DST_REL="$SRC_REL"
    fi

    DST_ROOT="$(MOD_PARTITION_DIR "$PARTITION")" || {
        echo "Unknown partition: $PARTITION"
        return 1
    }
    DST="$DST_ROOT/$DST_REL"

    local CP_FLAGS="-rfa"
    if [ "$(MOD_PROP_GET "$MOD_DIR/module.prop" overwrite)" = "false" ]; then
        CP_FLAGS="-rfan"
    fi

    sudo mkdir -p "$(dirname "$DST")" || return 1
    sudo cp $CP_FLAGS "$SRC" "$DST" || return 1
}

# MOD_APPLY <mod_dir>
# Applies a single mod: partition trees, optional customize.sh and logging.
MOD_APPLY() {
    local MOD_DIR="$1"
    local MOD_NAME
    local PARTITION
    local SKIP_AUTO_COPY=0
    local MOD_PARTITIONS=(system system_ext product vendor odm system_dlkm vendor_dlkm odm_dlkm)

    MOD_NAME="$(MOD_PROP_GET "$MOD_DIR/module.prop" name)"
    [ -z "$MOD_NAME" ] && MOD_NAME="$(basename "$MOD_DIR")"

    echo "${YELLOW} - Adding ${MOD_NAME}${RESET}"

    if MOD_IS_DISABLED "$MOD_DIR"; then
        echo "   disabled"
        return 0
    fi

    if ! MOD_DEVICE_MATCH "$MOD_DIR"; then
        echo "   skipped for $STOCK_DEVICE"
        return 0
    fi

    if [ -f "$MOD_DIR/customize.sh" ] && grep -q '^SKIPUNZIP=1$' "$MOD_DIR/customize.sh"; then
        SKIP_AUTO_COPY=1
    fi

    if [ "$SKIP_AUTO_COPY" -eq 0 ]; then
        for PARTITION in "${MOD_PARTITIONS[@]}"; do
            [ -d "$MOD_DIR/$PARTITION" ] || continue
            MOD_COPY_TREE "$MOD_DIR" "$PARTITION" || return 1
        done
    fi

    if [ -f "$MOD_DIR/customize.sh" ]; then
        MODPATH="$MOD_DIR"
        export MODPATH
        . "$MOD_DIR/customize.sh" || return 1
        unset MODPATH SKIPUNZIP
    fi

    return 0
}

# MOD_LIST <mods_dir>
# Prints "order<TAB>path" for every directory with a module.prop, sorted by
# order and then by path.
MOD_LIST() {
    local MODS_DIR="$1"
    local MOD_DIR
    local ORDER

    while IFS= read -r -d '' MOD_DIR; do
        [ -f "$MOD_DIR/module.prop" ] || continue

        ORDER="$(MOD_PROP_GET "$MOD_DIR/module.prop" order)"
        [ -z "$ORDER" ] && ORDER=50

        printf '%s\t%s\n' "$ORDER" "$MOD_DIR"
    done < <(find "$MODS_DIR" -mindepth 1 -maxdepth 1 -type d -print0) | \
        sort -n -k1,1 -k2,2
}

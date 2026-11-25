#!/bin/bash
#
# LumiROM features: fstab and SELinux/file-context fixes.
# Part of scripts/features/LumiROM.sh (sourced by it); not meant to run alone.

rom_patch_fstab_erofs() {
    local EXTRACTED_FIRM_DIR="$1"
    
    if [ -z "$EXTRACTED_FIRM_DIR" ]; then
        echo "Error: FIRM directory not specified."
        return 1
    fi

    echo "${YELLOW}Applying patches EROFS to fstab...${RESET}"

    local vendor_etc_dir="$EXTRACTED_FIRM_DIR/vendor/etc"
    local fstab_files=()
    mapfile -t fstab_files < <(find "$vendor_etc_dir" -maxdepth 1 -type f -name "fstab.mt*")

    if [ ${#fstab_files[@]} -eq 0 ]; then
        echo "${RED}No fstab files found in${RESET} $vendor_etc_dir"
        return 1
    fi

    local partitions="system system_ext vendor product odm"

    for target in "${fstab_files[@]}"; do
        local fstab_name=$(basename "$target")
        echo "${CYAN}Processing:${RESET} /vendor/etc/$fstab_name"
        
        for part in $partitions; do
            if sudo grep -E -q "^${part}[[:space:]]+.*erofs" "$target"; then
                echo "${YELLOW}Skipped:${RESET} Partition $part already contains 'erofs'."
                continue
            fi

            if sudo grep -E -q "^${part}[[:space:]]+.*ext4" "$target"; then
                echo "${GREEN}Patching:${RESET} $part (ext4 -> erofs)"
                sudo sed -i -E "/^${part}[[:space:]]+.*ext4/ { p; s/ext4/erofs/2; t; s/ext4/erofs/ }" "$target"
            fi
        done
    done

    echo "${GREEN}Done, now${RESET} $STOCK_DEVICE ${GREEN}is EROFS-enabled.${RESET}"
}

rom_auto_fix_selinux() {
    if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
        echo "Usage: ${FUNCNAME[0]} <EXTRACTED_FIRM_DIR> [TARGET_VER]"
        return 1
    fi

    local EXTRACTED_FIRM_DIR="${1%/}"
    local TARGET_VER="${2:-${SELINUX_TARGET_VER:-${STOCK_VNDK_VERSION:-31}}}"

    echo "${YELLOW}--- rom_auto_fix_selinux (target v${TARGET_VER}) ---${RESET}"

    # secilc in the host PATH?
    if command -v secilc &>/dev/null; then
        local SECILC_RUNNER="secilc"
    else
        echo "${YELLOW}  [!] secilc not available. Skipping rom_auto_fix_selinux.${RESET}"
        return 0
    fi

    local SYSTEM_EXT_DIR
    if [ -d "$EXTRACTED_FIRM_DIR/system/system_ext/etc/selinux" ]; then
        SYSTEM_EXT_DIR="$EXTRACTED_FIRM_DIR/system/system_ext"
    elif [ -d "$EXTRACTED_FIRM_DIR/system/system/system_ext/etc/selinux" ]; then
        SYSTEM_EXT_DIR="$EXTRACTED_FIRM_DIR/system/system/system_ext"
    else
        SYSTEM_EXT_DIR="${TARGET_ROM_SYSTEM_EXT_DIR:-$EXTRACTED_FIRM_DIR/system/system/system_ext}"
    fi
    local CIL_SET=(
        "$EXTRACTED_FIRM_DIR/system/system/etc/selinux/plat_sepolicy.cil"
        "$EXTRACTED_FIRM_DIR/system/system/etc/selinux/mapping/${TARGET_VER}.0.cil"
        "$SYSTEM_EXT_DIR/etc/selinux/mapping/${TARGET_VER}.0.compat.cil"
        "$SYSTEM_EXT_DIR/etc/selinux/system_ext_sepolicy.cil"
        "$SYSTEM_EXT_DIR/etc/selinux/mapping/${TARGET_VER}.0.cil"
        "$SYSTEM_EXT_DIR/etc/selinux/mapping/${TARGET_VER}.0.compat.cil"
        "$EXTRACTED_FIRM_DIR/product/etc/selinux/product_sepolicy.cil"
        "$EXTRACTED_FIRM_DIR/product/etc/selinux/mapping/${TARGET_VER}.0.cil"
        "$EXTRACTED_FIRM_DIR/vendor/etc/selinux/plat_pub_versioned.cil"
        "$EXTRACTED_FIRM_DIR/vendor/etc/selinux/vendor_sepolicy.cil"
    )

    # If any required CIL is missing, warn and skip (build continues)
    local MISSING_CIL=()
    for c in "${CIL_SET[@]}"; do
        [ ! -f "$c" ] && MISSING_CIL+=("${c#$EXTRACTED_FIRM_DIR/}")
    done
    if [ "${#MISSING_CIL[@]}" -gt 0 ]; then
        echo "${YELLOW}  [!] Required CILs missing, skipping rom_auto_fix_selinux:${RESET}"
        printf '      - %s\n' "${MISSING_CIL[@]}"
        return 0
    fi

    local OUTPUT_TMP
    OUTPUT_TMP=$(mktemp)
    local MAX_ITER=500
    local iteration=0 total=0

    while [ "$iteration" -lt "$MAX_ITER" ]; do
        iteration=$((iteration + 1))

        local secilc_exit=0
        local secilc_output
        secilc_output=$("$SECILC_RUNNER" -m -M true -G -N -v -c "$TARGET_VER" \
            "${CIL_SET[@]}" -o "$OUTPUT_TMP" -f /dev/null 2>&1) || secilc_exit=$?

        # Only consider the compile successful when secilc really exits 0. Relying on
        # a text match alone can mask errors like "Found conflicting genfscon rules"
        # that don't contain "Failed to resolve".
        if [ "$secilc_exit" -eq 0 ]; then
            echo "${GREEN}  [+] Policy compiled successfully (iteration $iteration).${RESET}"
            break
        fi

        local fixed=0
        while IFS= read -r err_line; do
            [ -z "$err_line" ] && continue

            local loc
            loc=$(echo "$err_line" | grep -oP 'at\s+\K\S+:\d+' | head -1 || true)
            [ -z "$loc" ] && continue

            local file="${loc%%:*}"
            local line_num="${loc##*:}"
            [ ! -f "$file" ] && continue

            # Skip if it is already a comment (idempotent)
            if sed -n "${line_num}p" "$file" | grep -qP '^\s*;;'; then
                continue
            fi

            sed -i "${line_num}s/^\(\s*\)/\1;; [auto-fixed] /" "$file"
            echo "  ${RED}[x] Commented:${RESET} ${file#$EXTRACTED_FIRM_DIR/}:$line_num"
            fixed=$((fixed + 1))
            total=$((total + 1))
        done <<< "$secilc_output"

        if [ "$fixed" -eq 0 ]; then
            echo "${YELLOW}  [!] Could not fix any more errors.${RESET}"
            echo "$secilc_output" | head -15
            break
        fi
    done

    rm -f "$OUTPUT_TMP"
    echo "${GREEN}  [+] rom_auto_fix_selinux: $total lines commented in $iteration iterations.${RESET}"
}

rom_remove_line() {
    if [ "$#" -ne 2 ]; then
        echo "Usage: ${FUNCNAME[0]} <TARGET_LINE> <TARGET_FILE>"
        return 1
    fi

    local LINE="$1"
    local FILE="$2"

    echo "${YELLOW}Deleting${RESET} $LINE ${YELLOW}from${RESET} $FILE"
    grep -vxF "$LINE" "$FILE" > "$FILE.tmp" && mv "$FILE.tmp" "$FILE"
}

rom_fix_property_contexts() {
    local EXTRACTED_FIRM_DIR="${1%/}"

    local WIFIX_WHITELIST=(
        "init.svc.vendor.wvkprov_server_hal"
    )

    local PLAT="$EXTRACTED_FIRM_DIR/system/system/etc/selinux/plat_property_contexts"

    local SYSTEM_EXT_DIR
    if [ -d "$EXTRACTED_FIRM_DIR/system/system_ext/etc/selinux" ]; then
        SYSTEM_EXT_DIR="$EXTRACTED_FIRM_DIR/system/system_ext"
    elif [ -d "$EXTRACTED_FIRM_DIR/system/system/system_ext/etc/selinux" ]; then
        SYSTEM_EXT_DIR="$EXTRACTED_FIRM_DIR/system/system/system_ext"
    else
        SYSTEM_EXT_DIR="${TARGET_ROM_SYSTEM_EXT_DIR:-$EXTRACTED_FIRM_DIR/system/system/system_ext}"
    fi
    local SYSTEM_EXT="$SYSTEM_EXT_DIR/etc/selinux/system_ext_property_contexts"

    local PRODUCT="$EXTRACTED_FIRM_DIR/product/etc/selinux/product_property_contexts"
    local VENDOR="$EXTRACTED_FIRM_DIR/vendor/etc/selinux/vendor_property_contexts"

    echo "${YELLOW}Fixing duplicate property-context prefixes${RESET}"

    local FILES=("$PLAT" "$SYSTEM_EXT" "$PRODUCT" "$VENDOR")
    local NAMES=("plat" "system_ext" "product" "vendor")

    # Collect active lines: prefix<TAB>priority<TAB>name<TAB>line_number<TAB>field_count
    local TMP_ALL=$(mktemp)
    local i
    for ((i=0; i<4; i++)); do
        local f="${FILES[$i]}"
        [ -f "$f" ] || continue
        awk -v prio="$((i+1))" -v name="${NAMES[$i]}" \
            '!/^#/ && $1 != "" {print $1 "\t" prio "\t" name "\t" NR "\t" NF}' "$f" >> "$TMP_ALL"
    done

    # Duplicate prefixes = prefixes appearing more than once
    local TMP_DUPES=$(mktemp)
    awk -F'\t' '
        { n=$1; if (!(n in c)) { order[++o]=n } c[n]++ }
        END { for (i=1;i<=o;i++) if (c[order[i]]>1) print order[i] }
    ' "$TMP_ALL" | grep -Fx -e "${WIFIX_WHITELIST[@]}" > "$TMP_DUPES"

    local COUNT
    COUNT=$(wc -l < "$TMP_DUPES" | tr -d ' ')
    if [ "$COUNT" -eq 0 ]; then
        echo "${GREEN}  [+] No whitelisted duplicate property-context prefixes.${RESET}"
        rm -f "$TMP_ALL" "$TMP_DUPES"
        return 0
    fi

    echo "  [!] $COUNT whitelisted duplicate prefix(es):"
    sed 's/^/    - /' "$TMP_DUPES"

    local removed=0
    while IFS= read -r prefix; do
        [ -z "$prefix" ] && continue

        # File to keep = the one with the highest priority
        local keep_name
        keep_name=$(awk -F'\t' -v p="$prefix" '$1==p {print $3 "\t" $2}' "$TMP_ALL" | sort -k2,2nr | head -1 | cut -f1)
        [ -z "$keep_name" ] && continue

        for ((i=0; i<4; i++)); do
            local f="${FILES[$i]}"
            [ -f "$f" ] || continue
            local name="${NAMES[$i]}"

            if [ "$name" == "$keep_name" ]; then
                # In the kept file keep only the most specific (max field count) entry
                local best
                best=$(awk -F'\t' -v p="$prefix" -v n="$name" '$1==p && $3==n {print $5 "\t" $4}' "$TMP_ALL" | sort -k1,1nr -k2,2n | head -1 | cut -f2)
                local TMP_OUT=$(mktemp)
                awk -v p="$prefix" -v b="$best" '!/^#/ && $1==p && NR!=b {next} {print}' "$f" > "$TMP_OUT"
                cp "$TMP_OUT" "$f" 2>/dev/null || echo "    [!] could not rewrite $name (permission)"
                rm -f "$TMP_OUT"
            else
                # Remove the prefix entirely from lower-priority files
                if awk -v p="$prefix" '!/^#/ && $1==p {found=1; exit} END {exit !found}' "$f"; then
                    local TMP_OUT2=$(mktemp)
                    awk -v p="$prefix" '!/^#/ && $1==p {next} {print}' "$f" > "$TMP_OUT2"
                    cp "$TMP_OUT2" "$f" 2>/dev/null || echo "    [!] could not rewrite $name (permission)"
                    rm -f "$TMP_OUT2"
                    echo "    - removed '$prefix' from $name (kept in $keep_name)"
                    removed=$((removed + 1))
                fi
            fi
        done
    done < "$TMP_DUPES"

    rm -f "$TMP_ALL" "$TMP_DUPES"
    echo "${GREEN}  [+] $removed duplicate property-context lines removed.${RESET}"
}

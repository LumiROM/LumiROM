#!/bin/bash

# =====================================================================
#  updater-script renderer
# =====================================================================
# Renders template/META-INF/com/google/android/updater-script, replacing
# the @PLACEHOLDER@ tokens with real values.
#
# Why a renderer instead of `sed -i` afterwards:
#   - A missing token is an explicit error instead of a silent no-op.
#   - Values never go through the shell parser, so quotes, spaces and
#     path separators cannot break the generated edify script.
#
# Template syntax:
#   @KEY@                  Replaced by the value passed as KEY=value.
#   #@IF KEY              Start of a conditional block.
#   #@ENDIF KEY           End of the block; kept only when KEY=true.
#                          Marker lines are always removed.
#
# Blocks cannot be nested.
# =====================================================================

# render_updater_script <template> <output> [KEY=value ...]
render_updater_script() {
    if [ "$#" -lt 2 ]; then
        echo "Usage: ${FUNCNAME[0]} <template> <output> [KEY=value ...]" >&2
        return 1
    fi

    local TEMPLATE="$1"
    local OUTPUT="$2"
    shift 2

    if [ ! -f "$TEMPLATE" ]; then
        echo "${RED:-}Error:${RESET:-} updater-script template not found: $TEMPLATE" >&2
        return 1
    fi

    local -A VALUES=()
    local PAIR KEY VALUE
    for PAIR in "$@"; do
        if [[ "$PAIR" != *=* ]]; then
            echo "${RED:-}Error:${RESET:-} render_updater_script expected KEY=value, got: $PAIR" >&2
            return 1
        fi
        KEY="${PAIR%%=*}"
        VALUE="${PAIR#*=}"
        if [[ ! "$KEY" =~ ^[A-Z][A-Z0-9_]*$ ]]; then
            echo "${RED:-}Error:${RESET:-} invalid placeholder name: $KEY" >&2
            return 1
        fi
        # Backslashes and '@' are modified by bash parameter substitution, so
        # they would corrupt the output silently. Reject them up front.
        if [[ "$VALUE" == *\\* || "$VALUE" == *@* ]]; then
            echo "${RED:-}Error:${RESET:-} value for $KEY contains an unsupported character (\\ or @)" >&2
            return 1
        fi
        VALUES["$KEY"]="$VALUE"
    done

    # bash >= 5.2 turns '&' in the replacement into the matched text when
    # patsub_replacement is enabled. We want literal replacements.
    shopt -u patsub_replacement 2>/dev/null || true

    local LINE OUT=""
    local SKIPPING="" BLOCK
    local -a MISSING=()

    while IFS= read -r LINE || [ -n "$LINE" ]; do
        if [[ "$LINE" =~ ^#@IF[[:space:]]+([A-Z][A-Z0-9_]*)$ ]]; then
            if [ -n "$SKIPPING" ]; then
                echo "${RED:-}Error:${RESET:-} nested #@IF ${BASH_REMATCH[1]} (already inside $SKIPPING)" >&2
                return 1
            fi
            BLOCK="${BASH_REMATCH[1]}"
            if [ "${VALUES[$BLOCK]:-}" = "true" ]; then
                SKIPPING=""
            else
                SKIPPING="$BLOCK"
            fi
            continue
        fi

        if [[ "$LINE" =~ ^#@ENDIF[[:space:]]+([A-Z][A-Z0-9_]*)$ ]]; then
            if [ -n "$SKIPPING" ] && [ "$SKIPPING" != "${BASH_REMATCH[1]}" ]; then
                echo "${RED:-}Error:${RESET:-} #@ENDIF ${BASH_REMATCH[1]} does not close $SKIPPING" >&2
                return 1
            fi
            SKIPPING=""
            continue
        fi

        if [ -n "$SKIPPING" ]; then
            continue
        fi

        for KEY in "${!VALUES[@]}"; do
            LINE="${LINE//@${KEY}@/${VALUES[$KEY]}}"
        done

        OUT+="$LINE"$'\n'
    done < "$TEMPLATE"

    if [ -n "$SKIPPING" ]; then
        echo "${RED:-}Error:${RESET:-} unterminated #@IF $SKIPPING in $TEMPLATE" >&2
        return 1
    fi

    # Any @TOKEN@ still present means the caller forgot a value.
    local LEFTOVER
    LEFTOVER="$(printf '%s' "$OUT" | grep -o '@[A-Z][A-Z0-9_]*@' | sort -u | tr '\n' ' ')"
    if [ -n "$LEFTOVER" ]; then
        echo "${RED:-}Error:${RESET:-} no value provided for: $LEFTOVER" >&2
        return 1
    fi

    mkdir -p "$(dirname "$OUTPUT")" || return 1
    printf '%s' "$OUT" > "$OUTPUT" || return 1
}

# =====================================================================
#  SamsungCamera dirty-flash cleanup
# =====================================================================
# A dirty flash can leave the camera's package cache pointing at the previous
# APK, so the same block is injected into the full OTA and the incremental OTA
# (and both are re-zipped before signing).
CAMERA_CLEANUP_MARKER="LumiROM SamsungCamera dirty-flash cleanup"
CAMERA_CLEANUP_ANCHOR="# --- End patching dynamic partitions ---"

camera_cleanup_block() {
    cat <<'EOF'
# --- LumiROM SamsungCamera dirty-flash cleanup ---
ui_print("Cleaning stale SamsungCamera state...");
run_program("/sbin/sh", "-c", "grep -q \" /data \" /proc/mounts || mount -o rw /data 2>/dev/null; rm -rf /data/system/package_cache/* /data/dalvik-cache/*SamsungCamera* /data/app/*com.sec.android.app.camera* /data/app/~~*/com.sec.android.app.camera* /data/data/com.sec.android.app.camera /data/user/0/com.sec.android.app.camera /data/user_de/0/com.sec.android.app.camera 2>/dev/null");
EOF
}

# inject_camera_cleanup_file <updater-script>
# Idempotent. Returns 1 if the anchor line is missing: a silently skipped
# injection would produce a dirty-flash bug that is hard to trace later.
inject_camera_cleanup_file() {
    local SCRIPT="$1"
    [ -f "$SCRIPT" ] || return 0

    if grep -q "$CAMERA_CLEANUP_MARKER" "$SCRIPT"; then
        return 0
    fi

    if ! grep -qxF "$CAMERA_CLEANUP_ANCHOR" "$SCRIPT"; then
        echo "${RED:-}Error:${RESET:-} cannot inject the camera cleanup: '$CAMERA_CLEANUP_ANCHOR' not found in $SCRIPT" >&2
        return 1
    fi

    local BLOCK_FILE
    BLOCK_FILE="$(mktemp)"
    camera_cleanup_block > "$BLOCK_FILE"
    sed -i "/^# --- End patching dynamic partitions ---\$/r $BLOCK_FILE" "$SCRIPT"
    rm -f "$BLOCK_FILE"
}

# inject_camera_cleanup_zip <zip>
# Re-zips the package, so it must run before signing.
inject_camera_cleanup_zip() {
    local ZIP_FILE="$1"
    [ -f "$ZIP_FILE" ] || return 0

    local ZIP_ABS TMP_DIR
    ZIP_ABS="$(readlink -f "$ZIP_FILE")"
    TMP_DIR="$(mktemp -d)"
    mkdir -p "$TMP_DIR/META-INF/com/google/android"

    if unzip -p "$ZIP_ABS" META-INF/com/google/android/updater-script \
            > "$TMP_DIR/META-INF/com/google/android/updater-script" 2>/dev/null; then
        if inject_camera_cleanup_file "$TMP_DIR/META-INF/com/google/android/updater-script"; then
            ( cd "$TMP_DIR" && zip -q "$ZIP_ABS" META-INF/com/google/android/updater-script )
        fi
    fi

    rm -rf "$TMP_DIR"
}

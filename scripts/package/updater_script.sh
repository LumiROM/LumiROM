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

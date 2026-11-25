#!/bin/bash
#
# Hugging Face bucket mirror for the base firmware images.
#
# Every LumiROM device is built from the same base firmware (Galaxy A34), and
# the build only needs the extracted partition images (the vendor image comes
# from the per-device vendor download). Downloading that 8.3 GB firmware from
# Samsung in every CI leg cost ~15 min per leg; the mirror keeps the extracted
# images in a public bucket instead.
#
# Layout:
#   FW/<model>/latest.txt
#   FW/<model>/<version>/images.zip
#
# Subcommands:
#   check                Print the version published in the bucket (empty if none).
#   pull                 Download and unpack the base images into $IMGS_DIR.
#   mirror               Make the bucket hold Samsung's latest base firmware.
#   push <version>       Publish the images in $IMGS_DIR as <version> and prune.
#   prune <version>      Delete every published version except <version>.
#
# Environment:
#   HF_USER, HF_TOKEN     Bucket owner and token (token only for write actions).
#   FW_BUCKET             Bucket id, defaults to "$HF_USER/FW".
#   IMGS_DIR, FIRM_DIR    Working directories (defaults: <repo>/IMGs, <repo>/FIRMWARE).
#   BASE_MODEL/BASE_CSC/BASE_IMEI
#                         Base firmware to mirror. Fall back to TARGET_*, then to
#                         the A34/EUX defaults used by the workflows.
#   BASE_PARTITIONS       Images kept in the mirror (default: system,product,odm,system_ext).
#
# The version recorded in latest.txt is the PDA of the Samsung release
# (e.g. A346BXXUHGZJ8), which is enough to detect a new base firmware.

set -eo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

HF_USER="${HF_USER:-}"
HF_TOKEN="${HF_TOKEN:-}"
BUCKET_ID="${FW_BUCKET:-${HF_USER}/FW}"
BASE_MODEL="${BASE_MODEL:-${TARGET_DEVICE:-SM-A346B}}"
BASE_CSC="${BASE_CSC:-${TARGET_CSC:-EUX}}"
BASE_IMEI="${BASE_IMEI:-${TARGET_IMEI:-353117555323497}}"
BASE_PARTITIONS="${BASE_PARTITIONS:-system,product,odm,system_ext}"
# PREPARE_PARTITIONS keeps only the partitions listed here.
export BUILD_PARTITIONS="${BUILD_PARTITIONS:-product,vendor,odm,system_ext,system}"
IMGS_DIR="${IMGS_DIR:-$REPO_ROOT/IMGs}"
FIRM_DIR="${FIRM_DIR:-$REPO_ROOT/FIRMWARE}"
HF_BASE_URL="${HF_BASE_URL:-https://huggingface.co/buckets}"

die() {
    echo "ERROR: $*" >&2
    exit 1
}

usage() {
    sed -n '2,32p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

# --- Bucket URLs ------------------------------------------------------------

latest_url() {
    echo "$HF_BASE_URL/$BUCKET_ID/resolve/FW/$BASE_MODEL/latest.txt?download=true"
}

images_url() {
    echo "$HF_BASE_URL/$BUCKET_ID/resolve/FW/$BASE_MODEL/$1/images.zip?download=true"
}

# upload <local> <remote>: upload_hf.py, passing the token only when set so the
# locally stored HF login keeps working.
upload() {
    local local_path="$1"
    local remote_path="$2"
    local -a args=("$local_path" "$remote_path" --bucket "$BUCKET_ID")
    [ -n "$HF_TOKEN" ] && args+=(--token "$HF_TOKEN")
    python3 scripts/package/upload_hf.py "${args[@]}"
}

# --- Helpers ----------------------------------------------------------------

# fetch <url> <output>: aria2c when available (parallel, resumable), curl otherwise.
fetch() {
    local url="$1"
    local out="$2"

    if command -v aria2c >/dev/null 2>&1; then
        local -a args=(
            -x 8 -s 8 -k 1M
            -d "$(dirname "$out")" -o "$(basename "$out")"
            --allow-overwrite=true --auto-file-renaming=false
            --console-log-level=error
        )
        [ -n "$HF_TOKEN" ] && args+=(--header="Authorization: Bearer $HF_TOKEN")
        aria2c "${args[@]}" "$url"
    else
        if [ -n "$HF_TOKEN" ]; then
            curl -fL --retry 3 -H "Authorization: Bearer $HF_TOKEN" -o "$out" "$url"
        else
            curl -fL --retry 3 -o "$out" "$url"
        fi
    fi
}

bucket_version() {
    local tmp="$1"

    curl -sfL --max-time 30 --retry 2 -o "$tmp" "$(latest_url)" || return 1
    sed -n 's/^version=//p' "$tmp" | head -n 1
}

samloader_version() {
    local out
    out="$(python3 -m samloader -m "$BASE_MODEL" -r "$BASE_CSC" -i "$BASE_IMEI" checkupdate 2>&1)" \
        || die "checkupdate failed for $BASE_MODEL/$BASE_CSC: $out"

    local pda="${out%%/*}"
    [[ "$pda" =~ ^[A-Z0-9]{8,}$ ]] || die "unexpected checkupdate output: $out"
    echo "$pda"
}

emit_version() {
    if [ -n "${GITHUB_OUTPUT:-}" ]; then
        echo "version=$1" >> "$GITHUB_OUTPUT"
    fi
}

# --- Commands ---------------------------------------------------------------

cmd_check() {
    local tmp version
    tmp="$(mktemp)"
    version="$(bucket_version "$tmp" || true)"
    rm -f "$tmp"
    [ -n "$version" ] && echo "$version"
    return 0
}

cmd_pull() {
    [ -n "$HF_USER" ] || { echo "HF_USER is not set, skipping the FW bucket" >&2; return 1; }

    local tmp_zip version
    local manifest
    manifest="$(mktemp)"
    version="$(bucket_version "$manifest" || true)"

    if [ -z "$version" ]; then
        rm -f "$manifest"
        echo "No base firmware published in $BUCKET_ID" >&2
        return 1
    fi

    echo "Pulling base firmware $version from $BUCKET_ID"
    mkdir -p "$IMGS_DIR"
    tmp_zip="$IMGS_DIR/base_images.zip"

    if ! fetch "$(images_url "$version")" "$tmp_zip"; then
        rm -f "$tmp_zip" "$manifest"
        echo "Download failed: $(images_url "$version")" >&2
        return 1
    fi

    if ! unzip -q -o "$tmp_zip" -d "$IMGS_DIR"; then
        rm -f "$tmp_zip" "$manifest"
        echo "Could not unpack $tmp_zip" >&2
        return 1
    fi
    rm -f "$tmp_zip"

    # Verify the unpacked images against the sizes published with the manifest,
    # so a truncated download cannot reach the build.
    local partitions part expected actual
    partitions="$(sed -n 's/^partitions=//p' "$manifest" | head -n 1)"
    partitions="${partitions:-$BASE_PARTITIONS}"
    IFS=',' read -r -a PART_LIST <<< "$partitions"
    for part in "${PART_LIST[@]}"; do
        expected="$(sed -n "s/^size_${part}=//p" "$manifest" | head -n 1)"
        actual="$(stat -c%s "$IMGS_DIR/$part.img" 2>/dev/null || echo 0)"
        if [ -n "$expected" ] && [ "$expected" != "$actual" ]; then
            rm -f "$manifest"
            echo "Size mismatch for $part.img (expected $expected, got $actual)" >&2
            return 1
        fi
    done
    rm -f "$manifest"

    # PREPARE_PARTITIONS prunes IMGs/, so the marker goes to FIRM_DIR (the
    # build reads it there to fill build_info.txt).
    mkdir -p "$FIRM_DIR"
    {
        echo "version=$version"
        echo "model=$BASE_MODEL"
    } > "$FIRM_DIR/base_firmware_version.txt"

    echo "Base images ready: $version"
    return 0
}

cmd_push() {
    local version="${1:-}"
    [ -n "$version" ] || die "push needs a version"
    [ -n "$HF_USER" ] || die "HF_USER is not set"

    local partitions part
    local -a parts=() files=()
    partitions="${BASE_PARTITIONS}"
    IFS=',' read -r -a parts <<< "$partitions"

    for part in "${parts[@]}"; do
        [ -f "$IMGS_DIR/$part.img" ] || die "missing $IMGS_DIR/$part.img"
        files+=("$part.img")
    done

    local manifest zip
    manifest="$(mktemp)"
    zip="$IMGS_DIR/base_images.zip"
    rm -f "$zip"

    echo "Packing ${#files[@]} images from $IMGS_DIR"
    ( cd "$IMGS_DIR" && zip -q -0 "$zip" "${files[@]}" ) || die "could not create $zip"

    local sha
    sha="$(sha256sum "$zip" | cut -d ' ' -f 1)"

    python3 scripts/package/hf_bucket.py --bucket "$BUCKET_ID" ensure
    upload "$zip" "FW/$BASE_MODEL/$version/images.zip"
    rm -f "$zip"

    {
        echo "version=$version"
        echo "model=$BASE_MODEL"
        echo "partitions=$partitions"
        for part in "${parts[@]}"; do
            echo "size_$part=$(stat -c%s "$IMGS_DIR/$part.img")"
        done
        echo "sha256=$sha"
        echo "published=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    } > "$manifest"

    upload "$manifest" "FW/$BASE_MODEL/latest.txt"
    rm -f "$manifest"

    cmd_prune "$version"
    echo "Published $BASE_MODEL/$version to $BUCKET_ID"
}

cmd_prune() {
    local keep="${1:-}"
    [ -n "$keep" ] || die "prune needs the version to keep"
    [ -n "$HF_USER" ] || return 0

    local listing
    listing="$(python3 scripts/package/hf_bucket.py --bucket "$BUCKET_ID" list "FW/$BASE_MODEL")" || return 0
    [ -n "$listing" ] || return 0

    local -a victims=()
    local path
    while IFS= read -r path; do
        [ -n "$path" ] || continue
        case "$path" in
            "FW/$BASE_MODEL/$keep/"*) ;;
            "FW/$BASE_MODEL/latest.txt") ;;
            *) victims+=("$path") ;;
        esac
    done <<< "$listing"

    if [ "${#victims[@]}" -gt 0 ]; then
        echo "Removing ${#victims[@]} file(s) from older versions"
        python3 scripts/package/hf_bucket.py --bucket "$BUCKET_ID" delete "${victims[@]}"
    fi
}

cmd_mirror() {
    [ -n "$HF_USER" ] || die "HF_USER is not set"

    local latest remote tmp
    tmp="$(mktemp)"
    latest="$(bucket_version "$tmp" || true)"
    rm -f "$tmp"

    remote="$(samloader_version)"
    echo "Samsung latest: $remote"
    echo "Bucket latest:  ${latest:-<none>}"

    if [ "$latest" = "$remote" ]; then
        echo "Bucket is already up to date."
        emit_version "$remote"
        return 0
    fi

    # DOWNLOAD_FIRMWARE writes into $FIRM_DIR/$MODEL and then moves the zip to
    # $IMGS_DIR; both must exist (the workflows create them, a bare run does not).
    mkdir -p "$IMGS_DIR" "$FIRM_DIR"

    source scripts/firmware/FW.sh
    DOWNLOAD_FIRMWARE "$BASE_MODEL" "$BASE_CSC" "$BASE_IMEI" "$FIRM_DIR" "$remote"
    EXTRACT_FIRMWARE "$IMGS_DIR"
    EXTRACT_SUPER_IMG "$IMGS_DIR"
    PREPARE_PARTITIONS "$IMGS_DIR"

    cmd_push "$remote"
    emit_version "$remote"
}

case "${1:-}" in
    check)  cmd_check ;;
    pull)   cmd_pull ;;
    mirror) cmd_mirror ;;
    push)   shift; cmd_push "$@" ;;
    prune)  shift; cmd_prune "$@" ;;
    *)      usage; exit 1 ;;
esac

#!/bin/bash

source scripts/utils/bash_colors.sh

deps_detect_os() {
    if [ -r /etc/os-release ]; then
        . /etc/os-release
    fi

    local MATCH=" $(printf '%s %s' "${ID:-}" "${ID_LIKE:-}") "
    MATCH="$(printf '%s' "$MATCH" | tr '[:upper:]' '[:lower:]')"

    case "$MATCH" in
        *" arch "*|*" archlinux "*)
            OS_TYPE="arch"
            ;;
        *" ubuntu "*|*" debian "*)
            OS_TYPE="debian"
            ;;
        *)
            echo -e "${BOLD_RED}[✗] Unsupported system: ${PRETTY_NAME:-unknown distribution}${RESET}" >&2
            echo -e "${BOLD_RED}    This script only supports Debian/Ubuntu and Arch Linux based systems.${RESET}" >&2
            exit 1
            ;;
    esac

    echo -e "${GREEN}[✓] Detected ${OS_TYPE} based system (${PRETTY_NAME:-${ID:-unknown}}).${RESET}"
}

deps_detect_os

deps_install_debian() {
    PACKAGES=(
        file
        7zip
        android-sdk-libsparse-utils
        python3
        python3-pip
        zipalign
        default-jre
        openjdk-17-jdk
        brotli
        bc
        bsdiff
        xxd
        android-sdk-build-tools
        patch
        e2fsprogs
        zstd
        aria2
        unzip
        tar
        lz4
        secilc
        tree
        git
        gnupg
        flex
        bison
        build-essential
        zip
        curl
        jq
        zlib1g-dev
        libncurses-dev
        libssl-dev
        libelf-dev
        libxml2-utils
        xsltproc
        fontconfig
        python3-protobuf
        libprotobuf32t64
    )

    echo "Searching for repository updates..."
    sudo apt update -qq

    echo -e "\nChecking dependency status...\n"

    for pkg in "${PACKAGES[@]}"; do
        if dpkg-query -s "$pkg" 2>/dev/null | grep -q "Status: install ok installed"; then
            IS_UPGRADABLE=$(apt list --upgradable "$pkg" 2>/dev/null | grep "$pkg" || true)

            if [ -n "$IS_UPGRADABLE" ]; then
                echo "${BOLD_YELLOW}[↑] Updating $pkg to the latest version...${RESET}"
                sudo DEBIAN_FRONTEND=noninteractive apt install --only-upgrade -y "$pkg"
            else
                echo "${GREEN}[✓] $pkg is updated.${RESET}"
            fi
        else
            echo "${YELLOW}[+] Installing $pkg...${RESET}"
            sudo DEBIAN_FRONTEND=noninteractive apt install -y "$pkg"
        fi
    done

    echo -e "\n¡All dependencies checked and updated!"
}

deps_install_arch() {
    REPO_PACKAGES=(
        file
        7zip
        brotli
        bc
        patch
        e2fsprogs
        zstd
        aria2
        unzip
        tar
        lz4
        tree
        git
        gnupg
        flex
        bison
        zip
        curl
        jq
        fontconfig
        python
        python-pip
        jdk17-openjdk
        base-devel
        ncurses
        openssl
        libelf
        libxml2
        libxslt
        python-protobuf
        protobuf
        android-tools
    )

    # xxd is provided by vim, which conflicts with the tinyxxd/xxd packages.
    # Only pull a provider when the command is actually missing.
    if ! command -v xxd >/dev/null 2>&1; then
        REPO_PACKAGES+=(tinyxxd)
    fi

    AUR_PACKAGES=(
        bsdiff
        android-sdk-build-tools
        secilc
    )

    local AUR_HELPER=""
    if command -v paru >/dev/null 2>&1; then
        AUR_HELPER="paru"
    elif command -v yay >/dev/null 2>&1; then
        AUR_HELPER="yay"
    fi

    echo -e "\nChecking dependency status...\n"

    if ! sudo pacman -S --needed --noconfirm "${REPO_PACKAGES[@]}"; then
        echo "${BOLD_YELLOW}[↑] Syncing package databases and retrying...${RESET}"
        sudo pacman -Sy --noconfirm
        if ! sudo pacman -S --needed --noconfirm "${REPO_PACKAGES[@]}"; then
            # A single conflicting package aborts the whole transaction, so
            # fall back to installing one by one and skip whatever conflicts.
            echo "${BOLD_YELLOW}[!] Batch install failed; installing individually, skipping conflicts...${RESET}"
            for pkg in "${REPO_PACKAGES[@]}"; do
                sudo pacman -S --needed --noconfirm "$pkg" || \
                    echo "${BOLD_YELLOW}[!] Skipping $pkg (conflict or unavailable)${RESET}"
            done
        fi
    fi

    echo "${GREEN}[✓] Official repository packages are installed.${RESET}"

    if [ -n "$AUR_HELPER" ]; then
        echo "${YELLOW}[+] Installing AUR packages with $AUR_HELPER...${RESET}"
        "$AUR_HELPER" -S --needed --noconfirm "${AUR_PACKAGES[@]}"
        echo "${GREEN}[✓] AUR packages are installed.${RESET}"
    else
        echo -e "${BOLD_YELLOW}[!] No AUR helper (paru/yay) found. Skipping AUR packages:${RESET}"
        echo -e "${BOLD_YELLOW}    ${AUR_PACKAGES[*]}${RESET}"
        echo -e "${BOLD_YELLOW}    Install paru or yay and re-run to install them.${RESET}"
    fi

    echo -e "\n¡All dependencies checked and updated!"
}

deps_install_python() {
    PIP_PACKAGES=(
        liblp
        tgcrypto
        pyrogram
        huggingface_hub
        hf_xet
    )

    SAMLOADER_URL="git+https://github.com/ananjaser1211/samloader.git"

    if [ "$OS_TYPE" = "arch" ]; then
        PIP_CMD=(sudo python3 -m pip install --break-system-packages)
    else
        PIP_CMD=(python3 -m pip install --break-system-packages)
    fi

    echo -e "Checking Python dependencies (pip3)...\n"

    for pkg in "${PIP_PACKAGES[@]}"; do
        if python3 -m pip show "$pkg" >/dev/null 2>&1; then
            echo "${GREEN}[✓] $pkg (pip) is already installed.${RESET}"
        else
            echo "${YELLOW}[+] Installing $pkg with pip3...${RESET}"
            "${PIP_CMD[@]}" "$pkg"
        fi
    done

    if python3 -m pip show samloader >/dev/null 2>&1; then
        echo "${GREEN}[✓] samloader (Git) is already installed.${RESET}"
    else
        echo "${YELLOW}[+] Installing samloader from GitHub...${RESET}"
        "${PIP_CMD[@]}" "$SAMLOADER_URL"
    fi

    echo -e "\nPython environment verified successfully!"
}

deps_install() {
    case "$OS_TYPE" in
        debian) deps_install_debian ;;
        arch)   deps_install_arch ;;
    esac
    deps_install_python
    deps_cleanup
}

deps_cleanup() {
    # Arch: no cache cleanup. It is not needed for the build and the previous
    # 'pacman -Sc' only added noise (and errors) to the build log.
    if [ "$OS_TYPE" = "arch" ]; then
        return 0
    fi

    sudo apt clean
    sudo apt autoclean
    sudo apt autoremove -y
    rm -rf ~/.cache/*
}

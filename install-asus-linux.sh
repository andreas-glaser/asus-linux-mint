#!/bin/bash

# ASUS Linux Tools Installation Script for Linux Mint 22.3 and Ubuntu 24.04
# Version: 22.3.3
#
# This script installs a tested asusctl release for ASUS laptops.
# supergfxctl is available only as an explicit opt-in for specialised use cases.
# It will also configure the systemd services to start on boot.
#
# Requirements:
# - Linux Mint 22.3 (primary) or Ubuntu 24.04
# - Internet connection for downloading dependencies
# - Sudo privileges
# - ASUS ROG/TUF laptop with supported hardware
# 
# Usage (review before running because this script uses sudo):
#   curl --proto '=https' --tlsv1.2 -fLo install-asus-linux.sh \
#     https://raw.githubusercontent.com/andreas-glaser/asus-linux-mint/main/install-asus-linux.sh
#   less install-asus-linux.sh
#   chmod +x install-asus-linux.sh
#   ./install-asus-linux.sh
# 
# To use a custom build directory:
#   ASUS_BUILD_DIR="/path/to/custom/dir" ./install-asus-linux.sh
# 
# For more information, visit: https://asus-linux.org/

set -euo pipefail

# Script configuration
SCRIPT_VERSION="22.3.3"
SUPPORTED_MINT_VERSION="22.3"
SUPPORTED_UBUNTU_VERSION="24.04"

# Pinned upstream revisions. Keeping these immutable prevents an upstream branch
# change from silently becoming privileged code on user systems.
ASUSCTL_VERSION="6.4.0"
ASUSCTL_COMMIT="e6c1469ccf2a745c6a1aff763852df90066c6baa"
ASUSCTL_REPO="https://github.com/OpenGamingCollective/asusctl.git"
SUPERGFXCTL_VERSION="5.2.7"
SUPERGFXCTL_COMMIT="a86383e1b2f32d4f87f8dd47f0d6b06690877c64"
SUPERGFXCTL_REPO="https://gitlab.com/asus-linux/supergfxctl.git"
SUPERGFXCTL_LOCK_SHA256="88136ef5d9d64bc023ef6e4504b95c75e5bfb26c55a5fb0299f739a06c6e1ecd"
SUPERGFXCTL_LOCK_URL="https://raw.githubusercontent.com/andreas-glaser/asus-linux-mint/main/assets/supergfxctl-5.2.7-Cargo.lock"

# Upstream kernel thresholds for specific components/features.
SUPERGFXCTL_MIN_KERNEL="6.1"
ASUS_ARMOURY_MIN_KERNEL="6.19"

# Keep build artifacts under the invoking account's registered home directory
# to constrain the scope of optional recursive cleanup.
ACCOUNT_HOME=$(getent passwd "$(id -u)" | cut -d: -f6)
BASE_DIR="${ASUS_BUILD_DIR:-$ACCOUNT_HOME/.local/src/asus-linux}"
SCRIPT_DIR=""
if ! SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" 2>/dev/null && pwd -P); then
    SCRIPT_DIR=""
fi

# Optional: install ROG Control Center GUI (build + desktop integration)
# Default: enabled for Linux Mint desktop users; set ASUS_INSTALL_ROG_GUI=0 to skip.
INSTALL_ROG_GUI="${ASUS_INSTALL_ROG_GUI:-1}"

# supergfxctl is no longer recommended as a general-purpose GPU switcher. It is
# retained as an opt-in for VFIO, eGPU, dGPU suspend, and monitoring use cases.
INSTALL_SUPERGFXCTL="${ASUS_INSTALL_SUPERGFXCTL:-0}"

# Firmware flashing is intentionally opt-in because it is independent of the
# ASUS utilities and may reboot devices or require AC power.
UPDATE_FIRMWARE="${ASUS_UPDATE_FIRMWARE:-0}"
RUST_TOOLCHAIN_BIN=""
DETECTED_DISTRIBUTION=""

# Cleanup function for graceful error handling
cleanup() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        print_error "Installation failed. You can try running the script again."
        print_error "Build directory: $BASE_DIR"
        print_error "Check logs above for specific error details."
    fi
    exit $exit_code
}

trap cleanup EXIT

# Function for colored output
print_status() {
    echo -e "\e[32m[INFO]\e[0m $1"
}

print_error() {
    echo -e "\e[31m[ERROR]\e[0m $1" >&2
}

print_warning() {
    echo -e "\e[33m[WARNING]\e[0m $1"
}

print_header() {
    echo -e "\e[1;34m"
    echo "========================================"
    echo "  ASUS Linux Tools Installation Script"
    echo "  Version $SCRIPT_VERSION"
    echo "========================================"
    echo -e "\e[0m"
}

validate_configuration() {
    local setting
    local canonical_base
    local canonical_home

    for setting in INSTALL_ROG_GUI INSTALL_SUPERGFXCTL UPDATE_FIRMWARE; do
        if [[ "${!setting}" != "0" && "${!setting}" != "1" ]]; then
            print_error "$setting must be either 0 or 1."
            return 1
        fi
    done

    if [[ "$BASE_DIR" != /* ]]; then
        print_error "ASUS_BUILD_DIR must be an absolute path."
        return 1
    fi

    if [ -L "$BASE_DIR" ]; then
        print_error "Refusing symlinked build directory: $BASE_DIR"
        return 1
    fi

    if [[ -z "$ACCOUNT_HOME" ]]; then
        print_error "Could not determine the invoking account's home directory."
        return 1
    fi
    canonical_home=$(realpath -m -- "$ACCOUNT_HOME")
    canonical_base=$(realpath -m -- "$BASE_DIR")
    if [[ "$canonical_base" != "$canonical_home"/* ]]; then
        print_error "ASUS_BUILD_DIR must remain below your account home: $canonical_home"
        return 1
    fi
}

version_lt() {
    local left="$1"
    local right="$2"

    [[ "$left" != "$right" && "$(printf '%s\n%s\n' "$left" "$right" | sort -V | head -n 1)" == "$left" ]]
}

# Fetch one exact, pinned commit without trusting remotes configured in a
# pre-existing checkout. Refuse to overwrite local work or follow a source-dir
# symlink; both behaviours are safer than the previous unconditional hard reset.
prepare_source_checkout() {
    local name="$1"
    local repository="$2"
    local expected_commit="$3"
    local expected_lock_hash="${4:-}"
    local source_dir="$BASE_DIR/$name"
    local fetched_commit
    local lock_hash
    local lock_status
    local non_lock_status

    if [ -L "$source_dir" ]; then
        print_error "Refusing to use symlinked source directory: $source_dir"
        return 1
    fi

    if [ -e "$source_dir" ] && [ ! -d "$source_dir/.git" ]; then
        print_error "Source path exists but is not a Git checkout: $source_dir"
        return 1
    fi

    if [ ! -d "$source_dir/.git" ]; then
        mkdir -p "$source_dir"
        git -C "$source_dir" init --quiet
    else
        # Cargo.lock is the one file this installer deliberately supplies. A
        # rerun may therefore find that exact verified file in an otherwise
        # clean checkout; all other changes remain protected.
        non_lock_status=$(git -C "$source_dir" status --porcelain -- . ':(exclude)Cargo.lock')
        if [ -n "$non_lock_status" ]; then
            print_error "Refusing to overwrite local changes in $source_dir"
            print_error "Commit or remove those changes, then run the installer again."
            return 1
        fi

        lock_status=$(git -C "$source_dir" status --porcelain -- Cargo.lock)
        if [ -n "$lock_status" ] && [ -f "$source_dir/Cargo.lock" ]; then
            lock_hash=$(sha256sum "$source_dir/Cargo.lock" | awk '{print $1}')
            if [[ -n "$expected_lock_hash" && "$lock_hash" != "$expected_lock_hash" ]]; then
                print_error "Refusing to overwrite an unrecognized Cargo.lock in $source_dir"
                return 1
            fi
        fi
    fi

    print_status "Fetching pinned $name revision $expected_commit..."
    git -C "$source_dir" fetch --quiet --depth 1 "$repository" "$expected_commit"
    fetched_commit=$(git -C "$source_dir" rev-parse FETCH_HEAD)
    if [[ "$fetched_commit" != "$expected_commit" ]]; then
        print_error "Revision verification failed for $name."
        return 1
    fi

    git -c core.hooksPath=/dev/null -C "$source_dir" checkout --quiet --force --detach "$expected_commit"
    print_status "Verified $name revision $expected_commit."
}

install_verified_dependency_lock() {
    local component="$1"
    local filename="$2"
    local expected_hash="$3"
    local download_url="$4"
    local destination="$5"
    local bundled_lock="$SCRIPT_DIR/assets/$filename"
    local source_lock="$bundled_lock"
    local temporary_lock=""
    local actual_hash

    if [ ! -f "$bundled_lock" ]; then
        temporary_lock=$(mktemp)
        source_lock="$temporary_lock"
        print_status "Downloading the project-supplied $component dependency lock..."
        if ! curl --proto '=https' --tlsv1.2 --fail --silent --show-error --location \
            "$download_url" --output "$source_lock"; then
            rm -f "$temporary_lock"
            print_error "Failed to download the $component dependency lock."
            return 1
        fi
    fi

    actual_hash=$(sha256sum "$source_lock" | awk '{print $1}')
    if [[ "$actual_hash" != "$expected_hash" ]]; then
        [ -z "$temporary_lock" ] || rm -f "$temporary_lock"
        print_error "$component dependency-lock verification failed."
        return 1
    fi

    install -m 0644 "$source_lock" "$destination"
    [ -z "$temporary_lock" ] || rm -f "$temporary_lock"
    print_status "Verified $component dependency lock ($expected_hash)."
}

# asusctl 6.3.11's system units contain one directive unavailable in the
# systemd 255 used by Mint 22.3 and Ubuntu 24.04, and use an invalid non-boolean
# value for another. Normalize
# those two lines so the intended control-group protection is actually enabled
# and systemd does not silently ignore configuration.
prepare_supported_systemd_unit() {
    local source_unit="$1"
    local destination_unit="$2"

    sed \
        -e '/^PrivateBPF=/d' \
        -e 's/^ProtectControlGroups=strict$/ProtectControlGroups=true/' \
        "$source_unit" > "$destination_unit"

    if grep -Eq '^PrivateBPF=|^ProtectControlGroups=strict$' "$destination_unit"; then
        print_error "Failed to normalize systemd directives in $source_unit."
        return 1
    fi
}

read_release_value() {
    local key="$1"
    local release_file="$2"

    awk -F= -v wanted="$key" '
        $1 == wanted {
            value = substr($0, index($0, "=") + 1)
            if (value ~ /^".*"$/) {
                value = substr(value, 2, length(value) - 2)
            }
            print value
            exit
        }
    ' "$release_file"
}

# Detect only the releases whose dependency and systemd paths this project
# explicitly validates. Parsing key/value files avoids executing their content.
detect_supported_distribution() {
    local mint_info_file="$1"
    local os_release_file="$2"
    local distribution_id
    local distribution_version
    local mint_edition

    if [ -f "$mint_info_file" ]; then
        distribution_version=$(read_release_value RELEASE "$mint_info_file")
        mint_edition=$(read_release_value EDITION "$mint_info_file")
        if [[ "$distribution_version" != "$SUPPORTED_MINT_VERSION" ]]; then
            print_error "Linux Mint $distribution_version detected. This release supports exactly Linux Mint $SUPPORTED_MINT_VERSION."
            return 1
        fi
        DETECTED_DISTRIBUTION="Linux Mint $distribution_version $mint_edition"
        return 0
    fi

    if [ -f "$os_release_file" ]; then
        distribution_id=$(read_release_value ID "$os_release_file")
        distribution_version=$(read_release_value VERSION_ID "$os_release_file")
        if [[ "$distribution_id" == "ubuntu" && "$distribution_version" == "$SUPPORTED_UBUNTU_VERSION" ]]; then
            DETECTED_DISTRIBUTION="Ubuntu $distribution_version"
            return 0
        fi
    fi

    print_error "This release supports Linux Mint $SUPPORTED_MINT_VERSION and Ubuntu $SUPPORTED_UBUNTU_VERSION only."
    return 1
}

# Check if running on a supported system
check_system() {
    local kernel_version
    local product_name
    local system_vendor

    print_status "Checking system requirements..."

    # Check if script is run as root (which we don't want)
    if [ "$EUID" -eq 0 ]; then
        print_error "This script should not be run as root. Run as a regular user with sudo access."
        exit 1
    fi
    
    # Check for systemd
    if ! systemctl --version &> /dev/null; then
        print_error "This script requires systemd. Please install manually on non-systemd systems."
        exit 1
    fi
    
    if ! detect_supported_distribution /etc/linuxmint/info /etc/os-release; then
        exit 1
    fi
    print_status "Detected $DETECTED_DISTRIBUTION"

    if [ ! -r /sys/class/dmi/id/sys_vendor ]; then
        print_error "Could not verify the system vendor through DMI."
        return 1
    fi
    system_vendor=$(< /sys/class/dmi/id/sys_vendor)
    if [[ "$system_vendor" != *ASUS* && "$system_vendor" != *ASUSTeK* ]]; then
        print_error "Unsupported system vendor: $system_vendor"
        return 1
    fi
    product_name="unknown model"
    if [ -r /sys/class/dmi/id/product_name ]; then
        product_name=$(< /sys/class/dmi/id/product_name)
    fi
    print_status "Detected ASUS system: $product_name"
    
    # Check kernel version
    kernel_version=$(uname -r | cut -d. -f1,2)
    if [[ "$INSTALL_SUPERGFXCTL" == "1" ]] && version_lt "$kernel_version" "$SUPERGFXCTL_MIN_KERNEL"; then
        print_error "Optional supergfxctl requires Linux $SUPERGFXCTL_MIN_KERNEL or newer."
        return 1
    fi
    if version_lt "$kernel_version" "$ASUS_ARMOURY_MIN_KERNEL"; then
        if [[ "$DETECTED_DISTRIBUTION" == Linux\ Mint* ]]; then
            print_warning "asus-armoury TDP/PPT controls require Linux $ASUS_ARMOURY_MIN_KERNEL+; see Update Manager → View → Linux Kernels."
        else
            print_warning "asus-armoury TDP/PPT controls require Linux $ASUS_ARMOURY_MIN_KERNEL+; use Ubuntu's supported kernel updates in Software Updater."
        fi
    else
        print_status "Kernel $kernel_version meets the asus-armoury version requirement."
    fi

    # Conflicting switchers matter only for the optional supergfxctl daemon.
    if [[ "$INSTALL_SUPERGFXCTL" == "1" ]]; then
        local conflicting_packages=("optimus-manager" "suse-prime" "ubuntu-prime" "system76-power")
        local conflicts_found=false
        local pkg
        for pkg in "${conflicting_packages[@]}"; do
            if dpkg-query -W -f='${db:Status-Abbrev}' "$pkg" 2>/dev/null | grep -q '^ii'; then
                print_warning "Conflicting package '$pkg' detected."
                conflicts_found=true
            fi
        done

        if [ "$conflicts_found" = true ]; then
            print_error "Remove conflicting GPU management software before installing supergfxctl."
            return 1
        fi
    fi

    # asusd implements net.hadess.PowerProfiles itself. Offer to disable native power-profiles-daemon.
    if systemctl is-active --quiet power-profiles-daemon.service 2>/dev/null; then
        echo
        print_warning "power-profiles-daemon is active and conflicts with asusd's profile management."
        print_warning "Both claim the net.hadess.PowerProfiles D-Bus interface; whichever wins the"
        print_warning "race controls platform_profile and CPU EPP — the loser is silently ignored."
        echo
        read -p "Disable power-profiles-daemon and let asusd manage profiles? (recommended) (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            sudo systemctl disable --now power-profiles-daemon.service
            print_status "✓ power-profiles-daemon disabled. asusd will manage platform profiles."
        else
            print_warning "Continuing with power-profiles-daemon active. Profile behaviour may be non-deterministic."
        fi
    fi

    # Create build directory
    mkdir -p "$BASE_DIR"
    cd "$BASE_DIR"
    print_status "Using build directory: $BASE_DIR"
}

# Select and update the stable Rust toolchain. rustup itself is installed from
# the distribution's signed package repository in install_dependencies().
install_rust() {
    local rustup_executable
    local rustup_home
    local rustup_host

    if ! command -v rustup &> /dev/null; then
        print_error "rustup is unavailable after dependency installation."
        return 1
    fi

    print_status "Installing or updating the latest stable Rust toolchain..."
    rustup_home=$(rustup show home)
    rustup_host=$(rustup show | awk '/^Default host:/ { print $3; exit }')
    if [[ -z "$rustup_home" || -z "$rustup_host" ]]; then
        print_error "Could not determine rustup's toolchain location."
        return 1
    fi
    rustup_executable=$(readlink -f -- "$(command -v rustup)")
    if [[ "$rustup_executable" == "/usr/bin/rustup" ]]; then
        # Ubuntu's packaged proxies live in /usr/bin. Tell rustup that /usr is
        # their managed prefix so it does not incorrectly expect ~/.cargo/bin;
        # keep rustup itself managed and updated only by APT.
        CARGO_HOME=/usr rustup toolchain install stable --profile minimal --no-self-update
    else
        rustup toolchain install stable --profile minimal --no-self-update
    fi
    RUST_TOOLCHAIN_BIN="$rustup_home/toolchains/stable-$rustup_host/bin"
    if [[ ! -x "$RUST_TOOLCHAIN_BIN/cargo" || ! -x "$RUST_TOOLCHAIN_BIN/rustc" ]]; then
        print_error "The stable Rust toolchain was installed at an unexpected location."
        return 1
    fi
    "$RUST_TOOLCHAIN_BIN/cargo" --version >/dev/null
    print_status "Rust $("$RUST_TOOLCHAIN_BIN/rustc" --version) is ready."
}

cargo_stable() {
    PATH="$RUST_TOOLCHAIN_BIN:$PATH" "$RUST_TOOLCHAIN_BIN/cargo" "$@"
}

# Install build dependencies
install_dependencies() {
    print_status "Installing build dependencies..."
    sudo apt-get update
    
    # Install essential dependencies
    sudo apt-get install -y \
        git \
        build-essential \
        cmake \
        libclang-dev \
        libudev-dev \
        libdbus-1-dev \
        libsystemd-dev \
        libssl-dev \
        pkg-config \
        meson \
        ninja-build \
        curl

    # Bootstrap rustup from Ubuntu/Mint's authenticated APT repository. Avoid
    # replacing an existing rustup installation managed by the user.
    if ! command -v rustup &> /dev/null; then
        print_status "Installing the distribution-signed rustup package..."
        sudo apt-get install -y rustup
    fi

    # Optional dependencies for rog-control-center (GUI)
    if [[ "$INSTALL_ROG_GUI" == "1" ]]; then
        print_status "Installing optional GUI build dependencies (rog-control-center)..."
        sudo apt-get install -y \
            libfontconfig1-dev \
            libfreetype6-dev \
            libexpat1-dev \
            libxkbcommon-dev \
            libx11-dev \
            libxcb-composite0-dev \
            libwayland-dev \
            libgbm-dev \
            libinput-dev \
            libseat-dev
    fi
        
    print_status "Build dependencies installed successfully."
}

# Update system firmware
update_firmware() {
    print_status "Updating system firmware..."
    print_warning "Firmware availability and results depend on hardware vendor support."
    
    # Check if fwupd is available
    if ! command -v fwupdmgr &> /dev/null; then
        print_status "Installing fwupd firmware update utility..."
        sudo apt-get install -y fwupd
    fi
    
    # Refresh firmware metadata and update firmware
    print_status "Refreshing firmware metadata..."
    if sudo fwupdmgr refresh --force; then
        print_status "✓ Firmware metadata refreshed successfully."
        
        print_status "Checking for firmware updates..."
        if sudo fwupdmgr update; then
            print_status "✓ Firmware updates completed successfully."
            print_warning "IMPORTANT: Some firmware updates may require a reboot to take effect."
        else
            print_warning "⚠ fwupdmgr did not complete an update successfully."
            print_warning "Review its output above; this can also mean that no supported update was available."
        fi
    else
        print_warning "⚠ Failed to refresh firmware metadata."
        print_warning "Continuing installation - firmware updates are recommended but not required."
    fi
    
    print_status "Firmware update step finished."
    print_status "Review fwupdmgr output above for the devices and changes actually applied."
}

# Install asusctl
install_asusctl() {
    local normalized_asusd_unit
    local normalized_shutdown_unit
    local normalized_unit_dir

    print_status "Installing asusctl $ASUSCTL_VERSION..."
    prepare_source_checkout "asusctl-$ASUSCTL_VERSION" "$ASUSCTL_REPO" "$ASUSCTL_COMMIT"

    cd "$BASE_DIR/asusctl-$ASUSCTL_VERSION"
    if [[ "$INSTALL_ROG_GUI" != "1" ]]; then
        print_status "Skipping rog-control-center (GUI) because ASUS_INSTALL_ROG_GUI=0."
    fi

    print_status "Building asusctl (daemon + CLI) (this may take several minutes)..."
    cargo_stable build --release --locked -p asusctl -p asusd -p asusd-user -p asus-shutdown
    if [[ "$INSTALL_ROG_GUI" == "1" ]]; then
        print_status "Building rog-control-center (GUI)..."
        # Linux Mint desktops commonly run X11; enable X11 backend to avoid runtime panics.
        cargo_stable build --release --locked -p rog-control-center --features "rog-control-center/x11"
    fi

    print_status "Installing asusctl and asusd..."
    sudo install -D -m 0755 "./target/release/asusctl" "/usr/bin/asusctl"
    sudo install -D -m 0755 "./target/release/asusd" "/usr/bin/asusd"
    sudo install -D -m 0755 "./target/release/asusd-user" "/usr/bin/asusd-user"
    sudo install -D -m 0755 "./target/release/asus-shutdown" "/usr/bin/asus-shutdown"

    # Install system integration files (udev, dbus, systemd, data assets)
    sudo install -D -m 0644 "./data/asusd.rules" "/usr/lib/udev/rules.d/99-asusd.rules"
    sudo install -D -m 0644 "./data/asusd.conf" "/usr/share/dbus-1/system.d/asusd.conf"
    normalized_unit_dir="$BASE_DIR/asusctl-$ASUSCTL_VERSION/target/installer-units"
    mkdir -p "$normalized_unit_dir"
    normalized_asusd_unit="$normalized_unit_dir/asusd.service"
    normalized_shutdown_unit="$normalized_unit_dir/asus-shutdown.service"
    prepare_supported_systemd_unit "./data/asusd.service" "$normalized_asusd_unit"
    prepare_supported_systemd_unit "./data/asus-shutdown.service" "$normalized_shutdown_unit"
    sudo install -D -m 0644 "$normalized_asusd_unit" "/usr/lib/systemd/system/asusd.service"
    sudo install -D -m 0644 "$normalized_shutdown_unit" "/usr/lib/systemd/system/asus-shutdown.service"
    sudo install -D -m 0644 "./data/asusd-user.service" "/usr/lib/systemd/user/asusd-user.service"
    sudo install -D -m 0644 "./rog-aura/data/aura_support.ron" "/usr/share/asusd/aura_support.ron"

    if [ -d "./rog-anime/data/anime" ]; then
        sudo mkdir -p "/usr/share/asusd"
        sudo cp -a "./rog-anime/data/anime" "/usr/share/asusd/"
        sudo chown -R root:root "/usr/share/asusd/anime"
        sudo find "/usr/share/asusd/anime" -type d -exec chmod 0755 {} +
        sudo find "/usr/share/asusd/anime" -type f -exec chmod 0644 {} +
    else
        print_warning "Anime data directory not found; continuing without it."
    fi

    # Optional: install ROG Control Center desktop integration
    if [[ "$INSTALL_ROG_GUI" == "1" ]]; then
        sudo install -D -m 0755 "./target/release/rog-control-center" "/usr/bin/rog-control-center"
        sudo install -D -m 0644 "./rog-control-center/data/org.opengamingcollective.rog-control-center.desktop" "/usr/share/applications/org.opengamingcollective.rog-control-center.desktop"
        sudo install -D -m 0644 "./rog-control-center/data/rog-control-center.png" "/usr/share/icons/hicolor/512x512/apps/rog-control-center.png"
        sudo install -D -m 0644 "./rog-control-center/data/org.opengamingcollective.rog-control-center.metainfo.xml" "/usr/share/metainfo/org.opengamingcollective.rog-control-center.metainfo.xml"

        if [ -d "./rog-aura/data/layouts" ]; then
            sudo mkdir -p "/usr/share/rog-gui/layouts"
            sudo cp -a "./rog-aura/data/layouts/." "/usr/share/rog-gui/layouts/"
            sudo chown -R root:root "/usr/share/rog-gui/layouts"
            sudo find "/usr/share/rog-gui/layouts" -type d -exec chmod 0755 {} +
            sudo find "/usr/share/rog-gui/layouts" -type f -exec chmod 0644 {} +
        fi

        sudo install -D -m 0644 "./data/icons/asus_notif_yellow.png" "/usr/share/icons/hicolor/512x512/apps/asus_notif_yellow.png"
        sudo install -D -m 0644 "./data/icons/asus_notif_green.png" "/usr/share/icons/hicolor/512x512/apps/asus_notif_green.png"
        sudo install -D -m 0644 "./data/icons/asus_notif_blue.png" "/usr/share/icons/hicolor/512x512/apps/asus_notif_blue.png"
        sudo install -D -m 0644 "./data/icons/asus_notif_red.png" "/usr/share/icons/hicolor/512x512/apps/asus_notif_red.png"
        sudo install -D -m 0644 "./data/icons/asus_notif_orange.png" "/usr/share/icons/hicolor/512x512/apps/asus_notif_orange.png"
        sudo install -D -m 0644 "./data/icons/asus_notif_white.png" "/usr/share/icons/hicolor/512x512/apps/asus_notif_white.png"

        sudo install -D -m 0644 "./data/icons/scalable/gpu-compute.svg" "/usr/share/icons/hicolor/scalable/status/gpu-compute.svg"
        sudo install -D -m 0644 "./data/icons/scalable/gpu-hybrid.svg" "/usr/share/icons/hicolor/scalable/status/gpu-hybrid.svg"
        sudo install -D -m 0644 "./data/icons/scalable/gpu-integrated.svg" "/usr/share/icons/hicolor/scalable/status/gpu-integrated.svg"
        sudo install -D -m 0644 "./data/icons/scalable/gpu-nvidia.svg" "/usr/share/icons/hicolor/scalable/status/gpu-nvidia.svg"
        sudo install -D -m 0644 "./data/icons/scalable/gpu-vfio.svg" "/usr/share/icons/hicolor/scalable/status/gpu-vfio.svg"
        sudo install -D -m 0644 "./data/icons/scalable/notification-reboot.svg" "/usr/share/icons/hicolor/scalable/status/notification-reboot.svg"
    fi

    # Reload daemons to recognize new service and rules
    sudo systemctl daemon-reload
    sudo udevadm control --reload-rules 2>/dev/null || true
    cd "$BASE_DIR"
    
    print_status "asusctl installed successfully."
}

# Install supergfxctl
install_supergfxctl() {
    print_warning "Installing optional supergfxctl for a specialised GPU workflow."
    prepare_source_checkout "supergfxctl-$SUPERGFXCTL_VERSION" "$SUPERGFXCTL_REPO" "$SUPERGFXCTL_COMMIT" "$SUPERGFXCTL_LOCK_SHA256"
    install_verified_dependency_lock \
        "supergfxctl" \
        "supergfxctl-$SUPERGFXCTL_VERSION-Cargo.lock" \
        "$SUPERGFXCTL_LOCK_SHA256" \
        "$SUPERGFXCTL_LOCK_URL" \
        "$BASE_DIR/supergfxctl-$SUPERGFXCTL_VERSION/Cargo.lock"

    # Build against the project-supplied, hash-verified dependency lock.
    cd "$BASE_DIR/supergfxctl-$SUPERGFXCTL_VERSION"
    print_status "Building supergfxctl (this may take several minutes)..."
    cargo_stable build --release --locked --features "daemon cli"
    print_status "Installing supergfxctl..."
    sudo install -D -m 0755 "./target/release/supergfxctl" "/usr/bin/supergfxctl"
    sudo install -D -m 0755 "./target/release/supergfxd" "/usr/bin/supergfxd"
    sudo install -D -m 0644 "./data/supergfxd.service" "/usr/lib/systemd/system/supergfxd.service"
    sudo install -D -m 0644 "./data/supergfxd.preset" "/usr/lib/systemd/system-preset/supergfxd.preset"
    sudo install -D -m 0644 "./data/org.supergfxctl.Daemon.conf" "/usr/share/dbus-1/system.d/org.supergfxctl.Daemon.conf"
    sudo install -D -m 0644 "./data/90-nvidia-screen-G05.conf" "/usr/share/X11/xorg.conf.d/90-nvidia-screen-G05.conf"
    sudo install -D -m 0644 "./data/90-supergfxd-nvidia-pm.rules" "/usr/lib/udev/rules.d/90-supergfxd-nvidia-pm.rules"
    
    # Reload systemd to recognize new service files
    sudo systemctl daemon-reload
    cd "$BASE_DIR"
    
    print_status "supergfxctl installed successfully."
}

# Configure and start services
configure_services() {
    print_status "Configuring and starting systemd services..."

    # asusd is a static D-Bus unit. An explicit restart is required on upgrades
    # so the running process cannot remain on the previously installed binary.
    if [ ! -f "/usr/lib/systemd/system/asusd.service" ]; then
        print_error "asusd.service not found. Installation may have failed."
        print_error "Expected unit file at /usr/lib/systemd/system/asusd.service."
        return 1
    fi
    sudo systemctl restart asusd.service
    print_status "asusd.service started with the newly installed binary."

    # asus-shutdown applies queued GPU firmware settings safely during shutdown.
    if [ ! -f "/usr/lib/systemd/system/asus-shutdown.service" ]; then
        print_error "asus-shutdown.service not found. GPU mode changes cannot be applied safely."
        return 1
    fi
    sudo systemctl enable asus-shutdown.service
    sudo systemctl restart asus-shutdown.service
    print_status "asus-shutdown.service enabled and started with the newly installed binary."
    
    if [[ "$INSTALL_SUPERGFXCTL" == "1" ]]; then
        # Enable and start the optional supergfxd service (system-level).
        if [ ! -f "/usr/lib/systemd/system/supergfxd.service" ]; then
            print_error "supergfxd.service not found. Installation may have failed."
            return 1
        fi
        sudo systemctl enable supergfxd.service
        sudo systemctl restart supergfxd.service
        print_status "supergfxd.service enabled and started with the newly installed binary."
    elif command -v supergfxctl &> /dev/null; then
        print_warning "Existing supergfxctl installation detected and left unchanged."
        print_warning "It is no longer installed by default; use ASUS_INSTALL_SUPERGFXCTL=1 to manage it here."
    fi
    
    # Enable asusd-user service for current user (user-level)
    systemctl --user daemon-reload 2>/dev/null || true
    if systemctl --user cat asusd-user.service &> /dev/null; then
        systemctl --user enable asusd-user.service 2>/dev/null || true
        systemctl --user restart asusd-user.service 2>/dev/null || true
        print_status "asusd-user.service enabled and restarted for current user."
    else
        print_warning "asusd-user.service not available in the current session. This is optional but recommended."
        print_warning "After reboot/login, you can enable it with: systemctl --user enable --now asusd-user.service"
    fi
    
    # Mint users invoking this installer already have an administrative group
    # accepted by supergfxctl's D-Bus policy (normally sudo or adm). Do not add
    # broader group memberships automatically.
    if [[ "$INSTALL_SUPERGFXCTL" == "1" ]]; then
        if id -nG | tr ' ' '\n' | grep -Eq '^(adm|sudo|users|wheel)$'; then
            print_status "Existing group membership permits supergfxctl D-Bus access."
        else
            print_warning "Your groups do not match supergfxctl's D-Bus policy (adm, sudo, users, or wheel)."
            print_warning "Review the policy and grant the narrowest appropriate existing group manually."
        fi
    fi
}

# Verify installation
verify_installation() {
    print_status "Verifying installation..."
    local success=true
    local info_output
    local version
    
    # Check if binaries are accessible
    if command -v asusctl &> /dev/null; then
        info_output=$(asusctl info 2>&1 || true)
        if grep -Fq "Software version: $ASUSCTL_VERSION" <<< "$info_output"; then
            print_status "✓ asusctl: $ASUSCTL_VERSION"
        else
            print_error "✗ asusctl did not report the expected version $ASUSCTL_VERSION."
            [ -z "$info_output" ] || print_warning "$info_output"
            success=false
        fi
    else
        print_error "✗ asusctl command not found in PATH."
        success=false
    fi
    
    if [[ "$INSTALL_SUPERGFXCTL" == "1" ]]; then
        if command -v supergfxctl &> /dev/null; then
            version=$(supergfxctl --version 2>/dev/null || true)
            if [[ "$version" == "$SUPERGFXCTL_VERSION" ]]; then
                print_status "✓ supergfxctl: $version"
            else
                print_error "✗ supergfxctl did not report the expected version $SUPERGFXCTL_VERSION."
                success=false
            fi
        else
            print_error "✗ supergfxctl command not found in PATH."
            success=false
        fi
    fi
    
    # Check service status
    if sudo systemctl is-active --quiet asusd.service; then
        print_status "✓ asusd.service is running."
    else
        print_warning "⚠ asusd.service is not running. Check: sudo systemctl status asusd.service"
        success=false
    fi
    
    if [[ "$INSTALL_SUPERGFXCTL" == "1" ]]; then
        if sudo systemctl is-active --quiet supergfxd.service; then
            print_status "✓ supergfxd.service is running."
        else
            print_warning "⚠ supergfxd.service is not running. Check: sudo systemctl status supergfxd.service"
            success=false
        fi
    fi

    if sudo systemctl is-active --quiet asus-shutdown.service; then
        print_status "✓ asus-shutdown.service is running."
    else
        print_warning "⚠ asus-shutdown.service is not running."
        success=false
    fi
    
    # Return 0 for success, 1 for failure
    if [ "$success" = "true" ]; then
        return 0
    else
        return 1
    fi
}

# Show status and usage information
show_status() {
    print_status "Installation completed! Here's the current status:"
    
    echo
    echo "=== ASUSCTL STATUS ==="
    if command -v asusctl &> /dev/null; then
        asusctl info --show-supported 2>/dev/null || print_warning "Could not query supported ASUS controls. Service may still be starting."
    fi
    
    if [[ "$INSTALL_SUPERGFXCTL" == "1" ]]; then
        echo
        echo "=== SUPERGFXCTL STATUS ==="
        supergfxctl --status 2>/dev/null || print_warning "Could not get supergfxctl status. Service may still be starting."
    fi
    
    echo
    echo "=== USAGE INFORMATION ==="
    echo "• Use 'asusctl --help' for ASUS laptop control options"
    echo "• GPU modes: use the ROG Control Center; changes are applied safely at shutdown"
    echo "• Check service logs: 'sudo journalctl -u asusd.service -u asus-shutdown.service'"
    if [[ "$INSTALL_SUPERGFXCTL" == "1" ]]; then
        echo "• Use 'supergfxctl --help' for specialised VFIO, eGPU, and dGPU controls"
    fi
    if [[ "$INSTALL_ROG_GUI" == "1" ]]; then
        echo "• GUI application: Launch 'rog-control-center' from your application menu"
    else
        echo "• GUI application: Re-run installer with ASUS_INSTALL_ROG_GUI=1 to install 'rog-control-center'"
    fi
    echo "• Builds use rustup's stable toolchain without changing your existing default toolchain"
    echo "• Fan curve control depends on laptop model/firmware; inspect 'asusctl info --show-supported'."
    echo
    print_warning "Some GPU mode changes require a reboot to take effect."
    
    echo
    echo "=== NEXT STEPS ==="
    echo "1. Reboot to ensure all changes take effect"
    echo "2. Check ASUS controls with: asusctl info --show-supported"
    if [[ "$INSTALL_ROG_GUI" == "1" ]]; then
        echo "3. Launch 'ROG Control Center' from your application menu"
    else
        echo "3. (Optional) Re-run with ASUS_INSTALL_ROG_GUI=1 to install the GUI"
    fi
}

# Main installation flow
main() {
    print_header
    print_status "Starting ASUS Linux tools installation for Linux Mint $SUPPORTED_MINT_VERSION / Ubuntu $SUPPORTED_UBUNTU_VERSION..."
    print_status "Script version: $SCRIPT_VERSION"
    echo

    validate_configuration
    check_system
    install_dependencies
    install_rust
    if [[ "$UPDATE_FIRMWARE" == "1" ]]; then
        update_firmware
    else
        print_status "Skipping firmware updates (set ASUS_UPDATE_FIRMWARE=1 to enable)."
    fi
    install_asusctl
    if [[ "$INSTALL_SUPERGFXCTL" == "1" ]]; then
        install_supergfxctl
    fi
    configure_services
    
    if verify_installation; then
        show_status
        echo
        print_status "✅ Installation completed successfully!"
        print_status "Build directory preserved at: $BASE_DIR"
    else
        print_error "❌ Installation completed with some issues. Please check the output above."
        return 1
    fi
}

# Run main only when executed, not when sourced by validation tests.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi

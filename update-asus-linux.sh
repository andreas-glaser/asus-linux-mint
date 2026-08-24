#!/bin/bash

# ASUS Linux Tools Update Script for Linux Mint 22.3
# Version: 22.3.2
#
# Updates an existing asusctl installation to the latest tagged release from
# https://github.com/OpenGamingCollective/asusctl
#
# Upstream publishes release tags but only ships Arch Linux binary packages, so
# this script builds the pinned tag from source, stages it with the upstream
# Makefile, wraps the staged tree in a .deb, and installs it with apt. dpkg then
# owns the files, which gives us version tracking, clean upgrades (files dropped
# upstream are removed instead of lingering), and rollback to a cached .deb.
#
# Requirements:
# - Linux Mint 22.3 (Cinnamon, MATE, or Xfce edition)
# - Sudo privileges
# - Build dependencies from install-asus-linux.sh (Rust toolchain, dev headers)
#
# Usage:
#   ./update-asus-linux.sh              # update to the latest release tag
#   ./update-asus-linux.sh --check      # report only, change nothing
#   ./update-asus-linux.sh --tag 6.3.10 # build a specific tag
#   ./update-asus-linux.sh --rollback   # reinstall the previous cached .deb
#   ./update-asus-linux.sh --install-timer   # weekly "update available" check
#
# To use a custom build directory:
#   ASUS_BUILD_DIR="/path/to/custom/dir" ./update-asus-linux.sh
#
# For more information, visit: https://asus-linux.org/

set -euo pipefail

# Packaged files and directories must not inherit a permissive user umask
# (Mint defaults to 002, which would ship group-writable 0775 directories).
umask 022

# Script configuration
SCRIPT_VERSION="22.3.2"
PKG_NAME="asusctl-ogc"
UPSTREAM_REPO="https://github.com/OpenGamingCollective/asusctl.git"
UPSTREAM_URL="https://github.com/OpenGamingCollective/asusctl"

# Set working directory (can be overridden with ASUS_BUILD_DIR environment variable)
BASE_DIR="${ASUS_BUILD_DIR:-$HOME/.local/src/asus-linux}"
SRC_DIR="$BASE_DIR/asusctl"
CACHE_DIR="/var/cache/asus-linux-mint"

# Optional: build ROG Control Center GUI (same switch as the installer)
INSTALL_ROG_GUI="${ASUS_INSTALL_ROG_GUI:-1}"

# Runtime flags (set by parse_args)
MODE="update"
REQUESTED_TAG=""
ASSUME_YES=0
NOTIFY=0
STAGE_DIR=""

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

print_success() {
    echo -e "\e[92m[SUCCESS]\e[0m $1"
}

print_header() {
    echo -e "\e[1;34m"
    echo "========================================"
    echo "  ASUS Linux Tools Update Script"
    echo "  Version $SCRIPT_VERSION"
    echo "========================================"
    echo -e "\e[0m"
}

# Remove the staging directory on exit; the built .deb lives in the cache
cleanup() {
    local exit_code=$?
    if [ -n "$STAGE_DIR" ] && [ -d "$STAGE_DIR" ]; then
        rm -rf "$STAGE_DIR"
    fi
    if [ $exit_code -ne 0 ] && [ "$MODE" = "update" ]; then
        print_error "Update failed. Your current installation was left untouched."
        print_error "Build directory: $SRC_DIR"
    fi
    exit $exit_code
}

trap cleanup EXIT

# Source the shared .deb packaging library
MAKE_DPKG_SH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/make-dpkg.sh"
# shellcheck source=make-dpkg.sh
source "$MAKE_DPKG_SH"

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTION]...

Update asusctl to the latest tagged release from the OpenGamingCollective
repository, packaged as a .deb so that apt/dpkg manage the installation.

Options:
  --check            Report installed and latest versions, then exit.
                     Exit code 0 = up to date, 10 = update available.
  --tag TAG          Build a specific upstream tag (e.g. 6.3.10) instead of
                     the latest release. Downgrades are allowed.
  --rollback         Reinstall the previous .deb from $CACHE_DIR.
  --no-gui           Skip rog-control-center (equivalent to ASUS_INSTALL_ROG_GUI=0).
  --yes, -y          Do not prompt for confirmation.
  --notify           With --check, also send a desktop notification.
  --install-timer    Install a weekly user systemd timer that checks for
                     updates and notifies. It never builds or installs.
  --remove-timer     Remove the weekly check timer.
  --help, -h         Show this help.

Environment:
  ASUS_BUILD_DIR         Build directory (default: \$HOME/.local/src/asus-linux)
  ASUS_INSTALL_ROG_GUI   Set to 0 to skip the GUI build (default: 1)
EOF
}

parse_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --check)         MODE="check" ;;
            --rollback)      MODE="rollback" ;;
            --install-timer) MODE="install-timer" ;;
            --remove-timer)  MODE="remove-timer" ;;
            --tag)
                if [ $# -lt 2 ]; then
                    print_error "--tag requires an argument."
                    exit 1
                fi
                REQUESTED_TAG="$2"
                shift
                ;;
            --no-gui)        INSTALL_ROG_GUI=0 ;;
            --yes|-y)        ASSUME_YES=1 ;;
            --notify)        NOTIFY=1 ;;
            --help|-h)       usage; exit 0 ;;
            *)
                print_error "Unknown option: $1"
                usage >&2
                exit 1
                ;;
        esac
        shift
    done
}

confirm() {
    local prompt="$1"
    if [ "$ASSUME_YES" -eq 1 ]; then
        return 0
    fi
    if [ ! -r /dev/tty ]; then
        print_error "Interactive confirmation requires a terminal (or use --yes)."
        return 1
    fi
    local reply
    read -r -p "$prompt (y/N): " -n 1 reply < /dev/tty
    echo
    [[ "$reply" =~ ^[Yy]$ ]]
}

# Check basic preconditions
check_system() {
    if [ "$EUID" -eq 0 ]; then
        print_error "This script should not be run as root. Run as a regular user with sudo access."
        exit 1
    fi

    local required=(git curl dpkg-deb)
    local missing=()
    local cmd
    for cmd in "${required[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            missing+=("$cmd")
        fi
    done

    if [ ${#missing[@]} -gt 0 ]; then
        print_error "Missing required commands: ${missing[*]}"
        print_error "Install them with: sudo apt install git curl dpkg-dev"
        exit 1
    fi
}

# Make cargo available; the installer puts it in ~/.cargo
ensure_rust() {
    if ! command -v cargo &> /dev/null && [ -f "$HOME/.cargo/env" ]; then
        # shellcheck disable=SC1091
        source "$HOME/.cargo/env"
    fi

    if ! command -v cargo &> /dev/null; then
        print_error "cargo not found. Run install-asus-linux.sh first to set up the build environment."
        exit 1
    fi
}

# Version currently installed, as dpkg sees it. Empty if not packaged or
# only residual config-files remain after apt remove (not apt purge).
get_installed_version() {
    dpkg-query -W -f='${Status} ${Version}' "$PKG_NAME" 2>/dev/null \
        | grep -q '^install ok installed ' \
        && dpkg-query -W -f='${Version}' "$PKG_NAME" 2>/dev/null || true
}

# True when asusctl is present on disk but not owned by our package, i.e. it was
# installed by the pre-.deb version of install-asus-linux.sh
has_legacy_install() {
    [ -z "$(get_installed_version)" ] && [ -x /usr/bin/asusctl ]
}

# Latest upstream release tag. git ls-remote avoids the GitHub API rate limit and
# needs no JSON parsing. Only x.y.z tags are considered; upstream also carries
# some unrelated v1.0.x tags that must not be treated as releases.
get_latest_tag() {
    git ls-remote --tags --refs "$UPSTREAM_REPO" 2>/dev/null \
        | awk '{print $2}' \
        | sed 's#refs/tags/##' \
        | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' \
        | sort -V \
        | tail -n 1
}

# Clone on first run, otherwise fetch. Never discards a dirty tree silently.
sync_source() {
    mkdir -p "$BASE_DIR"

    if [ ! -d "$SRC_DIR/.git" ]; then
        print_status "Cloning asusctl repository into $SRC_DIR..."
        git clone "$UPSTREAM_REPO" "$SRC_DIR"
        return
    fi

    print_status "Fetching upstream tags..."
    git -C "$SRC_DIR" fetch --tags --prune origin
}

# Check out the requested tag as a detached HEAD so the build is reproducible
checkout_tag() {
    local tag="$1"

    if [ -n "$(git -C "$SRC_DIR" status --porcelain)" ]; then
        print_warning "Local modifications found in $SRC_DIR; they will be discarded."
        if ! confirm "Discard local changes and continue?"; then
            print_status "Update cancelled by user."
            exit 0
        fi
        git -C "$SRC_DIR" reset --hard
        git -C "$SRC_DIR" clean -fd
    fi

    print_status "Checking out tag $tag..."
    git -C "$SRC_DIR" checkout --detach --quiet "refs/tags/$tag"
}

# Build the workspace.
#
# Note: no --locked here. Upstream does not commit a Cargo.lock and disabled
# --locked in their own Makefile on 2026-07-18, so passing it fails the build.
build_source() {
    print_status "Building asusctl (this may take several minutes)..."

    if [ "$INSTALL_ROG_GUI" = "1" ]; then
        # X11=1 adds the x11 feature; Linux Mint desktops commonly run X11 and
        # the GUI panics at runtime without it.
        make -C "$SRC_DIR" build X11=1
    else
        print_status "Skipping rog-control-center (GUI) build."
        cargo build --release --manifest-path "$SRC_DIR/Cargo.toml" \
            -p asusctl -p asusd -p asusd-user -p asus-shutdown
    fi
}

report_versions() {
    local installed="$1"
    local latest="$2"

    echo
    if [ -n "$installed" ]; then
        echo "  Installed: $installed"
    elif has_legacy_install; then
        echo "  Installed: unmanaged build (installed before .deb packaging)"
    else
        echo "  Installed: not installed"
    fi
    echo "  Latest:    $latest"
    echo "  Release:   $UPSTREAM_URL/releases/tag/$latest"
    echo
}

notify_update() {
    local latest="$1"
    command -v notify-send &> /dev/null || return 0
    notify-send --app-name="ASUS Linux Tools" \
        "asusctl $latest available" \
        "Run update-asus-linux.sh to build and install it." 2>/dev/null || true
}

do_check() {
    local installed latest

    installed="$(get_installed_version)"
    latest="$(get_latest_tag)"

    if [ -z "$latest" ]; then
        print_error "Could not determine the latest release tag from $UPSTREAM_URL"
        exit 1
    fi

    report_versions "$installed" "$latest"

    if [ -n "$installed" ] && dpkg --compare-versions "$installed" ge "$latest"; then
        print_success "asusctl is up to date."
        return 0
    fi

    if [ -n "$installed" ]; then
        print_status "Update available: $installed -> $latest"
    else
        print_status "asusctl $latest is available to install."
    fi

    if [ "$NOTIFY" -eq 1 ]; then
        notify_update "$latest"
    fi

    return 10
}

do_update() {
    local installed latest target

    installed="$(get_installed_version)"

    if [ -n "$REQUESTED_TAG" ]; then
        target="$REQUESTED_TAG"
        print_status "Requested tag: $target"
    else
        print_status "Looking up the latest release tag..."
        target="$(get_latest_tag)"
        if [ -z "$target" ]; then
            print_error "Could not determine the latest release tag from $UPSTREAM_URL"
            exit 1
        fi
    fi

    report_versions "$installed" "$target"

    if [ -z "$REQUESTED_TAG" ] && [ -n "$installed" ] \
        && dpkg --compare-versions "$installed" ge "$target"; then
        print_success "asusctl is already up to date. Nothing to do."
        print_status "Use --tag to rebuild or install a specific version."
        return 0
    fi

    if has_legacy_install; then
        print_warning "An existing asusctl install was found that is not managed by dpkg."
        print_warning "It was installed directly by install-asus-linux.sh."
        print_warning "This update replaces it with the '$PKG_NAME' package, after which"
        print_warning "apt manages upgrades and removal. /etc/asusd is left untouched."
        echo
    fi

    if ! confirm "Build and install asusctl $target?"; then
        print_status "Update cancelled by user."
        return 0
    fi

    ensure_rust
    sync_source
    checkout_tag "$target"
    build_source
    stage_install
    write_package_metadata "$target"

    local deb_path
    deb_path="$(build_deb "$target")"
    install_deb "$deb_path"
    enable_user_service
    warn_stale_gui "$target"
    prune_cache

    echo
    print_success "asusctl updated to $target."
    show_post_update "$target"
}

do_rollback() {
    local installed candidates previous

    installed="$(get_installed_version)"

    if [ ! -d "$CACHE_DIR" ]; then
        print_error "No cached packages found in $CACHE_DIR"
        exit 1
    fi

    mapfile -t candidates < <(find "$CACHE_DIR" -maxdepth 1 -name "${PKG_NAME}_*.deb" -printf '%T@ %p\n' \
        | sort -rn | cut -d' ' -f2-)

    if [ ${#candidates[@]} -eq 0 ]; then
        print_error "No cached packages found in $CACHE_DIR"
        exit 1
    fi

    previous=""
    local deb deb_version
    for deb in "${candidates[@]}"; do
        deb_version="$(dpkg-deb -f "$deb" Version 2>/dev/null || true)"
        if [ -n "$deb_version" ] && [ "$deb_version" != "$installed" ]; then
            previous="$deb"
            break
        fi
    done

    if [ -z "$previous" ]; then
        print_error "No cached package older than the installed version ($installed) is available."
        print_status "Cached packages:"
        printf '  %s\n' "${candidates[@]}"
        exit 1
    fi

    print_status "Currently installed: ${installed:-none}"
    print_status "Rolling back to:     $(basename "$previous")"
    echo

    if ! confirm "Install $(basename "$previous")?"; then
        print_status "Rollback cancelled by user."
        return 0
    fi

    install_deb "$previous"
    print_success "Rolled back to $(dpkg-deb -f "$previous" Version)."
}

timer_unit_dir() {
    echo "$HOME/.config/systemd/user"
}

do_install_timer() {
    local unit_dir script_path
    unit_dir="$(timer_unit_dir)"
    script_path="$(readlink -f "$0")"

    mkdir -p "$unit_dir"

    cat > "$unit_dir/asus-linux-update-check.service" <<EOF
[Unit]
Description=Check for asusctl updates
ConditionPathExists=$script_path

[Service]
Type=oneshot
# Exit code 10 means "update available"; it is expected, not a failure.
SuccessExitStatus=0 10
ExecStart=$script_path --check --notify
EOF

    cat > "$unit_dir/asus-linux-update-check.timer" <<EOF
[Unit]
Description=Weekly asusctl update check

[Timer]
OnCalendar=weekly
Persistent=true
RandomizedDelaySec=1h

[Install]
WantedBy=timers.target
EOF

    systemctl --user daemon-reload
    systemctl --user enable --now asus-linux-update-check.timer

    print_success "Weekly update check installed."
    print_status "It only notifies; it never builds or installs anything."
    print_status "Check status with: systemctl --user status asus-linux-update-check.timer"
}

do_remove_timer() {
    local unit_dir
    unit_dir="$(timer_unit_dir)"

    systemctl --user disable --now asus-linux-update-check.timer 2>/dev/null || true
    rm -f "$unit_dir/asus-linux-update-check.timer" \
          "$unit_dir/asus-linux-update-check.service"
    systemctl --user daemon-reload 2>/dev/null || true

    print_success "Weekly update check removed."
}

show_post_update() {
    local version="$1"

    echo
    echo "=== ASUSCTL STATUS ==="
    if command -v asusctl &> /dev/null; then
        asusctl info 2>/dev/null || print_warning "Could not get asusctl status. The service may still be starting."
    fi

    echo
    echo "=== MANAGED BY APT ==="
    echo "• Installed version:  dpkg-query -W $PKG_NAME"
    echo "• Remove everything:  sudo apt remove $PKG_NAME"
    echo "• Roll back:          $(basename "$0") --rollback"
    echo "• Cached packages:    $CACHE_DIR"
    echo
    echo "• Release notes: $UPSTREAM_URL/releases/tag/$version"
    echo "• Your settings in /etc/asusd were preserved."
    print_warning "Some changes only take effect after a reboot."
}

main() {
    parse_args "$@"

    case "$MODE" in
        check)
            check_system
            do_check
            ;;
        rollback)
            print_header
            check_system
            do_rollback
            ;;
        install-timer)
            print_header
            do_install_timer
            ;;
        remove-timer)
            print_header
            do_remove_timer
            ;;
        update)
            print_header
            print_status "asusctl updater for Linux Mint"
            print_status "Script version: $SCRIPT_VERSION"
            check_system
            do_update
            ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi

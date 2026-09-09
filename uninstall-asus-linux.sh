#!/bin/bash

# ASUS Linux Tools Uninstall Script for Linux Mint 22.3 and Ubuntu 24.04
# Version: 22.3.3
#
# This script removes asusctl, optional/legacy supergfxctl, and files managed
# by install-asus-linux.sh. User-customised asusd settings are opt-in cleanup.
#
# Requirements:
# - Linux Mint 22.3 or Ubuntu 24.04
# - Sudo privileges
# - Previously installed asusctl/supergfxctl via install-asus-linux.sh
# 
# Usage (review before running because this script uses sudo):
#   curl --proto '=https' --tlsv1.2 -fLo uninstall-asus-linux.sh \
#     https://raw.githubusercontent.com/andreas-glaser/asus-linux-mint/main/uninstall-asus-linux.sh
#   less uninstall-asus-linux.sh
#   chmod +x uninstall-asus-linux.sh
#   ./uninstall-asus-linux.sh
# 
# For more information, visit: https://asus-linux.org/

set -euo pipefail

# Script configuration
SCRIPT_VERSION="22.3.3"
ACCOUNT_HOME=$(getent passwd "$(id -u)" | cut -d: -f6)
BASE_DIR="${ASUS_BUILD_DIR:-$ACCOUNT_HOME/.local/src/asus-linux}"

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
    echo "  ASUS Linux Tools Uninstall Script"
    echo "  Version $SCRIPT_VERSION"
    echo "========================================"
    echo -e "\e[0m"
}

prompt_yes_no() {
    local prompt="$1"
    local reply

    if [ ! -r /dev/tty ]; then
        print_error "Interactive confirmation requires a terminal."
        return 1
    fi

    read -r -p "$prompt" -n 1 reply < /dev/tty
    echo
    [[ "$reply" =~ ^[Yy]$ ]]
}

validate_build_directory() {
    local canonical_base
    local canonical_home

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

# Confirm uninstallation
confirm_uninstall() {
    print_warning "This will remove files managed by the ASUS Linux tools installer:"
    echo "  • asusctl binaries and optional/legacy supergfxctl binaries"
    echo "  • All systemd services (asusd, asus-shutdown, and optional supergfxd)"
    echo "  • Configuration files and udev rules"
    echo "  • Desktop files and icons"
    echo "  • asusd runtime configuration directory (optional)"
    echo "  • Nouveau driver blacklist (optional)"
    echo "  • Build directories (optional)"
    echo
    print_warning "Your laptop will lose ASUS-specific hardware control features."
    echo
    if ! prompt_yes_no "Are you sure you want to continue? (y/N): "; then
        print_status "Uninstall cancelled by user."
        exit 0
    fi
}

# Stop and disable services
stop_services() {
    print_status "Stopping and disabling ASUS services..."
    
    if systemctl cat asus-shutdown.service &> /dev/null; then
        sudo systemctl stop asus-shutdown.service 2>/dev/null || true
        sudo systemctl disable asus-shutdown.service 2>/dev/null || true
        print_status "✓ asus-shutdown.service stopped and disabled."
    fi
    
    # Stop and disable asusd service (system-level)
    if systemctl cat asusd.service &> /dev/null; then
        sudo systemctl stop asusd.service 2>/dev/null || true
        sudo systemctl disable asusd.service 2>/dev/null || true
        print_status "✓ asusd.service stopped and disabled."
    fi
    
    # Stop and disable supergfxd service (system-level)
    if systemctl cat supergfxd.service &> /dev/null; then
        sudo systemctl stop supergfxd.service 2>/dev/null || true
        sudo systemctl disable supergfxd.service 2>/dev/null || true
        print_status "✓ supergfxd.service stopped and disabled."
    fi
    
    # Reload systemd
    sudo systemctl daemon-reload
    print_status "Systemd daemon reloaded."
}

# Remove binaries
remove_binaries() {
    print_status "Removing ASUS Linux binaries..."
    
    local binaries=(
        "/usr/bin/asusctl"
        "/usr/bin/asusd"
        "/usr/bin/asus-shutdown"
        "/usr/bin/rog-control-center"
        "/usr/bin/supergfxctl"
        "/usr/bin/supergfxd"
    )
    
    for binary in "${binaries[@]}"; do
        if [ -f "$binary" ]; then
            sudo rm -f "$binary"
            print_status "✓ Removed $binary"
        fi
    done
}

# Remove systemd service files
remove_service_files() {
    print_status "Removing systemd service files..."
    
    local service_files=(
        "/usr/lib/systemd/system/asusd.service"
        "/usr/lib/systemd/system/asus-shutdown.service"
        "/usr/lib/systemd/system/supergfxd.service"
        "/usr/lib/systemd/system-preset/supergfxd.preset"
    )
    
    for service_file in "${service_files[@]}"; do
        if [ -f "$service_file" ]; then
            sudo rm -f "$service_file"
            print_status "✓ Removed $service_file"
        fi
    done
    
    sudo systemctl daemon-reload
}

# Remove configuration files
remove_config_files() {
    print_status "Removing configuration and data files..."
    
    local config_files=(
        "/usr/share/dbus-1/system.d/asusd.conf"
        "/usr/share/dbus-1/system.d/org.supergfxctl.Daemon.conf"
        "/usr/lib/udev/rules.d/99-asusd.rules"
        "/usr/lib/udev/rules.d/90-supergfxd-nvidia-pm.rules"
        "/usr/share/X11/xorg.conf.d/90-nvidia-screen-G05.conf"
    )
    
    for config_file in "${config_files[@]}"; do
        if [ -f "$config_file" ]; then
            sudo rm -f "$config_file"
            print_status "✓ Removed $config_file"
        fi
    done
    
    # Remove data directories
    local data_dirs=(
        "/usr/share/asusd"
        "/usr/share/rog-gui"
    )
    
    for data_dir in "${data_dirs[@]}"; do
        if [ -d "$data_dir" ]; then
            sudo rm -rf "$data_dir"
            print_status "✓ Removed $data_dir"
        fi
    done
}

# Remove asusd runtime configuration directory (may hold user customisations)
remove_asusd_config() {
    print_status "Checking for asusd configuration directory..."

    local asusd_config_dir="/etc/asusd"

    if [ -d "$asusd_config_dir" ]; then
        print_warning "asusd configuration directory found: $asusd_config_dir"
        print_warning "This directory may contain user-customised fan curves, profiles, and LED settings."
        echo
        if prompt_yes_no "Remove asusd configuration directory? (y/N): "; then
            sudo rm -rf "$asusd_config_dir"
            print_status "✓ Removed $asusd_config_dir"
        else
            print_status "asusd configuration directory preserved."
        fi
    else
        print_status "✓ No asusd configuration directory found."
    fi
}

# Remove nouveau blacklist configuration
remove_nouveau_blacklist() {
    print_status "Checking for nouveau blacklist configuration..."
    
    local blacklist_file="/etc/modprobe.d/blacklist-nouveau.conf"
    local legacy_hash="3631c609cb22794edd9d980dbf6709dfd5ff13d504483334911e7c7025b0f9a1"
    local actual_hash
    
    if [ -f "$blacklist_file" ]; then
        print_warning "Nouveau blacklist configuration found: $blacklist_file"
        actual_hash=$(sha256sum "$blacklist_file" | awk '{print $1}')
        if [[ "$actual_hash" != "$legacy_hash" ]]; then
            print_warning "The file does not exactly match the legacy installer content."
            print_warning "It will be preserved to avoid deleting configuration owned by you or another package."
            return 0
        fi
        print_warning "This file exactly matches the configuration created by older installer releases."
        echo
        if prompt_yes_no "Remove legacy nouveau blacklist configuration? (y/N): "; then
            # Show current contents before removal
            print_status "Current contents of $blacklist_file:"
            sudo cat "$blacklist_file" | sed 's/^/    /' || true
            
            # Remove the blacklist file
            sudo rm -f "$blacklist_file"
            print_status "✓ Removed $blacklist_file"
            
            # Update initramfs to apply the changes
            print_status "Updating initramfs to apply nouveau blacklist removal..."
            sudo update-initramfs -u
            
            print_warning "IMPORTANT: A reboot will be required for the nouveau blacklist removal to take effect."
            print_warning "After reboot, the nouveau driver will be available again (if installed)."
        else
            print_status "Nouveau blacklist configuration preserved."
        fi
    else
        print_status "✓ No nouveau blacklist configuration found."
    fi
}

# Remove desktop files and icons
remove_desktop_files() {
    print_status "Removing desktop files and icons..."
    
    local desktop_files=(
        "/usr/share/applications/rog-control-center.desktop"
        "/usr/share/applications/org.opengamingcollective.rog-control-center.desktop"
        "/usr/share/metainfo/org.opengamingcollective.rog-control-center.metainfo.xml"
    )
    
    for desktop_file in "${desktop_files[@]}"; do
        if [ -f "$desktop_file" ]; then
            sudo rm -f "$desktop_file"
            print_status "✓ Removed $desktop_file"
        fi
    done
    
    # Remove only filenames installed by this project. Broad wildcards could
    # delete similarly named icons belonging to another package.
    local icon_files=(
        "/usr/share/icons/hicolor/512x512/apps/rog-control-center.png"
        "/usr/share/icons/hicolor/512x512/apps/asus_notif_yellow.png"
        "/usr/share/icons/hicolor/512x512/apps/asus_notif_green.png"
        "/usr/share/icons/hicolor/512x512/apps/asus_notif_blue.png"
        "/usr/share/icons/hicolor/512x512/apps/asus_notif_red.png"
        "/usr/share/icons/hicolor/512x512/apps/asus_notif_orange.png"
        "/usr/share/icons/hicolor/512x512/apps/asus_notif_white.png"
        "/usr/share/icons/hicolor/scalable/status/gpu-compute.svg"
        "/usr/share/icons/hicolor/scalable/status/gpu-hybrid.svg"
        "/usr/share/icons/hicolor/scalable/status/gpu-integrated.svg"
        "/usr/share/icons/hicolor/scalable/status/gpu-nvidia.svg"
        "/usr/share/icons/hicolor/scalable/status/gpu-vfio.svg"
        "/usr/share/icons/hicolor/scalable/status/notification-reboot.svg"
    )
    
    for icon_file in "${icon_files[@]}"; do
        if [ -f "$icon_file" ]; then
            sudo rm -f "$icon_file"
            print_status "✓ Removed $icon_file"
        fi
    done
    
    # Update icon cache
    sudo gtk-update-icon-cache /usr/share/icons/hicolor/ 2>/dev/null || true
}

# Remove build directories
remove_build_dirs() {
    if [ -d "$BASE_DIR" ]; then
        echo
        print_warning "Build directory found: $BASE_DIR"
        print_warning "This contains the source code and build artifacts."
        
        if prompt_yes_no "Remove build directory? (y/N): "; then
            rm -rf "$BASE_DIR"
            print_status "✓ Removed build directory: $BASE_DIR"
        else
            print_status "Build directory preserved: $BASE_DIR"
        fi
    fi
}

# Verify removal
verify_removal() {
    print_status "Verifying removal..."
    local issues_found=false
    local services_found=false
    local binary_path
    local service
    
    # Check only binary paths managed by this installer. A separately managed
    # /usr/local installation is outside this uninstaller's scope.
    local binary_paths=(
        "/usr/bin/asusctl"
        "/usr/bin/asusd"
        "/usr/bin/asus-shutdown"
        "/usr/bin/supergfxctl"
        "/usr/bin/supergfxd"
        "/usr/bin/rog-control-center"
    )
    for binary_path in "${binary_paths[@]}"; do
        if [ -e "$binary_path" ]; then
            print_warning "⚠ $binary_path is still present"
            issues_found=true
        else
            print_status "✓ $binary_path removed successfully"
        fi
    done
    
    # Check if system services still exist
    for service in asusd.service asus-shutdown.service supergfxd.service; do
        if systemctl cat "$service" &> /dev/null; then
            print_warning "⚠ $service is still present"
            issues_found=true
            services_found=true
        fi
    done

    if [ "$services_found" = false ]; then
        print_status "✓ Installer-managed systemd services removed"
    fi
    
    if [ "$issues_found" = true ]; then
        print_warning "Some components may still be present. Manual cleanup may be required."
        return 1
    else
        print_success "✓ Installer-managed components removed successfully!"
        return 0
    fi
}

# Show completion message
show_completion() {
    echo
    print_success "🎉 Installer-managed ASUS Linux tools have been removed from your system."
    echo
    echo "=== WHAT WAS REMOVED ==="
    echo "• asusctl and supergfxctl binaries"
    echo "• asusd, asus-shutdown, and supergfxd systemd services"
    echo "• Configuration files and udev rules"
    echo "• Desktop applications and icons"
    echo "• Nouveau driver blacklist (if selected)"
    echo "• Build directories (if selected)"
    echo
    echo "=== WHAT WAS PRESERVED ==="
    echo "• System firmware updates (via fwupd)"
    echo "• Existing Linux kernels"
    echo "• System packages and build tools"
    echo "• Rust toolchain (it may be shared with other development tools)"
    echo "• Existing group memberships"
    echo "• /etc/asusd settings (if selected to preserve)"
    echo
    echo "=== IMPORTANT NOTES ==="
    echo "• Controls provided by the removed tools are no longer available"
    echo "• GPU mode changes provided by these tools are no longer available"
    echo "• Fan curve, LED, and power-profile availability now depends on other installed software"
    echo "• Firmware and kernel changes were left unchanged"
    echo "• You may need to reboot for all changes to take effect"
    echo
    print_warning "To reinstall, visit: https://github.com/andreas-glaser/asus-linux-mint"
}

# Main uninstall flow
main() {
    print_header
    print_status "ASUS Linux tools uninstaller for Linux Mint"
    print_status "Script version: $SCRIPT_VERSION"
    echo
    
    # Check if running as root (which we don't want)
    if [ "$EUID" -eq 0 ]; then
        print_error "This script should not be run as root. Run as a regular user with sudo access."
        exit 1
    fi

    validate_build_directory
    confirm_uninstall
    stop_services
    remove_binaries
    remove_service_files
    remove_config_files
    remove_asusd_config
    remove_nouveau_blacklist
    remove_desktop_files
    remove_build_dirs
    
    echo
    if verify_removal; then
        show_completion
    else
        print_error "❌ Uninstall completed with some issues. Please check the output above."
        exit 1
    fi
}

# Run main only when executed, not when sourced by validation tests.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi

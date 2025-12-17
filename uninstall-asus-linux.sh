#!/bin/bash

# ASUS Linux Tools Uninstall Script for Linux Mint 22.2
# Version: 22.2.2
# 
# This script removes asusctl and supergfxctl and all associated files,
# services, and configurations that were installed by install-asus-linux.sh
# 
# Requirements:
# - Linux Mint 22.2 (Cinnamon, MATE, or Xfce edition)
# - Sudo privileges
# - Previously installed asusctl/supergfxctl via install-asus-linux.sh
# 
# Usage:
#   curl -sSL https://raw.githubusercontent.com/andreas-glaser/asus-linux-mint/main/uninstall-asus-linux.sh | bash
#   
#   Or download and run locally:
#   wget https://raw.githubusercontent.com/andreas-glaser/asus-linux-mint/main/uninstall-asus-linux.sh
#   chmod +x uninstall-asus-linux.sh
#   ./uninstall-asus-linux.sh
# 
# For more information, visit: https://asus-linux.org/

set -euo pipefail

# Script configuration
SCRIPT_VERSION="22.2.2"
BASE_DIR="${ASUS_BUILD_DIR:-$HOME/.local/src/asus-linux}"

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

# Confirm uninstallation
confirm_uninstall() {
    print_warning "This will completely remove ASUS Linux tools from your system:"
    echo "  • asusctl and supergfxctl binaries"
    echo "  • All systemd services (asusd, supergfxd, asusd-user)"
    echo "  • Configuration files and udev rules"
    echo "  • Desktop files and icons"
    echo "  • Nouveau driver blacklist (optional)"
    echo "  • Build directories (optional)"
    echo
    print_warning "Your laptop will lose ASUS-specific hardware control features."
    echo
    read -p "Are you sure you want to continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_status "Uninstall cancelled by user."
        exit 0
    fi
}

# Stop and disable services
stop_services() {
    print_status "Stopping and disabling ASUS services..."
    
    # Stop and disable asusd-user service (user-level)
    if systemctl --user list-unit-files | grep -q "asusd-user.service"; then
        systemctl --user stop asusd-user.service 2>/dev/null || true
        systemctl --user disable asusd-user.service 2>/dev/null || true
        print_status "✓ asusd-user.service stopped and disabled."
    fi
    
    # Stop and disable asusd service (system-level)
    if systemctl list-unit-files | grep -q "asusd.service"; then
        sudo systemctl stop asusd.service 2>/dev/null || true
        sudo systemctl disable asusd.service 2>/dev/null || true
        print_status "✓ asusd.service stopped and disabled."
    fi
    
    # Stop and disable supergfxd service (system-level)
    if systemctl list-unit-files | grep -q "supergfxd.service"; then
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
        "/usr/bin/asusd-user"
        "/usr/bin/rog-control-center"
        "/usr/bin/supergfxctl"
        "/usr/bin/supergfxd"
        "/usr/local/bin/asusctl"
        "/usr/local/bin/asusd"
        "/usr/local/bin/asusd-user"
        "/usr/local/bin/rog-control-center"
        "/usr/local/bin/supergfxctl"
        "/usr/local/bin/supergfxd"
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
        "/usr/lib/systemd/system/supergfxd.service"
        "/usr/lib/systemd/user/asusd-user.service"
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

# Remove nouveau blacklist configuration
remove_nouveau_blacklist() {
    print_status "Checking for nouveau blacklist configuration..."
    
    local blacklist_file="/etc/modprobe.d/blacklist-nouveau.conf"
    
    if [ -f "$blacklist_file" ]; then
        print_warning "Nouveau blacklist configuration found: $blacklist_file"
        print_warning "This file blacklists the nouveau driver to allow NVIDIA proprietary drivers."
        echo
        read -p "Remove nouveau blacklist configuration? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
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
    )
    
    for desktop_file in "${desktop_files[@]}"; do
        if [ -f "$desktop_file" ]; then
            sudo rm -f "$desktop_file"
            print_status "✓ Removed $desktop_file"
        fi
    done
    
    # Remove icons
    local icon_patterns=(
        "/usr/share/icons/hicolor/*/apps/rog-control-center.png"
        "/usr/share/icons/hicolor/*/apps/asus_notif_*.png"
        "/usr/share/icons/hicolor/*/status/gpu-*.svg"
        "/usr/share/icons/hicolor/*/status/notification-reboot.svg"
    )
    
    for pattern in "${icon_patterns[@]}"; do
        for icon_file in $pattern; do
            if [ -f "$icon_file" ]; then
                sudo rm -f "$icon_file"
                print_status "✓ Removed $icon_file"
            fi
        done 2>/dev/null || true
    done
    
    # Update icon cache
    sudo gtk-update-icon-cache /usr/share/icons/hicolor/ 2>/dev/null || true
}

# Remove user from groups (optional)
remove_user_groups() {
    print_status "Checking user group membership..."
    
    # Note: We don't automatically remove users from 'users' or 'wheel' groups
    # as these may be needed by other applications
    print_warning "Note: User '$USER' was added to groups during installation."
    print_warning "Groups like 'users' or 'wheel' are not automatically removed as they may be needed by other applications."
    
    echo
    read -p "Remove user '$USER' from 'users' group? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        if groups "$USER" | grep -q "\busers\b"; then
            sudo gpasswd -d "$USER" users 2>/dev/null || true
            print_status "✓ Removed user '$USER' from 'users' group."
            print_warning "You may need to log out and back in for group changes to take effect."
        else
            print_status "User '$USER' is not in 'users' group."
        fi
    fi
}

# Remove build directories
remove_build_dirs() {
    if [ -d "$BASE_DIR" ]; then
        echo
        print_warning "Build directory found: $BASE_DIR"
        print_warning "This contains the source code and build artifacts."
        
        read -p "Remove build directory? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            rm -rf "$BASE_DIR"
            print_status "✓ Removed build directory: $BASE_DIR"
        else
            print_status "Build directory preserved: $BASE_DIR"
        fi
    fi
}

# Optionally remove Rust toolchain
remove_rust() {
    if command -v rustup &> /dev/null; then
        echo
        print_warning "Rust toolchain detected (rustup)."
        print_warning "This may have been installed by the ASUS installer or may be used by other applications."
        
        read -p "Remove Rust toolchain (rustup)? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            rustup self uninstall -y 2>/dev/null || true
            print_status "✓ Removed Rust toolchain."
        else
            print_status "Rust toolchain preserved."
        fi
    fi
}

# Verify removal
verify_removal() {
    print_status "Verifying removal..."
    local issues_found=false
    
    # Check if binaries still exist
    local binaries=("asusctl" "asusd" "supergfxctl" "supergfxd" "rog-control-center")
    for binary in "${binaries[@]}"; do
        if command -v "$binary" &> /dev/null; then
            print_warning "⚠ $binary still found in PATH"
            issues_found=true
        else
            print_status "✓ $binary removed successfully"
        fi
    done
    
    # Check if services still exist
    if systemctl list-unit-files | grep -q "asusd.service\|supergfxd.service"; then
        print_warning "⚠ Some systemd services may still be present"
        issues_found=true
    else
        print_status "✓ All systemd services removed"
    fi
    
    if [ "$issues_found" = true ]; then
        print_warning "Some components may still be present. Manual cleanup may be required."
        return 1
    else
        print_success "✓ All components removed successfully!"
        return 0
    fi
}

# Show completion message
show_completion() {
    echo
    print_success "🎉 ASUS Linux tools have been completely removed from your system!"
    echo
    echo "=== WHAT WAS REMOVED ==="
    echo "• asusctl and supergfxctl binaries"
    echo "• All ASUS-related systemd services"
    echo "• Configuration files and udev rules"
    echo "• Desktop applications and icons"
    echo "• Nouveau driver blacklist (if selected)"
    echo "• Build directories (if selected)"
    echo
    echo "=== WHAT WAS PRESERVED ==="
    echo "• System firmware updates (via fwupd)"
    echo "• Linux kernel (if upgraded during installation)"
    echo "• System packages (linux-firmware, fwupd, build tools)"
    echo "• Rust toolchain (if selected to preserve)"
    echo
    echo "=== IMPORTANT NOTES ==="
    echo "• Your ASUS laptop hardware controls are no longer available"
    echo "• GPU switching functionality has been removed"
    echo "• Fan curves, LED controls, and power profiles are disabled"
    echo "• System firmware and kernel remain updated for optimal hardware support"
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
    
    confirm_uninstall
    stop_services
    remove_binaries
    remove_service_files
    remove_config_files
    remove_nouveau_blacklist
    remove_desktop_files
    remove_user_groups
    remove_build_dirs
    remove_rust
    
    echo
    if verify_removal; then
        show_completion
    else
        print_error "❌ Uninstall completed with some issues. Please check the output above."
        exit 1
    fi
}

# Run main function
main "$@" 

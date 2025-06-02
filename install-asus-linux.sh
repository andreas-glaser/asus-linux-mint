#!/bin/bash

# ASUS Linux Tools Installation Script for Linux Mint 22.1+
# Version: 22.1.1
# 
# This script installs the latest versions of asusctl and supergfxctl for ASUS laptops.
# It will also configure the systemd services to start on boot.
# 
# Requirements:
# - Linux Mint 22.1+ (Cinnamon, MATE, or Xfce edition)
# - Internet connection for downloading dependencies
# - Sudo privileges
# - ASUS ROG/TUF laptop with supported hardware
# 
# Usage:
#   curl -sSL https://raw.githubusercontent.com/andreas-glaser/asus-linux-mint/v22.1.1/install-asus-linux.sh | bash
#   
#   Or download and run locally:
#   wget https://raw.githubusercontent.com/andreas-glaser/asus-linux-mint/v22.1.1/install-asus-linux.sh
#   chmod +x install-asus-linux.sh
#   ./install-asus-linux.sh
# 
# To use a custom build directory:
#   ASUS_BUILD_DIR="/path/to/custom/dir" ./install-asus-linux.sh
# 
# For more information, visit: https://asus-linux.org/

set -euo pipefail

# Script configuration
SCRIPT_VERSION="22.1.1"
MIN_MINT_VERSION="22.1"
MIN_KERNEL_VERSION="6.1"

# ASUS hardware support kernel requirements
ASUS_MIN_KERNEL="6.1"           # Minimum for full ASUS hardware support
ASUS_RECOMMENDED_KERNEL="6.11"  # Recommended for latest features

# Set working directory (can be overridden with ASUS_BUILD_DIR environment variable)
BASE_DIR="${ASUS_BUILD_DIR:-$HOME/.local/src/asus-linux}"

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
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║           ASUS Linux Tools Installation Script              ║"
    echo "║                     Version $SCRIPT_VERSION                        ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "\e[0m"
}

# Check if running on a supported system
check_system() {
    print_status "Checking system requirements..."
    
    # Check if script is run as root (which we don't want)
    if [ "$EUID" -eq 0 ]; then
        print_error "This script should not be run as root. Run as a regular user with sudo access."
        exit 1
    fi
    
    # Check for internet connectivity
    if ! ping -c 1 google.com &> /dev/null; then
        print_error "No internet connection detected. Please check your network connection."
        exit 1
    fi
    
    # Check for systemd
    if ! systemctl --version &> /dev/null; then
        print_error "This script requires systemd. Please install manually on non-systemd systems."
        exit 1
    fi
    
    # Check if running on Linux Mint
    if [ -f /etc/linuxmint/info ]; then
        mint_version=$(grep "RELEASE=" /etc/linuxmint/info | cut -d'=' -f2)
        mint_edition=$(grep "EDITION=" /etc/linuxmint/info | cut -d'=' -f2 | tr -d '"')
        print_status "Detected Linux Mint $mint_version $mint_edition"
        
        # Check minimum version
        if command -v bc &> /dev/null && (( $(echo "$mint_version < $MIN_MINT_VERSION" | bc -l) )); then
            print_error "Linux Mint $mint_version detected. Version $MIN_MINT_VERSION+ is required."
            exit 1
        elif ! command -v bc &> /dev/null; then
            print_warning "Cannot verify Linux Mint version (bc not installed). Continuing anyway..."
        fi
    else
        print_warning "This script is designed for Linux Mint. You're running a different distribution."
        print_warning "The script may still work but is not officially supported."
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_status "Installation cancelled by user."
            exit 0
        fi
    fi
    
    # Check kernel version
    kernel_version=$(uname -r | cut -d. -f1,2)
    if command -v bc &> /dev/null && (( $(echo "$kernel_version < $MIN_KERNEL_VERSION" | bc -l) )); then
        print_warning "Kernel version $kernel_version detected. Version $MIN_KERNEL_VERSION+ is recommended for best compatibility."
    fi
    
    # Check for conflicting GPU switchers
    conflicting_packages=("optimus-manager" "suse-prime" "ubuntu-prime" "system76-power")
    conflicts_found=false
    for pkg in "${conflicting_packages[@]}"; do
        if dpkg -l | grep -q "^ii.*$pkg" 2>/dev/null; then
            print_warning "Conflicting package '$pkg' detected."
            conflicts_found=true
        fi
    done
    
    if [ "$conflicts_found" = true ]; then
        print_warning "Conflicting GPU management software detected. Consider removing them to avoid conflicts."
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_status "Installation cancelled by user."
            exit 0
        fi
    fi
    
    # Create build directory
    mkdir -p "$BASE_DIR"
    cd "$BASE_DIR"
    print_status "Using build directory: $BASE_DIR"
}

# Remove old Rust toolchain (if any)
remove_old_rust() {
    print_status "Checking for old Rust installations..."
    if dpkg -l | grep -q "^ii.*rustc\|^ii.*cargo" 2>/dev/null; then
        print_status "Removing old Rust toolchain from package manager..."
        sudo apt purge -y rustc cargo || true
        sudo apt autoremove -y || true
    fi
}

# Install rustup (modern Rust toolchain)
install_rust() {
    if ! command -v rustup &> /dev/null; then
        print_status "Installing rustup..."
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path
        source "$HOME/.cargo/env"
    else
        print_status "Rustup already installed."
        source "$HOME/.cargo/env"
    fi

    # Use latest stable Rust
    rustup default stable
    rustup update
    print_status "Rust $(rustc --version) installed successfully."
}

# Install build dependencies
install_dependencies() {
    print_status "Installing build dependencies..."
    sudo apt update
    
    # Install essential dependencies
    sudo apt install -y \
        git \
        build-essential \
        libclang-dev \
        libudev-dev \
        libdbus-1-dev \
        libsystemd-dev \
        pkg-config \
        meson \
        ninja-build \
        bc \
        curl \
        wget \
        linux-firmware \
        fwupd
        
    print_status "Build dependencies installed successfully."
}

# Install recent kernel for optimal ASUS hardware support
install_recent_kernel() {
    print_status "Checking kernel version for ASUS hardware compatibility..."
    
    # Get current kernel version
    current_kernel=$(uname -r | cut -d. -f1,2)
    print_status "Current kernel version: $current_kernel"
    
    # Use configurable kernel versions
    local min_kernel="$ASUS_MIN_KERNEL"
    local recommended_kernel="$ASUS_RECOMMENDED_KERNEL"
    
    # Check if current kernel meets minimum requirements
    if command -v bc &> /dev/null && (( $(echo "$current_kernel < $min_kernel" | bc -l) )); then
        print_warning "Kernel $current_kernel is below minimum recommended version $min_kernel for ASUS laptops."
        
        # Check if user wants to install a newer kernel
        echo
        print_warning "ASUS Linux tools require kernel $min_kernel+ for full functionality:"
        echo "  • Fan curve control requires kernel 5.17+"
        echo "  • TUF laptop support requires kernel 6.1+"
        echo "  • Latest features require kernel $recommended_kernel+"
        echo "  • GPU switching and power management improvements"
        echo
        read -p "Install newer kernel for better ASUS hardware support? (y/N): " -n 1 -r
        echo
        
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            print_status "Installing Hardware Enablement (HWE) kernel stack..."
            
            # Install HWE kernel for Linux Mint/Ubuntu
            if sudo apt install -y linux-generic-hwe-22.04 linux-headers-generic-hwe-22.04 2>/dev/null; then
                print_status "✓ HWE kernel stack installed successfully."
                print_warning "IMPORTANT: Reboot required to use the new kernel."
                
                # Show what kernel will be available after reboot
                latest_installed=$(dpkg -l | grep "linux-image-[0-9]" | grep -v "linux-image-generic" | sort -V | tail -1 | awk '{print $2}' | sed 's/linux-image-//')
                if [ -n "$latest_installed" ]; then
                    latest_version=$(echo "$latest_installed" | cut -d- -f1 | cut -d. -f1,2)
                    print_status "New kernel version available after reboot: $latest_version"
                fi
            elif sudo apt install -y linux-generic linux-headers-generic 2>/dev/null; then
                print_status "✓ Updated kernel stack installed successfully."
                print_warning "IMPORTANT: Reboot required to use the new kernel."
            else
                print_warning "⚠ Could not install newer kernel automatically."
                print_warning "Consider manually updating your kernel for optimal ASUS hardware support."
                print_warning "You can continue with the current kernel, but some features may be limited."
            fi
        else
            print_warning "Continuing with current kernel. Some ASUS features may be limited."
        fi
    elif command -v bc &> /dev/null && (( $(echo "$current_kernel < $recommended_kernel" | bc -l) )); then
        print_status "✓ Kernel $current_kernel meets minimum requirements."
        print_status "Note: Kernel $recommended_kernel+ is recommended for latest features."
    else
        print_status "✓ Kernel $current_kernel is up-to-date for ASUS hardware support."
    fi
}

# Create nouveau blacklist configuration
create_nouveau_blacklist() {
    print_status "Creating nouveau driver blacklist configuration..."
    
    # Create the blacklist configuration file
    local blacklist_file="/etc/modprobe.d/blacklist-nouveau.conf"
    
    # Check if file already exists
    if [ -f "$blacklist_file" ]; then
        print_warning "Blacklist file already exists: $blacklist_file"
        read -p "Do you want to overwrite it? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_status "Skipping nouveau blacklist creation."
            return 0
        fi
    fi
    
    # Create the blacklist file with proper content
    sudo tee "$blacklist_file" > /dev/null << EOF
blacklist nouveau
options nouveau modeset=0
EOF
    
    # Verify the file was created correctly
    if [ -f "$blacklist_file" ]; then
        print_status "✓ Created $blacklist_file"
        print_status "  Contents:"
        sudo cat "$blacklist_file" | sed 's/^/    /'
        
        # Update initramfs to apply the changes
        print_status "Updating initramfs to apply nouveau blacklist..."
        sudo update-initramfs -u
        
        print_warning "IMPORTANT: A reboot will be required for the nouveau blacklist to take effect."
    else
        print_error "Failed to create $blacklist_file"
        return 1
    fi
}

# Update system firmware
update_firmware() {
    print_status "Updating system firmware..."
    print_status "This ensures ASUS laptop hardware compatibility and optimal performance."
    
    # Check if fwupd is available
    if ! command -v fwupdmgr &> /dev/null; then
        print_status "Installing fwupd firmware update utility..."
        sudo apt install -y fwupd
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
            # fwupdmgr update returns non-zero when no updates are available
            exit_code=$?
            if [ $exit_code -eq 2 ]; then
                print_status "✓ No firmware updates available - system is up to date."
            else
                print_warning "⚠ Firmware update process completed with warnings."
                print_warning "This is often normal - some devices may not support firmware updates."
            fi
        fi
    else
        print_warning "⚠ Failed to refresh firmware metadata."
        print_warning "Continuing installation - firmware updates are recommended but not required."
    fi
    
    print_status "Firmware update process completed."
    print_status "Updated firmware improves:"
    echo "  • BIOS compatibility with Linux and hardware detection"
    echo "  • Embedded Controller (EC) for better power/thermal management"
    echo "  • Device firmware for optimal ASUS feature support"
    echo "  • Security patches and performance improvements"
}

# Install asusctl
install_asusctl() {
    print_status "Installing asusctl..."
    
    # Clone or update asusctl
    if [ ! -d "asusctl" ]; then
        print_status "Cloning asusctl repository..."
        git clone https://gitlab.com/asus-linux/asusctl.git
    else
        print_status "Updating asusctl repository..."
        cd asusctl
        git fetch --all
        git reset --hard origin/main
        cd ..
    fi

    # Build and install asusctl using the official Makefile
    cd asusctl
    print_status "Building asusctl (this may take several minutes)..."
    make
    print_status "Installing asusctl..."
    sudo make install
    
    # Reload systemd to recognize new service files
    sudo systemctl daemon-reload
    cd ..
    
    print_status "asusctl installed successfully."
}

# Install supergfxctl
install_supergfxctl() {
    print_status "Installing supergfxctl..."
    
    # Clone or update supergfxctl
    if [ ! -d "supergfxctl" ]; then
        print_status "Cloning supergfxctl repository..."
        git clone https://gitlab.com/asus-linux/supergfxctl.git
    else
        print_status "Updating supergfxctl repository..."
        cd supergfxctl
        git fetch --all
        git reset --hard origin/main
        cd ..
    fi

    # Build and install supergfxctl using the official Makefile
    cd supergfxctl
    print_status "Building supergfxctl (this may take several minutes)..."
    make
    print_status "Installing supergfxctl..."
    sudo make install
    
    # Reload systemd to recognize new service files
    sudo systemctl daemon-reload
    cd ..
    
    print_status "supergfxctl installed successfully."
}

# Configure and start services
configure_services() {
    print_status "Configuring and starting systemd services..."
    
    # Enable and start asusd service (system-level)
    if systemctl list-unit-files | grep -q "asusd.service"; then
        sudo systemctl enable asusd.service
        sudo systemctl start asusd.service
        print_status "asusd.service enabled and started."
    else
        print_error "asusd.service not found. Installation may have failed."
        return 1
    fi
    
    # Enable and start supergfxd service (system-level)
    if systemctl list-unit-files | grep -q "supergfxd.service"; then
        sudo systemctl enable supergfxd.service
        sudo systemctl start supergfxd.service
        print_status "supergfxd.service enabled and started."
    else
        print_error "supergfxd.service not found. Installation may have failed."
        return 1
    fi
    
    # Enable asusd-user service for current user (user-level)
    if systemctl --user list-unit-files | grep -q "asusd-user.service"; then
        systemctl --user enable asusd-user.service
        systemctl --user start asusd-user.service
        print_status "asusd-user.service enabled and started for current user."
    else
        print_warning "asusd-user.service not found. This is optional but recommended."
    fi
    
    # Add user to appropriate group for supergfxctl
    if getent group users > /dev/null; then
        sudo usermod -a -G users "$USER"
        print_status "User $USER added to 'users' group."
    elif getent group wheel > /dev/null; then
        sudo usermod -a -G wheel "$USER"
        print_status "User $USER added to 'wheel' group."
    else
        print_warning "Neither 'users' nor 'wheel' group found. You may need to add your user to an appropriate group manually."
    fi
}

# Verify installation
verify_installation() {
    print_status "Verifying installation..."
    local success=true
    
    # Check if binaries are accessible
    if command -v asusctl &> /dev/null; then
        version=$(asusctl --version 2>/dev/null || echo "unknown")
        print_status "✓ asusctl: $version"
    else
        print_error "✗ asusctl command not found in PATH."
        success=false
    fi
    
    if command -v supergfxctl &> /dev/null; then
        version=$(supergfxctl --version 2>/dev/null || echo "unknown")
        print_status "✓ supergfxctl: $version"
    else
        print_error "✗ supergfxctl command not found in PATH."
        success=false
    fi
    
    # Check service status
    if sudo systemctl is-active --quiet asusd.service; then
        print_status "✓ asusd.service is running."
    else
        print_warning "⚠ asusd.service is not running. Check: sudo systemctl status asusd.service"
        success=false
    fi
    
    if sudo systemctl is-active --quiet supergfxd.service; then
        print_status "✓ supergfxd.service is running."
    else
        print_warning "⚠ supergfxd.service is not running. Check: sudo systemctl status supergfxd.service"
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
        asusctl -s 2>/dev/null || print_warning "Could not get asusctl status. Service may still be starting."
    fi
    
    echo
    echo "=== SUPERGFXCTL STATUS ==="
    if command -v supergfxctl &> /dev/null; then
        supergfxctl --status 2>/dev/null || print_warning "Could not get supergfxctl status. Service may still be starting."
    fi
    
    echo
    echo "=== USAGE INFORMATION ==="
    echo "• Use 'asusctl --help' for ASUS laptop control options"
    echo "• Use 'supergfxctl --help' for GPU switching options"
    echo "• GPU modes: Integrated, Hybrid, Vfio (and possibly AsusEgpu, AsusMuxDgpu)"
    echo "• Example: 'supergfxctl --mode Hybrid' to enable hybrid graphics"
    echo "• Check service logs: 'sudo journalctl -u asusd.service' or 'sudo journalctl -u supergfxd.service'"
    echo "• GUI application: Install 'asusctl-gui' for graphical interface"
    echo
    print_warning "IMPORTANT: You may need to log out and back in (or reboot) for group changes to take effect."
    print_warning "Some GPU mode changes require a reboot to take effect."
    
    echo
    echo "=== NEXT STEPS ==="
    echo "1. Reboot to ensure all changes take effect"
    echo "2. Test GPU switching with: supergfxctl --mode Integrated"
    echo "3. Check ASUS controls with: asusctl -s"
    echo "4. Install asusctl-gui for a graphical interface (optional)"
}

# Main installation flow
main() {
    print_header
    print_status "Starting ASUS Linux tools installation for Linux Mint $MIN_MINT_VERSION+..."
    print_status "Script version: $SCRIPT_VERSION"
    echo
    
    check_system
    remove_old_rust
    install_rust
    install_dependencies
    install_recent_kernel
    create_nouveau_blacklist
    update_firmware
    install_asusctl
    install_supergfxctl
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

# Run main function
main "$@"


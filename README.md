# ASUS Linux Tools Installer for Linux Mint

An automated installation script for [asusctl](https://gitlab.com/asus-linux/asusctl) and [supergfxctl](https://gitlab.com/asus-linux/supergfxctl) on ASUS ROG/TUF laptops running **Linux Mint**.

## 🚀 Features

- **Automated installation** of latest asusctl and supergfxctl for Linux Mint
- **System firmware updates** via fwupd for optimal hardware compatibility
- **Kernel compatibility checking** with automatic upgrade options
- **NVIDIA driver preparation** with nouveau blacklist configuration
- **Comprehensive dependency management** including linux-firmware
- **Proper systemd service configuration** 
- **Comprehensive error handling** with colored output
- **Linux Mint compatibility** for versions 22.1+
- **Safe uninstallation** with complete cleanup
- **ASUS ROG/TUF hardware support** for all major laptop models

## 📋 Requirements

- **Linux Mint 22.1+** (Cinnamon, MATE, or Xfce edition)
- **ASUS ROG/TUF laptop** with compatible hardware
- **Internet connection** for downloading dependencies
- **Sudo privileges** for system modifications

## 🚀 Kernel Recommendations for ASUS Hardware

### 📊 Kernel Support Levels

**🟢 Optimal Support: Kernel 6.12+** *(requires mainline installation)*
- **Enhanced ASUS WMI driver** with thermal profile initialization fixes
- **Intel Lunar Lake performance boost** (~22% improvement on ASUS laptops)
- **Improved ROG Ally support** with better suspend/resume functionality
- **Mini-LED support** for 2024 ROG laptop models
- **Enhanced GPU MUX switching** for Vivobook series
- **Better power management** and thermal controls

**🟡 Good Support: Kernel 6.8+** *(available through standard HWE)*
- Full TUF/ROG laptop hardware support
- Fan curve control and RGB lighting
- GPU switching functionality
- Most ASUS-specific features working

**🔴 Basic Support: Kernel 6.1+** *(minimum requirement)*
- Basic ASUS hardware recognition
- Limited feature support

### 📦 Installation Options

**Standard Installation (HWE Kernels up to ~6.8):**
- Our installation script automatically offers HWE kernel updates
- Uses official Ubuntu/Linux Mint repositories
- Safe and well-tested
- Provides good ASUS hardware support

**Advanced Installation (Mainline 6.12+ for optimal support):**
- Requires manual mainline kernel installation
- Provides absolute best ASUS hardware support
- More experimental but offers latest improvements

### ⚡ Quick Kernel Check
Check your current kernel version:
```bash
uname -r
```

**If you have 6.12+**: Perfect! You have optimal ASUS support.
**If you have 6.8+**: Great! You have good ASUS support via HWE.
**If you have 6.1+**: Basic support. Consider upgrading for better features.
**If you have <6.1**: Upgrade needed for ASUS tools to work properly.

### 🔧 Advanced: Mainline Kernel 6.12+ Installation

For users who want **absolute optimal ASUS support**, you can manually install mainline kernel 6.12+:

<details>
<summary>📋 Click to expand mainline kernel installation methods</summary>

**⚠️ Important Warnings:**
- Mainline kernels are experimental and unsigned
- Always keep a working kernel as backup
- You may need to reinstall NVIDIA drivers after kernel updates
- Test thoroughly before relying on mainline kernels

**Option 1: Ubuntu Mainline Kernel Installer**
```bash
# Install the mainline kernel tool
sudo apt install -y wget
wget -qO - https://raw.githubusercontent.com/pimlie/ubuntu-mainline-kernel.sh/master/ubuntu-mainline-kernel.sh | sudo bash

# Install latest stable kernel
sudo ubuntu-mainline-kernel.sh -i
```

**Option 2: Manual Installation**
1. Visit [Ubuntu Mainline Kernels](https://kernel.ubuntu.com/mainline/)
2. Download the latest 6.12+ kernel packages for your architecture
3. Install using: `sudo dpkg -i *.deb`

**Option 3: GUI Tool (TuxInvader)**
```bash
sudo add-apt-repository ppa:tuxinvader/mainline
sudo apt update && sudo apt install mainline
# Launch 'mainline' GUI and install latest kernel
```

</details>

## 🛠️ Installation

### Quick Install (Recommended)

```bash
curl -sSL https://raw.githubusercontent.com/andreas-glaser/asus-linux-mint/v22.1.3/install-asus-linux.sh | bash
```

### Manual Install

```bash
# Download the script
wget https://raw.githubusercontent.com/andreas-glaser/asus-linux-mint/v22.1.3/install-asus-linux.sh

# Make it executable
chmod +x install-asus-linux.sh

# Run the installer
./install-asus-linux.sh
```

### Custom Build Directory

```bash
# Use custom directory for build files
ASUS_BUILD_DIR="/opt/asus-build" ./install-asus-linux.sh
```

## 📦 What Gets Installed

### Core Components
- **asusctl** - Primary ASUS laptop control utility
- **supergfxctl** - GPU switching and power management
- **Rust toolchain** - Latest stable version via rustup
- **Build dependencies** - All required development packages
- **linux-firmware** - Essential hardware firmware blobs

### System Configuration
- **systemd services** - asusd, supergfxd, and asusd-user
- **udev rules** - Hardware detection and device permissions
- **DBus configuration** - Inter-process communication setup
- **Firmware updates** - Latest BIOS, EC, and device firmware
- **Kernel compatibility** - Ensures minimum required kernel version
- **NVIDIA preparation** - Nouveau driver blacklist for proper GPU switching

### Hardware Features Enabled
- **Fan curve control** - Custom cooling profiles
- **RGB lighting control** - Keyboard and logo lighting
- **Power profiles** - Battery optimization modes
- **GPU switching** - Integrated/Hybrid/Discrete modes
- **Keyboard shortcuts** - Fn key combinations
- **Thermal management** - Advanced cooling control

## 🔧 Usage

### Basic Commands

```bash
# Check ASUS laptop status
asusctl -s

# Check GPU switching status
supergfxctl --status

# Switch to integrated graphics (power saving)
supergfxctl --mode Integrated

# Switch to hybrid graphics (balanced)
supergfxctl --mode Hybrid

# Set fan curve to performance mode
asusctl fan-curve -p performance

# Control RGB lighting
asusctl led-pow -s on
asusctl led-mode static
```

### Service Management

```bash
# Check service status
sudo systemctl status asusd supergfxd

# Restart services if needed
sudo systemctl restart asusd supergfxd

# View service logs
sudo journalctl -u asusd.service -f
sudo journalctl -u supergfxd.service -f
```

## 🗑️ Uninstallation

### Quick Uninstall

```bash
curl -sSL https://raw.githubusercontent.com/andreas-glaser/asus-linux-mint/v22.1.3/uninstall-asus-linux.sh | bash
```

### Manual Uninstall

```bash
# Download the uninstall script
wget https://raw.githubusercontent.com/andreas-glaser/asus-linux-mint/v22.1.3/uninstall-asus-linux.sh

# Make it executable
chmod +x uninstall-asus-linux.sh

# Run the uninstaller
./uninstall-asus-linux.sh
```

### What Gets Removed
- All ASUS Linux tool binaries and libraries
- System services and configuration files
- Build directories and source code
- Desktop applications and icons
- Optional: nouveau blacklist configuration
- Optional: build directories

### What Gets Preserved
- System firmware updates
- Kernel upgrades
- System packages (linux-firmware, build tools)
- Rust toolchain
- User data and personal settings

## 🔍 Troubleshooting

### Common Issues

**Services not starting:**
```bash
# Check service logs
sudo journalctl -u asusd.service -n 50
sudo journalctl -u supergfxd.service -n 50

# Reload and restart
sudo systemctl daemon-reload
sudo systemctl restart asusd supergfxd
```

**GPU switching not working:**
```bash
# Ensure nouveau is blacklisted
cat /etc/modprobe.d/blacklist-nouveau.conf

# Check GPU status
supergfxctl --status
lspci | grep -i vga

# Reboot after GPU mode changes
sudo reboot
```

**Permission issues:**
```bash
# Check user groups
groups $USER

# Add user to appropriate groups
sudo usermod -a -G users $USER
```

**Build failures:**
```bash
# Clean and rebuild
rm -rf ~/.local/src/asus-linux
./install-asus-linux.sh

# Check dependencies
sudo apt update && sudo apt upgrade
```

### Support Information

When reporting issues, please include:
- Linux Mint version and edition
- ASUS laptop model
- Kernel version (`uname -r`)
- Graphics hardware (`lspci | grep -i vga`)
- Service status (`sudo systemctl status asusd supergfxd`)
- Installation logs and error messages

For more help, visit:
- [ASUS Linux Community](https://asus-linux.org/)
- [asusctl GitLab Issues](https://gitlab.com/asus-linux/asusctl/-/issues)
- [supergfxctl GitLab Issues](https://gitlab.com/asus-linux/supergfxctl/-/issues)

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🤝 Contributing

Contributions are welcome! Please feel free to submit issues, feature requests, or pull requests.

## ⚠️ Disclaimer

This script modifies system configurations and installs software that may affect your system's stability. Use at your own risk. Always ensure you have backups before making system changes.
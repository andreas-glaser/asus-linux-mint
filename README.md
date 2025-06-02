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
- **Linux Mint compatibility checks** (version, kernel, conflicting packages)
- **Complete verification** of installation
- **User-friendly status reporting**

## 📋 Requirements

- **Linux Mint 22.1+** (Cinnamon, MATE, or Xfce edition)
- **ASUS ROG/TUF laptop** with supported hardware
- Kernel version 6.1+ (automatically checked and upgraded if needed)
- Internet connection for downloading dependencies and firmware updates
- Sudo privileges
- Rust toolchain will be automatically installed

## 🛠️ Installation

### One-line Installation (Recommended)
```bash
curl -sSL https://raw.githubusercontent.com/andreas-glaser/asus-linux-mint/v22.1.1/install-asus-linux.sh | bash
```

### Manual Download and Install
```bash
# Download the script
wget https://raw.githubusercontent.com/andreas-glaser/asus-linux-mint/v22.1.1/install-asus-linux.sh

# Make it executable
chmod +x install-asus-linux.sh

# Run the installer
./install-asus-linux.sh
```

### Custom Build Directory

```bash
ASUS_BUILD_DIR="/path/to/custom/dir" ./install-asus-linux.sh
```

## 📋 Supported Linux Mint Versions

- **Linux Mint 22.1 "Xia"** (Cinnamon, MATE, Xfce)
- Future Linux Mint versions will be supported as they are released

## 🔧 Installation Process

The script performs the following steps automatically:

1. **System Requirements Check**
   - Verifies Linux Mint version and compatibility
   - Checks for conflicting GPU management software
   - Validates internet connectivity and systemd

2. **Dependency Installation**
   - Installs build tools and development packages
   - Adds `linux-firmware` for comprehensive hardware support
   - Installs `fwupd` for firmware management

3. **Kernel Compatibility**
   - Checks current kernel version against ASUS hardware requirements
   - Offers to install Hardware Enablement (HWE) kernel if needed
   - Minimum: kernel 6.1+, Recommended: kernel 6.11+

4. **NVIDIA Driver Preparation** 
   - Creates `/etc/modprobe.d/blacklist-nouveau.conf` to disable nouveau driver
   - Updates initramfs to apply nouveau blacklist
   - Prepares system for NVIDIA proprietary drivers

5. **Firmware Updates**
   - Updates system firmware via fwupd for optimal hardware compatibility
   - Refreshes firmware metadata and applies available updates
   - Improves BIOS, Embedded Controller (EC), and device firmware

6. **ASUS Tools Installation**
   - Builds and installs latest asusctl and supergfxctl from source
   - Configures systemd services (asusd, supergfxd, asusd-user)
   - Verifies installation and service status

## 🎮 What Gets Installed

### asusctl
- ASUS laptop hardware control (fans, LEDs, profiles)
- Power management and performance profiles
- Keyboard backlight and function key controls
- Custom fan curve support
- Battery charge limit control

### supergfxctl  
- GPU switching for hybrid graphics setups
- Modes: Integrated, Hybrid, VFIO
- Power saving and performance optimization
- NVIDIA Dynamic Boost support (Ryzen 6000+)

### System Enhancements
- **Firmware updates** for improved hardware compatibility
- **Kernel upgrades** (if needed) for latest ASUS hardware support
- **NVIDIA driver preparation** via nouveau blacklist
- **Enhanced hardware support** via linux-firmware package

## 🔧 Post-Installation Usage

```bash
# Check ASUS controls status
asusctl -s

# View current power profile
asusctl profile

# Switch to performance mode
asusctl profile -P Performance

# Set battery charge limit to 80%
asusctl -c 80

# Control keyboard lighting
asusctl aura static --help

# Check GPU status
supergfxctl --status

# Switch to integrated graphics (power saving)
supergfxctl --mode Integrated

# Switch to hybrid graphics (performance)
supergfxctl --mode Hybrid

# Launch graphical control center
rog-control-center
```

**Important Notes:**
- GPU mode changes require reboot to take effect
- Some firmware updates may require reboot
- Nouveau blacklist requires reboot to disable nouveau driver

## 🗑️ Uninstallation

If you need to remove ASUS Linux tools completely:

### One-line Uninstallation
```bash
curl -sSL https://raw.githubusercontent.com/andreas-glaser/asus-linux-mint/v22.1.1/uninstall-asus-linux.sh | bash
```

### Manual Download and Uninstall
```bash
# Download the uninstall script
wget https://raw.githubusercontent.com/andreas-glaser/asus-linux-mint/v22.1.1/uninstall-asus-linux.sh

# Make it executable
chmod +x uninstall-asus-linux.sh

# Run the uninstaller
./uninstall-asus-linux.sh
```

### What Gets Removed
- All ASUS-specific binaries and services
- Configuration files and udev rules
- Desktop applications and icons
- Nouveau driver blacklist (optional)
- Build directories (optional)
- Rust toolchain (optional)

### What Gets Preserved
- System firmware updates (beneficial for all hardware)
- Linux kernel upgrades (improves overall system performance)
- System packages (linux-firmware, fwupd, build tools)
- User data and settings

## 🚨 Troubleshooting

### Common Issues

**GPU switching not working:**
- Ensure you've rebooted after installation
- Check: `sudo journalctl -u supergfxd`
- Verify NVIDIA drivers are properly installed

**Kernel too old:**
- The script will automatically detect and offer kernel upgrades
- Minimum kernel 6.1+ required for full ASUS hardware support
- Recommended kernel 6.11+ for latest features

**Service not starting:**
- Check service status: `sudo systemctl status asusd supergfxd`
- Restart services: `sudo systemctl restart asusd supergfxd`
- Check logs: `sudo journalctl -u asusd` or `sudo journalctl -u supergfxd`

**Firmware update issues:**
- Ensure internet connectivity during installation
- Some firmware updates require multiple reboots
- Check: `fwupdmgr get-devices` and `fwupdmgr get-updates`

## 🐛 Bug Reports

If you encounter issues, please provide:
- Linux Mint version (`cat /etc/linuxmint/info`)
- Kernel version (`uname -r`)
- ASUS laptop model (`sudo dmidecode -s system-product-name`)
- Installation logs and error messages
- Service status (`sudo systemctl status asusd supergfxd`)

## 📄 License

MIT License - see [LICENSE](LICENSE) file for details.

## 🙏 Credits

- [asusctl](https://gitlab.com/asus-linux/asusctl) by Luke Jones
- [supergfxctl](https://gitlab.com/asus-linux/supergfxctl) by Luke Jones
- [ASUS Linux community](https://asus-linux.org/)
- Linux Mint community for excellent hardware support

## 🔗 Links

- [Official ASUS Linux Documentation](https://asus-linux.org/)
- [asusctl GitLab Repository](https://gitlab.com/asus-linux/asusctl)
- [supergfxctl GitLab Repository](https://gitlab.com/asus-linux/supergfxctl)
- [Linux Mint Official Website](https://linuxmint.com/)
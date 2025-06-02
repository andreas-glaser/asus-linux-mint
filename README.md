# ASUS Linux Tools Installer for Linux Mint

An automated installation script for [asusctl](https://gitlab.com/asus-linux/asusctl) and [supergfxctl](https://gitlab.com/asus-linux/supergfxctl) on ASUS ROG/TUF laptops running **Linux Mint**.

## 🚀 Features

- **Automated installation** of latest asusctl and supergfxctl for Linux Mint
- **Proper systemd service configuration** 
- **Comprehensive error handling** with colored output
- **Linux Mint compatibility checks** (version, kernel, conflicting packages)
- **Complete verification** of installation
- **User-friendly status reporting**

## 📋 Requirements

- **Linux Mint 22.1+** (Cinnamon, MATE, or Xfce edition)
- **ASUS ROG/TUF laptop** with supported hardware
- Kernel version 6.1+ (recommended for best compatibility with Linux Mint)
- Internet connection for downloading dependencies
- Sudo privileges
- Rust toolchain will be automatically installed

## 🛠️ Installation

### One-line Installation (Recommended)
```bash
curl -sSL https://raw.githubusercontent.com/andreas-glaser/asus-linux-mint/v22.1.0/install-asus-linux.sh | bash
```

### Manual Download and Install
```bash
# Download the script
wget https://raw.githubusercontent.com/andreas-glaser/asus-linux-mint/v22.1.0/install-asus-linux.sh

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

## 🎮 What Gets Installed

### asusctl
- ASUS laptop hardware control (fans, LEDs, profiles)
- Power management and performance profiles
- Keyboard backlight and function key controls

### supergfxctl  
- GPU switching for hybrid graphics setups
- Modes: Integrated, Hybrid, VFIO
- Power saving and performance optimization

## 🔧 Post-Installation Usage

```bash
# Check ASUS controls status
asusctl -s

# Switch to integrated graphics (power saving)
supergfxctl --mode Integrated

# Switch to hybrid graphics (performance)
supergfxctl --mode Hybrid

# Check GPU status
supergfxctl --status
```

**Note:** GPU mode changes require reboot to take effect on Linux Mint.

## 🗑️ Uninstallation

If you need to remove ASUS Linux tools completely:

### Manual Download and Uninstall
```bash
# Download the uninstall script
wget https://raw.githubusercontent.com/andreas-glaser/asus-linux-mint/v22.1.0/uninstall-asus-linux.sh

# Make it executable
chmod +x uninstall-asus-linux.sh

# Run the uninstaller
./uninstall-asus-linux.sh

# Optional: Reboot System
```

The uninstall script will:
- Stop and disable all ASUS-related services
- Remove all binaries and configuration files
- Clean up desktop files and icons
- Optionally remove build directories and Rust toolchain
- Verify complete removal

## 🐛 Bug Reports for Linux Mint

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
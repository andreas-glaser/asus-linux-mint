# ASUS Linux Tools Installer for Linux Mint

An automated installer for [asusctl](https://github.com/OpenGamingCollective/asusctl) 6.3.11 - the latest published stable release as of August 9, 2026 - on supported ASUS ROG/TUF laptops. **Linux Mint 22.3 is the primary target**; Ubuntu 24.04 is a secondary compatibility target. The specialised [supergfxctl](https://gitlab.com/asus-linux/supergfxctl) daemon is available as an explicit opt-in.

## 🚀 Features

- **Pinned installation** of asusctl 6.3.11 with a hash-verified dependency lock
- **Optional system firmware updates** via fwupd
- **Kernel compatibility checking** without changing installed kernels
- **Build dependency installation** limited to packages used by the selected components
- **GPU mode handling** through ROG Control Center and the asus-shutdown service
- **Optional supergfxctl** for VFIO, eGPU, dGPU suspend, and monitoring workflows
- **Fail-fast error handling** with explicit verification
- **Linux Mint 22.3 support** and a narrowly checked Ubuntu 24.04 compatibility path
- **Guided uninstallation** of installer-managed files, including legacy cleanup
- **ASUS ROG/TUF controls** where supported by the laptop model, firmware, and kernel

## 📋 Requirements

- **Linux Mint 22.3** (Cinnamon, MATE, or Xfce edition; primary target) or **Ubuntu 24.04** (secondary target)
- **ASUS ROG/TUF laptop** with compatible hardware
- **Internet connection** for downloading dependencies
- **Sudo privileges** for system modifications

## 🧰 Kernel

- Linux Mint 22.3's supported HWE stack already supplies a modern signed kernel. This installer checks the running version and leaves kernel installation and updates to Mint's Update Manager.
- Upstream recommends staying on the latest supported kernel because ASUS driver work is ongoing. TDP/PPT controls using `asus-armoury` require Linux 6.19 or later, while optional supergfxctl requires Linux 6.1 or later. Available controls still depend on the exact laptop and firmware.

On Mint, review or install a newer supported HWE kernel in **Update Manager → View → Linux Kernels**. On Ubuntu, use its repository-supported kernel updates through **Software Updater**.

The complete pinned source and dependency build is tested in a clean Ubuntu 24.04 environment. Hardware/service validation is performed on Mint first, so Ubuntu is not claimed to have identical hardware coverage until that is tested on an installed Ubuntu system.

## 🛠️ Installation

### Review Then Install (Recommended)

```bash
curl --proto '=https' --tlsv1.2 -fLo install-asus-linux.sh \
  https://raw.githubusercontent.com/andreas-glaser/asus-linux-mint/main/install-asus-linux.sh
less install-asus-linux.sh
chmod +x install-asus-linux.sh
./install-asus-linux.sh
```

Reviewing the downloaded script is important because the installer uses `sudo` to add system services and hardware-control tools.

### Alternative Downloader

```bash
# Download the script
wget --https-only -O install-asus-linux.sh \
  https://raw.githubusercontent.com/andreas-glaser/asus-linux-mint/main/install-asus-linux.sh

# Make it executable
chmod +x install-asus-linux.sh

# Run the installer
./install-asus-linux.sh
```

### Custom Build Directory

For safe optional cleanup, a custom build directory must remain below your account's home directory.

```bash
# Use custom directory for build files
ASUS_BUILD_DIR="$HOME/.local/src/asus-linux-test" ./install-asus-linux.sh
```

### Optional: Install ROG Control Center (GUI)

By default, the installer includes `rog-control-center` (GUI).

```bash
# Skip the GUI (CLI + daemon only)
ASUS_INSTALL_ROG_GUI=0 ./install-asus-linux.sh
```

### Optional: Install supergfxctl

`supergfxctl` 5.2.7 (the latest published stable release as of August 9, 2026) is not installed by default. Its upstream documentation recommends it only for systems that cannot suspend the dGPU, VFIO passthrough, GPU monitoring, hotplug/eGPU, or similar specialised workflows.

```bash
ASUS_INSTALL_SUPERGFXCTL=1 ./install-asus-linux.sh
```

Existing `supergfxctl` installations are detected and left unchanged unless this option is enabled. Do not combine it with another GPU switcher.

### Optional: Update firmware

Firmware flashing is independent of asusctl and is disabled by default:

```bash
ASUS_UPDATE_FIRMWARE=1 ./install-asus-linux.sh
```

## 🔄 Updating

`update-asus-linux.sh` updates an existing installation to the latest **tagged release** of
[asusctl](https://github.com/OpenGamingCollective/asusctl).

Upstream publishes release tags but only ships Arch Linux binaries, so the script builds the
pinned tag from source, then wraps the result in a `.deb` and installs it with apt. dpkg
therefore owns the files, which gives you version tracking, clean upgrades, and rollback.

```bash
# See what's installed and what's available (changes nothing)
./update-asus-linux.sh --check

# Build and install the latest release
./update-asus-linux.sh

# Build a specific release
./update-asus-linux.sh --tag 6.3.10

# Go back to the previously installed version
./update-asus-linux.sh --rollback
```

### Already installed with `install-asus-linux.sh`?

**Run the updater directly. Do not uninstall first.** The first run converts your existing
file-based install into the `asusctl-ogc` package: it removes the leftovers that upstream has
since renamed, and dpkg takes ownership of the rest. Running `uninstall-asus-linux.sh` first
would offer to delete your `/etc/asusd` settings, the build directory and the Rust toolchain,
all of which the updater reuses.

After the conversion:

```bash
dpkg-query -W asusctl-ogc          # which version is installed
sudo apt remove asusctl-ogc        # remove everything the package owns
```

Your settings in `/etc/asusd` (fan curves, profiles, LED settings) are **not** part of the
package and survive upgrades and removal.

`uninstall-asus-linux.sh` detects which of the two layouts you have and removes it the right
way, so it is safe to use either before or after converting.

### Rolling back

`--rollback` reinstalls a `.deb` from the local cache, so it only works once the updater has
built at least one package. On your **first** update there is nothing cached yet; to go back to
a specific earlier release, rebuild it by tag:

```bash
./update-asus-linux.sh --tag 6.3.8

# Which release is the current install based on?
git -C ~/.local/src/asus-linux/asusctl describe --tags
```

### Optional: weekly update check

```bash
# Notifies when a new release appears; never builds or installs on its own
./update-asus-linux.sh --install-timer
./update-asus-linux.sh --remove-timer
```

> **Note:** the update still compiles asusctl from source, so it needs the Rust toolchain and
> build dependencies installed by `install-asus-linux.sh`, and it takes several minutes.

## 📦 What Gets Installed

### Core Components
- **asusctl** - Primary ASUS laptop control utility
- **asus-shutdown** - Safely applies queued GPU firmware settings during shutdown
- **rog-control-center** - GUI, including Integrated/Hybrid/Ultimate GPU modes
- **supergfxctl** - Optional specialised GPU management
- **Rust toolchain** - Latest stable toolchain managed by rustup, bootstrapped from Mint/Ubuntu's authenticated APT repository without changing an existing default toolchain
- **Build dependencies** - All required development packages

### System Configuration
- **systemd services** - asusd, asus-shutdown, and asusd-user; optionally supergfxd
- **udev rules** - Hardware detection and device permissions
- **DBus configuration** - Inter-process communication setup
- **Firmware updates** - Only when explicitly enabled
- **Kernel compatibility** - Verifies the running version without installing or replacing a kernel

### Hardware Features

Available features depend on the exact laptop model, firmware, and kernel. On supported hardware, asusctl can expose fan curves, Aura lighting, platform power profiles, GPU modes, and ASUS hotkeys.

The installer enables ROG Control Center's X11 build feature because Mint desktops commonly use X11. Upstream explicitly does not support X11-specific issues, so the daemon and CLI are the more reliable fallback if the GUI has a display-server problem.

## 🔧 Usage

### Basic Commands

```bash
# Show software, hardware, and supported controls
asusctl info --show-supported

# Switch GPU modes safely
# Open ROG Control Center and choose Integrated, Hybrid, or Ultimate.
# The change is queued and applied by asus-shutdown during shutdown/reboot.

# Inspect profiles and fan-curve availability
asusctl profile list
asusctl fan-curve --get-enabled

# Inspect the current keyboard brightness
asusctl leds get
```

### Service Management

```bash
# Check service status
sudo systemctl status asusd asus-shutdown

# Restart services if needed
sudo systemctl restart asusd asus-shutdown

# View service logs
sudo journalctl -u asusd.service -f
sudo journalctl -u asus-shutdown.service -f
```

## 🗑️ Uninstallation

### Review Then Uninstall (Recommended)

```bash
curl --proto '=https' --tlsv1.2 -fLo uninstall-asus-linux.sh \
  https://raw.githubusercontent.com/andreas-glaser/asus-linux-mint/main/uninstall-asus-linux.sh
less uninstall-asus-linux.sh
chmod +x uninstall-asus-linux.sh
./uninstall-asus-linux.sh
```

### Manual Uninstall

```bash
# Download the uninstall script
wget --https-only -O uninstall-asus-linux.sh \
  https://raw.githubusercontent.com/andreas-glaser/asus-linux-mint/main/uninstall-asus-linux.sh

# Make it executable
chmod +x uninstall-asus-linux.sh

# Run the uninstaller
./uninstall-asus-linux.sh
```

### What Gets Removed
- Installer-managed ASUS Linux tool binaries
- Installer-managed system services and integration files
- Desktop applications and icons
- Optional: legacy nouveau blacklist configuration created by older releases
- Optional: build directories

### What Gets Preserved
- System firmware updates
- Existing kernels
- System build packages
- Rust toolchain
- Existing group memberships and `/etc/asusd` settings unless their explicit removal is selected

## 🔐 Security and Maintenance

Upstream source revisions and dependency locks are pinned and verified before building, and CI checks weekly that the selected releases are still the latest published stable versions. RustSec found no known vulnerabilities in either lock on August 9, 2026. It did report maintenance warnings for four asusctl dependencies (`bincode`, `paste`, `rustybuzz`, and `ttf-parser`) and one optional supergfxctl dependency (`gumdrop`); those require upstream dependency changes and are not represented here as resolved vulnerabilities.

No installer can guarantee absolute security or compatibility across every firmware and laptop model. Firmware updates and supergfxctl therefore remain explicit opt-ins, and hardware testing should be performed with a working kernel available as a fallback.

## 🔍 Troubleshooting

### Common Issues

**Services not starting:**
```bash
# Check service logs
sudo journalctl -u asusd.service -n 50
sudo journalctl -u asus-shutdown.service -n 50

# Reload and restart
sudo systemctl daemon-reload
sudo systemctl restart asusd asus-shutdown
```

**GPU switching not working:**
```bash
# Check GPU status
lspci | grep -i vga

# Check the deferred GPU-mode service
sudo systemctl status asus-shutdown

# Reboot after GPU mode changes
sudo reboot
```

**Screen brightness is stuck dim or the slider does nothing (Cinnamon/X11):**
On some hybrid AMD/NVIDIA ASUS laptops, Cinnamon picks the NVIDIA firmware backlight (`nvidia_wmi_ec_backlight`) instead of the real panel backlight (`amdgpu_bl1`).

```bash
# Force Cinnamon to prefer the AMD raw backlight
gsettings set org.cinnamon.settings-daemon.plugins.power backlight-helper-force true
gsettings set org.cinnamon.settings-daemon.plugins.power backlight-helper-preference-order "['raw', 'platform', 'firmware']"
```

Log out and back in, or reboot. If it still fails after reboot, check `/sys/class/backlight/` and consider disabling `nvidia_wmi_ec_backlight` system-wide.

**Optional supergfxctl permission issues:**
```bash
# Its D-Bus policy accepts adm, sudo, users, or wheel.
id -nG
```

Mint administrator accounts normally already belong to `sudo` or `adm`. The installer does not broaden group membership automatically; if none of the accepted groups is present, review `/usr/share/dbus-1/system.d/org.supergfxctl.Daemon.conf` before making a manual permissions change.

**Build failures:**
```bash
# Rebuild in a fresh directory without deleting the previous checkout
ASUS_BUILD_DIR="$(mktemp -d)" ./install-asus-linux.sh

# Re-run after reviewing the first build error; the pinned checkout is preserved.
```

### Support Information

When reporting issues, please include:
- Distribution, version, and desktop edition
- ASUS laptop model
- Kernel version (`uname -r`)
- Graphics hardware (`lspci | grep -i vga`)
- Service status (`sudo systemctl status asusd asus-shutdown`)
- Installation logs and error messages

For more help, visit:
- [ASUS Linux Community](https://asus-linux.org/)
- [asusctl GitHub Issues](https://github.com/OpenGamingCollective/asusctl/issues)
- [supergfxctl GitLab Issues](https://gitlab.com/asus-linux/supergfxctl/-/issues)

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🤝 Contributing

Contributions are welcome! Please feel free to submit issues, feature requests, or pull requests.

## ⚠️ Disclaimer

This script modifies system configurations and installs software that may affect your system's stability. Use at your own risk. Always ensure you have backups before making system changes.

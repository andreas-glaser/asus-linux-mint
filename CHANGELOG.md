# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project follows Linux Mint release versioning with patch numbers.

## [Unreleased]

### Added
- `update-asus-linux.sh`: update an existing installation to the latest upstream release tag. The pinned tag is built from source, staged with upstream's own Makefile rules, wrapped in an `asusctl-ogc` `.deb` and installed with apt, so dpkg tracks the installed version, removes files dropped by upstream on upgrade, and makes rollback possible. Supports `--check`, `--tag`, `--rollback`, `--no-gui` and an optional notify-only weekly systemd timer (`--install-timer` / `--remove-timer`).
- `make-dpkg.sh`: shared Bash library (sourced by both `update-asus-linux.sh` and `install-asus-linux.sh --dpkg`) providing staging, dependency resolution, .deb metadata with maintainer scripts, build, install, stale-GUI warning, user-service enablement, and cache pruning.
- Installer: `--dpkg` flag that builds asusctl and installs it as the `asusctl-ogc` `.deb` package via apt, instead of raw file copy. Plain installer behavior is unchanged.
- Uninstaller: remove the user-level `asus-linux-update-check` timer and service if present.
- Uninstaller: warn when a running `rog-control-center` process is still on the previous binary after an update.
- README: "Updating" section covering the update, rollback and package-removal workflow.

### Changed
- Uninstaller: detect whether the installation is the `asusctl-ogc` package or an unmanaged file-based one. Packaged installs are removed with `apt remove` so dpkg's database stays consistent, with an optional prompt to clear the rollback package cache; unmanaged installs keep the previous file-by-file removal.
- Updater: do not enable or disable the static `asusd.service` (it is D-Bus activated and has no `[Install]` section).
- Updater: use `asusctl info` for status reporting instead of the unsupported `--version` flag.

### Fixed
- Updater: install `asusd-user.service` explicitly. Upstream declares `install-data-asusd_user` as `.PHONY` but gives it no recipe, so `make install` silently skips the user unit.
- Updater: `get_installed_version()` now checks the dpkg `Status` field for `install ok installed` instead of just the version string, so a residual `deinstall ok config-files` state (left by `apt remove` without `apt purge`) no longer causes a false "up to date" report.
- Installer `--dpkg`: explicitly start and enable `asusd.service` and `asus-shutdown.service` after `apt install`, because the postinst upgrade branch uses `try-restart` which is a no-op when services are stopped (e.g. after an uninstall+reinstall cycle).
- postinst: always run `systemctl enable asus-shutdown.service` before the fresh/upgrade branch, so the unit is enabled regardless of whether dpkg treats the install as fresh or an upgrade.
- Tests: mock `notify-send` to prevent real desktop notifications during test runs (D-Bus bypasses stdout redirection).

## [22.3.3] - 2026-08-09

### Added
- Installer: install and enable `asus-shutdown` from asusctl 6.3.11 so queued GPU firmware changes are applied during shutdown.
- Installer: add `ASUS_INSTALL_SUPERGFXCTL=1` for specialised VFIO, eGPU, dGPU suspend, and monitoring workflows; supergfxctl is disabled by default.
- Installer: add opt-in firmware updates through `ASUS_UPDATE_FIRMWARE=1`.
- Supply hash-verified Cargo dependency locks for the pinned asusctl and optional supergfxctl sources.
- Accept Ubuntu 24.04 as a narrowly versioned secondary compatibility target while keeping Mint 22.3 primary.

### Changed
- Pin asusctl to stable release 6.3.11 (`4d8a45b3`) and optional supergfxctl to stable release 5.2.7 (`a86383e1`) instead of building moving `main` branches.
- Treat Linux 6.19 as the minimum for `asus-armoury` TDP/PPT support and leave kernel management to Mint's signed HWE stack instead of installing kernels from this project.
- Preserve existing supergfxctl installations when the default asusctl-only path is selected.
- Use versioned source directories so a future stable upgrade cannot collide with an older release's dependency lock.
- Firmware flashing is now opt-in rather than part of every installation.
- Bootstrap rustup from the authenticated Mint/Ubuntu package repository, then select the latest stable Rust toolchain.
- Pin CI and release actions to the exact commits behind their latest stable releases.
- Refuse unvalidated distributions and releases instead of continuing with incompatible package and service assumptions.
- Verify the ASUS system vendor through DMI before making package or service changes.

### Fixed
- Install the current ROG Control Center desktop filename and AppStream metainfo file used by asusctl 6.3.11.
- Compare Mint and kernel versions with version-aware ordering instead of decimal arithmetic.
- Read interactive confirmations from the terminal so prompts remain usable when standard input is redirected.
- Retain legacy supergfxctl cleanup in the uninstaller for users upgrading from earlier releases.
- Normalize two asusctl unit directives for Mint's systemd 255 so unsupported settings are not silently ignored.
- Invoke binaries from the selected stable toolchain directly, avoiding Ubuntu rustup proxy failures in a clean environment.
- Restart already-running ASUS daemons after replacing their binaries so upgrades cannot leave an older process active.
- Use `apt-get`'s stable scripting interface for dependency installation.

### Security
- Constrain build directories to the invoking account's real home, reject symlinks, and refuse to overwrite source changes other than the exact installer-supplied lock on a rerun.
- Fetch and verify exact upstream commit IDs without trusting checkout-configured remotes.
- Stop unconditionally blacklisting Nouveau, purging distro Rust packages, running `apt autoremove`, or offering to remove shared group membership.
- Remove a legacy Nouveau blacklist only when it exactly matches content written by older releases.
- Remove documentation and installer guidance that executed downloaded Rust or kernel scripts through a shell pipeline.
- Remove mainline-kernel installation guidance now that Mint's signed HWE stack provides a sufficiently recent kernel.
- Stop installing the unrelated `linux-firmware` package as a build dependency.

### Thanks
- Thanks to @farfalk for proposing the supergfxctl default removal in PR #8.
- Thanks to @1-Archit-1 for identifying the current asusctl integration changes in PR #11.

## [22.3.2] - 2026-06-20

### Changed
- Installer: clone `asusctl` from its new home at `https://github.com/OpenGamingCollective/asusctl` (the project migrated from GitLab to the OpenGamingCollective on GitHub, where future development happens). `supergfxctl` remains on GitLab.
- README: point asusctl source and issue links to the OGC GitHub repository.
- CI: validate the asusctl source URL against its new GitHub home.

### Thanks
- Thanks to @farfalk for reporting the asusctl OGC migration in issue #6.

## [22.3.1] - 2026-05-20

### Added
- README: add troubleshooting guidance for Cinnamon/X11 screen brightness issues on hybrid AMD/NVIDIA ASUS laptops.
- Uninstaller: prompt to remove `/etc/asusd` runtime configuration directory (preserves user-customised fan curves, profiles, and LED settings by default).

### Fixed
- Installer: create `/etc/asusd` before starting `asusd.service` to prevent `status=226/NAMESPACE` failures on fresh installs. The upstream unit declares `ProtectSystem=strict` with `ReadWritePaths=/etc/asusd/`, so systemd refuses to set up the unit's mount namespace if the directory is missing.

### Thanks
- Thanks to @cyntalan for reporting the `asusd.service` start failure and tracking down the workaround in issue #5.

## [22.3.0] - 2026-01-15

### Added
- Target Linux Mint 22.3 (Zena) only.

### Changed
- Scripts: set minimum supported Mint to 22.3.
- README: update requirements and kernel section for Mint 22.3.

### Fixed
- Installer: post-install messages now correctly reflect whether `rog-control-center` GUI was installed.

## [22.2.2] - 2025-12-17

### Fixed
- Prevent `rog-control-center` build failures on fresh Mint installs by installing the required GUI dependencies (e.g. `libfontconfig1-dev`).
- Prevent `rog-control-center` panics on X11 sessions by building with X11 support enabled.
- Install `asusd.service` more reliably and improve service discovery when enabling units.

### Changed
- Installer: add core build deps `cmake` and `libssl-dev`.
- Installer: install `rog-control-center` by default; set `ASUS_INSTALL_ROG_GUI=0` to opt out.
in 
### Thanks
- Thanks to @NoonyaBeeznus for the detailed report and logs in issue #2.

## [22.2.1] - 2025-10-19

### Fixed
- Prevent the install script from re-running `cargo build` as root, avoiding git fetch failures for `slint` when network access is restricted.
- Limit privilege escalation to file installation so builds reuse the user environment and finish reliably.

## [22.2.0] - 2025-09-06

### Added
- Target Linux Mint 22.2 (Zara) only.

### Changed
- README: simplify kernel section to reflect Mint 22.2's default HWE kernel 6.14; keep optional mainline instructions.
- Scripts: set minimum supported Mint to 22.2; align kernel guidance to 6.14; correct HWE meta-packages to `linux-generic`/`linux-headers-generic`.
- CI: update release requirements text to "Linux Mint 22.2 (Zara)".

### Fixed
- Uninstall script header label and version alignment.

## [22.1.3] - 2025-07-16

### Added
- **Accurate kernel version guidance** distinguishing between HWE and mainline kernels
- **Mainline kernel installation instructions** for optimal ASUS support (6.12+)
- **Multi-tier kernel support documentation** (Basic 6.1+, Good 6.8+, Optimal 6.12+)
- **Helper functions** for HWE kernel installation and mainline kernel guidance
- **Comprehensive kernel installation options** with safety warnings

### Enhanced
- **Corrected kernel availability information** - HWE provides up to ~6.8, not 6.12+
- **Improved kernel detection logic** with realistic expectations for standard repositories
- **Better user guidance** on when to use HWE vs mainline kernels
- **Enhanced README structure** with expandable mainline installation section
- **More accurate installation prompts** based on what's actually available

### Fixed
- **Critical correction**: Kernel 6.12+ requires mainline installation, not available via HWE
- **Misleading kernel recommendations** that suggested 6.12+ was available through standard repos
- **Installation script promises** that couldn't be fulfilled with standard package managers

### Technical Improvements
- **ASUS WMI driver enhancements**: Better thermal profile initialization (6.12+ mainline)
- **Intel Lunar Lake performance**: ~22% improvement on ASUS laptops (6.12+ mainline)
- **ROG Ally support**: Enhanced suspend/resume functionality (6.12+ mainline)
- **Mini-LED support**: 2024 ROG laptop compatibility (6.12+ mainline)
- **GPU MUX switching**: Improved Vivobook series support (6.12+ mainline)
- **Realistic HWE benefits**: Up to kernel 6.8 through standard repositories

## [22.1.2] - 2025-01-28

### Added
- **System firmware updates** via fwupd for optimal hardware compatibility
- **Kernel compatibility checking** with automatic upgrade options for ASUS hardware support
- **NVIDIA driver preparation** with nouveau blacklist creation (`/etc/modprobe.d/blacklist-nouveau.conf`)
- **Enhanced dependency management** including linux-firmware package
- **Dynamic kernel version support** with configurable minimum and recommended versions
- **Improved uninstall process** with nouveau blacklist removal option
- **Comprehensive firmware update flow** with error handling and user feedback
- **Hardware Enablement (HWE) kernel installation** for better ASUS laptop support

### Enhanced
- Installation process now includes firmware updates for BIOS, EC, and device compatibility
- Better kernel version management with automatic upgrade suggestions
- Improved error handling for firmware update scenarios
- Enhanced documentation with troubleshooting sections
- Updated README with comprehensive feature list and usage examples

### Fixed
- Added missing essential dependencies for optimal hardware support
- Improved service configuration reliability
- Better handling of edge cases in firmware update process

## [22.1.1] - 2025-01-28

### Added
- GitHub Actions CI/CD workflows for automated testing and releases
- Shell script linting with ShellCheck
- Multi-distribution testing (Ubuntu 22.04, 24.04, Debian 12)  
- External dependency validation
- Security scanning for potential vulnerabilities
- Documentation validation
- Automated release creation with checksums

## [22.1.0] - 2025-01-28

### Added
- Initial release for Linux Mint 22.1 "Xia"
- Complete installation script for asusctl and supergfxctl
- Comprehensive uninstall script for clean removal
- Professional error handling and user feedback
- System compatibility checks and verification 

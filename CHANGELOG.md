# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project follows Linux Mint release versioning with patch numbers.

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
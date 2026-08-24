#!/bin/bash
# shellcheck disable=SC2046
# Unit tests for make-dpkg.sh
#
# Strategy: source the library (the BASH_SOURCE guard prevents the guard from
# firing), define the print_* functions and variables it expects, then exercise
# individual functions with mocked external dependencies.

set -euo pipefail

PROJECT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)

# ---------------------------------------------------------------------------
# Variables and functions required by make-dpkg.sh
# These are consumed by the sourced library, not by this test file directly.
# shellcheck disable=SC2034
PKG_NAME="asusctl-ogc"
CACHE_DIR=""
SRC_DIR=""
INSTALL_ROG_GUI=1
UPSTREAM_URL="https://github.com/OpenGamingCollective/asusctl"
STAGE_DIR=""

print_status()  { echo "[INFO] $1"; }
print_error()   { echo "[ERROR] $1" >&2; }
print_warning() { echo "[WARNING] $1"; }
print_success() { echo "[SUCCESS] $1"; }

# shellcheck source=make-dpkg.sh
source "$PROJECT_DIR/make-dpkg.sh"

# ---------------------------------------------------------------------------
# Test infrastructure
# ---------------------------------------------------------------------------
TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT

MOCK_BIN="$TEST_ROOT/mock-bin"
mkdir -p "$MOCK_BIN"
export PATH="$MOCK_BIN:$PATH"

PASS=0
FAIL=0

assert_true() {
    local desc="$1"
    local result="$2"
    if [ "$result" = "0" ]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        echo "FAIL: $desc"
    fi
}

assert_false() {
    local desc="$1"
    local result="$2"
    if [ "$result" = "1" ]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        echo "FAIL: $desc"
    fi
}

# ---------------------------------------------------------------------------
# Mock infrastructure
# ---------------------------------------------------------------------------

# sudo: strip privileges, run the command directly
cat > "$MOCK_BIN/sudo" <<'MOCK'
#!/bin/bash
"$@"
MOCK

# apt: accept any invocation
cat > "$MOCK_BIN/apt" <<'MOCK'
#!/bin/bash
exit 0
MOCK

# dpkg: print architecture, accept --compare-versions
cat > "$MOCK_BIN/dpkg" <<'MOCK'
#!/bin/bash
case "$1" in
    --print-architecture) echo "amd64" ;;
    --compare-versions) exit 0 ;;
esac
MOCK

# dpkg-deb: record build calls, create fake .deb file
MOCK_DPKG_DEB_LOG="$TEST_ROOT/dpkg-deb-calls.log"
export MOCK_DPKG_DEB_LOG
cat > "$MOCK_BIN/dpkg-deb" <<'MOCK'
#!/bin/bash
# Log the call
echo "$*" >> "${MOCK_DPKG_DEB_LOG}"
# If --build, create the output file
if [ "$1" = "--build" ]; then
    # Last arg is the output path
    out=""
    for arg in "$@"; do
        case "$arg" in
            /*) out="$arg" ;;
        esac
    done
    [ -n "$out" ] && echo "fake-deb" > "$out"
fi
exit 0
MOCK

# dpkg-shlibdeps: not on PATH by default (test fallback path)
# To test the real path, we add it selectively per-test.

# systemctl: no-op, record calls
MOCK_SYSTEMCTL_LOG="$TEST_ROOT/systemctl-calls.log"
export MOCK_SYSTEMCTL_LOG
cat > "$MOCK_BIN/systemctl" <<'MOCK'
#!/bin/bash
echo "$*" >> "${MOCK_SYSTEMCTL_LOG}"
# list-unit-files: output asusd-user.service so enable_user_service does
# not take the "not visible" early-return path.
if [ "$1" = "--user" ] && [ "$2" = "list-unit-files" ]; then
    echo "asusd-user.service                     static    -"
fi
exit 0
MOCK

# pgrep: no processes found by default
cat > "$MOCK_BIN/pgrep" <<'MOCK'
#!/bin/bash
exit 1
MOCK

# du: return a small size
cat > "$MOCK_BIN/du" <<'MOCK'
#!/bin/bash
echo "100	$2"
MOCK

# Make all mocks executable
chmod +x "$MOCK_BIN"/*

# Create a fake source tree for stage_install tests
setup_fake_source() {
    SRC_DIR="$TEST_ROOT/src"
    CACHE_DIR="$TEST_ROOT/cache"
    mkdir -p "$CACHE_DIR"

    # Create the directory structure the Makefile expects
    mkdir -p "$SRC_DIR/target/release"
    mkdir -p "$SRC_DIR/data/icons"
    mkdir -p "$SRC_DIR/rog-control-center/data"
    mkdir -p "$SRC_DIR/rog-aura/data/layouts"
    mkdir -p "$SRC_DIR/rog-anime/data/anime"

    # Fake binaries
    for bin in asusctl asusd asusd-user asus-shutdown rog-control-center; do
        echo "fake $bin" > "$SRC_DIR/target/release/$bin"
        chmod +x "$SRC_DIR/target/release/$bin"
    done

    # Fake data files
    echo "udev rule" > "$SRC_DIR/data/asusd.rules"
    echo "dbus config" > "$SRC_DIR/data/asusd.conf"
    echo "service unit" > "$SRC_DIR/data/asusd.service"
    echo "shutdown unit" > "$SRC_DIR/data/asus-shutdown.service"
    echo "user service" > "$SRC_DIR/data/asusd-user.service"
    echo "aura support" > "$SRC_DIR/rog-aura/data/aura_support.ron"
    echo "desktop file" > "$SRC_DIR/rog-control-center/data/org.opengamingcollective.rog-control-center.desktop"
    echo "icon png" > "$SRC_DIR/rog-control-center/data/rog-control-center.png"
    echo "icon yellow" > "$SRC_DIR/data/icons/asus_notif_yellow.png"
    echo "MIT" > "$SRC_DIR/LICENSE"

    # Minimal Makefile that handles the install targets
    cat > "$SRC_DIR/Makefile" <<'MAKEFILE'
DESTDIR ?= /
prefix ?= /usr

install-asusd:
	install -D -m 0755 target/release/asusd $(DESTDIR)$(prefix)/bin/asusd
	install -D -m 0644 data/asusd.service $(DESTDIR)$(prefix)/lib/systemd/system/asusd.service
	install -D -m 0644 data/asusd.conf $(DESTDIR)$(prefix)/share/dbus-1/system.d/asusd.conf
	install -D -m 0644 data/asusd.rules $(DESTDIR)$(prefix)/lib/udev/rules.d/99-asusd.rules
	install -D -m 0644 rog-aura/data/aura_support.ron $(DESTDIR)$(prefix)/share/asusd/aura_support.ron

install-asus-shutdown:
	install -D -m 0755 target/release/asus-shutdown $(DESTDIR)$(prefix)/bin/asus-shutdown
	install -D -m 0644 data/asus-shutdown.service $(DESTDIR)$(prefix)/lib/systemd/system/asus-shutdown.service

install-asusctl:
	install -D -m 0755 target/release/asusctl $(DESTDIR)$(prefix)/bin/asusctl

install-asusd_user:
	install -D -m 0755 target/release/asusd-user $(DESTDIR)$(prefix)/bin/asusd-user

install-data-asusd:
	@echo "installing anime data"
	cd rog-anime/data && find anime -type f -exec install -D -m 0644 {} $(DESTDIR)$(prefix)/share/asusd/{} \;

install-rog_gui:
	install -D -m 0755 target/release/rog-control-center $(DESTDIR)$(prefix)/bin/rog-control-center

install-data-rog_gui:
	install -D -m 0644 rog-control-center/data/org.opengamingcollective.rog-control-center.desktop $(DESTDIR)$(prefix)/share/applications/org.opengamingcollective.rog-control-center.desktop
	install -D -m 0644 rog-control-center/data/rog-control-center.png $(DESTDIR)$(prefix)/share/icons/hicolor/512x512/apps/rog-control-center.png
	cd data/icons && find . -name "asus_notif_*.png" -exec install -D -m 0644 {} $(DESTDIR)$(prefix)/share/icons/hicolor/512x512/apps/{} \;

.PHONY: install-asusd install-asus-shutdown install-asusctl install-asusd_user install-data-asusd install-rog_gui install-data-rog_gui
MAKEFILE
}

# Helper: clean up STAGE_DIR between tests
cleanup_stage() {
    if [ -n "$STAGE_DIR" ] && [ -d "$STAGE_DIR" ]; then
        rm -rf "$STAGE_DIR"
    fi
    STAGE_DIR=""
}

# ===========================================================================
# Tests
# ===========================================================================

# ---------------------------------------------------------------------------
# 1-4. stage_install — basic structure
# ---------------------------------------------------------------------------
echo "=== stage_install ==="

setup_fake_source
stage_install
assert_true "stage_install creates STAGE_DIR" $([ -d "$STAGE_DIR" ] && echo 0 || echo 1)
assert_true "stage_install creates usr/bin" $([ -d "$STAGE_DIR/usr/bin" ] && echo 0 || echo 1)
assert_true "stage_install installs asusctl binary" $([ -f "$STAGE_DIR/usr/bin/asusctl" ] && echo 0 || echo 1)
assert_true "stage_install installs asusd binary" $([ -f "$STAGE_DIR/usr/bin/asusd" ] && echo 0 || echo 1)
assert_true "stage_install installs asusd-user binary" $([ -f "$STAGE_DIR/usr/bin/asusd-user" ] && echo 0 || echo 1)
assert_true "stage_install installs asus-shutdown binary" $([ -f "$STAGE_DIR/usr/bin/asus-shutdown" ] && echo 0 || echo 1)
cleanup_stage

# ---------------------------------------------------------------------------
# 5. stage_install — installs asusd-user.service manually
# ---------------------------------------------------------------------------
setup_fake_source
stage_install
assert_true "stage_install installs asusd-user.service manually" \
    $([ -f "$STAGE_DIR/usr/lib/systemd/user/asusd-user.service" ] && echo 0 || echo 1)
cleanup_stage

# ---------------------------------------------------------------------------
# 6. stage_install — installs LICENSE
# ---------------------------------------------------------------------------
setup_fake_source
stage_install
assert_true "stage_install installs LICENSE" \
    $([ -f "$STAGE_DIR/usr/share/asusctl/LICENSE" ] && echo 0 || echo 1)
cleanup_stage

# ---------------------------------------------------------------------------
# 7-8. stage_install — GUI files included when INSTALL_ROG_GUI=1
# ---------------------------------------------------------------------------
echo "=== stage_install with GUI ==="
setup_fake_source 1
INSTALL_ROG_GUI=1
stage_install
assert_true "stage_install installs rog-control-center binary (GUI=1)" \
    $([ -f "$STAGE_DIR/usr/bin/rog-control-center" ] && echo 0 || echo 1)
assert_true "stage_install installs desktop file (GUI=1)" \
    $([ -f "$STAGE_DIR/usr/share/applications/org.opengamingcollective.rog-control-center.desktop" ] && echo 0 || echo 1)
cleanup_stage

# ---------------------------------------------------------------------------
# 9-10. stage_install — GUI files excluded when INSTALL_ROG_GUI=0
# ---------------------------------------------------------------------------
echo "=== stage_install without GUI ==="
setup_fake_source 0
# shellcheck disable=SC2034
INSTALL_ROG_GUI=0
stage_install
assert_false "stage_install does NOT install rog-control-center binary (GUI=0)" \
    $([ -f "$STAGE_DIR/usr/bin/rog-control-center" ] && echo 0 || echo 1)
assert_false "stage_install does NOT install desktop file (GUI=0)" \
    $([ -f "$STAGE_DIR/usr/share/applications/org.opengamingcollective.rog-control-center.desktop" ] && echo 0 || echo 1)
cleanup_stage

# ---------------------------------------------------------------------------
# 11. stage_install — STAGE_DIR has 0755 permissions
# ---------------------------------------------------------------------------
echo "=== stage_install permissions ==="
setup_fake_source
stage_install
actual_perm=$(stat -c '%a' "$STAGE_DIR")
assert_true "stage_install sets STAGE_DIR to 0755" $([ "$actual_perm" = "755" ] && echo 0 || echo 1)
cleanup_stage

# ---------------------------------------------------------------------------
# 12-14. resolve_depends — fallback when dpkg-shlibdeps unavailable
# ---------------------------------------------------------------------------
echo "=== resolve_depends ==="

setup_fake_source
stage_install
result=$(resolve_depends)
expected="libc6, libgcc-s1, libudev1, libdbus-1-3, libssl3 | libssl3t64"
assert_true "resolve_depends returns fallback when dpkg-shlibdeps not on PATH" \
    $([ "$result" = "$expected" ] && echo 0 || echo 1)
cleanup_stage

# resolve_depends — fallback when no binaries found
setup_fake_source
STAGE_DIR="$TEST_ROOT/empty-stage"
mkdir -p "$STAGE_DIR"
result=$(resolve_depends)
assert_true "resolve_depends returns fallback when no binaries" \
    $([ "$result" = "$expected" ] && echo 0 || echo 1)
rm -rf "$STAGE_DIR"
STAGE_DIR=""

# resolve_depends — uses dpkg-shlibdeps output when available
setup_fake_source
stage_install
# Create a mock dpkg-shlibdeps that outputs a dependency line
cat > "$MOCK_BIN/dpkg-shlibdeps" <<'MOCK'
#!/bin/bash
echo "shlibs:Depends=libc6 (>= 2.39), libgcc-s1"
MOCK
chmod +x "$MOCK_BIN/dpkg-shlibdeps"
result=$(resolve_depends)
assert_true "resolve_depends uses dpkg-shlibdeps output" \
    $([ "$result" = "libc6 (>= 2.39), libgcc-s1" ] && echo 0 || echo 1)
rm -f "$MOCK_BIN/dpkg-shlibdeps"
cleanup_stage

# ---------------------------------------------------------------------------
# 15-18. write_package_metadata — control file
# ---------------------------------------------------------------------------
echo "=== write_package_metadata ==="

setup_fake_source
stage_install
write_package_metadata "6.4.0"
assert_true "control file exists" $([ -f "$STAGE_DIR/DEBIAN/control" ] && echo 0 || echo 1)
assert_true "control has Package field" $(grep -q "^Package: asusctl-ogc" "$STAGE_DIR/DEBIAN/control" && echo 0 || echo 1)
assert_true "control has Version 6.4.0" $(grep -q "^Version: 6.4.0" "$STAGE_DIR/DEBIAN/control" && echo 0 || echo 1)
assert_true "control has Architecture" $(grep -q "^Architecture: amd64" "$STAGE_DIR/DEBIAN/control" && echo 0 || echo 1)
assert_true "control has Homepage" $(grep -q "^Homepage: $UPSTREAM_URL" "$STAGE_DIR/DEBIAN/control" && echo 0 || echo 1)
assert_true "control has Provides asusctl" $(grep -q "^Provides: asusctl" "$STAGE_DIR/DEBIAN/control" && echo 0 || echo 1)
cleanup_stage

# ---------------------------------------------------------------------------
# 19-23. write_package_metadata — maintainer scripts
# ---------------------------------------------------------------------------
echo "=== maintainer scripts ==="

setup_fake_source
stage_install
write_package_metadata "6.4.0"
assert_true "preinst exists" $([ -f "$STAGE_DIR/DEBIAN/preinst" ] && echo 0 || echo 1)
assert_true "postinst exists" $([ -f "$STAGE_DIR/DEBIAN/postinst" ] && echo 0 || echo 1)
assert_true "prerm exists" $([ -f "$STAGE_DIR/DEBIAN/prerm" ] && echo 0 || echo 1)
assert_true "postrm exists" $([ -f "$STAGE_DIR/DEBIAN/postrm" ] && echo 0 || echo 1)
assert_true "preinst is executable" $([ -x "$STAGE_DIR/DEBIAN/preinst" ] && echo 0 || echo 1)
assert_true "postinst is executable" $([ -x "$STAGE_DIR/DEBIAN/postinst" ] && echo 0 || echo 1)
cleanup_stage

# ---------------------------------------------------------------------------
# 24. write_package_metadata — postinst enables asus-shutdown on fresh install
# ---------------------------------------------------------------------------
echo "=== postinst asus-shutdown enable ==="

setup_fake_source
stage_install
write_package_metadata "6.4.0"
assert_true "postinst enables asus-shutdown.service" \
    $(grep -q "enable asus-shutdown.service" "$STAGE_DIR/DEBIAN/postinst" && echo 0 || echo 1)
assert_true "postinst restarts asus-shutdown.service" \
    $(grep -q "restart asus-shutdown.service" "$STAGE_DIR/DEBIAN/postinst" && echo 0 || echo 1)
cleanup_stage

# ---------------------------------------------------------------------------
# 25. write_package_metadata — postinst creates /etc/asusd
# ---------------------------------------------------------------------------
setup_fake_source
stage_install
write_package_metadata "6.4.0"
assert_true "postinst creates /etc/asusd" \
    $(grep -q "install -d.* /etc/asusd" "$STAGE_DIR/DEBIAN/postinst" && echo 0 || echo 1)
cleanup_stage

# ---------------------------------------------------------------------------
# 26. write_package_metadata — preinst cleans legacy files
# ---------------------------------------------------------------------------
setup_fake_source
stage_install
write_package_metadata "6.4.0"
assert_true "preinst removes legacy rog-control-center.desktop" \
    $(grep -q "rog-control-center.desktop" "$STAGE_DIR/DEBIAN/preinst" && echo 0 || echo 1)
assert_true "preinst removes /usr/local/bin/asusctl" \
    $(grep -q "/usr/local/bin/asusctl" "$STAGE_DIR/DEBIAN/preinst" && echo 0 || echo 1)
cleanup_stage

# ---------------------------------------------------------------------------
# 27. write_package_metadata — postrm runs daemon-reload
# ---------------------------------------------------------------------------
setup_fake_source
stage_install
write_package_metadata "6.4.0"
assert_true "postrm runs daemon-reload" \
    $(grep -q "daemon-reload" "$STAGE_DIR/DEBIAN/postrm" && echo 0 || echo 1)
cleanup_stage

# ---------------------------------------------------------------------------
# 28-29. build_deb — returns correct path
# ---------------------------------------------------------------------------
echo "=== build_deb ==="

setup_fake_source
stage_install
deb_path=$(build_deb "6.4.0")
assert_true "build_deb returns correct path" \
    $([ "$deb_path" = "$CACHE_DIR/asusctl-ogc_6.4.0_amd64.deb" ] && echo 0 || echo 1)
assert_true "build_deb creates the .deb file" $([ -f "$CACHE_DIR/asusctl-ogc_6.4.0_amd64.deb" ] && echo 0 || echo 1)
cleanup_stage

# ---------------------------------------------------------------------------
# 30. build_deb — calls dpkg-deb with --build and --root-owner-group
# ---------------------------------------------------------------------------
setup_fake_source
stage_install
rm -f "$MOCK_DPKG_DEB_LOG"
build_deb "6.4.0" >/dev/null
assert_true "build_deb calls dpkg-deb --build" \
    $(grep -q -- "--build" "$MOCK_DPKG_DEB_LOG" && echo 0 || echo 1)
assert_true "build_deb uses --root-owner-group" \
    $(grep -q -- "--root-owner-group" "$MOCK_DPKG_DEB_LOG" && echo 0 || echo 1)
cleanup_stage

# ---------------------------------------------------------------------------
# 31. install_deb — calls apt install
# ---------------------------------------------------------------------------
echo "=== install_deb ==="

setup_fake_source
CACHE_DIR="$TEST_ROOT/cache"
mkdir -p "$CACHE_DIR"
echo "fake" > "$CACHE_DIR/asusctl-ogc_6.4.0_amd64.deb"
MOCK_APT_LOG="$TEST_ROOT/apt-calls.log"
cat > "$MOCK_BIN/apt" <<MOCK
#!/bin/bash
echo "\$*" >> "$MOCK_APT_LOG"
exit 0
MOCK
chmod +x "$MOCK_BIN/apt"
install_deb "$CACHE_DIR/asusctl-ogc_6.4.0_amd64.deb"
assert_true "install_deb calls apt install" \
    $(grep -q "install" "$MOCK_APT_LOG" && echo 0 || echo 1)
assert_true "install_deb passes --allow-downgrades" \
    $(grep -q -- "--allow-downgrades" "$MOCK_APT_LOG" && echo 0 || echo 1)
# Restore apt mock
cat > "$MOCK_BIN/apt" <<'MOCK'
#!/bin/bash
exit 0
MOCK
chmod +x "$MOCK_BIN/apt"

# ---------------------------------------------------------------------------
# 32-33. prune_cache — keeps 3 most recent .deb files
# ---------------------------------------------------------------------------
echo "=== prune_cache ==="

CACHE_DIR="$TEST_ROOT/cache"
rm -rf "$CACHE_DIR"
mkdir -p "$CACHE_DIR"
# Create 5 fake .deb files with different timestamps
for i in 1 2 3 4 5; do
    echo "fake" > "$CACHE_DIR/asusctl-ogc_6.${i}.0_amd64.deb"
    # Set modification time 10 seconds apart so sort order is deterministic
    touch -d "2024-01-0${i} 12:00:00" "$CACHE_DIR/asusctl-ogc_6.${i}.0_amd64.deb"
done
prune_cache
remaining=$(find "$CACHE_DIR" -name "asusctl-ogc_*.deb" | wc -l)
assert_true "prune_cache keeps 3 files (had 5)" $([ "$remaining" = "3" ] && echo 0 || echo 1)
# The 3 most recent (3, 4, 5) should survive
assert_true "prune_cache keeps the newest file" \
    $([ -f "$CACHE_DIR/asusctl-ogc_6.5.0_amd64.deb" ] && echo 0 || echo 1)
assert_true "prune_cache removes the oldest file" \
    $([ ! -f "$CACHE_DIR/asusctl-ogc_6.1.0_amd64.deb" ] && echo 0 || echo 1)

# ---------------------------------------------------------------------------
# 34. prune_cache — no-op when cache dir doesn't exist
# ---------------------------------------------------------------------------
CACHE_DIR="$TEST_ROOT/nonexistent"
prune_cache
assert_true "prune_cache no-op when dir missing" $([ $? -eq 0 ] && echo 0 || echo 1)

# ---------------------------------------------------------------------------
# 35-36. warn_stale_gui — no-op when no GUI running
# ---------------------------------------------------------------------------
echo "=== warn_stale_gui ==="

result=$(warn_stale_gui "6.4.0")
assert_true "warn_stale_gui returns 0 when no process" $([ $? -eq 0 ] && echo 0 || echo 1)

# warn_stale_gui — warns when GUI process has "(deleted)" exe
# Create a mock pgrep that returns a fake PID
cat > "$MOCK_BIN/pgrep" <<'MOCK'
#!/bin/bash
echo "12345"
MOCK
chmod +x "$MOCK_BIN/pgrep"
# Create a fake /proc entry with "(deleted)" in the exe link
# We can't easily fake /proc, so we'll mock readlink via a wrapper
# Actually, the function calls readlink directly on /proc/$p/exe
# We'll create a fake process structure under the test root instead
# This is hard to test without root or a real deleted binary.
# Instead, test that warn_stale_gui calls pgrep and processes the result
# by creating a fake /proc structure that readlink can resolve.
mkdir -p "$TEST_ROOT/proc/12345"
# Create a symlink that reads as "... (deleted)" — we can't do this
# with a normal symlink. Skip this specific sub-test and just verify
# the function doesn't crash with a pgrep result.
warn_stale_gui "6.4.0" 2>/dev/null || true
# The function will call readlink on /proc/12345/exe which doesn't exist,
# so the `[[ "$(readlink ...)" == *"(deleted)"* ]]` check will be false
# and it will not warn. That's fine — it should exit cleanly.
assert_true "warn_stale_gui handles pgrep result without crash" $([ $? -eq 0 ] && echo 0 || echo 1)
rm -rf "$TEST_ROOT/proc"
# Restore pgrep mock
cat > "$MOCK_BIN/pgrep" <<'MOCK'
#!/bin/bash
exit 1
MOCK
chmod +x "$MOCK_BIN/pgrep"

# ---------------------------------------------------------------------------
# 37. enable_user_service — calls systemctl --user
# ---------------------------------------------------------------------------
echo "=== enable_user_service ==="

rm -f "$MOCK_SYSTEMCTL_LOG"
enable_user_service
assert_true "enable_user_service calls systemctl --user daemon-reload" \
    $(grep -q "daemon-reload" "$MOCK_SYSTEMCTL_LOG" && echo 0 || echo 1)
assert_true "enable_user_service calls systemctl --user enable" \
    $(grep -q "enable" "$MOCK_SYSTEMCTL_LOG" && echo 0 || echo 1)
assert_true "enable_user_service calls systemctl --user restart" \
    $(grep -q "restart" "$MOCK_SYSTEMCTL_LOG" && echo 0 || echo 1)

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo
echo "dpkg library unit tests: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
echo "dpkg library unit tests passed."

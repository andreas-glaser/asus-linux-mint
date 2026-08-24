#!/bin/bash

# Unit tests for update-asus-linux.sh
#
# Strategy: source the script (the BASH_SOURCE guard prevents main from
# running), then exercise individual functions with mocked external
# dependencies. Mocks are shell scripts placed in a temp bin/ dir prepended
# to PATH. Each test saves and restores the globals it modifies.

set -euo pipefail

PROJECT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)

# shellcheck disable=SC1091
source "$PROJECT_DIR/update-asus-linux.sh"

# Replace the cleanup EXIT trap set by the sourced script with our own.
TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT

# ---------------------------------------------------------------------------
# Mock infrastructure
# ---------------------------------------------------------------------------
MOCK_BIN="$TEST_ROOT/mock-bin"
mkdir -p "$MOCK_BIN"

# sudo: strip privileges, run the command directly
cat > "$MOCK_BIN/sudo" <<'MOCK'
#!/bin/bash
"$@"
MOCK

# apt: accept any invocation (install, remove, etc.)
cat > "$MOCK_BIN/apt" <<'MOCK'
#!/bin/bash
exit 0
MOCK

# dpkg-query: simulate dpkg's Status+Version output.
# MOCK_INSTALLED_VERSION: version string (empty = not in dpkg at all)
# MOCK_INSTALLED_STATUS: dpkg status (default: "install ok installed")
#   Set to "deinstall ok config-files" to simulate apt-remove-without-purge.
export MOCK_INSTALLED_VERSION=""
export MOCK_INSTALLED_STATUS=""
cat > "$MOCK_BIN/dpkg-query" <<'MOCK'
#!/bin/bash
# Extract the -f format string (handles both -f VAL and -f=VAL forms)
fmt=""
while [ $# -gt 0 ]; do
    case "$1" in
        -f)  fmt="$2"; shift 2 ;;
        -f=*) fmt="${1#-f=}"; shift ;;
        -W)  shift ;;
        *)   shift ;;
    esac
done
if [ -n "${MOCK_INSTALLED_VERSION:-}" ]; then
    status="${MOCK_INSTALLED_STATUS:-install ok installed}"
    case "$fmt" in
        *Status*Version*) echo "$status ${MOCK_INSTALLED_VERSION}" ;;
        *Status*)         echo "$status" ;;
        *)                echo "${MOCK_INSTALLED_VERSION}" ;;
    esac
    exit 0
fi
exit 1
MOCK

# dpkg-deb: extract version from the .deb filename for -f queries
cat > "$MOCK_BIN/dpkg-deb" <<'MOCK'
#!/bin/bash
if [ "$1" = "-f" ] && [ "$3" = "Version" ]; then
    basename "$2" | sed -n 's/^asusctl-ogc_\([^_]*\)_.*/\1/p'
fi
MOCK

# systemctl: no-op (user and system calls)
cat > "$MOCK_BIN/systemctl" <<'MOCK'
#!/bin/bash
exit 0
MOCK

# notify-send: suppress real desktop notifications during tests
cat > "$MOCK_BIN/notify-send" <<'MOCK'
#!/bin/bash
exit 0
MOCK

chmod +x "$MOCK_BIN"/*
export PATH="$MOCK_BIN:$PATH"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
fail() {
    echo "FAIL: $1" >&2
    exit 1
}

assert_true() {
    local message="$1"
    shift
    "$@" || fail "$message"
}

assert_false() {
    local message="$1"
    shift
    if "$@"; then
        fail "$message"
    fi
}

reset_globals() {
    MODE="update"
    REQUESTED_TAG=""
    ASSUME_YES=0
    NOTIFY=0
    INSTALL_ROG_GUI=1
    STAGE_DIR=""
}

# Local git repo with mixed tags for get_latest_tag tests
setup_test_repo() {
    local work="$TEST_ROOT/asusctl-work"
    local bare="$TEST_ROOT/asusctl-bare"

    git init --quiet "$work"
    git -C "$work" config user.name "Test"
    git -C "$work" config user.email "test@example.invalid"
    touch "$work/file"
    git -C "$work" add file
    git -C "$work" commit --quiet -m "init"

    for tag in 6.3.8 6.3.10 6.4.0 v1.0.0 v2.0.1; do
        git -C "$work" tag "$tag"
    done

    git init --quiet --bare "$bare"
    local branch
    branch=$(git -C "$work" symbolic-ref --short HEAD)
    git -C "$work" remote add origin "$bare"
    git -C "$work" push --quiet origin "$branch" --tags

    echo "$bare"
}

# ---------------------------------------------------------------------------
# 1. Script constants
# ---------------------------------------------------------------------------
[[ "$SCRIPT_VERSION" == "22.3.2" ]] || fail "unexpected update script version"
[[ "$PKG_NAME" == "asusctl-ogc" ]] || fail "unexpected package name"
[[ "$CACHE_DIR" == "/var/cache/asus-linux-mint" ]] || fail "unexpected cache directory"
[[ "$UPSTREAM_REPO" == *"asusctl.git" ]] || fail "unexpected upstream repo URL"

# ---------------------------------------------------------------------------
# 2. Usage output contains all documented options
# ---------------------------------------------------------------------------
usage_text=$(usage 2>&1)
for opt in --check --tag --rollback --no-gui --yes --notify --install-timer --remove-timer --help; do
    echo "$usage_text" | grep -qF -- "$opt" || fail "usage missing option $opt"
done

# ---------------------------------------------------------------------------
# 3-10. parse_args
# ---------------------------------------------------------------------------
reset_globals
parse_args --check
[[ "$MODE" == "check" ]] || fail "--check did not set MODE=check"

reset_globals
parse_args --tag 6.3.10
[[ "$REQUESTED_TAG" == "6.3.10" ]] || fail "--tag did not set REQUESTED_TAG"

reset_globals
parse_args --rollback --no-gui --yes
[[ "$MODE" == "rollback" ]] || fail "--rollback did not set MODE"
[[ "$INSTALL_ROG_GUI" -eq 0 ]] || fail "--no-gui did not clear INSTALL_ROG_GUI"
[[ "$ASSUME_YES" -eq 1 ]] || fail "--yes did not set ASSUME_YES"

reset_globals
parse_args --notify
[[ "$NOTIFY" -eq 1 ]] || fail "--notify did not set NOTIFY"

reset_globals
parse_args --install-timer
[[ "$MODE" == "install-timer" ]] || fail "--install-timer did not set MODE"

reset_globals
parse_args --remove-timer
[[ "$MODE" == "remove-timer" ]] || fail "--remove-timer did not set MODE"

reset_globals
( parse_args --help ) >/dev/null 2>&1 || fail "--help should exit 0"
reset_globals
( parse_args -h ) >/dev/null 2>&1 || fail "-h should exit 0"

reset_globals
( parse_args --tag ) 2>/dev/null && fail "--tag without argument should exit non-zero"

reset_globals
( parse_args --bogus ) 2>/dev/null && fail "unknown option should exit non-zero"

# ---------------------------------------------------------------------------
# 11-12. confirm
# ---------------------------------------------------------------------------
ASSUME_YES=1
assert_true "confirm should return 0 with ASSUME_YES" confirm "test"
ASSUME_YES=0

if [ ! -r /dev/tty ]; then
    assert_false "confirm should fail without tty when ASSUME_YES=0" confirm "test"
fi

# ---------------------------------------------------------------------------
# 13-14. get_installed_version
# ---------------------------------------------------------------------------
MOCK_INSTALLED_VERSION=""
result=$(get_installed_version)
[[ -z "$result" ]] || fail "get_installed_version should be empty when not installed"

MOCK_INSTALLED_VERSION="6.4.0"
result=$(get_installed_version)
[[ "$result" == "6.4.0" ]] || fail "get_installed_version should return the version"
MOCK_INSTALLED_VERSION=""

# 14b. get_installed_version with residual config-files (apt remove without purge)
MOCK_INSTALLED_VERSION="6.4.0"
MOCK_INSTALLED_STATUS="deinstall ok config-files"
result=$(get_installed_version)
[[ -z "$result" ]] || fail "get_installed_version should be empty for deinstall ok config-files"
MOCK_INSTALLED_VERSION=""
MOCK_INSTALLED_STATUS=""

# ---------------------------------------------------------------------------
# 15-17. has_legacy_install
# ---------------------------------------------------------------------------
MOCK_INSTALLED_VERSION=""
if [ ! -x /usr/bin/asusctl ]; then
    assert_false "has_legacy_install should be false when not installed and no binary" has_legacy_install
fi

MOCK_INSTALLED_VERSION="6.4.0"
assert_false "has_legacy_install should be false when package is installed" has_legacy_install
MOCK_INSTALLED_VERSION=""

if [ -w /usr/bin ]; then
    MOCK_INSTALLED_VERSION=""
    touch /usr/bin/asusctl
    chmod +x /usr/bin/asusctl
    assert_true "has_legacy_install should be true when binary exists but not packaged" has_legacy_install
    rm -f /usr/bin/asusctl
    MOCK_INSTALLED_VERSION=""
fi

# ---------------------------------------------------------------------------
# 18. get_latest_tag (local git repo, mixed tags)
# ---------------------------------------------------------------------------
ORIG_UPSTREAM_REPO="$UPSTREAM_REPO"
TEST_REPO=$(setup_test_repo)
UPSTREAM_REPO="$TEST_REPO"
latest=$(get_latest_tag)
[[ "$latest" == "6.4.0" ]] || fail "get_latest_tag should return 6.4.0, got '$latest'"

# ---------------------------------------------------------------------------
# 19. resolve_depends: fallback when no binaries staged
# ---------------------------------------------------------------------------
STAGE_DIR="$TEST_ROOT/empty-stage"
mkdir -p "$STAGE_DIR/usr/bin"
result=$(resolve_depends)
expected_fallback="libc6, libgcc-s1, libudev1, libdbus-1-3, libssl3 | libssl3t64"
[[ "$result" == "$expected_fallback" ]] || fail "resolve_depends fallback mismatch: '$result'"
STAGE_DIR=""

# ---------------------------------------------------------------------------
# 20-21. prune_cache
# ---------------------------------------------------------------------------
ORIG_CACHE_DIR="$CACHE_DIR"

CACHE_TEST="$TEST_ROOT/cache"
mkdir -p "$CACHE_TEST"
for i in 1 2 3 4 5; do
    f="$CACHE_TEST/${PKG_NAME}_6.3.${i}0_amd64.deb"
    touch "$f"
    touch -d "2024-01-0${i}" "$f"
done
CACHE_DIR="$CACHE_TEST"
prune_cache
remaining=$(find "$CACHE_TEST" -name "${PKG_NAME}_*.deb" | wc -l)
[[ "$remaining" -eq 3 ]] || fail "prune_cache should keep 3 files, got $remaining"

CACHE_DIR="/nonexistent/asus-linux-mint-12345"
assert_true "prune_cache should return 0 when cache dir is missing" prune_cache

CACHE_DIR="$ORIG_CACHE_DIR"

# ---------------------------------------------------------------------------
# 22-24. do_rollback
# ---------------------------------------------------------------------------
ORIG_CACHE_DIR="$CACHE_DIR"

# Success: two cached debs, one matches installed, one is the rollback target
ROLLBACK_CACHE="$TEST_ROOT/rollback-cache"
mkdir -p "$ROLLBACK_CACHE"
touch "$ROLLBACK_CACHE/${PKG_NAME}_6.4.0_amd64.deb"
touch -d "2024-01-05" "$ROLLBACK_CACHE/${PKG_NAME}_6.4.0_amd64.deb"
touch "$ROLLBACK_CACHE/${PKG_NAME}_6.3.10_amd64.deb"
touch -d "2024-01-01" "$ROLLBACK_CACHE/${PKG_NAME}_6.3.10_amd64.deb"

MOCK_INSTALLED_VERSION="6.4.0"
CACHE_DIR="$ROLLBACK_CACHE"
ASSUME_YES=1
rc=0
( do_rollback ) >/dev/null 2>&1 || rc=$?
[[ "$rc" -eq 0 ]] || fail "do_rollback should succeed, got exit $rc"
ASSUME_YES=0
MOCK_INSTALLED_VERSION=""

# No cache directory
MOCK_INSTALLED_VERSION="6.4.0"
CACHE_DIR="/nonexistent/asus-linux-mint-67890"
rc=0
( do_rollback ) >/dev/null 2>&1 || rc=$?
[[ "$rc" -eq 1 ]] || fail "do_rollback should exit 1 when cache is missing, got $rc"
MOCK_INSTALLED_VERSION=""

# Only the currently installed version cached
ONLY_CURRENT="$TEST_ROOT/only-current"
mkdir -p "$ONLY_CURRENT"
touch "$ONLY_CURRENT/${PKG_NAME}_6.4.0_amd64.deb"
MOCK_INSTALLED_VERSION="6.4.0"
CACHE_DIR="$ONLY_CURRENT"
rc=0
( do_rollback ) >/dev/null 2>&1 || rc=$?
[[ "$rc" -eq 1 ]] || fail "do_rollback should exit 1 when only current version is cached, got $rc"
MOCK_INSTALLED_VERSION=""

CACHE_DIR="$ORIG_CACHE_DIR"

# ---------------------------------------------------------------------------
# 25-28. do_check
# ---------------------------------------------------------------------------
UPSTREAM_REPO="$TEST_REPO"

# Up to date
MOCK_INSTALLED_VERSION="6.4.0"
rc=0
( do_check ) >/dev/null 2>&1 || rc=$?
[[ "$rc" -eq 0 ]] || fail "do_check should return 0 when up to date, got $rc"
MOCK_INSTALLED_VERSION=""

# Update available
MOCK_INSTALLED_VERSION="6.3.8"
rc=0
( do_check ) >/dev/null 2>&1 || rc=$?
[[ "$rc" -eq 10 ]] || fail "do_check should return 10 when update available, got $rc"
MOCK_INSTALLED_VERSION=""

# Not installed at all
MOCK_INSTALLED_VERSION=""
rc=0
( do_check ) >/dev/null 2>&1 || rc=$?
[[ "$rc" -eq 10 ]] || fail "do_check should return 10 when not installed, got $rc"
MOCK_INSTALLED_VERSION=""

# With NOTIFY=1 and no notify-send (should not crash)
MOCK_INSTALLED_VERSION="6.3.8"
NOTIFY=1
rc=0
( do_check ) >/dev/null 2>&1 || rc=$?
[[ "$rc" -eq 10 ]] || fail "do_check with NOTIFY should still return 10, got $rc"
NOTIFY=0
MOCK_INSTALLED_VERSION=""

UPSTREAM_REPO="$ORIG_UPSTREAM_REPO"

# ---------------------------------------------------------------------------
# 29-30. report_versions
# ---------------------------------------------------------------------------
output=$(report_versions "6.3.8" "6.4.0" 2>&1)
echo "$output" | grep -q "Installed: 6.3.8" || fail "report_versions missing installed version"
echo "$output" | grep -q "Latest:.*6.4.0" || fail "report_versions missing latest version"
echo "$output" | grep -q "Release:" || fail "report_versions missing release URL"

MOCK_INSTALLED_VERSION=""
if [ ! -x /usr/bin/asusctl ]; then
    output=$(report_versions "" "6.4.0" 2>&1)
    echo "$output" | grep -q "Installed: not installed" || fail "report_versions should show 'not installed'"
fi

# ---------------------------------------------------------------------------
# 31. notify_update: graceful when notify-send is unavailable
# ---------------------------------------------------------------------------
assert_true "notify_update should return 0 when notify-send is missing" notify_update "6.4.0"

# ---------------------------------------------------------------------------
# 32-33. do_install_timer / do_remove_timer
# ---------------------------------------------------------------------------
ORIG_HOME="$HOME"
export HOME="$TEST_ROOT"
mkdir -p "$TEST_ROOT/.config/systemd/user"

do_install_timer >/dev/null 2>&1
TIMER_UNIT="$TEST_ROOT/.config/systemd/user/asus-linux-update-check.timer"
SERVICE_UNIT="$TEST_ROOT/.config/systemd/user/asus-linux-update-check.service"
[[ -f "$TIMER_UNIT" ]] || fail "do_install_timer should create the timer unit"
[[ -f "$SERVICE_UNIT" ]] || fail "do_install_timer should create the service unit"
grep -q "OnCalendar=weekly" "$TIMER_UNIT" || fail "timer unit missing OnCalendar=weekly"
grep -q "ExecStart=" "$SERVICE_UNIT" || fail "service unit missing ExecStart"

do_remove_timer >/dev/null 2>&1
[[ ! -f "$TIMER_UNIT" ]] || fail "do_remove_timer should remove the timer unit"
[[ ! -f "$SERVICE_UNIT" ]] || fail "do_remove_timer should remove the service unit"

export HOME="$ORIG_HOME"

# ---------------------------------------------------------------------------
# 34. timer_unit_dir
# ---------------------------------------------------------------------------
expected_timer_dir="$HOME/.config/systemd/user"
[[ "$(timer_unit_dir)" == "$expected_timer_dir" ]] || fail "timer_unit_dir returned unexpected path"

echo "Update script unit tests passed."

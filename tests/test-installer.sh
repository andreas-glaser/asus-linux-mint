#!/bin/bash

set -euo pipefail

PROJECT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)

# shellcheck disable=SC1091
source "$PROJECT_DIR/install-asus-linux.sh"

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

[[ "$ASUSCTL_VERSION" == "6.4.0" ]] || fail "unexpected asusctl version"
[[ "$SCRIPT_VERSION" == "22.3.3" ]] || fail "unexpected installer release version"
[[ "$SUPPORTED_MINT_VERSION" == "22.3" ]] || fail "unexpected supported Mint release"
[[ "$SUPPORTED_UBUNTU_VERSION" == "24.04" ]] || fail "unexpected supported Ubuntu release"
[[ "$ASUSCTL_COMMIT" == "e6c1469ccf2a745c6a1aff763852df90066c6baa" ]] || fail "unexpected asusctl commit"
[[ "$SUPERGFXCTL_VERSION" == "5.2.7" ]] || fail "unexpected supergfxctl version"
[[ "$SUPERGFXCTL_COMMIT" == "a86383e1b2f32d4f87f8dd47f0d6b06690877c64" ]] || fail "unexpected supergfxctl commit"
[[ "$SUPERGFXCTL_MIN_KERNEL" == "6.1" ]] || fail "unexpected supergfxctl kernel threshold"
[[ "$ASUS_ARMOURY_MIN_KERNEL" == "6.19" ]] || fail "unexpected asus-armoury kernel threshold"
[[ "$INSTALL_SUPERGFXCTL" == "0" ]] || fail "supergfxctl must default to disabled"
[[ "$UPDATE_FIRMWARE" == "0" ]] || fail "firmware updates must default to disabled"
if grep -Eq 'apt install .*linux-(generic|image|headers)' "$PROJECT_DIR/install-asus-linux.sh"; then
    fail "installer must leave kernel management to Linux Mint"
fi
if grep -qi 'mainline' "$PROJECT_DIR/install-asus-linux.sh" "$PROJECT_DIR/README.md"; then
    fail "current installer documentation must not recommend mainline kernels"
fi
if ! grep -Fq 'sudo systemctl restart asusd.service' "$PROJECT_DIR/install-asus-linux.sh"; then
    fail "asusd must be restarted after replacing its binary during an upgrade"
fi
if grep -Fq 'systemctl enable --now asusd.service' "$PROJECT_DIR/install-asus-linux.sh"; then
    fail "enable --now does not restart an already-running asusd during an upgrade"
fi

for managed_path in \
    /usr/bin/asusctl \
    /usr/bin/asusd \
    /usr/bin/asusd-user \
    /usr/bin/asus-shutdown \
    /usr/bin/rog-control-center \
    /usr/bin/supergfxctl \
    /usr/bin/supergfxd \
    /usr/lib/systemd/system/asusd.service \
    /usr/lib/systemd/system/asus-shutdown.service \
    /usr/lib/systemd/system/supergfxd.service \
    /usr/lib/systemd/user/asusd-user.service \
    /usr/share/applications/org.opengamingcollective.rog-control-center.desktop \
    /usr/share/metainfo/org.opengamingcollective.rog-control-center.metainfo.xml; do
    grep -Fq "\"$managed_path\"" "$PROJECT_DIR/uninstall-asus-linux.sh" \
        || fail "uninstaller does not cover $managed_path"
done

if grep -Eq 'gpu-\*|asus_notif_\*' "$PROJECT_DIR/uninstall-asus-linux.sh"; then
    fail "uninstaller must not use broad icon wildcards"
fi

assert_true "6.9 must compare lower than 6.14" version_lt 6.9 6.14
assert_false "6.14 must not compare lower than 6.9" version_lt 6.14 6.9
assert_false "7.0 must not compare lower than 6.19" version_lt 7.0 6.19
assert_true "22.2 must compare lower than 22.3" version_lt 22.2 22.3
assert_false "equal versions must not compare lower" version_lt 22.3 22.3

original_base_dir="$BASE_DIR"
BASE_DIR="/"
assert_false "filesystem root must be rejected as a build directory" validate_configuration
BASE_DIR="/tmp/asus-linux-build"
assert_false "build directories outside the account home must be rejected" validate_configuration
BASE_DIR="$original_base_dir"
assert_true "default configuration must be valid" validate_configuration

expected_lock_hash="$SUPERGFXCTL_LOCK_SHA256"
actual_lock_hash=$(sha256sum "$PROJECT_DIR/assets/supergfxctl-$SUPERGFXCTL_VERSION-Cargo.lock" | awk '{print $1}')
[[ "$actual_lock_hash" == "$expected_lock_hash" ]] || fail "supergfxctl dependency-lock hash mismatch"

test_root=$(mktemp -d)
trap 'rm -rf "$test_root"' EXIT

# asusctl 6.4.0+ ships Cargo.lock in the upstream repo; the bundled lock asset
# and install_verified_dependency_lock call are no longer used for asusctl.
# re-enable if the lock is dropped upstream again.
#
# expected_lock_hash="$ASUSCTL_LOCK_SHA256"
# actual_lock_hash=$(sha256sum "$PROJECT_DIR/assets/asusctl-$ASUSCTL_VERSION-Cargo.lock" | awk '{print $1}')
# [[ "$actual_lock_hash" == "$expected_lock_hash" ]] || fail "asusctl dependency-lock hash mismatch"
#
# lock_destination="$test_root/Cargo.lock"
# assert_true "bundled lock must pass verification" \
#     install_verified_dependency_lock \
#         "asusctl" \
#         "asusctl-$ASUSCTL_VERSION-Cargo.lock" \
#         "$ASUSCTL_LOCK_SHA256" \
#         "https://example.invalid/unused" \
#         "$lock_destination"
# cmp -s "$PROJECT_DIR/assets/asusctl-$ASUSCTL_VERSION-Cargo.lock" "$lock_destination" \
#     || fail "verified lock was not copied exactly"
#
# assert_false "an incorrect lock hash must be rejected" \
#     install_verified_dependency_lock \
#         "asusctl" \
#         "asusctl-$ASUSCTL_VERSION-Cargo.lock" \
#         "0000000000000000000000000000000000000000000000000000000000000000" \
#         "https://example.invalid/unused" \
#         "$lock_destination"

unit_source="$test_root/upstream.service"
unit_destination="$test_root/supported.service"
printf '%s\n' \
    '[Service]' \
    'PrivateBPF=true' \
    'ProtectControlGroups=strict' \
    'ProtectSystem=strict' > "$unit_source"
prepare_supported_systemd_unit "$unit_source" "$unit_destination"
assert_false "unsupported PrivateBPF directive must be removed" grep -q '^PrivateBPF=' "$unit_destination"
grep -q '^ProtectControlGroups=true$' "$unit_destination" \
    || fail "control-group protection was not normalized to a valid boolean"
grep -q '^ProtectSystem=strict$' "$unit_destination" \
    || fail "unrelated systemd hardening directives must be preserved"

mint_info="$test_root/linuxmint-info"
os_release="$test_root/os-release"
printf '%s\n' 'RELEASE=22.3' 'EDITION="Cinnamon"' > "$mint_info"
assert_true "Mint 22.3 must be accepted" detect_supported_distribution "$mint_info" "$os_release"
[[ "$DETECTED_DISTRIBUTION" == "Linux Mint 22.3 Cinnamon" ]] \
    || fail "Mint release was not identified correctly"

rm -f "$mint_info"
printf '%s\n' 'ID=ubuntu' 'VERSION_ID="24.04"' > "$os_release"
assert_true "Ubuntu 24.04 must be accepted" detect_supported_distribution "$mint_info" "$os_release"
[[ "$DETECTED_DISTRIBUTION" == "Ubuntu 24.04" ]] \
    || fail "Ubuntu release was not identified correctly"

printf '%s\n' 'ID=ubuntu' 'VERSION_ID="26.04"' > "$os_release"
assert_false "unvalidated Ubuntu releases must be rejected" \
    detect_supported_distribution "$mint_info" "$os_release"

printf '%s\n' 'ID=debian' 'VERSION_ID="12"' > "$os_release"
assert_false "unvalidated distributions must be rejected" \
    detect_supported_distribution "$mint_info" "$os_release"

upstream="$test_root/upstream"
mkdir -p "$upstream"
git -C "$upstream" init --quiet
git -C "$upstream" config user.name "Installer Test"
git -C "$upstream" config user.email "installer-test@example.invalid"
touch "$upstream/source-file"
git -C "$upstream" add source-file
git -C "$upstream" commit --quiet -m "test source"
expected_commit=$(git -C "$upstream" rev-parse HEAD)

BASE_DIR="$test_root/build"
mkdir -p "$BASE_DIR"
prepare_source_checkout "component" "$upstream" "$expected_commit"
actual_commit=$(git -C "$BASE_DIR/component" rev-parse HEAD)
[[ "$actual_commit" == "$expected_commit" ]] || fail "pinned checkout selected the wrong commit"

# asusctl 6.4.0+ ships Cargo.lock in the upstream repo; the bundled lock asset
# and install_verified_dependency_lock call are no longer used for asusctl.
# re-enable if the lock is dropped upstream again.
#
# install -m 0644 "$PROJECT_DIR/assets/asusctl-$ASUSCTL_VERSION-Cargo.lock" "$BASE_DIR/component/Cargo.lock"
# assert_true "a rerun must accept the exact installer-supplied lock" \
#     prepare_source_checkout "component" "$upstream" "$expected_commit" "$ASUSCTL_LOCK_SHA256"
#
# printf 'tampered lock\n' > "$BASE_DIR/component/Cargo.lock"
# assert_false "a modified installer lock must not be overwritten" \
#     prepare_source_checkout "component" "$upstream" "$expected_commit" "$ASUSCTL_LOCK_SHA256"
# install -m 0644 "$PROJECT_DIR/assets/asusctl-$ASUSCTL_VERSION-Cargo.lock" "$BASE_DIR/component/Cargo.lock"

touch "$BASE_DIR/component/local-change"
assert_false "dirty checkouts must not be overwritten" \
    prepare_source_checkout "component" "$upstream" "$expected_commit"

echo "Installer unit tests passed."

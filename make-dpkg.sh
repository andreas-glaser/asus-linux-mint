#!/bin/bash
# make-dpkg.sh — Shared .deb packaging logic for asusctl-ogc
#
# This is a Bash library, not a standalone script. It must be sourced by a
# caller that provides the following variables and functions:
#
# Required variables (must be set before sourcing):
#   PKG_NAME        — package name (e.g. "asusctl-ogc")
#   CACHE_DIR       — directory for cached .deb files
#   SRC_DIR         — asusctl source checkout directory
#   INSTALL_ROG_GUI — 1 to include GUI, 0 to skip
#   UPSTREAM_URL    — homepage URL for the control file
#
# Required functions (must be defined by the caller):
#   print_status, print_error, print_warning, print_success
#
# Output variables (set by functions in this library):
#   STAGE_DIR — set by stage_install(), cleaned up by the caller's trap

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    echo "make-dpkg.sh is a library and must be sourced, not executed." >&2
    exit 1
fi

# Stage the build into a DESTDIR tree using upstream's own install rules, so the
# file list follows upstream instead of drifting from it.
stage_install() {
    STAGE_DIR="$(mktemp -d -t asusctl-stage-XXXXXX)"
    # install-data-asusd resolves DESTDIR with realpath, so it must exist first.
    # mktemp creates the directory 0700; that mode would end up on the package's
    # own root entry, so reset it to the standard 0755.
    mkdir -p "$STAGE_DIR"
    chmod 0755 "$STAGE_DIR"

    print_status "Staging files into a temporary package root..."

    local targets=(install-asusd install-asus-shutdown install-asusctl install-asusd_user)
    if [ "$INSTALL_ROG_GUI" = "1" ]; then
        targets+=(install-rog_gui install-data-rog_gui)
    fi
    targets+=(install-data-asusd)

    # Individual targets rather than the aggregate `install` target, which always
    # pulls in rog_gui and would force a GUI build even with --no-gui.
    make -C "$SRC_DIR" "${targets[@]}" DESTDIR="$STAGE_DIR" prefix=/usr

    # install-data-asusd_user is declared .PHONY upstream but carries no recipe,
    # so make reports "nothing to be done" and the user unit is never installed
    # even though data/ ships it. Install it ourselves.
    install -D -m 0644 "$SRC_DIR/data/asusd-user.service" \
        "$STAGE_DIR/usr/lib/systemd/user/asusd-user.service"

    install -D -m 0644 "$SRC_DIR/LICENSE" "$STAGE_DIR/usr/share/asusctl/LICENSE"
}

# Resolve shared library dependencies from the built binaries. Falls back to a
# conservative list if dpkg-shlibdeps is unavailable or unhappy.
resolve_depends() {
    local fallback="libc6, libgcc-s1, libudev1, libdbus-1-3, libssl3 | libssl3t64"
    local shlibdeps_dir binaries depends

    if ! command -v dpkg-shlibdeps &> /dev/null; then
        echo "$fallback"
        return
    fi

    mapfile -t binaries < <(find "$STAGE_DIR/usr/bin" -type f 2>/dev/null)
    if [ ${#binaries[@]} -eq 0 ]; then
        echo "$fallback"
        return
    fi

    # dpkg-shlibdeps insists on being run from a tree containing debian/control
    shlibdeps_dir="$(mktemp -d -t asusctl-shlibdeps-XXXXXX)"
    mkdir -p "$shlibdeps_dir/debian"
    cat > "$shlibdeps_dir/debian/control" <<EOF
Source: $PKG_NAME
Package: $PKG_NAME
Architecture: any
EOF

    # dpkg-shlibdeps may exit non-zero (e.g. missing info despite --ignore-missing-info).
    # Suppress that so set -e does not kill the script before the fallback runs,
    # and always clean up the temp directory.
    depends="$(cd "$shlibdeps_dir" && dpkg-shlibdeps -O --ignore-missing-info "${binaries[@]}" 2>/dev/null \
        | sed -n 's/^shlibs:Depends=//p' || true)"
    rm -rf "$shlibdeps_dir"

    if [ -n "$depends" ]; then
        echo "$depends"
    else
        echo "$fallback"
    fi
}

# Write DEBIAN/ control and maintainer scripts into the staged tree
write_package_metadata() {
    local version="$1"
    local arch depends installed_size debian_dir

    arch="$(dpkg --print-architecture)"
    depends="$(resolve_depends)"
    installed_size="$(du -ks "$STAGE_DIR" | cut -f1)"
    debian_dir="$STAGE_DIR/DEBIAN"
    mkdir -p "$debian_dir"

    cat > "$debian_dir/control" <<EOF
Package: $PKG_NAME
Version: $version
Architecture: $arch
Maintainer: asus-linux-mint <https://github.com/farfalk/asus-linux-mint>
Installed-Size: $installed_size
Depends: $depends
Section: utils
Priority: optional
Homepage: $UPSTREAM_URL
Provides: asusctl
Conflicts: asusctl
Replaces: asusctl
Description: Laptop feature control for ASUS ROG and TUF laptops
 asusctl, asusd and rog-control-center built from the OpenGamingCollective
 asusctl release $version.
 .
 This package was built locally from source; it is not an official Debian or
 upstream package.
EOF

    # /etc/asusd is deliberately not shipped in the package: it holds user fan
    # curves, profiles and LED settings, and must survive upgrade and removal.
    cat > "$debian_dir/preinst" <<'EOF'
#!/bin/sh
set -e

# On first install, clear files left by the pre-.deb installer that this
# package does not ship, so they do not linger unowned. Paths the package does
# own are simply overwritten by dpkg.
if [ "$1" = "install" ] && [ -z "$2" ]; then
    rm -f /usr/share/applications/rog-control-center.desktop
    rm -f /usr/local/bin/asusctl /usr/local/bin/asusd \
          /usr/local/bin/asusd-user /usr/local/bin/rog-control-center
fi

exit 0
EOF

    cat > "$debian_dir/postinst" <<'EOF'
#!/bin/sh
set -e

if [ "$1" = "configure" ]; then
    # asusd.service uses ProtectSystem=strict with ReadWritePaths=/etc/asusd/.
    # systemd refuses to start the unit (exit 226/NAMESPACE) if it is missing.
    install -d -m 0755 /etc/asusd

    systemctl daemon-reload || true
    udevadm control --reload-rules || true
    gtk-update-icon-cache /usr/share/icons/hicolor/ 2>/dev/null || true

    # asusd.service has no [Install] section: it is Type=dbus with a BusName and
    # is therefore D-Bus activated and "static". enable/disable do not apply.
    # asus-shutdown.service has an [Install] section (WantedBy=
    # multi-user.target) and must be explicitly enabled. Always enable it
    # because a previous removal may have disabled it.
    systemctl enable asus-shutdown.service || true

    if [ -z "$2" ]; then
        # Fresh install. Note this also covers taking over an unmanaged install,
        # where an old asusd is already running: "start" would be a no-op and
        # leave the previous binary serving D-Bus, so restart unconditionally.
        # restart also starts the unit when it is not running.
        systemctl restart asusd.service || true
        systemctl restart asus-shutdown.service || true
    else
        # Upgrade: only restart if it was already running. This avoids
        # starting a service the admin deliberately stopped. However,
        # asus-shutdown.service was already enabled above so it will
        # start on next boot regardless.
        systemctl try-restart asusd.service || true
        systemctl try-restart asus-shutdown.service || true
    fi
fi

exit 0
EOF

    cat > "$debian_dir/prerm" <<'EOF'
#!/bin/sh
set -e

if [ "$1" = "remove" ]; then
    # No disable: the unit is static (D-Bus activated), so it is never enabled.
    systemctl stop asusd.service || true
fi

exit 0
EOF

    cat > "$debian_dir/postrm" <<'EOF'
#!/bin/sh
set -e

if [ "$1" = "remove" ] || [ "$1" = "purge" ]; then
    systemctl daemon-reload || true
    udevadm control --reload-rules || true
fi

exit 0
EOF

    chmod 0755 "$debian_dir/preinst" "$debian_dir/postinst" \
        "$debian_dir/prerm" "$debian_dir/postrm"
}

# Build the .deb into the cache directory and echo its path
build_deb() {
    local version="$1"
    local arch deb_path

    arch="$(dpkg --print-architecture)"
    deb_path="$CACHE_DIR/${PKG_NAME}_${version}_${arch}.deb"

    sudo install -d -m 0755 "$CACHE_DIR"
    print_status "Building package ${PKG_NAME}_${version}_${arch}.deb..." >&2
    sudo dpkg-deb --build --root-owner-group "$STAGE_DIR" "$deb_path" >&2

    echo "$deb_path"
}

install_deb() {
    local deb_path="$1"

    print_status "Installing $(basename "$deb_path")..."
    sudo apt install -y --allow-downgrades "$deb_path"
}

# A GUI that was already running keeps executing the replaced binary: Linux
# holds the old inode open, and /proc/PID/exe then reads "... (deleted)".
# Nothing restarts it for us, so tell the user it is stale.
warn_stale_gui() {
    local version="$1"
    local pids p

    mapfile -t pids < <(pgrep -f '[r]og-control-center' 2>/dev/null || true)
    [ ${#pids[@]} -gt 0 ] || return 0

    for p in "${pids[@]}"; do
        if [[ "$(readlink "/proc/$p/exe" 2>/dev/null)" == *"(deleted)"* ]]; then
            print_warning "rog-control-center (PID $p) is still running the previous binary."
            print_warning "Quit and relaunch it to use $version."
            return 0
        fi
    done
}

# asusd-user.service is a user unit with an [Install] section, so unlike
# asusd.service it does need enabling. The package's postinst runs as root and
# cannot do that for the invoking user, so handle it here.
enable_user_service() {
    systemctl --user daemon-reload 2>/dev/null || true

    if ! systemctl --user list-unit-files 2>/dev/null | grep -q "^asusd-user\.service"; then
        print_warning "asusd-user.service is not visible in this session."
        print_warning "After the next login, enable it with:"
        print_warning "  systemctl --user enable --now asusd-user.service"
        return 0
    fi

    systemctl --user enable asusd-user.service 2>/dev/null || true
    systemctl --user restart asusd-user.service 2>/dev/null || true
    print_status "asusd-user.service enabled and restarted for $USER."
}

# Keep the three most recent packages so rollback has something to fall back to
prune_cache() {
    local keep=3
    local old

    [ -d "$CACHE_DIR" ] || return 0

    mapfile -t old < <(find "$CACHE_DIR" -maxdepth 1 -name "${PKG_NAME}_*.deb" -printf '%T@ %p\n' \
        | sort -rn | tail -n +$((keep + 1)) | cut -d' ' -f2-)

    if [ ${#old[@]} -gt 0 ]; then
        print_status "Pruning ${#old[@]} old cached package(s)..."
        sudo rm -f "${old[@]}"
    fi
}

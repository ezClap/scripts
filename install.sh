#!/bin/sh
# servburn installer.
#
#   curl -fsSL https://raw.githubusercontent.com/ezClap/scripts/main/install.sh | sudo sh
#
# That is the whole install. The package is downloaded from DEFAULT_URL below
# (the folder in the repo this script lives in); set SERVBURN_URL to use a
# different location, or run the script from a directory that already holds
# the package files and nothing is downloaded at all.
#
# Picks the RPM on dnf/yum/zypper systems, the DEB on apt systems, and falls
# back to the tarball (installed under /usr/local) anywhere else. The window
# needs an X11 or Wayland display and libGL; the terminal mode
# (servburn --headless) needs nothing beyond glibc 2.28.
set -eu
VERSION="${SERVBURN_VERSION:-2.0.0}"
DEFAULT_URL="https://raw.githubusercontent.com/ezClap/scripts/main"
BASE_URL="${SERVBURN_URL:-$DEFAULT_URL}"
HERE=$(cd "$(dirname "$0")" && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

say() { printf '%s\n' "$*"; }
die() { say "install.sh: $*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "run as root: curl -fsSL .../install.sh | sudo sh"

fetch() {
    # $1 = file name; result path echoed
    if [ -f "$HERE/$1" ]; then
        printf '%s' "$HERE/$1"
        return
    fi
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL -o "$WORK/$1" "$BASE_URL/$1" || die "could not download $BASE_URL/$1"
    elif command -v wget >/dev/null 2>&1; then
        wget -q -O "$WORK/$1" "$BASE_URL/$1" || die "could not download $BASE_URL/$1"
    else
        die "neither curl nor wget is available to download $1"
    fi
    printf '%s' "$WORK/$1"
}

install_rpm() {
    pkg=$(fetch "servburn-$VERSION-1.x86_64.rpm")
    if command -v dnf >/dev/null 2>&1; then
        dnf install -y "$pkg"
    elif command -v zypper >/dev/null 2>&1; then
        zypper --non-interactive install --allow-unsigned-rpm "$pkg"
    else
        yum install -y "$pkg"
    fi
}

install_deb() {
    pkg=$(fetch "servburn_${VERSION}_amd64.deb")
    if command -v apt-get >/dev/null 2>&1; then
        apt-get install -y "$pkg" 2>/dev/null || { dpkg -i "$pkg" || apt-get install -f -y; }
    else
        dpkg -i "$pkg"
    fi
}

install_tarball() {
    tgz=$(fetch "servburn-$VERSION-linux-x86_64.tar.gz")
    tar -C "$WORK" -xzf "$tgz"
    src="$WORK/servburn-$VERSION-linux-x86_64"
    install -m 0755 "$src/servburn" /usr/local/bin/servburn
    mkdir -p /usr/local/share/applications /usr/local/share/icons/hicolor/256x256/apps /usr/local/share/doc/servburn
    sed 's#^Exec=servburn#Exec=/usr/local/bin/servburn#' "$src/servburn.desktop" > /usr/local/share/applications/servburn.desktop
    install -m 0644 "$src/servburn.png" /usr/local/share/icons/hicolor/256x256/apps/servburn.png
    install -m 0644 "$src/README.md" /usr/local/share/doc/servburn/README.md
    update-desktop-database /usr/local/share/applications >/dev/null 2>&1 || true
}

# Prefer the running binary's own view of the world: an existing tarball
# install under /usr/local is left alone if a package manager takes over.
if command -v dnf >/dev/null 2>&1 || command -v yum >/dev/null 2>&1 || command -v zypper >/dev/null 2>&1; then
    say "== installing the RPM"
    install_rpm
elif command -v apt-get >/dev/null 2>&1 || command -v dpkg >/dev/null 2>&1; then
    say "== installing the DEB"
    install_deb
else
    say "== no dnf/yum/zypper/apt found, installing the tarball under /usr/local"
    install_tarball
fi

say ""
if command -v servburn >/dev/null 2>&1; then
    say "== installed: $(servburn --version)"
else
    die "servburn is not on PATH after install"
fi

# Say what will actually happen when they run it.
if [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]; then
    say "   A display is present: 'servburn' opens the window."
else
    say "   No display in this session: 'servburn' runs in the terminal."
    say "   For the window, run it from the console or with 'ssh -X'."
fi
say "   Headless: servburn --headless -p safe -d 4h -y -o /var/log/burnin"
say "   Plan only: servburn --preflight"
if ! command -v smartctl >/dev/null 2>&1; then
    say "   Tip: install smartmontools so drive SMART counters are diffed across the run."
fi

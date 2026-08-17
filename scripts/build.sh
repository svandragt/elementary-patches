#!/bin/bash
# build.sh — build a patched package and optionally install it
# Usage: ./build.sh <package-name> [--install]

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_DIR="${WORK_DIR:-$HOME/src}"

PACKAGE="${1:-}"
INSTALL="${2:-}"

if [[ -z "$PACKAGE" ]]; then
    echo "Usage: $0 <package-name> [--install]"
    exit 1
fi

SOURCE_DIR=$(find "$WORK_DIR" -maxdepth 1 -type d -name "${PACKAGE}-*" 2>/dev/null | sort -V | tail -1)
if [[ -z "$SOURCE_DIR" ]]; then
    echo "Error: source directory not found for $PACKAGE in $WORK_DIR"
    echo "Run: ./scripts/apply.sh $PACKAGE"
    exit 1
fi

# Make sure all patches are applied
echo "==> Ensuring all patches are applied..."
(cd "$SOURCE_DIR" && QUILT_PC="$SOURCE_DIR/.pc" QUILT_PATCHES="$SOURCE_DIR/patches" quilt --quiltrc "$REPO_DIR/quiltrc" push -a) 2>/dev/null || true

echo "==> Installing build dependencies..."
sudo apt build-dep "$PACKAGE" -y

echo "==> Building..."
cd "$SOURCE_DIR"

# Build as <archive version>+ep1. At the archive's own version string the local
# .deb still differs in metadata (Installed-Size, shlibs deps), so apt records a
# second version under the same string, lists the package as upgradable, and the
# next full-upgrade puts the stock build back over the patched one. A strictly
# greater version ends that loop; a real archive update still sorts above +ep1.
if ! grep -q '+ep1)' debian/changelog; then
    DEBEMAIL="${DEBEMAIL:-$USER@localhost}" DEBFULLNAME="${DEBFULLNAME:-elementary-patches}" \
        dch --local +ep --nomultimaint "Local patched build (elementary-patches)"
fi
BUILT_VERSION=$(dpkg-parsechangelog -S Version)
BUILT_VERSION="${BUILT_VERSION#*:}"   # .deb filenames carry no epoch

dpkg-buildpackage -us -uc -b -j"$(nproc)"

echo ""
echo "==> Build complete. Packages:"
find "$WORK_DIR" -maxdepth 1 -name "*.deb" | sort

if [[ "$INSTALL" == "--install" ]]; then
    echo "==> Installing..."
    # Every already-installed binary from this build, not just $PACKAGE:
    # siblings such as libgala0 carry a (= version) dependency and must move
    # together. Binaries the system never had are skipped — appcenter-casper
    # needs live-CD-only 'casper', and pulling it in just fails the install.
    # `|| true`: the filter loop reports non-zero when it skips a package, and
    # an empty list is handled below, not by set -e.
    DEBS=$(find "$WORK_DIR" -maxdepth 1 -name "*_${BUILT_VERSION}_*.deb" | sort | while read -r deb; do
        name=$(dpkg-deb -f "$deb" Package)
        if [[ "$(dpkg-query -W -f='${Status}' "$name" 2>/dev/null)" == "install ok installed" ]]; then
            echo "$deb"
        fi
    done) || true
    if [[ -z "$DEBS" ]]; then
        echo "Warning: no .deb found matching $PACKAGE"
    else
        sudo dpkg -i $DEBS
        echo "==> Installed."
    fi
fi

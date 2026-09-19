#!/usr/bin/env bash
# Build himmelblau-omarchy with makepkg inside archlinux:base-devel.
# Output: dist/himmelblau-omarchy-*.pkg.tar.zst
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
[[ -n $ENGINE ]] || die "need podman or docker"
mkdir -p "$DIST"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
cp -r "$ROOT/pkg/himmelblau-omarchy" "$WORK/build"
"$ENGINE" run --rm -i -v "$WORK:/w" --security-opt label=disable archlinux:base-devel bash -euo pipefail <<'IN'
pacman -Sy --noconfirm --quiet >/dev/null 2>&1 || true
useradd -m build; chown -R build /w/build
# -d: himmelblau is not in a repo the container can see.
runuser -u build -- bash -c 'cd /w/build && makepkg -f -d --skipinteg >/dev/null'
IN
# dist/ is the set to publish: one version of each package. Drop the old one.
rm -f "$DIST"/himmelblau-omarchy-*.pkg.tar.zst
cp -f "$WORK"/build/himmelblau-omarchy-*.pkg.tar.zst "$DIST/"
log "built: $(ls "$DIST" | grep -E '^himmelblau-omarchy-.*\.zst$' | tail -1)"

#!/usr/bin/env bash
# Build himmelblau-omarchy with makepkg inside archlinux:base-devel.
# Output: dist/himmelblau-omarchy-*.pkg.tar.zst
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
[[ -n $ENGINE ]] || die "need podman or docker"
mkdir -p "$DIST"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
# mktemp gives 0700; the container's build user (a different uid on CI) must
# be able to traverse it.
chmod 755 "$WORK"
cp -r "$ROOT/pkg/himmelblau-omarchy" "$WORK/build"
"$ENGINE" run --rm -i -v "$WORK:/w" --security-opt label=disable archlinux:base-devel bash -euo pipefail <<'IN'
pacman -Sy --noconfirm --quiet >/dev/null 2>&1 || true
useradd -m build; chown -R build /w/build
# -d: himmelblau is not in a repo the container can see.
runuser -u build -- bash -c 'cd /w/build && makepkg -f -d --skipinteg >/dev/null'
# Give the results back to whoever owns the mount, so the host can read and
# clean them up without sudo.
chown -R "$(stat -c '%u:%g' /w)" /w/build
IN
# dist/ is the set to publish: one version of each package. Drop the old one.
rm -f "$DIST"/himmelblau-omarchy-*.pkg.tar.zst
cp -f "$WORK"/build/himmelblau-omarchy-*.pkg.tar.zst "$DIST/"
log "built: $(ls "$DIST" | grep -E '^himmelblau-omarchy-.*\.zst$' | tail -1)"

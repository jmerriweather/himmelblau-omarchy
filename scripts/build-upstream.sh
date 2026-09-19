#!/usr/bin/env bash
# Build upstream Himmelblau's own Arch package (platform/arch/PKGBUILD via
# `make arch`) at the ref pinned in versions.env. Output: dist/himmelblau-*.pkg.tar.zst
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
source "$ROOT/versions.env"
SRC="$ROOT/upstream"
[[ -n $ENGINE ]] || die "need podman or docker"
for c in git make python3; do command -v "$c" >/dev/null || die "missing $c"; done
if [[ ! -d $SRC/.git ]]; then
  log "cloning himmelblau"
  git clone https://github.com/himmelblau-idm/himmelblau.git "$SRC"
fi
git -C "$SRC" fetch -q origin
git -C "$SRC" checkout -q --force "$HIMMELBLAU_REF"
log "building at $(git -C "$SRC" rev-parse --short HEAD) ($(git -C "$SRC" log -1 --format=%cs))"
mkdir -p "$DIST"
( cd "$SRC" && make arch ) > "$DIST/build-upstream.log" 2>&1 || { tail -30 "$DIST/build-upstream.log" >&2; die "make arch failed (log: dist/build-upstream.log)"; }
shopt -s nullglob; pkgs=( "$SRC"/packaging/himmelblau-*.pkg.tar.zst )
(( ${#pkgs[@]} )) || die "no package produced"
# dist/ is the set to publish: one version of each package. Drop the old one.
find "$DIST" -maxdepth 1 -name 'himmelblau-[0-9]*.pkg.tar.zst' -delete
cp -f "${pkgs[@]}" "$DIST/"
log "built: $(basename "${pkgs[-1]}")"

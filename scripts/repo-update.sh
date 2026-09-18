#!/usr/bin/env bash
# Sign every package in dist/ and (re)build the pacman repository in repo/:
#   repo/<pkg>.pkg.tar.zst            + .sig   (detached, per package)
#   repo/himmelblau-omarchy.db(.tar.zst) + .sig   (signed database)
#   repo/himmelblau-omarchy.files
#   repo/himmelblau-omarchy.pub.asc          (so remote clients can fetch the key)
# Clients use SigLevel = Required DatabaseRequired: both layers are checked.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
KEY="$(keyid)"
shopt -s nullglob
pkgs=( "$DIST"/*.pkg.tar.zst )
(( ${#pkgs[@]} )) || die "nothing in dist/; run build-upstream.sh and build-glue.sh"
mkdir -p "$REPO_DIR"
cp -f "$ROOT/client/$REPO_NAME.pub.asc" "$REPO_DIR/"
log "signing ${#pkgs[@]} package(s) with $KEY"
for p in "${pkgs[@]}"; do
  cp -f "$p" "$REPO_DIR/"
  gpg --batch --yes --detach-sign --no-armor -u "$KEY" "$REPO_DIR/$(basename "$p")"
  echo "  $(basename "$p")"
done
log "repo-add (signed database)"
# -R drops superseded package files; -s -k signs the database.
repo-add -s -k "$KEY" -R "$REPO_DIR/$REPO_NAME.db.tar.zst" "$REPO_DIR"/*.pkg.tar.zst 2>&1 | grep -vE '^==> (Extracting|Creating updated|Adding package|Computing|Signing|Created signature)' || true
log "verifying"
gpg --batch --verify "$REPO_DIR/$REPO_NAME.db.tar.zst.sig" "$REPO_DIR/$REPO_NAME.db.tar.zst" 2>&1 | grep -E 'Good signature' || die "database signature does not verify"
for p in "$REPO_DIR"/*.pkg.tar.zst; do
  gpg --batch --verify "$p.sig" "$p" >/dev/null 2>&1 || die "bad signature: $(basename "$p")"
done
echo "  database and all packages verify against $KEY"
echo; ls -1 "$REPO_DIR"

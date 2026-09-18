#!/usr/bin/env bash
# One-time: create the dedicated package-signing key and export its public half
# into client/ (committed) and repo/ (served). Private key lives only in
# $GNUPGHOME, outside this checkout. No passphrase, so repo-add can sign
# unattended: protect it by protecting that directory, or move it to CI.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
UID_STR="${1:-himmelblau-omarchy packaging <$(git -C "$ROOT" config user.email 2>/dev/null || echo packaging@localhost)>}"
mkdir -p "$GNUPGHOME"; chmod 700 "$GNUPGHOME"
if fpr=$(gpg --batch --list-secret-keys --with-colons "himmelblau-omarchy packaging" 2>/dev/null | awk -F: '/^fpr/{print $10; exit}') && [[ -n $fpr ]]; then
  log "key already exists: $fpr"
else
  log "generating ed25519 signing key: $UID_STR"
  gpg --batch --pinentry-mode loopback --passphrase '' --quick-generate-key "$UID_STR" ed25519 sign 2y
  fpr=$(gpg --batch --list-secret-keys --with-colons "himmelblau-omarchy packaging" | awk -F: '/^fpr/{print $10; exit}')
fi
echo "$fpr" > "$ROOT/client/keyid"
gpg --batch --armor --export "$fpr" > "$ROOT/client/$REPO_NAME.pub.asc"
mkdir -p "$REPO_DIR"; cp -f "$ROOT/client/$REPO_NAME.pub.asc" "$REPO_DIR/"
log "public key exported to client/$REPO_NAME.pub.asc (fingerprint $fpr)"
gpg --batch --list-keys "$fpr" | sed -n '1,4p'

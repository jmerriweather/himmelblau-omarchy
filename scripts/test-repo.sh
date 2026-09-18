#!/usr/bin/env bash
# Prove the signed repo works for a client with SigLevel = Required
# DatabaseRequired, and that a tampered package is refused. Throwaway container.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
[[ -f "$REPO_DIR/$REPO_NAME.db" ]] || die "no repo; run scripts/repo-update.sh"
KEY="$(keyid)"
"$ENGINE" run --rm -i -v "$REPO_DIR:/repo:ro" -e "KEY=$KEY" -e "REPO_NAME=$REPO_NAME" --security-opt label=disable archlinux:base bash -uo pipefail <<'IN'
pass=0; fail=0
ok()  { printf '  \033[1;32mPASS\033[0m %s\n' "$*"; pass=$((pass+1)); }
bad() { printf '  \033[1;31mFAIL\033[0m %s\n' "$*"; fail=$((fail+1)); }
step(){ printf '\n\033[1;34m===> %s\033[0m\n' "$*"; }
pacman -Sy --noconfirm --quiet >/dev/null 2>&1 || true

step "Client trusts the packaging key"
pacman-key --init >/dev/null 2>&1
pacman-key --add /repo/$REPO_NAME.pub.asc >/dev/null 2>&1 && pacman-key --lsign-key "$KEY" >/dev/null 2>&1 && ok "key imported and locally signed" || bad "key import"

step "Repo configured the Omarchy way (Include snippet above [core])"
printf '[%s]\nSigLevel = Required DatabaseRequired\nServer = file:///repo\n' "$REPO_NAME" > /etc/pacman.d/custom-repos.conf
sed -i '0,/^\[core\]/s||Include = /etc/pacman.d/custom-repos.conf\n\n[core]|' /etc/pacman.conf
if out=$(pacman -Sy 2>&1); then ok "database fetched and its signature accepted"; else bad "pacman -Sy: $out"; fi
pacman -Sl $REPO_NAME | sed 's/^/    /'

step "Install from the repo"
if out=$(pacman -S --noconfirm --assume-installed omarchy-settings $REPO_NAME 2>&1); then
  ok "installed: $(pacman -Q himmelblau himmelblau-omarchy | tr '\n' ' ')"
  echo "$out" | grep -qi 'checking package integrity' && ok "package signatures were checked" || bad "no integrity check seen"
else
  bad "install failed"; echo "$out" | tail -5 | sed 's/^/    /'
fi

step "A tampered package must be refused"
cp -r /repo /tmp/evil; chmod -R u+w /tmp/evil
# Same size, different bytes: a size change is refused before any signature
# check, which proves nothing about signing. Flip bytes in the middle instead.
f=$(ls /tmp/evil/himmelblau-omarchy-*.pkg.tar.zst); printf '\xde\xad\xbe\xef' | dd of="$f" bs=1 seek=2048 conv=notrunc 2>/dev/null
sed -i 's|file:///repo|file:///tmp/evil|' /etc/pacman.d/custom-repos.conf
pacman -R --noconfirm himmelblau-omarchy >/dev/null 2>&1
# The valid copy is in pacman's cache under the same name; drop it so the
# tampered file is what gets fetched.
rm -f /var/cache/pacman/pkg/himmelblau-omarchy-*
pacman -Sy >/dev/null 2>&1
if out=$(pacman -S --noconfirm --assume-installed omarchy-settings himmelblau-omarchy 2>&1); then
  bad "tampered package was INSTALLED"
else
  reason=$(echo "$out" | grep -iE 'signature|corrupt|invalid|checksum|failed' | head -1 | xargs)
  [[ -n $reason ]] && ok "refused: $reason" || { bad "refused for an unexpected reason"; echo "$out" | tail -6 | sed 's/^/    /'; }
fi

step "A tampered database must be refused (DatabaseRequired)"
cp -r /repo /tmp/evildb; chmod -R u+w /tmp/evildb
printf 'x' >> /tmp/evildb/$REPO_NAME.db.tar.zst
sed -i 's|file:///tmp/evil$|file:///tmp/evildb|' /etc/pacman.d/custom-repos.conf
rm -rf /var/lib/pacman/sync/$REPO_NAME.*
if out=$(pacman -Sy 2>&1); then
  echo "$out" | grep -qiE "$REPO_NAME.*(invalid|signature)" && ok "database refused: $(echo "$out" | grep -iE "$REPO_NAME.*(invalid|signature)" | head -1 | xargs)" || bad "tampered database was ACCEPTED"
else
  echo "$out" | grep -qiE 'signature|invalid|corrupt' && ok "database refused: $(echo "$out" | grep -iE 'signature|invalid|corrupt' | head -1 | xargs)" || bad "sync failed for an unexpected reason: $(echo "$out" | tail -1)"
fi

step "Summary: $pass passed, $fail failed"; exit $(( fail > 0 ))
IN

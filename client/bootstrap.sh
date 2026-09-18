#!/usr/bin/env bash
# Point an Omarchy machine at the himmelblau-omarchy repo, the way Omarchy
# itself expects custom repos to be added (so `omarchy refresh pacman` keeps it):
#   sudo ./bootstrap.sh --server https://github.com/jmerriweather/himmelblau-omarchy/releases/latest/download
#   sudo ./bootstrap.sh --server file:///home/jm/Work/himmelblau-omarchy/repo
# Then:  sudo pacman -S himmelblau-omarchy
set -euo pipefail
REPO_NAME=himmelblau-omarchy
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER=""; while (($#)); do case "$1" in --server) SERVER="$2"; shift 2;; *) echo "unknown: $1" >&2; exit 1;; esac; done
[[ -n $SERVER ]] || { echo "--server <url> is required" >&2; exit 1; }
(( EUID == 0 )) || { echo "run with sudo" >&2; exit 1; }

key="$HERE/$REPO_NAME.pub.asc"
if [[ ! -f $key ]]; then
  key="$(mktemp)"; curl -fsSL "$SERVER/$REPO_NAME.pub.asc" -o "$key"
fi
fpr=$(gpg --batch --with-colons --show-keys "$key" 2>/dev/null | awk -F: '/^fpr/{print $10; exit}')
pacman-key --add "$key" >/dev/null && pacman-key --lsign-key "$fpr" >/dev/null
echo "trusted packaging key $fpr"

snippet=/etc/pacman.d/custom-repos.conf
if ! grep -qs "^\[$REPO_NAME\]" "$snippet"; then
  printf '\n[%s]\nSigLevel = Required DatabaseRequired\nServer = %s\n' "$REPO_NAME" "$SERVER" >> "$snippet"
fi
grep -qxF "Include = $snippet" /etc/pacman.conf || sed -i "0,/^\[core\]/s||Include = $snippet\n\n[core]|" /etc/pacman.conf
echo "repo [$REPO_NAME] -> $SERVER"

# Omarchy rewrites /etc/pacman.conf on channel changes; its shipped sample hook
# re-adds the Include. Enable it for the invoking user.
u="${SUDO_USER:-}"; if [[ -n $u ]]; then
  d="$(getent passwd "$u" | cut -d: -f6)/.config/omarchy/hooks/pre-refresh-pacman.d"
  if [[ -f $d/add-custom-repo.sample && ! -f $d/add-custom-repo ]]; then
    cp "$d/add-custom-repo.sample" "$d/add-custom-repo"; chown "$u:" "$d/add-custom-repo"
    echo "enabled Omarchy's pre-refresh-pacman hook for $u"
  fi
fi
pacman -Sy >/dev/null && echo "ready: sudo pacman -S $REPO_NAME"

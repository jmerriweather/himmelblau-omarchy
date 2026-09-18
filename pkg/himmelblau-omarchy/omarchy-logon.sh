#!/usr/bin/env bash
# /etc/himmelblau/omarchy-logon.sh
#
# Called by himmelblaud as root after a successful Entra auth, with USERNAME set
# (a UPN, e.g. you@contoso.onmicrosoft.com) and ACCESS_TOKEN set (empty offline).
#
# Why this exists: /etc/skel gives a new cloud user Omarchy's config, but the
# steps in omarchy-provision-user need a real $HOME and cannot be seeded from
# skel — agent skill symlinks (which point at OMARCHY_PATH, possibly a dev
# checkout), xdg-user-dirs, GTK bookmarks, default browser and mailto handlers.
#
# Contract: exit 0 = proceed, 1 = soft failure (login still proceeds),
# 2 = HARD failure, the user cannot log in. This script must therefore never
# return 2, and never block: provisioning is detached and the script returns
# immediately, so a slow first login is not a failed login.

set -uo pipefail

MARKER_REL=".local/state/omarchy/done/finalize-user"
PROVISION="/usr/share/omarchy/bin/omarchy-provision-user"

[[ -n "${USERNAME:-}" ]] || exit 1
[[ -x "$PROVISION" ]] || exit 0   # not an Omarchy box; nothing to do

home="$(getent passwd "$USERNAME" | cut -d: -f6)"
[[ -n "$home" && -d "$home" ]] || exit 1

# omarchy-provision-user is itself idempotent (it checks this marker), but
# checking here too keeps every login after the first free of a forked process.
[[ -e "$home/$MARKER_REL" ]] && exit 0

logger -t himmelblau-omarchy "provisioning Omarchy user setup for $USERNAME"

# Detached, as the user, never as root: the script refuses to run with EUID 0.
setsid runuser -u "$USERNAME" -- \
  env HOME="$home" OMARCHY_PATH=/usr/share/omarchy \
  "$PROVISION" >/dev/null 2>&1 < /dev/null &

exit 0

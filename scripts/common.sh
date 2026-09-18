# shellcheck shell=bash
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_NAME=himmelblau-omarchy
REPO_DIR="$ROOT/repo"
DIST="$ROOT/dist"
export GNUPGHOME="${HIMMELBLAU_OMARCHY_GNUPGHOME:-$HOME/.local/share/himmelblau-omarchy/gnupg}"
ENGINE="$(command -v podman || command -v docker || true)"
log() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
die() { printf '\033[1;31merror: %s\033[0m\n' "$*" >&2; exit 1; }
keyid() { [[ -f "$ROOT/client/keyid" ]] && cat "$ROOT/client/keyid" || die "no signing key; run scripts/keygen.sh"; }

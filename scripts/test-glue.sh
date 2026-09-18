#!/usr/bin/env bash
# The package's own end-to-end test (layout, idempotency, simulated Omarchy
# upgrade, local-login speed with the daemon dead, rollback guard, CLI, removal).
# Lives in the spike as 05-test-glue.sh; this wrapper runs it against dist/.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
SPIKE="${SPIKE:-$ROOT/scripts}"
[[ -x $SPIKE/test-glue-impl.sh ]] || die "spike test not found at $SPIKE/test-glue-impl.sh"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/out"; cp "$DIST"/*.pkg.tar.zst "$tmp/out/"
sed -e "s|^OUT=.*|OUT=$tmp/out|" "$SPIKE/test-glue-impl.sh" > "$tmp/test.sh"
bash "$tmp/test.sh"

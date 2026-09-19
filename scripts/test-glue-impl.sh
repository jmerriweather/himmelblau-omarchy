#!/usr/bin/env bash
# Stage 5: install himmelblau + himmelblau-omarchy into a throwaway container
# seeded with this host's PAM stack, and prove the glue's promises:
#   - gated layout in system-auth only, no double-stack, lock screen wired
#   - idempotent; survives a simulated omarchy-settings upgrade (nsswitch reset,
#     omarchy-lock-password regenerated) via the pacman-hook path
#   - local user logs in fast with the daemon dead; wrong password denied
#   - validation guard rolls back a broken write instead of leaving it
#   - clean removal
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="$ROOT/out"
ENGINE="$(command -v podman || command -v docker)"
IMAGE="${IMAGE:-archlinux:base}"
ls "$OUT"/himmelblau-5*.pkg.tar.zst "$OUT"/himmelblau-omarchy-*.pkg.tar.zst >/dev/null

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/host-pam"
for f in system-auth system-login system-local-login omarchy-lock-password sddm sddm-autologin; do
  [[ -f /etc/pam.d/$f ]] && cp "/etc/pam.d/$f" "$WORK/host-pam/$f"
done
cp /usr/share/omarchy/etc-overrides/nsswitch.conf "$WORK/omarchy-nsswitch.conf"

cat > "$WORK/inside.sh" <<'IN'
#!/usr/bin/env bash
set -uo pipefail
pass=0; fail=0
step() { printf '\n\033[1;34m===> %s\033[0m\n' "$*"; }
ok()   { printf '  \033[1;32mPASS\033[0m %s\n' "$*"; pass=$((pass+1)); }
bad()  { printf '  \033[1;31mFAIL\033[0m %s\n' "$*"; fail=$((fail+1)); }
assert() { local msg=$1; shift; if "$@" >/dev/null 2>&1; then ok "$msg"; else bad "$msg"; fi; }
count() { local c; c=$(grep -c "$1" "$2" 2>/dev/null); echo "${c:-0}"; }
bare()  { awk '/himmelblau-omarchy:begin/{s=1} /himmelblau-omarchy:end/{s=0;next} !s && /pam_himmelblau/{n++} END{print n+0}' "$1"; }

pacman -Sy --noconfirm --quiet >/dev/null 2>&1 || true
pacman -S --noconfirm --needed --quiet python diffutils >/dev/null 2>&1
for f in /spike/host-pam/*; do cp "$f" "/etc/pam.d/$(basename "$f")"; done
cp /spike/omarchy-nsswitch.conf /etc/nsswitch.conf
useradd -m localjm && echo 'localjm:hunter2' | chpasswd

step "Install both packages in one transaction"
# omarchy-settings is in Omarchy's repo, not Arch's; the container cannot see it.
pacman -U --noconfirm --assume-installed omarchy-settings /pkgs/himmelblau-5*.pkg.tar.zst /pkgs/himmelblau-omarchy-*.pkg.tar.zst 2>&1 | grep -E 'Re-asserting|himmelblau-omarchy:|written|ok$|warning|error' | sed 's/^/    /'
cp /usr/lib/himmelblau-omarchy/pamprobe.py /tmp/pamprobe.py
probe() { python3 - "$@" <<'PY'
import sys, time; sys.path.insert(0, "/tmp"); from pamprobe import probe
svc, user, pw = sys.argv[1:4]; t0 = time.monotonic(); rc, d = probe(svc, user, pw); dt = time.monotonic() - t0
print(f"{rc} {dt:.2f} {d}")
PY
}

step "Layout after install"
assert "nsswitch: passwd/group/shadow carry himmelblau" bash -c "grep -E '^passwd:.*himmelblau' /etc/nsswitch.conf && grep -E '^shadow:.*himmelblau' /etc/nsswitch.conf"
assert "system-auth: 4 managed blocks (auth/account/password/session)" [ "$(count 'himmelblau-omarchy:begin' /etc/pam.d/system-auth)" = 4 ]
assert "system-auth: no bare pam_himmelblau lines (no double-stack)" [ "$(bare /etc/pam.d/system-auth)" = 0 ]
assert "system-login: zero pam_himmelblau lines" [ "$(count pam_himmelblau /etc/pam.d/system-login)" = 0 ]
assert "omarchy-lock-password: gated auth block present" [ "$(count 'himmelblau-omarchy:begin' /etc/pam.d/omarchy-lock-password)" = 1 ]
assert "every pam_himmelblau line is preceded by a pam_localuser gate" bash -c '! grep -B1 pam_himmelblau /etc/pam.d/system-auth /etc/pam.d/omarchy-lock-password | grep -vE "pam_localuser|pam_himmelblau|^--"'
assert "pristine originals kept" bash -c 'ls /etc/pam.d/system-auth.pre-himmelblau-omarchy /etc/pam.d/omarchy-lock-password.pre-himmelblau-omarchy'
assert "greeter drop-in selects omarchy-entra" grep -q 'Current=omarchy-entra' /etc/sddm.conf.d/50-himmelblau-omarchy.conf
echo "  --- system-auth, managed lines in context ---"; grep -nE 'himmelblau|pam_localuser|pam_unix|systemd_home' /etc/pam.d/system-auth | sed 's/^/    /'

step "Idempotency"
assert "apply --check reports no drift" /usr/lib/himmelblau-omarchy/apply --check
m1=$(md5sum /etc/pam.d/system-auth /etc/pam.d/omarchy-lock-password /etc/nsswitch.conf | md5sum)
/usr/lib/himmelblau-omarchy/apply >/dev/null
m2=$(md5sum /etc/pam.d/system-auth /etc/pam.d/omarchy-lock-password /etc/nsswitch.conf | md5sum)
assert "second apply changes nothing" [ "$m1" = "$m2" ]

step "Simulated omarchy-settings upgrade (nsswitch reset, lock file regenerated)"
cp /spike/omarchy-nsswitch.conf /etc/nsswitch.conf
cp /spike/host-pam/omarchy-lock-password /etc/pam.d/omarchy-lock-password
assert "drift detected" bash -c '! /usr/lib/himmelblau-omarchy/apply --check'
/usr/lib/himmelblau-omarchy/apply | sed 's/^/    /'
assert "nsswitch re-wired by the hook path" grep -qE '^passwd:.*himmelblau' /etc/nsswitch.conf
assert "lock screen re-wired by the hook path" [ "$(count 'himmelblau-omarchy:begin' /etc/pam.d/omarchy-lock-password)" = 1 ]

step "Local user, daemon dead: fast, and wrong password denied"
for svc in system-auth system-login sddm omarchy-lock-password; do
  read -r rc dt d <<<"$(probe "$svc" localjm hunter2)"
  if [[ $rc = 0 ]] && awk "BEGIN{exit !($dt < 0.5)}"; then ok "$svc: OK in ${dt}s"; else bad "$svc: rc=$rc ${dt}s [$d]"; fi
done
read -r rc dt d <<<"$(probe system-auth localjm wrong)"
[[ $rc != 0 ]] && ok "wrong password denied [$d]" || bad "wrong password ACCEPTED"

step "Validation guard: a broken write must be rolled back"
mv /usr/lib/security/pam_localuser.so /tmp/
cp /spike/host-pam/omarchy-lock-password /etc/pam.d/omarchy-lock-password   # force a rewrite
/usr/lib/himmelblau-omarchy/apply 2>&1 | sed 's/^/    /'; rc=${PIPESTATUS[0]}
assert "apply exits non-zero" [ "$rc" != 0 ]
assert "lock file left as it was (no half-applied block)" [ "$(count 'pam_himmelblau' /etc/pam.d/omarchy-lock-password)" = 0 ]
read -r rc dt d <<<"$(probe omarchy-lock-password localjm hunter2)"
[[ $rc = 0 ]] && ok "local unlock still works after the failed apply" || bad "local unlock broken: $d"
mv /tmp/pam_localuser.so /usr/lib/security/
/usr/lib/himmelblau-omarchy/apply >/dev/null && ok "apply succeeds again once the module is back"

step "CLI"
st=$(himmelblau-omarchy status)
assert "status: tenant line is a single line with the hint before setup" bash -c "grep -qE '^tenant: +\(not set' <<<'$st' && [ \"\$(grep -c . <<<'$st')\" = \"\$(grep -cE '^[a-z]+: ' <<<'$st')\" ]"
assert "status: daemon states are single tokens" bash -c "grep -qE '^daemons: +himmelblaud=[a-z/]+ himmelblaud-tasks=[a-z/]+$' <<<'$st'"
himmelblau-omarchy setup --domain example.onmicrosoft.com --allow 11111111-2222-3333-4444-555555555555 --sudo-group 11111111-2222-3333-4444-555555555555 2>&1 | sed 's/^/    /'
assert "conf rendered with domain" grep -q '^domain = example.onmicrosoft.com' /etc/himmelblau/himmelblau.conf
assert "status: tenant shows the domain after setup" bash -c "himmelblau-omarchy status | grep -qE '^tenant: +example.onmicrosoft.com$'"
assert "conf: pam_allow_groups set" grep -q '^pam_allow_groups = 1111' /etc/himmelblau/himmelblau.conf
assert "conf: sudo_groups + local_sudo_group=wheel" bash -c "grep -q '^sudo_groups = 1111' /etc/himmelblau/himmelblau.conf && grep -q '^local_sudo_group = wheel' /etc/himmelblau/himmelblau.conf"
assert "conf: template placeholder gone" bash -c '! grep -q TENANT_DOMAIN /etc/himmelblau/himmelblau.conf'
assert "setup refuses to overwrite without --force" bash -c '! himmelblau-omarchy setup --domain other.onmicrosoft.com'
echo "  --- status ---"; himmelblau-omarchy status | sed 's/^/    /'

step "Removal"
pacman -R --noconfirm himmelblau-omarchy 2>&1 | grep -iE 'stripped|warning|error' | sed 's/^/    /'
assert "system-auth: no pam_himmelblau after removal" [ "$(count pam_himmelblau /etc/pam.d/system-auth)" = 0 ]
assert "lock file: no pam_himmelblau after removal" [ "$(count pam_himmelblau /etc/pam.d/omarchy-lock-password)" = 0 ]
assert "nsswitch left to the himmelblau package (still wired)" grep -qE '^passwd:.*himmelblau' /etc/nsswitch.conf
assert "greeter drop-in and theme removed" bash -c '! ls /etc/sddm.conf.d/50-himmelblau-omarchy.conf /usr/share/sddm/themes/omarchy-entra 2>/dev/null'
read -r rc dt d <<<"$(probe system-auth localjm hunter2)"
[[ $rc = 0 ]] && ok "local login works after removal" || bad "local login broken after removal: $d"

step "Summary: $pass passed, $fail failed"
exit $(( fail > 0 ))
IN
chmod +x "$WORK/inside.sh"
"$ENGINE" run --rm -i -v "$OUT:/pkgs:ro" -v "$WORK:/spike:ro" --security-opt label=disable "$IMAGE" bash /spike/inside.sh

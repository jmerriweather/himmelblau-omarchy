#!/usr/bin/env python3
"""himmelblau-omarchy apply — make Omarchy's auth stack Entra-capable, idempotently.

Runs from this package's post_install/post_upgrade, and from a pacman hook after
any omarchy-settings upgrade, because that package's post_upgrade overwrites
/etc/nsswitch.conf ("intentionally destructive", its own words).

  apply            assert the layout (writes only what differs)
  apply --check    report drift, change nothing; exit 1 if any
  apply --remove   strip everything this package added

Every write is validated by driving PAM for a nonexistent user with a wrong
password: the stack must answer "authentication failure" or "unknown user".
Anything else means a module failed to load, and the previous file content is
put back before we exit non-zero. Local logins are never left broken.
"""
import os, re, sys, tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from pamprobe import probe, PAM_AUTH_ERR, PAM_USER_UNKNOWN  # noqa: E402

BEGIN, END = "# himmelblau-omarchy:begin", "# himmelblau-omarchy:end"
NSS = "/etc/nsswitch.conf"
SYSTEM_AUTH, SYSTEM_LOGIN = "/etc/pam.d/system-auth", "/etc/pam.d/system-login"
LOCK = "/etc/pam.d/omarchy-lock-password"
SECURITY = "/usr/lib/security"
PROBE_USER = "himmelblau-omarchy-probe"   # must not exist; never a real account

# Every pam_himmelblau line sits behind a pam_localuser gate: a local user
# skips it and never contacts himmelblaud (measured 0.1s login with the daemon
# dead, vs 1-2s with upstream's ungated auto-config). This is the layout
# pam_himmelblau(8) recommends; `aad-tool configure-pam` does not emit it.
GATE = "{k}\t[success=1 default=ignore]\tpam_localuser.so"
LINES = {
    "auth":     [GATE, "{k}\tsufficient\tpam_himmelblau.so ignore_unknown_user set_authtok"],
    "account":  [GATE, "{k}\t[success=ok auth_err=die default=ignore]\tpam_himmelblau.so ignore_unknown_user"],
    "password": [GATE, "{k}\tsufficient\tpam_himmelblau.so ignore_unknown_user set_authtok"],
    "session":  [GATE, "{k}\toptional\tpam_himmelblau.so"],
}


def block(kind):
    return [BEGIN] + [l.format(k=kind) for l in LINES[kind]] + [END]


def strip(lines):
    """Drop our managed blocks and any bare pam_himmelblau line (upstream's
    unflagged configure-pam output, which double-stacks on Arch)."""
    out, skipping = [], False
    for l in lines:
        s = l.strip()
        if s == BEGIN: skipping = True; continue
        if s == END: skipping = False; continue
        if skipping or "pam_himmelblau" in s: continue
        out.append(l)
    return out


def first_of(lines, kind):
    for i, l in enumerate(lines):
        t = l.strip().lstrip("-").split()
        if t and t[0] == kind:
            return i
    return None


def layout(lines, kinds):
    """Our block goes ABOVE the first line of each type. Arch's stock stack uses
    `[success=N ...]` jumps that count lines; inserting between them (as the
    upstream auto-config does) silently changes what they skip."""
    lines = strip(lines)
    for kind in kinds:
        i = first_of(lines, kind)
        if i is not None:
            lines[i:i] = block(kind)
    return lines


def nss_wired(text):
    out = []
    for l in text.splitlines():
        m = re.match(r"^(passwd|group|shadow|initgroups):(.*)$", l)
        if m and "himmelblau" not in m.group(2):
            l = l.rstrip() + " himmelblau"
        out.append(l)
    return "\n".join(out) + "\n"


def modules_present(lines):
    missing = []
    for l in lines:
        t = l.strip().lstrip("-").split()
        if not t or t[0].startswith("#") or len(t) < 3:
            continue
        if t[1] in ("include", "substack"):
            continue
        i = 1
        if t[i].startswith("["):
            while not t[i].endswith("]"):
                i += 1
        i += 1
        mod = t[i]
        if "/" not in mod and not os.path.exists(os.path.join(SECURITY, mod)):
            missing.append(mod)
    return missing


def stack_answers(service):
    """A wrong password for a nonexistent user must reach pam_unix and be
    refused. Any other answer means the stack is broken."""
    rc, detail = probe(service, PROBE_USER, "not-a-password", timeout=40)
    return rc in (PAM_AUTH_ERR, PAM_USER_UNKNOWN), detail


def write(path, text):
    st = os.stat(path)
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path), prefix=".himmelblau-omarchy.")
    with os.fdopen(fd, "w") as f:
        f.write(text)
    os.chmod(tmp, st.st_mode & 0o7777)
    os.replace(tmp, path)


def keep_pristine(path, text):
    """The first apply keeps the file as it was found, next to it. That may
    already carry upstream's configure-pam lines when both packages install in
    one transaction; it is still the honest pre-glue state."""
    bak = path + ".pre-himmelblau-omarchy"
    if not os.path.exists(bak):
        with open(bak, "w") as f:
            f.write(text)


def main(argv):
    mode = argv[0] if argv else "apply"
    if mode not in ("apply", "--check", "--remove"):
        sys.exit(__doc__)
    if os.geteuid() != 0:
        sys.exit("apply: must run as root")
    check, remove = mode == "--check", mode == "--remove"
    drift, failed = [], []

    def plan(path, new_text, validate_service=None):
        if not os.path.exists(path):
            return
        old_text = open(path).read()
        if new_text == old_text:
            print(f"  {path}: ok")
            return
        drift.append(path)
        if check:
            print(f"  {path}: DRIFT")
            return
        keep_pristine(path, old_text)
        write(path, new_text)
        if validate_service:
            missing = modules_present(new_text.splitlines())
            ok, detail = (False, f"missing modules: {missing}") if missing else stack_answers(validate_service)
            if not ok:
                write(path, old_text)
                failed.append(path)
                print(f"  {path}: VALIDATION FAILED ({detail}); previous content restored")
                return
        print(f"  {path}: {'stripped' if remove else 'written'}")

    # NSS: upstream's own package wires this, and omarchy-settings unwires it on
    # every upgrade. Ours is the one that survives. Left alone on --remove: the
    # himmelblau package still owns that decision.
    if not remove:
        plan(NSS, nss_wired(open(NSS).read()))

    for path, kinds, svc in ((SYSTEM_AUTH, ["auth", "account", "password", "session"], "system-auth"),
                             (SYSTEM_LOGIN, [], "system-login"),
                             (LOCK, ["auth"], "omarchy-lock-password")):
        if not os.path.exists(path):
            continue
        lines = open(path).read().splitlines()
        new = strip(lines) if remove else layout(lines, kinds)
        plan(path, "\n".join(new) + "\n", svc)

    if failed:
        print("apply: FAILED validation on: " + ", ".join(failed), file=sys.stderr)
        return 2
    if check and drift:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

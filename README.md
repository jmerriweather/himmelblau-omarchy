# himmelblau-omarchy

Sign in to [Omarchy](https://omarchy.org) with a Microsoft Entra ID account.

[Himmelblau](https://himmelblau-idm.org) already brings Entra ID (and Intune)
authentication to Linux through PAM and NSS. This project packages it for
Omarchy and adds the pieces Omarchy needs on top: wiring that survives Omarchy's
own updates, a PAM layout that keeps local accounts independent of the cloud, a
login screen that can take a username, and first-login provisioning for cloud
users. Everything is delivered as a signed pacman repository.

> **Status: early.** Builds, installs, and every behaviour described below is
> verified by automated tests in containers seeded with a real Omarchy PAM
> stack. It has not yet been run on a physical Omarchy desktop, so the greeter's
> rendering, TPM-backed keys, and a live tenant sign-in are unconfirmed.
> Read [Safety](#safety) before installing, and expect rough edges.

## Requirements

- Omarchy 4.x on x86_64 (tested against 4.0.4)
- An Entra ID tenant, and an account with MFA configured — the first sign-in
  registers the device and Entra requires MFA for that step
- Any app-registration / admin-consent prerequisites from the
  [Himmelblau documentation](https://himmelblau-idm.org/docs/introduction/)

## Install

```bash
git clone https://github.com/jmerriweather/himmelblau-omarchy
cd himmelblau-omarchy
sudo ./client/bootstrap.sh --server https://github.com/jmerriweather/himmelblau-omarchy/releases/latest/download
sudo pacman -S himmelblau-omarchy
```

`bootstrap.sh` trusts the packaging key, adds the repository to
`/etc/pacman.d/custom-repos.conf`, includes it from `pacman.conf`, and enables
Omarchy's own `pre-refresh-pacman` hook so `omarchy refresh pacman` does not
drop it. To do it by hand instead:

```ini
# /etc/pacman.d/custom-repos.conf
[himmelblau-omarchy]
SigLevel = Required DatabaseRequired
Server = https://github.com/jmerriweather/himmelblau-omarchy/releases/latest/download
```

Packaging key fingerprint: `9415C9A390B8A3D1E396383120481B8611C97606`
(`client/himmelblau-omarchy.pub.asc`).

## Set up

```bash
sudo himmelblau-omarchy setup --domain contoso.onmicrosoft.com \
     [--allow <group-object-id>,<user@domain>,...] \
     [--sudo-group <group-object-id>] \
     [--disable-autologin]
```

- `--allow` restricts who may sign in. **Without it, any account in the tenant
  can log into the machine.** Entra groups must be given by Object ID; names
  are not unique and are rejected.
- `--sudo-group` grants `wheel` to members of that Entra group.
- `--disable-autologin` shows the login screen at boot. Omarchy installs with
  autologin on; leave it on for your first attempts (see Safety).

Then, **from an open shell, before you log out or lock the screen:**

```bash
sudo himmelblau-omarchy check <your-local-user>
```

This drives PAM for every login path (`sudo`, tty, SDDM, the lock screen) and
prints OK or DENY with timings. Only when all four say OK, do the first Entra
sign-in from a text console (`Ctrl+Alt+F3`) using your full UPN. That first
login performs the device registration and MFA, which the graphical greeter
cannot drive. After that, sign in from the greeter.

`himmelblau-omarchy status` shows daemons, tenant, and whether the wiring is
in place.

## What it does

| Problem on Omarchy | What this package does |
|---|---|
| `omarchy-settings` overwrites `/etc/nsswitch.conf` on **every** upgrade (its own comment: "intentionally destructive"), silently removing cloud users | A pacman hook re-asserts NSS and PAM after any `omarchy-settings`, `omarchy`, or `himmelblau` transaction |
| `aad-tool configure-pam` patches both `system-auth` and `system-login` on Arch; the latter includes the former, so every login runs the module twice, and the daemon is consulted for local users too | Installs the layout `pam_himmelblau(8)` recommends but the tool does not emit: each line behind a `pam_localuser` gate, in `system-auth` only. Local users never contact the daemon |
| Omarchy's Quickshell lock screen uses its own PAM service, which nothing configures | Wired, gated, re-applied if Omarchy regenerates the file |
| The stock SDDM theme has no username field; it logs in `userModel.lastUser`, so a cloud account cannot be selected | Ships `omarchy-entra`, the stock theme plus a username field, selected by a drop-in. Its images are symlinks to the stock theme, so Omarchy theme changes carry over |
| A new cloud user gets `/etc/skel` (Omarchy's full config) but not the per-user steps `omarchy-provision-user` runs | A Himmelblau `logon_script` runs it, detached, on first login |
| Tenant configuration does not belong in a package | `setup` renders `/etc/himmelblau/himmelblau.conf` from a template |

## Safety

The design goal is that **a local account can always log in**, whatever the
state of Himmelblau. Measured behaviour, from the test suite:

- Every `pam_himmelblau` line is `sufficient` or `default=ignore`: a stopped
  daemon or a broken module degrades to ordinary `pam_unix` login.
- With the `pam_localuser` gate, a local login completes in ~0.06 s with the
  daemon dead. Without it (upstream's auto-config) the same login waits 1–2 s.
- `apply` validates every PAM file it writes by driving PAM for a nonexistent
  user; if the stack answers anything other than "authentication failure" or
  "unknown user", the previous content is restored and it exits non-zero. A
  broken write is never left in place.
- The first `apply` keeps each file as found, next to it
  (`*.pre-himmelblau-omarchy`).
- `pacman -R himmelblau-omarchy` strips exactly what it added and leaves local
  login working (tested).

What the package cannot protect you from is your own edits to `/etc/pam.d`.
Sensible practice for a first install on a machine you care about: take a
snapshot (`omarchy-snapshot create` — Omarchy's snapper + Limine setup makes it
bootable from the boot menu), keep a root shell open in another terminal,
leave autologin on until `check` passes, and keep your admin account local.
Never convert the account you administer the machine with to a cloud identity.

## Limitations

- **MFA and Hello PIN enrollment cannot happen at the graphical login.** SDDM
  sends a single password; it cannot carry a multi-step PAM conversation.
  Enrol from a tty first. `enable_hello` is off in the rendered config for
  the same reason.
- The lock screen answers any PAM prompt with what you typed, so a PIN works
  but a prompt that needs a different answer does not display.
- Omarchy deliberately runs a passwordless default keyring and strips
  `pam_gnome_keyring` from SDDM's stack; keyring unlock for cloud users is
  not addressed here.
- Fingerprint unlock is a separate PAM service and is not wired.
- Cloud users get uids from 200000 upward; anything on the machine assuming a
  single uid-1000 owner will treat them as guests.

## Uninstall

```bash
sudo pacman -R himmelblau-omarchy      # strips PAM blocks, removes the greeter theme
sudo pacman -R himmelblau              # upstream leaves nsswitch.conf lines; remove by hand if wanted
```

## Building and releasing

```
pkg/himmelblau-omarchy/   PKGBUILD and sources for the glue package
scripts/
  build-upstream.sh       upstream Himmelblau via its own PKGBUILD and `make arch`, at the ref in versions.env
  build-glue.sh           makepkg in a container
  test-glue.sh            35-check end-to-end test (layout, idempotency, simulated Omarchy upgrade,
                          login speed with the daemon dead, rollback guard, CLI, removal)
  keygen.sh               one-time signing key, kept outside the checkout
  repo-update.sh          sign every package, build a signed database  -> repo/
  test-repo.sh            client-side verification, plus tampered package and tampered database refusal
client/                   public key, bootstrap.sh
```

A release is `build-upstream.sh`, `build-glue.sh`, `test-glue.sh`,
`repo-update.sh`, `test-repo.sh`, then `gh release create vX.Y.Z repo/*`.
`.github/workflows/release.yml` runs the same on a `v*` tag, given the private
key as the `PACKAGING_GPG_KEY` secret.

Both the packages and the repository database are signed, and clients are
configured to require both. The signing key is a dedicated ed25519 key that
never lives in the repository.

Upstream Himmelblau is built unmodified from its in-tree `platform/arch/PKGBUILD`.
Two behaviours found here would be better fixed upstream: `configure-pam`
double-stacking on Arch, and emitting the `pam_localuser` gate its man page
recommends.

## License

MIT. Himmelblau itself is GPL-3.0-or-later.

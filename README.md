# himmelblau-omarchy

Entra ID login on [Omarchy](https://omarchy.org) via [Himmelblau](https://himmelblau-idm.org),
packaged so it survives Omarchy updates, plus a signed pacman repository to
install it from on any Omarchy machine.

Background, measurements and the reasoning behind every decision are in the
spike: `~/Work/himmelblau-omarchy-spike/README.md`.

## Layout

```
pkg/himmelblau-omarchy/   the glue package (PKGBUILD + sources)
scripts/                  build, sign, publish, test
client/                   what a new machine needs: public key + bootstrap.sh
versions.env              pinned upstream Himmelblau ref
dist/                     built packages            (generated, ignored)
repo/                     signed pacman repository  (generated, ignored)
```

Two packages ship in the repo: `himmelblau` (upstream's own Arch PKGBUILD,
built at the pinned ref) and `himmelblau-omarchy` (this glue).

## Signing

One dedicated key, kept outside the checkout in
`~/.local/share/himmelblau-omarchy/gnupg` (override with
`HIMMELBLAU_OMARCHY_GNUPGHOME`). Created once with `scripts/keygen.sh`; the
public half lives in `client/` (committed) and is also served from the repo.
ed25519, expires after two years — rerun `keygen.sh` before then to extend, or
generate a new one and re-run `repo-update.sh`.

Both layers are signed: every package has a detached `.sig`, and the database
is signed by `repo-add -s`. Clients are configured `SigLevel = Required
DatabaseRequired`, so a tampered package **or** a tampered index is refused.
`scripts/test-repo.sh` proves both in a container.

The key has no passphrase, so `repo-update.sh` runs unattended. Protect it by
protecting that directory; for CI, export it as a secret and import it in the
workflow.

## Publish a release

```
./scripts/build-upstream.sh   # make arch at versions.env ref  -> dist/
./scripts/build-glue.sh       # makepkg in a container         -> dist/
./scripts/test-glue.sh        # 32-check end-to-end run against dist/
./scripts/repo-update.sh      # sign + repo-add                 -> repo/
./scripts/test-repo.sh        # client-side verification + tamper refusal
```

Serve `repo/` from anywhere static. A GitHub Release works with no server:

```
gh release create v0.1.0 repo/* --title "v0.1.0"
# Server = https://github.com/jmerriweather/himmelblau-omarchy/releases/latest/download
```

`.github/workflows/release.yml` does the same on a `v*` tag, given the key as
the `PACKAGING_GPG_KEY` secret.

## On a new Omarchy machine

```
sudo ./client/bootstrap.sh --server https://github.com/jmerriweather/himmelblau-omarchy/releases/latest/download
sudo pacman -S himmelblau-omarchy
sudo himmelblau-omarchy setup --domain <tenant>.onmicrosoft.com [--allow <guid>,...] [--sudo-group <guid>]
sudo himmelblau-omarchy check <local-user>      # every login path OK, from an open shell, BEFORE logging out
```

`bootstrap.sh` trusts the key, writes `/etc/pacman.d/custom-repos.conf`,
includes it above `[core]`, and enables Omarchy's own
`pre-refresh-pacman.d/add-custom-repo` hook so `omarchy refresh pacman` keeps
the repo. On this machine the server can be `file:///home/jm/Work/himmelblau-omarchy/repo`.

Then the first Entra login from a TTY (device join needs MFA, which the greeter
cannot drive), and from there the greeter.

## Bumping upstream

Edit `versions.env`, rebuild both packages (the glue depends on
`himmelblau>=5.0.0`; bump `pkgrel`/`pkgver` in the PKGBUILD as appropriate), run
`test-glue.sh`, then `repo-update.sh`. `repo-add -R` drops superseded files.

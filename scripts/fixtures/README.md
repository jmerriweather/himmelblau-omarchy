# Test fixtures

Copies of the PAM services and the nsswitch override an Omarchy 4.0.4 machine
has, taken from `/etc/pam.d/` and `/usr/share/omarchy/etc-overrides/`. The
end-to-end test seeds its container with these so it exercises the real stack
this package is written for, on any machine (including CI runners that are not
Arch). Refresh them when Omarchy changes its PAM layout:

    for f in system-auth system-login system-local-login sddm sddm-autologin omarchy-lock-password; do cp /etc/pam.d/$f scripts/fixtures/pam.d/; done
    cp /usr/share/omarchy/etc-overrides/nsswitch.conf scripts/fixtures/omarchy-nsswitch.conf

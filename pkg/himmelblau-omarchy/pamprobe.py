#!/usr/bin/env python3
"""Drive libpam directly: auth + account, the phases login, sudo, SDDM and the
lock screen all run.

Library:  probe(service, user, password) -> (rc, detail)
CLI:      pamprobe.py check USER SERVICE...   (root; password via getpass)
"""
import ctypes, ctypes.util, getpass, signal, sys, time

PAM_SUCCESS, PAM_AUTH_ERR, PAM_USER_UNKNOWN = 0, 7, 10
PAM_PROMPT_ECHO_OFF = 1

_libpam = ctypes.CDLL(ctypes.util.find_library("pam"))
_libc = ctypes.CDLL(ctypes.util.find_library("c"))
_libpam.pam_strerror.restype = ctypes.c_char_p
_libc.calloc.restype = ctypes.c_void_p; _libc.calloc.argtypes = [ctypes.c_size_t, ctypes.c_size_t]
_libc.strdup.restype = ctypes.c_void_p; _libc.strdup.argtypes = [ctypes.c_char_p]

class _Msg(ctypes.Structure):  _fields_ = [("style", ctypes.c_int), ("msg", ctypes.c_char_p)]
class _Resp(ctypes.Structure): _fields_ = [("resp", ctypes.c_char_p), ("code", ctypes.c_int)]
_CONV = ctypes.CFUNCTYPE(ctypes.c_int, ctypes.c_int, ctypes.POINTER(ctypes.POINTER(_Msg)),
                         ctypes.POINTER(ctypes.POINTER(_Resp)), ctypes.c_void_p)
class _Conv(ctypes.Structure): _fields_ = [("conv", _CONV), ("appdata", ctypes.c_void_p)]


def probe(service, user, password, timeout=30):
    """Returns (rc, detail). rc 0 = auth and account both passed."""
    def conv(n, msgs, resp, _):
        buf = _libc.calloc(n, ctypes.sizeof(_Resp))
        arr = ctypes.cast(buf, ctypes.POINTER(_Resp))
        for i in range(n):
            if msgs[i].contents.style == PAM_PROMPT_ECHO_OFF:
                arr[i].resp = ctypes.cast(_libc.strdup(password.encode()), ctypes.c_char_p)
        resp[0] = ctypes.cast(buf, ctypes.POINTER(_Resp))
        return 0

    c = _Conv(_CONV(conv), None); h = ctypes.c_void_p()
    rc = _libpam.pam_start(service.encode(), user.encode(), ctypes.byref(c), ctypes.byref(h))
    if rc:
        return rc, f"pam_start failed ({rc})"
    old = signal.signal(signal.SIGALRM, lambda *_: (_ for _ in ()).throw(TimeoutError()))
    signal.alarm(timeout)
    try:
        rc = _libpam.pam_authenticate(h, 0)
        detail = "auth: " + _libpam.pam_strerror(h, rc).decode()
        if rc == PAM_SUCCESS:
            rc = _libpam.pam_acct_mgmt(h, 0)
            detail += ", acct: " + _libpam.pam_strerror(h, rc).decode()
    except TimeoutError:
        rc, detail = -1, f"no answer within {timeout}s"
    finally:
        signal.alarm(0); signal.signal(signal.SIGALRM, old)
        _libpam.pam_end(h, 0)
    return rc, detail


def main(argv):
    if len(argv) < 3 or argv[0] != "check":
        sys.exit(__doc__)
    user, services = argv[1], argv[2:]
    pw = getpass.getpass(f"password for {user}: ")
    failed = 0
    for svc in services:
        t0 = time.monotonic(); rc, detail = probe(svc, user, pw); dt = time.monotonic() - t0
        print(f"{'OK  ' if rc == 0 else 'DENY'}  {svc:24s} {dt:5.2f}s  [{detail}]")
        failed += rc != 0
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

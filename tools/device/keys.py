#!/usr/bin/env python3
# The app's keys in com.palm.keymanager, for tools/test-device.sh: reads and
# writes them in the app's own namespace (luna-send -a <app id>), the way
# the app does. Runs on the device. Secrets are never printed.
#
#   python3 keys.py index            the newer index, as JSON (no secrets)
#   python3 keys.py seed             test accounts (ids "test...") with the
#                                    RFC 6238/4226 test secrets; refuses if
#                                    the app already has an index
#   python3 keys.py clear-test       removes the test accounts' keys (ids
#                                    "test...", or the site TEST_ISSUER)
#                                    and, if nothing else is listed, the
#                                    index; else writes it without them
#   python3 keys.py real             how many accounts are not test ones
#   python3 keys.py has <keyname>    "yes" or "no"
import json
import subprocess
import sys

APP = "org.webosports.app.authenticator"
INDEX_KEYS = ["otp.index.a", "otp.index.b"]
# The site of the accounts tools/test-device.sh adds through the app.
TEST_ISSUER = "LuneOS device test"


def is_test(account):
    return account["id"].startswith("test") or account["issuer"] == TEST_ISSUER


def call(method, params):
    out = subprocess.run(["luna-send", "-n", "1", "-w", "10000", "-a", APP,
                          "luna://com.palm.keymanager/" + method, json.dumps(params)],
                         capture_output=True, text=True).stdout
    return json.loads(out)


def fetch(name):
    r = call("fetchKey", {"keyname": name})
    return r.get("keydata") if r.get("returnValue", True) is not False else None


def newest_index():
    best = None
    for name in INDEX_KEYS:
        text = fetch(name)
        if text is None:
            continue
        try:
            index = json.loads(text)
        except ValueError:
            continue
        if best is None or index["generation"] > best[1]["generation"]:
            best = (name, index)
    return best


def store(name, data):
    r = call("store", {"keyname": name, "keydata": data, "type": "ASCIIBLOB",
                       "nohide": True, "noexport": True})
    if r.get("returnValue") is False:
        sys.exit("could not store %s: %s" % (name, r.get("errorText")))


def account(id_, type_, issuer, label, algorithm, digits, period=30, counter=0):
    return {"id": id_, "type": type_, "issuer": issuer, "label": label, "algorithm": algorithm,
            "digits": digits, "period": period, "counter": counter}


cmd = sys.argv[1]
if cmd == "index":
    best = newest_index()
    print(json.dumps(best[1] if best else None))
elif cmd == "has":
    print("yes" if fetch(sys.argv[2]) is not None else "no")
elif cmd == "seed":
    if newest_index() is not None:
        sys.exit("the app already has accounts; not seeding over them")
    accounts = [
        account("test1", "totp", "RFC 6238", "SHA-1, 8 digits", "SHA1", 8),
        account("test2", "totp", "RFC 6238", "SHA-256, 8 digits", "SHA256", 8),
        account("test3", "totp", "RFC 6238", "SHA-512, 8 digits", "SHA512", 8),
        account("test4", "hotp", "RFC 4226", "Counter", "SHA1", 6, counter=0),
    ]
    secrets = {
        "test1": "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ",
        "test2": "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZA",
        "test3": "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNA",
        "test4": "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ",
    }
    for id_, secret in secrets.items():
        store("otp.secret." + id_, secret)
    store(INDEX_KEYS[0], json.dumps({"generation": 1, "accounts": accounts}))
    print("seeded %d accounts" % len(accounts))
elif cmd == "real":
    best = newest_index()
    print(len([a for a in best[1]["accounts"] if not is_test(a)]) if best else 0)
elif cmd == "clear-test":
    best = newest_index()
    accounts = best[1]["accounts"] if best else []
    others = [a for a in accounts if not is_test(a)]
    if not others:
        for name in INDEX_KEYS:
            call("remove", {"keyname": name})
    else:
        # As the app writes it: into the key that does not hold the newest.
        target = INDEX_KEYS[1] if best[0] == INDEX_KEYS[0] else INDEX_KEYS[0]
        call("remove", {"keyname": target})
        store(target, json.dumps({"generation": best[1]["generation"] + 1, "accounts": others}))
    for a in accounts:
        if is_test(a):
            call("remove", {"keyname": "otp.secret." + a["id"]})
    print("removed %d test account(s); %d other(s) kept" % (len(accounts) - len(others), len(others)))

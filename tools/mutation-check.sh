#!/bin/bash
# Breaks the app on purpose, one way at a time, and checks that the tests
# notice: each mutation below must make tools/run-tests.sh fail. The file
# is put back after each, and on exit.
#
#   tools/mutation-check.sh [path to luneos-components]
set -e
cd "$(dirname "$0")/.."
LC=${1:-../luneos-components}
SAVE=build/mutation
mkdir -p "$SAVE"
current=""
restore() { [ -n "$current" ] && cp "$SAVE/original" "$current"; current=""; }
trap restore EXIT

# what ¦ file ¦ text ¦ replacement (\n for a new line)
mutations=(
"SHA-1 rotates by 29 ¦ qml/js/Sha.js ¦ c = rotl(b, 30); ¦ c = rotl(b, 29);"
"SHA-256 sigma0 shifts by 2 ¦ qml/js/Sha.js ¦ (w[t - 15] >>> 3) ¦ (w[t - 15] >>> 2)"
"SHA-512 loses its carry ¦ qml/js/Sha.js ¦     hi += Math.floor(lo / 0x100000000); ¦     hi += 0;"
"HMAC with a block of 64 for SHA-512 ¦ qml/js/Sha.js ¦ \"SHA512\": { hash: sha512, blockBytes: 128 } ¦ \"SHA512\": { hash: sha512, blockBytes: 64 }"
"truncation offset of 3 bits ¦ qml/js/Otp.js ¦ var offset = mac[mac.length - 1] & 0x0f; ¦ var offset = mac[mac.length - 1] & 0x07;"
"truncation keeps the sign bit ¦ qml/js/Otp.js ¦ ((mac[offset] & 0x7f) * 0x1000000) ¦ ((mac[offset] & 0xff) * 0x1000000)"
"no leading zeros ¦ qml/js/Otp.js ¦     while (code.length < n) ¦     while (false)"
"time step rounds ¦ qml/js/Otp.js ¦ return Math.floor(Math.floor(timeMs / 1000) / (period  ¦  ¦  30)); ¦ return Math.round(timeMs / 1000 / (period  ¦  ¦  30));"
"Base32 takes a dangling character ¦ qml/js/Base32.js ¦     if (rest === 1 || rest === 3 || rest === 6)\n        return null; ¦     if (false)\n        return null;"
"label issuer wins over the parameter ¦ qml/js/OtpAuthUri.js ¦     if (params.issuer !== undefined && params.issuer.trim() !== \"\") ¦     if (issuer === \"\" && params.issuer !== undefined)"
"index always to the first key ¦ qml/AccountStore.qml ¦         var slot = _currentSlot === 0 ? 1 : 0; ¦         var slot = 0;"
"writes before the index is read ¦ qml/AccountStore.qml ¦         if (status !== \"ready\") { ¦         if (false) {"
"secret stored hidden ¦ qml/AccountStore.qml ¦                 \"keydata\": secret,\n                \"type\": \"ASCIIBLOB\",\n                \"nohide\": true, ¦                 \"keydata\": secret,\n                \"type\": \"ASCIIBLOB\",\n                \"nohide\": false,"
"orphan secret kept ¦ qml/AccountStore.qml ¦                         _call(\"remove\", { \"keyname\": Accounts.secretKeyName(id) }, function() {});\n                        _report(\"The account could not be saved: \" ¦                         _report(\"The account could not be saved: \""
"HOTP shows the next counter's code ¦ qml/AccountStore.qml ¦ callback(\"\", changed.counter - 1); ¦ callback(\"\", changed.counter);"
"a missing key counts as an empty store ¦ qml/AccountStore.qml ¦                 if (error !== \"\" && !_isNotFound(error))\n                    failure = error; ¦                 if (false)\n                    failure = error;"
"duplicates added ¦ qml/EditAccountPage.qml ¦         if (!editing && Accounts.isDuplicate( ¦         if (false && Accounts.isDuplicate("
"back gesture also leaves the page under a dialog ¦ qml/EditAccountPage.qml ¦         if (event.key === Qt.Key_Escape && _escapeTaken) { ¦         if (false) {"
"back gesture ignored while reordering ¦ qml/AccountsPage.qml ¦         } else if (reordering) { ¦         } else if (false) {"
"link added without asking ¦ qml/main.qml ¦         openEditor({ \"prefill\": parsed.account, \"fromLink\": true }); ¦         accountStore.add(parsed.account);"
"copy not copied ¦ qml/main.qml ¦         clipboardHelper.copy(); ¦         clipboardHelper.deselect();"
)

failures=0
for m in "${mutations[@]}"; do
    what=${m%% ¦ *}; rest=${m#* ¦ }
    file=${rest%% ¦ *}; rest=${rest#* ¦ }
    from=$(printf '%b' "${rest%% ¦ *}")
    to=$(printf '%b' "${rest#* ¦ }")
    cp "$file" "$SAVE/original"
    current=$file
    if ! FROM="$from" TO="$to" python3 -I -c '
import os, sys
p = sys.argv[1]; s = open(p).read(); a = os.environ["FROM"]
if s.count(a) != 1:
    sys.exit("not found once: " + a)
open(p, "w").write(s.replace(a, os.environ["TO"]))' "$file"; then
        echo "BAD  $what: the text to change is not in $file"
        failures=$((failures + 1)); restore; continue
    fi
    if tools/run-tests.sh "$LC" > "$SAVE/out" 2>&1; then
        echo "MISS $what: the tests still pass"
        failures=$((failures + 1))
    else
        echo "ok   $what: $(grep -cE '^FAIL|^FAIL!' "$SAVE/out") failing"
    fi
    restore
done
tools/run-tests.sh "$LC" > "$SAVE/out" 2>&1 || { echo "the tests fail on the unchanged tree"; exit 1; }
echo "$([ $failures = 0 ] && echo PASS || echo "FAILED: $failures") - ${#mutations[@]} mutations"
exit $failures

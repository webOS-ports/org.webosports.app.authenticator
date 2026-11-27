#!/bin/bash
# Breaks the app on purpose, one way at a time, and checks that the tests
# notice: each mutation below must make tools/run-tests.sh fail. The file
# is put back after each, and on exit.
#
#   [ONLY=<regex>] tools/mutation-check.sh [path to luneos-components]
#
# ONLY runs just the mutations whose description matches. The screens
# (tst_screens.qml, once per profile) are left out unless PROFILES names
# some: none of the mutations is about the layout, and they would take
# minutes each.
set -e
export PROFILES=${PROFILES-}
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
"lock left out of the index ¦ qml/js/Accounts.js ¦     if (options && options.lock === true) { ¦     if (false) {"
"secrets read while locked ¦ qml/AccountStore.qml ¦         if (lockEnabled && !_unlocked) { ¦         if (false) {"
"secrets kept when locked again ¦ qml/AccountStore.qml ¦         _secrets = {};\n        _keys = {};\n        accounts = [];\n        status = \"locked\"; ¦         status = \"locked\";"
"lock does not wait for a save ¦ qml/AccountStore.qml ¦         if (_busy || _queue.length > 0) { ¦         if (false) {"
"a wrong passcode opens ¦ qml/LockScreen.qml ¦             if (result.matched) { ¦             if (!result.error && !result.lockedOut) {"
"tries during a lockout ¦ qml/LockScreen.qml ¦     readonly property bool canEnter: !checking && !lockedOut && ¦     readonly property bool canEnter: !checking &&"
"a missed fingerprint opens ¦ qml/DeviceAuth.qml ¦         if (reply.identified === true) { ¦         if (reply.identified !== undefined && reply.finished !== true) {"
"misses forgotten on coming back ¦ qml/main.qml ¦             lockScreen.focusEntry(); ¦             lockScreen.reset();"
"misses not counted ¦ qml/DeviceAuth.qml ¦                 fingerprintMisses++; ¦                 fingerprintMisses += 0;"
"sensor armed in the background ¦ qml/main.qml ¦ accountStore.status === \"locked\" && appWindow.inFront ¦ accountStore.status === \"locked\""
"never locks again ¦ qml/main.qml ¦         if (backgroundSince > 0 && lockClock() - backgroundSince >= relockAfterMs) ¦         if (false)"
"face stored without the lock ¦ qml/js/Accounts.js ¦             face: index.lock === true && index.face === true, ¦             face: index.face === true,"
"face used without being turned on ¦ qml/DeviceAuth.qml ¦     readonly property bool faceReady: faceAllowed && faceAvailable ¦     readonly property bool faceReady: faceAvailable"
"a face that does not match opens ¦ qml/DeviceAuth.qml ¦         if (reply.recognized === true) { ¦         if (reply.recognized !== undefined) {"
"an empty frame counts as a miss ¦ qml/DeviceAuth.qml ¦             if (reason !== \"noFace\" && reason !== \"aborted\") { ¦             if (reason !== \"aborted\") {"
"face misses not counted ¦ qml/DeviceAuth.qml ¦                 faceMisses++; ¦                 faceMisses += 0;"
"face tried without end ¦ qml/DeviceAuth.qml ¦ listening && faceReady && faceTries < maxFaceTries && !faceBlocked ¦ listening && faceReady && !faceBlocked"
"busy camera tried again at once ¦ qml/DeviceAuth.qml ¦         faceBlocked = true; ¦         faceBlocked = false;"
"camera held in the background ¦ qml/DeviceAuth.qml ¦     readonly property bool faceActive: listening && ¦     readonly property bool faceActive: true &&"
"a stale face reply counts ¦ qml/DeviceAuth.qml ¦ function(message) { if (_faceCall === call) _faceReply(message); }, ¦ function(message) { _faceReply(message); },"
"lock off keeps face ¦ qml/AccountStore.qml ¦         _setOptions({ lock: on, face: on && faceEnabled }, callback); ¦         _setOptions({ lock: on, face: faceEnabled }, callback);"
"face on without asking ¦ qml/main.qml ¦         faceDialog.ask({ ¦         accountStore.setFaceEnabled(true); void({"
"face on when cancelled ¦ qml/main.qml ¦             onAccepted: function() {\n                accountStore.setFaceEnabled(true ¦             onRejected: function() {\n                accountStore.setFaceEnabled(true"
"deleted from the list when cancelled ¦ qml/AccountsPage.qml ¦ onAccepted: function() { page.store.remove(account.id); } ¦ onRejected: function() { page.store.remove(account.id); }"
"deleted from the list without asking ¦ qml/AccountsPage.qml ¦                 deleteDialog.ask({ ¦                 page.store.remove(account.id); deleteDialog.ask({"
"deleted from the editor when cancelled ¦ qml/EditAccountPage.qml ¦                         onAccepted: function() {\n                            page.store.remove( ¦                         onRejected: function() {\n                            page.store.remove("
"back gesture deletes ¦ qml/EditAccountPage.qml ¦             deleteDialog.rejected();\n            _escapeTaken = true; ¦             deleteDialog.accepted();\n            _escapeTaken = true;"
"toast shown nowhere ¦ qml/main.qml ¦         toast.show(text); ¦         toast.text = text;"
"toast in the middle ¦ qml/main.qml ¦         anchors.centerIn: undefined ¦         anchors.centerIn: parent"
"toast stays up ¦ qml/main.qml ¦         id: toast\n ¦         id: toast\n        duration: 60000\n"
"lock on with no passcode to fall back on ¦ qml/main.qml ¦         if (!accountStore.lockEnabled && !deviceAuth.hasPasscode) { ¦         if (false) {"
"export link imported without asking ¦ qml/main.qml ¦         pageStack.push(Qt.resolvedUrl(\"ImportPage.qml\"), { ¦         accountStore.addAll(parsed.entries.map(function(e) { return e.account; })); pageStack.push(Qt.resolvedUrl(\"ImportPage.qml\"), {"
"import adds what is already there ¦ qml/ImportPage.qml ¦             if (Accounts.isDuplicate(store.accounts, a, a.secret, store._secrets) ¦             if (false"
"import adds the same account twice ¦ qml/ImportPage.qml ¦                     || Accounts.isDuplicate(taken, a, a.secret, secrets)) { ¦                     || false) {"
"import writes the index first ¦ qml/AccountStore.qml ¦             storeFrom(0);\n        }); ¦             writeIndex();\n        });"
"import keeps secrets the index lost ¦ qml/AccountStore.qml ¦                         // Not listed, so not kept.\n                        undo();\n                        _report(\"The accounts ¦                         // Not listed, so not kept.\n                        _report(\"The accounts"
"import goes on after a refused secret ¦ qml/AccountStore.qml ¦                         undo();\n                        _report(\"The accounts could not be saved: \" + error, callback);\n                        next();\n                        return; ¦                         undo();\n                        _report(\"The accounts could not be saved: \" + error, callback);"
"MD5 imported as SHA-1 ¦ qml/js/Migration.js ¦ var ALGORITHMS = { 0: \"SHA1\", 1: \"SHA1\", ¦ var ALGORITHMS = { 4: \"SHA1\", 0: \"SHA1\", 1: \"SHA1\","
"eight digits read as six ¦ qml/js/Migration.js ¦             digits: digits === 2 ? 8 : 6, ¦             digits: 6,"
"a site's prefix kept in the name ¦ qml/js/Migration.js ¦             label = label.substr(colon + 1); ¦             label = label;"
"counters cut to 32 bits ¦ qml/js/Migration.js ¦         v = Math.floor(v / 128); ¦         v = v >>> 7;"
"a + read as a space ¦ qml/js/Migration.js ¦     var bytes = base64Decode(data.replace(/ /g, \"+\")); ¦     var bytes = base64Decode(data);"
"UTF-8 overlong forms taken ¦ qml/js/Migration.js ¦         if (cp < min || cp > 0x10ffff ¦         if (cp > 0x10ffff"
"7-digit codes exported ¦ qml/js/Migration.js ¦     if (account.digits !== 6 && account.digits !== 8) ¦     if (false)"
"60-second codes exported ¦ qml/js/Migration.js ¦     if (account.type === \"totp\" && account.period !== 30) ¦     if (false)"
"every code says it is the first ¦ qml/js/Migration.js ¦     writeNumber(out, 4, batchIndex); ¦     writeNumber(out, 4, 0);"
"codes of any size ¦ qml/js/Migration.js ¦         if (group.length > 0 && (group.length >= MAX_PER_CODE ¦         if (group.length > 0 && (false"
"accounts left out exported anyway ¦ qml/ExportPage.qml ¦         codes = Migration.compose(chosen, ¦         codes = Migration.compose(exportable,"
"codes left on the screen in the background ¦ qml/ExportPage.qml ¦             if (!appWindow.inFront && page.step === \"codes\") ¦             if (false)"
"back gesture leaves the codes for the list ¦ qml/ExportPage.qml ¦         if (event.key === Qt.Key_Escape && _escapeTaken) { ¦         if (false) {"
"pasted export link left in the key field ¦ qml/EditAccountPage.qml ¦                         if (!page.editing && Migration.isMigration(text)) { ¦                         if (false) {"
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
    if [ -n "$ONLY" ] && ! printf '%s' "$what" | grep -qE "$ONLY"; then
        restore; continue
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

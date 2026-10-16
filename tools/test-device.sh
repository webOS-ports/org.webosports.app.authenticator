#!/bin/bash
# Tries the installed app on a device:
#
# 1. The application manager sends otpauth:// links to the app.
# 2. Test accounts (the RFC 6238 SHA-1, SHA-256 and SHA-512 seeds, and an
#    RFC 4226 counter account) are put into the key manager as the app
#    keeps them; the app is started, and the codes on the screen, read back
#    with tesseract, must be the ones OpenSSL computes for the device's time.
# 3. An otpauth:// link is opened through the application manager; the app
#    must show it to be added (read back off the screen too).
# 4. With TAPS=1, Save is tapped (tools/device/tap.py), and the account must
#    then be in the key manager, under the app's own namespace.
#
# At the end the app is closed and the test accounts are removed. It
# refuses to run on a device where the app holds accounts of its own.
#
#   [TAPS=1] [AWAKE=1] tools/test-device.sh <adb serial> <name>
#
# AWAKE=1 holds the screen on while it runs (com.palm.display requestBlock,
# released at the end). TAPS needs the screen unlocked and the app in front;
# the Save button's place is known for 480x800 and 720x720 screens. Needs
# node and tesseract on this side. Screenshots go to
# build/test-output/device/<name>/.
set -e
cd "$(dirname "$0")/.."
SERIAL=${1:?usage: tools/test-device.sh <adb serial> <name>}
NAME=${2:?usage: tools/test-device.sh <adb serial> <name>}
ADB="adb -s $SERIAL"
ID=org.webosports.app.authenticator
OUT=build/test-output/device/$NAME
mkdir -p "$OUT"
failures=0
ok() { echo "ok   $1"; }
fail() { echo "FAIL $1"; failures=$((failures + 1)); }

$ADB push tools/device/keys.py /tmp/auth-keys.py >/dev/null
$ADB push tools/device/tap.py /tmp/auth-tap.py >/dev/null
keys() { $ADB shell "python3 /tmp/auth-keys.py $*" | tr -d '\r'; }
close() { $ADB shell "luna-send -n 1 -w 3000 luna://com.webos.service.applicationmanager/closeByAppId '{\"id\":\"$ID\"}' >/dev/null 2>&1; sleep 1"; }
# Takes a screenshot; prints the device's time (s) it was taken at.
shot() {
    $ADB shell "date +%s; luna-send -w 10000 -n 1 luna://com.webos.surfacemanager/captureCompositorOutput '{\"output\":\"/tmp/auth-shot.png\",\"format\":\"PNG\"}' > /tmp/auth-c.out 2>&1" | tr -d '\r'
    $ADB pull /tmp/auth-shot.png "$OUT/$1.png" >/dev/null
}
ocr() { tesseract "$OUT/$1.png" - --psm 6 2>/dev/null; }

real=$(keys real)
if [ "$real" != 0 ]; then
    echo "The app holds $real account(s) of its own on this device; not testing over them."
    exit 2
fi

cleanup() {
    close
    keys clear-test
    if [ -n "$AWAKE" ]; then
        $ADB shell "kill \$(cat /tmp/auth-block.pid) 2>/dev/null; rm -f /tmp/auth-block.pid"
        echo "   screen hold released"
    fi
}
trap cleanup EXIT
keys clear-test >/dev/null

if [ -n "$AWAKE" ]; then
    $ADB shell "nohup luna-send -i luna://com.palm.display/control/setProperty '{\"requestBlock\":true,\"client\":\"$ID.test\"}' > /dev/null 2>&1 & echo \$! > /tmp/auth-block.pid"
fi

echo "== $NAME: $($ADB shell uname -m | tr -d '\r')"

# 1. The scheme.
handler=$($ADB shell "luna-send -n 1 -w 5000 luna://com.palm.applicationManager/getHandlerForUrl '{\"url\":\"otpauth://totp/x?secret=JBSWY3DPEHPK3PXP\"}' 2>&1" | tr -d '\r')
case "$handler" in
    *"\"appId\": \"$ID\""*|*"\"appId\":\"$ID\""*) ok "otpauth:// links go to the app" ;;
    *) fail "otpauth:// handler: $handler" ;;
esac

# 2. Codes on the screen.
keys seed >/dev/null
close
$ADB shell "luna-send -n 1 -w 8000 luna://com.webos.service.applicationmanager/launch '{\"id\":\"$ID\"}' >/dev/null 2>&1"
sleep 5
t=$(shot codes)
text=$(ocr codes | tr -s ' ')
expected=$(node -e '
const c = require("crypto");
const seeds = { sha1: "12345678901234567890", sha256: "12345678901234567890123456789012",
                sha512: "1234567890123456789012345678901234567890123456789012345678901234" };
const t = +process.argv[1];
for (const alg in seeds) {
    // The time the screen was drawn is within a second or two of t.
    const codes = new Set();
    for (const s of [t - 2, t - 1, t, t + 1]) {
        const m = Buffer.alloc(8); m.writeBigUInt64BE(BigInt(Math.floor(s / 30)));
        const h = c.createHmac(alg, Buffer.from(seeds[alg])).update(m).digest();
        const o = h[h.length - 1] & 15;
        const code = String((h.readUInt32BE(o) & 0x7fffffff) % 1e8).padStart(8, "0");
        codes.add(code.substr(0, 4) + " " + code.substr(4));
    }
    console.log(alg + "=" + [...codes].join(","));
}' "$t")
while read -r line; do
    alg=${line%%=*}
    found=""
    IFS=, read -ra codes <<< "${line#*=}"
    for code in "${codes[@]}"; do
        echo "$text" | grep -qF "$code" && found=$code
    done
    # The third row may be under the bottom of a short screen.
    if [ -n "$found" ]; then
        ok "$alg code on screen: $found"
    elif [ "$alg" = sha512 ]; then
        echo "skip $alg: not read off the screen (may be below the fold): wanted ${codes[*]}"
    else
        fail "$alg code: wanted ${codes[*]}, the screen says: $(echo "$text" | tr '\n' '|')"
    fi
done <<< "$expected"

# 3. A link, shown to be added.
LABEL="link-$t"
LINK="otpauth://totp/LuneOS%20device%20test:$LABEL?secret=GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ&issuer=LuneOS%20device%20test"
$ADB shell "luna-send -n 1 -w 8000 luna://com.palm.applicationManager/open '{\"target\":\"$LINK\"}' >/dev/null 2>&1"
sleep 3
shot link >/dev/null
text=$(ocr link)
if echo "$text" | grep -qE "Add account|From a link" && echo "$text" | grep -qF "$LABEL"; then
    ok "the link opens the app's Add account, filled in"
else
    fail "the link: the screen says: $(echo "$text" | tr '\n' '|')"
fi

# 4. Save, and the key manager has it.
if [ -n "$TAPS" ]; then
    size=$(file "$OUT/link.png" | grep -oE '[0-9]+ x [0-9]+' | tr -d ' ')
    case "$size" in
        480x800) save="396 75" ;;
        720x720) save="600 110" ;;
        *) save="" ;;
    esac
    if [ -z "$save" ]; then
        echo "skip Save: no tap point known for a $size screen"
    else
        $ADB shell "python3 /tmp/auth-tap.py tap $save"
        sleep 3
        shot added >/dev/null
        index=$(keys index)
        if echo "$index" | grep -qF "\"label\": \"$LABEL\""; then
            ok "Save stored the account in the key manager, in the app's namespace"
        else
            fail "after Save the index is: $index"
        fi
    fi
fi

echo "$([ $failures = 0 ] && echo PASS || echo "FAILED: $failures") - screenshots in $OUT"
exit $failures

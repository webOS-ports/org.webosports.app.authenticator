#!/bin/sh
# Every host test: the JavaScript under Node (vectors, and OpenSSL as a
# second opinion), then the QML tests in QML's own engine (tst_otp.qml),
# the app's pages (tst_ui.qml) and every screen once per device profile
# (tst_screens.qml, pictures in build/test-output/ui), then the export's QR
# codes read back off those pictures with zbar (tests/js/read-qr-shots.js).
#
#   tools/run-tests.sh [path to luneos-components]
#
# tools/mutation-check.sh breaks the code on purpose and checks that these
# notice; tools/test-device.sh tries the app on a device.
set -e
cd "$(dirname "$0")/.."
LC=${1:-../luneos-components}
status=0
echo "== Node"
node tests/js/run-node-tests.js || status=1
echo "== QML"
# Pictures from an earlier run must not be read back as this one's.
rm -f build/test-output/ui/*-export-code.png build/test-output/ui/*-export-codes.png
out=$(tests/run-qml-tests.sh "$LC" 2>&1) || status=1
echo "$out" | grep -E "^(FAIL|XFAIL|XPASS|Totals)|^   (Actual|Expected|Loc)" || true
if [ -n "${PROFILES-x}" ]; then
    echo "== QR codes read back"
    qr=0
    node tests/js/read-qr-shots.js || qr=$?
    # 77: zbar or PIL missing, said so above; not a failure of the app.
    [ $qr -eq 0 ] || [ $qr -eq 77 ] || status=1
fi
exit $status

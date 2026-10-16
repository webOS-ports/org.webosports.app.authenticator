#!/bin/sh
# Every host test: the JavaScript under Node (vectors, and OpenSSL as a
# second opinion), then the QML tests in QML's own engine (tst_otp.qml)
# and the app's pages (tst_ui.qml).
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
out=$(tests/run-qml-tests.sh "$LC" 2>&1) || status=1
echo "$out" | grep -E "^(FAIL|Totals)|^   (Actual|Expected|Loc)" || true
exit $status

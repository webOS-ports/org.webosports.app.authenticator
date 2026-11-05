#!/bin/sh
# Runs the QML tests on the build host: the one-time code JavaScript in
# QML's own engine (tst_otp.qml) and the app's pages (tst_ui.qml) once,
# then every screen (tst_screens.qml) once per device screen in PROFILES -
# by default the mindphone, the Q25, the TouchPad and the FuriPhone FLX1s
# (radon) - each saved as build/test-output/ui/<profile>-<screen>.png. All
# with luneos-components' desktop stand-ins, FakeKeyManager.qml for the key
# manager and FakeAuth.qml for the screen lock and the sensors.
#
#   tests/run-qml-tests.sh [path to luneos-components [qmltestrunner arguments]]
#
# luneos-components needs its desktop build (CONFIG+=desktop, see its
# README) for the style and the LuneOS.Components plugin. QML_TESTS lists
# the files run once (default tst_otp.qml tst_ui.qml, empty for none),
# PROFILES the screens tst_screens.qml runs on (empty for none):
#   QML_TESTS= PROFILES=q25 tests/run-qml-tests.sh <luneos-components>
#
# The stand-ins read their profile, and with it the window's size and the
# grid unit, once as they load, and qmltestrunner passes no --profile on:
# each profile runs against a copy of LunaNext.Common whose default profile
# is that screen, imported ahead of the stand-ins.
set -e
cd "$(dirname "$0")/.."
LC=${1:-../luneos-components}
[ $# -gt 0 ] && shift
QML_TESTS=${QML_TESTS-tst_otp.qml tst_ui.qml}
PROFILES=${PROFILES-mindphone q25 tp radon}
# Throwaway settings and cache, under build/ rather than the user's.
mkdir -p build/test-output/ui
CONF=$(mktemp -d "$PWD/build/qmltest.XXXXXX")
trap 'rm -rf "$CONF"' EXIT

run() {
    rm -rf "$CONF/config" "$CONF/cache"
    XDG_CONFIG_HOME=$CONF/config XDG_CACHE_HOME=$CONF/cache QT_QPA_PLATFORM=${QT_QPA_PLATFORM:-offscreen} \
    QT_QUICK_CONTROLS_STYLE=QtQuick.Controls.LuneOS \
        ${QMLTESTRUNNER:-/usr/lib/qt6/bin/qmltestrunner} \
        -import "$LC/modules" -import "$LC/test/imports" "$@"
}

status=0
for t in $QML_TESTS; do
    echo "--- $t"
    run -input "tests/qml/${t#tests/qml/}" "$@" || status=1
done
for profile in $PROFILES; do
    common=$CONF/profile-$profile/LunaNext/Common
    mkdir -p "$common"
    cp "$LC"/test/imports/LunaNext/Common/* "$common/"
    sed -i "s/^var defaultProfile = .*/var defaultProfile = \"$profile\";/" "$common/SettingsStub.js"
    if ! grep -q "^var defaultProfile = \"$profile\";" "$common/SettingsStub.js"; then
        echo "could not select profile $profile in SettingsStub.js" >&2
        status=1
        continue
    fi
    echo "--- tst_screens.qml ($profile)"
    run -import "$CONF/profile-$profile" -input tests/qml/tst_screens.qml "$@" || status=1
done
exit $status

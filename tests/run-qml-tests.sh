#!/bin/sh
# Runs the QML tests on the build host: the one-time code JavaScript in
# QML's own engine (tst_otp.qml) and the app's pages (tst_ui.qml), with
# luneos-components' desktop stand-ins and FakeKeyManager.qml for the key
# manager.
#
#   tests/run-qml-tests.sh [path to luneos-components [qmltestrunner arguments]]
#
# luneos-components needs its desktop build (CONFIG+=desktop, see its
# README) for the style and the LuneOS.Components plugin. QML_TESTS=<file>
# runs one file.
set -e
cd "$(dirname "$0")/.."
LC=${1:-../luneos-components}
[ $# -gt 0 ] && shift
# Throwaway settings and cache, under build/ rather than the user's.
mkdir -p build
CONF=$(mktemp -d "$PWD/build/qmltest.XXXXXX")
trap 'rm -rf "$CONF"' EXIT
XDG_CONFIG_HOME=$CONF XDG_CACHE_HOME=$CONF/cache QT_QPA_PLATFORM=${QT_QPA_PLATFORM:-offscreen} \
QT_QUICK_CONTROLS_STYLE=QtQuick.Controls.LuneOS \
    ${QMLTESTRUNNER:-/usr/lib/qt6/bin/qmltestrunner} \
    -import "$LC/modules" -import "$LC/test/imports" \
    -input "${QML_TESTS:-tests/qml}" "$@"

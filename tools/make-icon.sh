#!/bin/sh
# Renders images/icon.svg to icon.png and icon-256x256.png (256x256) with
# Qt's SVG renderer (tools/icon/tst_render_icon.qml).
#
#   tools/make-icon.sh
set -e
cd "$(dirname "$0")/.."
QT_QPA_PLATFORM=${QT_QPA_PLATFORM:-offscreen} ${QMLTESTRUNNER:-/usr/lib/qt6/bin/qmltestrunner} \
    -input tools/icon/tst_render_icon.qml -silent

/*
 * Copyright 2026 Herman van Hazendonk <github.com@herrie.org>
 * SPDX-License-Identifier: GPL-3.0-only
 *
 * Not a test: renders images/icon.svg to icon.png and icon-256x256.png
 * with Qt's SVG renderer, the one the device draws with. Run through
 * qmltestrunner, the host's only QML runtime here, by tools/make-icon.sh.
 */
import QtQuick
import QtTest

TestCase {
    name: "RenderIcon"
    when: windowShown

    Image {
        id: image
        width: 256
        height: 256
        source: Qt.resolvedUrl("../../images/icon.svg")
        sourceSize.width: 256
        sourceSize.height: 256
    }

    function localPath(relative) {
        return Qt.resolvedUrl(relative).toString().replace(/^file:\/\//, "");
    }

    function test_render() {
        tryCompare(image, "status", Image.Ready);
        var done = false;
        image.grabToImage(function(result) {
            verify(result.saveToFile(localPath("../../icon.png")));
            verify(result.saveToFile(localPath("../../icon-256x256.png")));
            done = true;
        }, Qt.size(256, 256));
        tryVerify(function() { return done; });
    }
}

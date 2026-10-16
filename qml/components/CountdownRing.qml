/*
 * Copyright 2026 Herman van Hazendonk <github.com@herrie.org>
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

import QtQuick
import QtQuick.Shapes
import QtQuick.Controls

import LunaNext.Common 0.1

/*
 * How long the code has left: a ring that empties clockwise from the top,
 * with the seconds in it. Red for the last five seconds, when a code
 * typed now may well arrive too late.
 */
Item {
    id: ring

    property int secondsLeft: 30
    property int period: 30
    readonly property bool ending: secondsLeft <= 5
    readonly property real fraction: period > 0 ? Math.max(0, Math.min(1, secondsLeft / period)) : 0
    property color color: ending ? "#be0003" : "#2a7ab0"
    property real lineWidth: Math.max(2, width / 10)

    implicitWidth: Units.gu(4.5)
    implicitHeight: implicitWidth

    Shape {
        anchors.fill: parent
        // The track, then what is left on it.
        ShapePath {
            strokeColor: "#30000000"
            strokeWidth: ring.lineWidth
            fillColor: "transparent"
            PathAngleArc {
                centerX: ring.width / 2
                centerY: ring.height / 2
                radiusX: (ring.width - ring.lineWidth) / 2
                radiusY: radiusX
                startAngle: -90
                sweepAngle: 360
            }
        }
        ShapePath {
            strokeColor: ring.color
            strokeWidth: ring.lineWidth
            fillColor: "transparent"
            capStyle: ShapePath.FlatCap
            PathAngleArc {
                objectName: "remainingArc"
                centerX: ring.width / 2
                centerY: ring.height / 2
                radiusX: (ring.width - ring.lineWidth) / 2
                radiusY: radiusX
                startAngle: -90
                sweepAngle: 360 * ring.fraction
            }
        }
    }

    Label {
        anchors.centerIn: parent
        text: ring.secondsLeft
        color: ring.ending ? "#be0003" : "#2a2929"
        font.pixelSize: ring.height * 0.36
    }
}

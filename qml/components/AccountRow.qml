/*
 * Copyright 2026 Herman van Hazendonk <github.com@herrie.org>
 *
 * This program is free software: you can redistribute it and/or modify it
 * under the terms of the GNU General Public License version 3, as published
 * by the Free Software Foundation.
 *
 * This program is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranties of
 * MERCHANTABILITY, SATISFACTORY QUALITY, or FITNESS FOR A PARTICULAR
 * PURPOSE.  See the GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License along
 * with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 * SPDX-License-Identifier: GPL-3.0-only
 */

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import QtQuick.Controls.LuneOS 2.0
import LunaNext.Common 0.1
import LuneOS.Components 1.0
import LuneOS.Forms 1.0

import "../js/Otp.js" as Otp
import "../js/Accounts.js" as Accounts

/*
 * One account: the site and the name, the code, and how long it has left
 * (time-based) or a button for the next one (counter-based). Tap to copy
 * the code; touch and hold for Edit and Delete. While reordering, arrows
 * take the place of the code's timer.
 */
Item {
    id: row

    property var account: ({})
    // The secret's bytes; null when the key manager has none for it.
    property var key: null
    property real now: 0
    property bool reordering: false
    // Smaller codes, for a short screen (the Q25's square) to show more rows.
    property bool compact: false
    property int index: 0
    property int count: 1

    signal copyRequested(string code)
    signal menuRequested()
    signal nextCodeRequested()
    signal moveRequested(int to)

    readonly property bool timeBased: account.type !== "hotp"
    readonly property real step: timeBased ? Otp.timeStep(now, account.period) : -1
    // For a counter-based account, the counter of the code on show; -1 for
    // none yet (each one shown costs a step of the counter, so not unasked).
    property real shownCounter: -1
    readonly property string code: codeFor(step, shownCounter)

    function codeFor(timeStep, counter) {
        if (!key)
            return "";
        if (timeBased)
            return Otp.hotp(key, timeStep, account.digits, account.algorithm);
        return counter >= 0 ? Otp.hotp(key, counter, account.digits, account.algorithm) : "";
    }

    width: ListView.view ? ListView.view.width : implicitWidth
    height: Math.max(compact ? Units.gu(7) : Units.gu(9), content.implicitHeight + (compact ? Units.gu(1) : Units.gu(2)))

    Rectangle {
        anchors.fill: parent
        color: mouse.pressed && !row.reordering ? "#20000000" : "transparent"
    }

    MouseArea {
        id: mouse
        objectName: "rowMouse"
        anchors.fill: parent
        enabled: !row.reordering
        onClicked: {
            if (row.code !== "")
                row.copyRequested(row.code);
            else if (!row.timeBased && row.key)
                row.nextCodeRequested();
        }
        onPressAndHold: row.menuRequested()
    }

    RowLayout {
        id: content
        anchors.fill: parent
        anchors.leftMargin: Units.gu(2)
        anchors.rightMargin: Units.gu(2)
        spacing: Units.gu(1.5)

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            Label {
                objectName: "titleLabel"
                Layout.fillWidth: true
                text: Accounts.title(row.account)
                elide: Text.ElideRight
                font.weight: Font.Bold
                font.pixelSize: FontUtils.sizeToPixels("medium")
                color: Colors.text
            }
            Label {
                objectName: "subtitleLabel"
                Layout.fillWidth: true
                visible: text !== ""
                text: Accounts.subtitle(row.account)
                elide: Text.ElideRight
                font.pixelSize: FontUtils.sizeToPixels("small")
                color: Colors.secondaryText
            }
            Label {
                objectName: "codeLabel"
                Layout.fillWidth: true
                text: !row.key ? "No key stored; add the account again."
                      : row.code !== "" ? Otp.format(row.code)
                      : "Tap for a code"
                elide: Text.ElideRight
                color: !row.key ? Colors.error
                       : row.code === "" ? Colors.secondaryText
                       : (row.timeBased && ring.ending ? "#be0003" : "#1f5f8b")
                font.pixelSize: row.code !== "" ? FontUtils.sizeToPixels(row.compact ? "large" : "x-large")
                                                : FontUtils.sizeToPixels("medium")
                font.weight: row.code !== "" ? Font.Bold : Font.Normal
                font.letterSpacing: row.code !== "" ? Units.gu(0.2) : 0
            }
        }

        CountdownRing {
            id: ring
            objectName: "countdownRing"
            visible: row.timeBased && !row.reordering && !!row.key
            period: row.account.period || 30
            secondsLeft: Otp.secondsLeft(row.now, period)
        }

        Button {
            objectName: "nextCodeButton"
            visible: !row.timeBased && !row.reordering && !!row.key
            text: row.code === "" ? "Show code" : "Next code"
            onClicked: row.nextCodeRequested()
        }

        Button {
            objectName: "moveUpButton"
            visible: row.reordering
            enabled: row.index > 0
            text: "Up"
            implicitWidth: Units.gu(8)
            onClicked: row.moveRequested(row.index - 1)
        }
        Button {
            objectName: "moveDownButton"
            visible: row.reordering
            enabled: row.index < row.count - 1
            text: "Down"
            implicitWidth: Units.gu(8)
            onClicked: row.moveRequested(row.index + 1)
        }
    }

    ListDelegateSeparator {
        anchors.fill: parent
        index: row.index
        count: row.count
    }
}

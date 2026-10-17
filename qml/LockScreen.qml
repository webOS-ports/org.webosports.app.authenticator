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

import LunaNext.Common 0.1
import LuneOS.Passcode 1.0

/*
 * Over the whole window while the app is locked: a fingerprint, or the
 * screen lock passcode, entered the way the lock screen takes it (PIN pad,
 * password or pattern). Nothing under it can be touched.
 */
Rectangle {
    id: lockScreen

    objectName: "lockScreen"
    color: "#262626"

    // DeviceAuth.
    property var auth: null

    // What to say under the title; "" for the usual prompt.
    property string message: ""
    property bool messageIsError: false
    property bool checking: false
    property string pin: ""
    property int lockoutLeft: 0
    readonly property bool lockedOut: lockoutLeft > 0
    readonly property bool canEnter: !checking && !lockedOut && auth !== null && auth.hasPasscode

    signal unlocked()

    // Locked anew: a clean slate, but a lockout still running stays.
    function reset() {
        message = "";
        messageIsError = false;
        pin = "";
        passwordField.text = "";
        patternGrid.reset();
        if (auth)
            auth.reset();
        focusEntry();
    }

    // Back in front, still locked: the same tries left as before.
    function focusEntry() {
        if (visible && auth && auth.lockMode === "password")
            passwordField.forceActiveFocus();
        else
            lockScreen.forceActiveFocus();
    }

    function prompt() {
        if (!auth || auth.lockMode === "")
            return "Checking the screen lock…";
        var finger = auth.fingerprintActive ? "Touch the fingerprint sensor, or " : "";
        switch (auth.lockMode) {
        case "pin":
            return finger + (finger ? "enter" : "Enter") + " the screen lock PIN.";
        case "password":
            return finger + (finger ? "enter" : "Enter") + " the screen lock password.";
        case "pattern":
            return finger + (finger ? "draw" : "Draw") + " the screen lock pattern.";
        }
        // No passcode to fall back on.
        return (auth.fingerprintActive ? "Touch the fingerprint sensor. " : "")
                + "No screen lock passcode is set; set one in Screen & Lock, then enter it here.";
    }

    function waitText(seconds) {
        if (seconds < 60)
            return "Too many tries. Try again in " + seconds + (seconds === 1 ? " second." : " seconds.");
        var minutes = Math.ceil(seconds / 60);
        return "Too many tries. Try again in " + minutes + (minutes === 1 ? " minute." : " minutes.");
    }

    function submit(passcode) {
        if (!canEnter || passcode === "")
            return;
        checking = true;
        auth.checkPasscode(passcode, function(result) {
            checking = false;
            pin = "";
            passwordField.text = "";
            patternGrid.reset();
            if (result.matched) {
                message = "";
                unlocked();
            } else if (result.error) {
                message = result.error;
                messageIsError = true;
            } else if (result.lockedOut) {
                lockoutLeft = result.lockoutSeconds;
                message = "";
            } else {
                message = auth.lockMode === "pattern" ? "That is not the pattern."
                        : auth.lockMode === "pin" ? "That is not the PIN." : "That is not the password.";
                messageIsError = true;
                if (auth.lockMode === "pattern")
                    patternGrid.showError();
            }
        });
    }

    Connections {
        target: lockScreen.auth
        function onFingerprintMatched() {
            lockScreen.message = "";
            lockScreen.unlocked();
        }
        function onFingerprintMissed() {
            lockScreen.messageIsError = true;
            lockScreen.message = lockScreen.auth.fingerprintMisses >= lockScreen.auth.maxFingerprintMisses
                    ? "Too many tries with the fingerprint; use the passcode."
                    : "The fingerprint was not recognised.";
        }
    }

    Timer {
        interval: 1000
        repeat: true
        running: lockScreen.lockedOut
        onTriggered: lockScreen.lockoutLeft--
    }

    // Taps and drags stop here.
    MouseArea {
        anchors.fill: parent
    }

    // A keyboard (the Q25's) types the PIN too.
    Keys.onPressed: function(event) {
        if (!auth || auth.lockMode !== "pin")
            return;
        if (event.text.length === 1 && event.text >= "0" && event.text <= "9") {
            if (canEnter)
                pin += event.text;
            event.accepted = true;
        } else if (event.key === Qt.Key_Backspace) {
            pin = pin.slice(0, -1);
            event.accepted = true;
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            submit(pin);
            event.accepted = true;
        }
    }
    // The back gesture has nothing to go back to.
    Keys.onEscapePressed: function(event) { event.accepted = true; }

    Flickable {
        anchors.fill: parent
        contentHeight: Math.max(height, column.implicitHeight + Units.gu(4))
        boundsBehavior: Flickable.StopAtBounds
        clip: true

        Column {
            id: column
            y: Math.max(Units.gu(2), (parent.height - implicitHeight) / 2)
            width: parent.width
            spacing: Units.gu(1.5)

            Image {
                anchors.horizontalCenter: parent.horizontalCenter
                source: Qt.resolvedUrl("../icon.png")
                width: Units.gu(6)
                height: width
                sourceSize.width: width
                sourceSize.height: height
            }

            Label {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Authenticator is locked"
                color: "white"
                font.bold: true
                font.pixelSize: FontUtils.sizeToPixels("large")
            }

            Label {
                objectName: "lockMessage"
                x: Units.gu(2)
                width: parent.width - Units.gu(4)
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                color: lockScreen.lockedOut || lockScreen.messageIsError ? "#ff8a80" : "#d0d0d0"
                text: lockScreen.lockedOut ? lockScreen.waitText(lockScreen.lockoutLeft)
                    : lockScreen.message !== "" ? lockScreen.message : lockScreen.prompt()
            }

            // PIN: dots for what is typed, and the pad.
            Label {
                objectName: "pinDots"
                anchors.horizontalCenter: parent.horizontalCenter
                visible: lockScreen.auth !== null && lockScreen.auth.lockMode === "pin"
                height: Units.gu(4)
                verticalAlignment: Text.AlignVCenter
                color: "white"
                font.pixelSize: FontUtils.sizeToPixels("x-large")
                font.letterSpacing: Units.gu(0.5)
                text: "●".repeat(lockScreen.pin.length)
            }
            PinPad {
                objectName: "pinPad"
                anchors.horizontalCenter: parent.horizontalCenter
                visible: lockScreen.auth !== null && lockScreen.auth.lockMode === "pin"
                enabled: lockScreen.canEnter
                width: Math.min(Units.gu(32), lockScreen.width - Units.gu(4))
                onKeyAction: function(keyText) {
                    if (keyText === "\b")
                        lockScreen.pin = lockScreen.pin.slice(0, -1);
                    else
                        lockScreen.pin += keyText;
                }
            }

            TextField {
                id: passwordField
                objectName: "passwordField"
                anchors.horizontalCenter: parent.horizontalCenter
                visible: lockScreen.auth !== null && lockScreen.auth.lockMode === "password"
                enabled: lockScreen.canEnter
                width: Math.min(Units.gu(32), lockScreen.width - Units.gu(4))
                echoMode: TextInput.Password
                inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
                placeholderText: "Password"
                onAccepted: lockScreen.submit(text)
            }

            PatternLockGrid {
                id: patternGrid
                objectName: "patternGrid"
                anchors.horizontalCenter: parent.horizontalCenter
                visible: lockScreen.auth !== null && lockScreen.auth.lockMode === "pattern"
                enabled: lockScreen.canEnter
                width: Math.min(Units.gu(28), lockScreen.width - Units.gu(4))
                height: width
                onPatternDrawn: function(encoded) { lockScreen.submit(encoded); }
                onTooShort: {
                    lockScreen.message = "That is not the pattern.";
                    lockScreen.messageIsError = true;
                    patternGrid.reset();
                }
            }

            Button {
                objectName: "unlockButton"
                anchors.horizontalCenter: parent.horizontalCenter
                visible: lockScreen.auth !== null
                         && (lockScreen.auth.lockMode === "pin" || lockScreen.auth.lockMode === "password")
                enabled: lockScreen.canEnter
                         && (lockScreen.auth.lockMode === "pin" ? lockScreen.pin : passwordField.text) !== ""
                width: Math.min(Units.gu(20), lockScreen.width - Units.gu(4))
                text: lockScreen.checking ? "Checking…" : "Unlock"
                onClicked: lockScreen.submit(lockScreen.auth.lockMode === "pin" ? lockScreen.pin : passwordField.text)
            }
        }
    }
}

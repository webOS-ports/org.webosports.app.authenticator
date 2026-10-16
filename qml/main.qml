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
import QtQuick.Controls
import QtQuick.Controls.LuneOS 2.0

import LunaNext.Common 0.1
import LuneOS.Service 1.0
import LuneOS.System 1.0
import LuneOS.Forms 1.0

import "js/OtpAuthUri.js" as OtpAuthUri

/*
 * Authenticator: the one-time codes for signing in with two-step
 * verification, time-based (TOTP) and counter-based (HOTP). Accounts come
 * from an otpauth:// link - a QR code read by the Camera opens here - or
 * are typed in.
 */
AppWindow {
    id: appWindow

    title: "Authenticator"
    icon: Qt.resolvedUrl("../icon.png")
    initialPage: Qt.resolvedUrl("AccountsPage.qml")

    readonly property string appId: "org.webosports.app.authenticator"

    // The bus the accounts are kept over; the tests hand in a stand-in.
    property var bus: service
    // The time the codes are for. The tests set their own.
    property var clock: function() { return Date.now(); }
    property real now: clock()

    property alias store: accountStore
    property alias appMenu: appMenu
    // Says what went wrong, under the header, until dismissed.
    property string notice: ""
    // A short "Copied" and the like, that goes by itself.
    property string toast: ""
    // An otpauth:// link that came before the accounts were read.
    property string pendingLink: ""

    LunaService {
        id: service
        name: appWindow.appId
    }

    AccountStore {
        id: accountStore
        bus: appWindow.bus
        onSaveFailed: function(message) { appWindow.notice = message; }
        onStatusChanged: {
            if (status === "ready" && appWindow.pendingLink !== "") {
                var link = appWindow.pendingLink;
                appWindow.pendingLink = "";
                appWindow.openLink(link);
            }
        }
    }

    Component.onCompleted: accountStore.load()

    // The codes change on the second; nothing runs while the card is in the
    // background.
    Timer {
        interval: 500
        repeat: true
        running: Qt.application.state === Qt.ApplicationActive
        onTriggered: appWindow.now = appWindow.clock()
    }
    Connections {
        target: Qt.application
        function onStateChanged() {
            if (Qt.application.state === Qt.ApplicationActive)
                appWindow.now = appWindow.clock();
        }
    }

    // QML has no clipboard of its own; a text field does.
    TextEdit {
        id: clipboardHelper
        visible: false
    }

    function copyText(text) {
        clipboardHelper.text = text;
        clipboardHelper.selectAll();
        clipboardHelper.copy();
        clipboardHelper.text = "";
    }

    function showToast(text) {
        toast = text;
        toastTimer.restart();
    }

    Timer {
        id: toastTimer
        interval: 2500
        onTriggered: appWindow.toast = ""
    }

    /*
     * {"target": "otpauth://..."}: the application manager opens such
     * links here (appinfo.json's mimeTypes), from the Camera's QR reader or
     * anywhere else. The account is shown to be added, not added unasked.
     */
    LaunchParams {
        window: appWindow
        onAppMenuRequested: appMenu.popup(0, 0)
        onLaunched: function(params) {
            if (typeof params.target === "string" && params.target !== "")
                appWindow.openLink(params.target);
        }
    }

    function openLink(link) {
        if (!OtpAuthUri.isOtpAuth(link)) {
            notice = "Authenticator only opens otpauth:// links.";
            return;
        }
        if (accountStore.status === "loading") {
            pendingLink = link;
            return;
        }
        var parsed = OtpAuthUri.parse(link);
        if (parsed.error) {
            notice = parsed.error;
            return;
        }
        openEditor({ "prefill": parsed.account, "fromLink": true });
    }

    function openEditor(properties) {
        pageStack.pop(null);
        pageStack.push(Qt.resolvedUrl("EditAccountPage.qml"), properties || {});
    }

    // Needs "application.launcher".
    AppLauncher {
        id: launcher
        clientName: appWindow.appId
    }

    function scanWithCamera() {
        launcher.launch("org.webosports.app.camera", null, undefined, function(error) {
            appWindow.notice = "Could not open the Camera: " + error;
        });
    }

    Menu {
        id: appMenu
        // The app menu drops from the top of the window. Declared in
        // AppWindow it would sit in the column under the header.
        parent: appWindow.contentItem
        LuneOSMenu.appMenuStyle: true

        MenuItem {
            text: "Add account"
            enabled: accountStore.status === "ready"
            onTriggered: appWindow.openEditor({})
        }
        MenuItem {
            text: "Scan a QR code"
            onTriggered: appWindow.scanWithCamera()
        }
        MenuItem {
            objectName: "reorderMenuItem"
            text: "Change the order"
            enabled: accountStore.status === "ready" && accountStore.accounts.length > 1
            onTriggered: {
                appWindow.pageStack.pop(null);
                appWindow.pageStack.currentItem.reordering = true;
            }
        }
    }

    // Under the header: trouble, until dismissed.
    Item {
        width: appWindow.width
        height: statusNotice.visible ? statusNotice.height + Units.gu(2) : 0

        StatusNotice {
            id: statusNotice
            objectName: "statusNotice"

            x: Units.gu(1)
            y: Units.gu(1)
            width: parent.width - Units.gu(2)
            visible: text !== ""
            text: accountStore.status === "failed" ? accountStore.errorText : appWindow.notice
            onDismissed: {
                if (accountStore.status === "failed")
                    accountStore.load();
                appWindow.notice = "";
            }
        }
    }

    // "Copied": at the bottom, over the list, for a moment.
    Rectangle {
        objectName: "toast"
        parent: appWindow.contentItem
        z: 100
        visible: appWindow.toast !== ""
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Units.gu(3)
        width: toastLabel.implicitWidth + Units.gu(4)
        height: toastLabel.implicitHeight + Units.gu(2)
        radius: height / 2
        color: "#e0303030"

        Label {
            id: toastLabel
            anchors.centerIn: parent
            color: "white"
            text: appWindow.toast
            font.pixelSize: FontUtils.sizeToPixels("medium")
        }
    }
}

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
import QtQuick.Controls.LuneOS 2.0

import LunaNext.Common 0.1
import LuneOS.Service 1.0
import LuneOS.System 1.0
import LuneOS.Forms 1.0
import LuneOS.Components 1.0

import "js/OtpAuthUri.js" as OtpAuthUri

/*
 * Authenticator: the one-time codes for signing in with two-step
 * verification, time-based (TOTP) and counter-based (HOTP). Accounts come
 * from an otpauth:// link - a QR code read by the Camera opens here - or
 * are typed in.
 *
 * Locked (store.lockEnabled), it asks for a fingerprint or the screen lock
 * passcode when it starts, and again after relockAfterMs in the
 * background, before the secrets are read.
 */
AppWindow {
    id: appWindow

    title: "Authenticator"
    icon: Qt.resolvedUrl("../icon.png")
    initialPage: Qt.resolvedUrl("AccountsPage.qml")

    readonly property string appId: "org.webosports.app.authenticator"

    // The bus the accounts are kept over; the tests hand in a stand-in.
    property var bus: service
    // The bus for the screen lock and the fingerprint sensor; likewise.
    property var authBus: service
    // The time the codes are for. The tests set their own.
    property var clock: function() { return Date.now(); }
    property real now: clock()

    property alias store: accountStore
    property alias appMenu: appMenu
    // Says what went wrong, under the header, until dismissed.
    property string notice: ""
    // An otpauth:// link that came before the accounts were read.
    property string pendingLink: ""

    // In front, not in the background; the tests set it themselves.
    property bool inFront: Qt.application.state === Qt.ApplicationActive
    onInFrontChanged: {
        if (inFront)
            now = clock();
        _stateChanged(inFront);
    }

    // Time in the background after which the app locks again.
    property int relockAfterMs: 60000
    // When the app went to the background, by lockClock; 0 when in front.
    property real backgroundSince: 0
    // Not the codes' clock, which the tests stop.
    property var lockClock: function() { return Date.now(); }
    // Asked to lock while a change was being saved: covered already.
    property bool relocking: false
    readonly property bool locked: accountStore.status === "locked" || relocking
    property alias deviceAuth: deviceAuth

    LunaService {
        id: service
        name: appWindow.appId
    }

    AccountStore {
        id: accountStore
        bus: appWindow.bus
        onSaveFailed: function(message) { appWindow.notice = message; }
        onStatusChanged: {
            if (status !== "ready")
                appWindow.relocking = false;
            if (status === "ready" && appWindow.pendingLink !== "") {
                var link = appWindow.pendingLink;
                appWindow.pendingLink = "";
                appWindow.openLink(link);
            }
        }
    }

    Component.onCompleted: accountStore.load()

    DeviceAuth {
        id: deviceAuth
        bus: appWindow.authBus
        listening: appWindow.locked && accountStore.status === "locked" && appWindow.inFront
        faceAllowed: accountStore.faceEnabled
    }

    // Leaves the pages and lets go of the secrets.
    function lock() {
        if (!accountStore.lockEnabled || accountStore.status !== "ready" || relocking)
            return;
        appMenu.close();
        pageStack.pop(null);
        relocking = true;
        accountStore.lock();
    }

    onLockedChanged: {
        if (locked)
            lockScreen.reset();
    }

    // Away long enough: locked, even if timers do not run in the
    // background (checked again on coming back).
    Timer {
        interval: appWindow.relockAfterMs
        running: appWindow.backgroundSince > 0 && accountStore.lockEnabled
        onTriggered: appWindow.lock()
    }

    function _stateChanged(active) {
        if (!active) {
            if (backgroundSince === 0)
                backgroundSince = lockClock();
            return;
        }
        if (backgroundSince > 0 && lockClock() - backgroundSince >= relockAfterMs)
            lock();
        backgroundSince = 0;
        if (locked) {
            deviceAuth.cameBack();
            lockScreen.focusEntry();
        }
    }

    // Face is asked about first: it is weaker, and the dialog says so.
    function toggleFace() {
        if (accountStore.faceEnabled) {
            accountStore.setFaceEnabled(false, function(error) {
                if (error === "")
                    showToast("No longer opened with a face");
            });
            return;
        }
        faceDialog.ask({
            title: "Open with a face?",
            message: "A face is weaker than the passcode: the camera sees only a picture, so someone who "
                     + "looks like you, or a good photo of you, can sometimes pass. Anyone who opens the "
                     + "app can see and copy your codes.",
            onAccepted: function() {
                accountStore.setFaceEnabled(true, function(error) {
                    if (error === "")
                        showToast("Opened with a face too");
                });
            }
        });
    }

    function toggleLock() {
        if (!accountStore.lockEnabled && !deviceAuth.hasPasscode) {
            notice = "Set a screen lock passcode in Screen & Lock first: it opens the app when "
                    + "a fingerprint cannot.";
            return;
        }
        var on = !accountStore.lockEnabled;
        accountStore.setLockEnabled(on, function(error) {
            if (error === "")
                showToast(on ? "Locked when opened" : "No longer locked");
        });
    }

    // The codes change on the second; nothing runs while the card is in the
    // background.
    Timer {
        interval: 500
        repeat: true
        running: appWindow.inFront
        onTriggered: appWindow.now = appWindow.clock()
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

    // A short "Copied" and the like, that goes by itself.
    function showToast(text) {
        toast.show(text);
    }

    /*
     * {"target": "otpauth://..."}: the application manager opens such
     * links here (appinfo.json's mimeTypes), from the Camera's QR reader or
     * anywhere else. The account is shown to be added, not added unasked.
     */
    LaunchParams {
        window: appWindow
        onAppMenuRequested: {
            if (!appWindow.locked)
                appMenu.popup(0, 0);
        }
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
        if (accountStore.status === "loading" || locked) {
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
        MenuItem {
            objectName: "lockMenuItem"
            text: accountStore.lockEnabled ? "Stop locking the app" : "Lock with fingerprint or passcode"
            enabled: accountStore.status === "ready"
            onTriggered: appWindow.toggleLock()
        }
        // Only where a face is enrolled, or it is on already.
        MenuItem {
            objectName: "faceMenuItem"
            text: accountStore.faceEnabled ? "Stop opening with a face" : "Also open with a face"
            visible: accountStore.lockEnabled
                     && (accountStore.faceEnabled || (deviceAuth.faceAvailable && deviceAuth.faceEnrolled))
            height: visible ? implicitHeight : 0
            enabled: accountStore.status === "ready"
            onTriggered: appWindow.toggleFace()
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

    ConfirmDialog {
        id: faceDialog
        objectName: "faceDialog"
        parent: appWindow.contentItem
        visible: false
        dialogHeight: Units.gu(30)
        dialogWidth: Math.min(Units.gu(40), appWindow.width - Units.gu(4))
    }

    LockScreen {
        id: lockScreen
        parent: appWindow.contentItem
        anchors.fill: parent
        z: 200
        visible: appWindow.locked
        auth: deviceAuth
        onUnlocked: accountStore.unlock()
    }

    // "Copied": at the bottom, over the list, for a moment.
    Toast {
        id: toast
        parent: appWindow.contentItem
        anchors.centerIn: undefined
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Units.gu(3)
        // The app's pill, as it was, there and gone without a fade
        radius: height / 2
        color: "#e0303030"
        fadeDuration: 0
    }
}

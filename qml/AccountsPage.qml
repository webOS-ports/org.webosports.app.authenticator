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
import QtQuick.Layouts

import QtQuick.Controls.LuneOS 2.0
import LunaNext.Common 0.1
import LuneOS.Components 1.0
import LuneOS.Forms 1.0

import "components"
import "js/Accounts.js" as Accounts

/*
 * The accounts and their codes. Tap a code to copy it; touch and hold an
 * account to edit or delete it. "Change the order" in the app menu puts
 * arrows on the rows; the back gesture or Done ends it.
 */
AppPage {
    id: page

    objectName: "accountsPage"
    title: "Authenticator"
    focus: true

    readonly property var store: appWindow.store
    property bool reordering: false
    // The account the touch-and-hold menu is about.
    property var menuAccount: null

    explanationOnShortScreen: false
    explanation: reordering ? ""
               : store.status === "ready" && store.accounts.length > 0
                 ? "Tap a code to copy it; touch and hold an account to edit or delete it." : ""

    headerAction: reordering ? doneAction : (store.status === "ready" ? addAction : null)

    Component {
        id: addAction
        Button {
            objectName: "addButton"
            text: "Add"
            LuneOSButton.mainColor: LuneOSButton.affirmativeColor
            onClicked: appWindow.openEditor({})
        }
    }
    Component {
        id: doneAction
        Button {
            objectName: "doneButton"
            text: "Done"
            onClicked: page.reordering = false
        }
    }

    // The back gesture: out of a dialog, a menu or reordering first.
    Keys.onEscapePressed: function(event) {
        if (deleteDialog.visible) {
            deleteDialog.visible = false;
            event.accepted = true;
        } else if (reordering) {
            reordering = false;
            event.accepted = true;
        } else {
            event.accepted = false;
        }
    }

    /*
     * The accounts as a ListModel kept in step with the store's list -
     * moved, changed, added and removed in place rather than replaced - so
     * a change does not rebuild every row or scroll the list back to the
     * top.
     */
    ListModel {
        id: accountModel
    }

    function syncModel() {
        var target = store.accounts;
        var i, j;
        for (i = accountModel.count - 1; i >= 0; i--) {
            var id = accountModel.get(i).accountId;
            if (!target.some(function(a) { return a.id === id; }))
                accountModel.remove(i);
        }
        for (i = 0; i < target.length; i++) {
            var a = target[i];
            var entry = { accountId: a.id, type: a.type, issuer: a.issuer, label: a.label,
                          algorithm: a.algorithm, digits: a.digits, period: a.period, counter: a.counter };
            for (j = i; j < accountModel.count; j++) {
                if (accountModel.get(j).accountId === a.id)
                    break;
            }
            if (j >= accountModel.count) {
                accountModel.insert(i, entry);
            } else {
                if (j !== i)
                    accountModel.move(j, i, 1);
                accountModel.set(i, entry);
            }
        }
    }

    Connections {
        target: page.store
        function onAccountsChanged() { page.syncModel(); }
    }
    Component.onCompleted: syncModel()
    // The back gesture comes as Escape to whatever has the focus.
    StackView.onActivated: forceActiveFocus()

    // The counter-based codes on show, by account id: { counter }. Kept
    // here, not in the rows, which come and go as the list scrolls.
    property var shownCounters: ({})

    ListView {
        id: list
        objectName: "accountsList"
        anchors.fill: parent
        clip: true
        visible: page.store.status === "ready" && count > 0
        model: accountModel

        delegate: AccountRow {
            id: row
            required property string accountId
            required property string type
            required property string issuer
            required property string label
            required property string algorithm
            required property int digits
            required property int period
            required property real counter
            required property int index

            account: ({ id: accountId, type: type, issuer: issuer, label: label,
                        algorithm: algorithm, digits: digits, period: period, counter: counter })
            key: page.store.keyOf(accountId)
            now: appWindow.now
            reordering: page.reordering
            compact: list.height < Units.gu(60)
            count: list.count
            shownCounter: page.shownCounters[accountId] !== undefined ? page.shownCounters[accountId] : -1
            onCopyRequested: function(code) {
                appWindow.copyText(code);
                appWindow.showToast("Copied " + Accounts.title(account) + "’s code");
            }
            onMenuRequested: {
                page.menuAccount = account;
                accountMenu.popup();
            }
            onNextCodeRequested: {
                var id = accountId;
                page.store.advanceCounter(id, function(error, shown) {
                    if (error !== "")
                        return;
                    var counters = Object.assign({}, page.shownCounters);
                    counters[id] = shown;
                    page.shownCounters = counters;
                });
            }
            onMoveRequested: function(to) { page.store.move(index, to); }
        }
    }

    // No accounts yet: how to get one.
    ColumnLayout {
        objectName: "emptyState"
        anchors.centerIn: parent
        width: Math.min(parent.width - Units.gu(4), Units.gu(45))
        visible: page.store.status === "ready" && page.store.accounts.length === 0
        spacing: Units.gu(2)

        Label {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: "No accounts yet"
            font.pixelSize: FontUtils.sizeToPixels("large")
            font.weight: Font.Bold
            color: Colors.text
        }
        Label {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: "When a site offers two-step verification, it shows a QR code and a key. Read the QR code with the Camera, or type the key in here."
            color: Colors.secondaryText
            font.pixelSize: FontUtils.sizeToPixels("medium")
        }
        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: Units.gu(1)
            Button {
                objectName: "scanButton"
                text: "Scan QR code"
                onClicked: appWindow.scanWithCamera()
            }
            Button {
                objectName: "typeKeyButton"
                text: "Enter a key"
                LuneOSButton.mainColor: LuneOSButton.affirmativeColor
                onClicked: appWindow.openEditor({})
            }
        }
    }

    BusyIndicator {
        anchors.centerIn: parent
        running: page.store.status === "loading"
        visible: running
    }

    property alias accountMenu: accountMenu
    Menu {
        id: accountMenu
        objectName: "accountMenu"

        MenuItem {
            objectName: "editMenuItem"
            text: "Edit"
            onTriggered: appWindow.openEditor({ "accountId": page.menuAccount.id })
        }
        MenuItem {
            objectName: "deleteMenuItem"
            text: "Delete"
            onTriggered: {
                deleteDialog.visible = true;
                page.forceActiveFocus();
            }
        }
    }

    ConfirmDialog {
        id: deleteDialog
        objectName: "deleteDialog"

        visible: false
        title: "Delete account"
        message: page.menuAccount
                 ? "Delete “" + Accounts.title(page.menuAccount) + "”? Without it you cannot make its codes, so turn off two-step verification at the site first, or keep its recovery codes."
                 : ""
        dialogHeight: Units.gu(25)
        dialogWidth: Math.min(Units.gu(40), page.width - Units.gu(4))
        onAccepted: {
            visible = false;
            if (page.menuAccount)
                page.store.remove(page.menuAccount.id);
        }
        onRejected: visible = false
    }
}

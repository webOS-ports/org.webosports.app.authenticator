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

import "js/Accounts.js" as Accounts
import "js/Base32.js" as Base32
import "js/OtpAuthUri.js" as OtpAuthUri

/*
 * A new account, typed in or from an otpauth:// link, or one to change.
 * Most sites need only the key: time-based, SHA1, 6 digits, 30 seconds
 * are what nearly all of them use, so those sit under "More settings".
 * An otpauth:// link pasted into the key field fills in everything.
 */
AppPage {
    id: page

    objectName: "editAccountPage"
    title: accountId !== "" ? "Edit account" : "Add account"
    focus: true

    readonly property var store: appWindow.store
    // The account being changed; "" for a new one.
    property string accountId: ""
    // Fields to start from: an otpauth:// link's.
    property var prefill: null
    // From a link, so the user is asked to check it, not to type it.
    property bool fromLink: false
    // Once Save has been tried, every problem shows, not just the key's.
    property bool triedSave: false
    property bool saving: false

    readonly property bool editing: accountId !== ""
    readonly property var fields: ({
        type: typeSelector.value,
        issuer: issuerField.text,
        label: labelField.text,
        secret: secretField.text,
        algorithm: algorithmSelector.value,
        digits: digitsSelector.value,
        period: parseInt(periodField.text, 10),
        counter: parseInt(counterField.text, 10)
    })
    readonly property var problems: Accounts.problems(fields, editing)
    readonly property bool acceptable: Object.keys(problems).length === 0

    headerAction: Component {
        Button {
            objectName: "saveButton"
            text: "Save"
            enabled: !page.saving
            LuneOSButton.mainColor: LuneOSButton.affirmativeColor
            onClicked: page.save()
        }
    }

    function fill(account) {
        typeSelector.value = account.type || "totp";
        issuerField.text = account.issuer || "";
        labelField.text = account.label || "";
        algorithmSelector.value = account.algorithm || "SHA1";
        digitsSelector.value = account.digits || 6;
        periodField.text = String(account.period || 30);
        counterField.text = String(account.counter || 0);
        if (account.secret !== undefined) {
            secretField.text = account.secret;
            // The start of the key in view, to check against the site's.
            secretField.cursorPosition = 0;
        }
        moreSettings.checked = moreSettings.checked || account.type === "hotp"
                || account.algorithm !== "SHA1" || account.digits !== 6 || account.period !== 30;
    }

    // The back gesture comes as Escape to whatever has the focus.
    StackView.onActivated: forceActiveFocus()

    Component.onCompleted: {
        if (editing) {
            var account = store.accountById(accountId);
            if (account)
                fill(account);
        } else if (prefill) {
            fill(prefill);
        }
    }

    function save() {
        triedSave = true;
        if (!acceptable)
            return;
        var f = fields;
        if (!editing && Accounts.isDuplicate(store.accounts, f, f.secret, store._secrets)) {
            appWindow.notice = "“" + Accounts.title(Accounts.metaFrom(f, "")) + "” is already there.";
            appWindow.pageStack.pop();
            return;
        }
        saving = true;
        var done = function(error) {
            saving = false;
            if (error === "") {
                appWindow.showToast(page.editing ? "Saved" : "Added " + Accounts.title(Accounts.metaFrom(f, "")));
                appWindow.pageStack.pop();
            }
        };
        if (editing)
            store.update(accountId, f, done);
        else
            store.add(f, done);
    }

    Flickable {
        id: flick
        anchors.fill: parent
        contentHeight: content.implicitHeight + Units.gu(2)
        clip: true

        ColumnLayout {
            id: content

            x: Units.gu(1)
            y: Units.gu(1)
            width: parent.width - Units.gu(2)
            spacing: Units.gu(1)

            ExplanationText {
                objectName: "linkExplanation"
                Layout.fillWidth: true
                visible: page.fromLink
                text: "From a link: check that this is the site you meant, then Save."
            }

            FormGroup {
                Layout.fillWidth: true
                title: "Account"

                LabelAndTextField {
                    id: issuerField
                    objectName: "issuerField"
                    label: "Site"
                    placeholderText: "Example"
                    inputMethodHints: Qt.ImhNoPredictiveText
                }
                LabelAndTextField {
                    id: labelField
                    objectName: "labelField"
                    label: "Name"
                    placeholderText: "you@example.com"
                    inputMethodHints: Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
                    acceptable: !(page.triedSave && page.problems.label !== undefined)
                }
            }

            Label {
                objectName: "labelProblem"
                Layout.fillWidth: true
                visible: page.triedSave && page.problems.label !== undefined
                text: page.problems.label || ""
                wrapMode: Text.WordWrap
                color: Colors.error
            }

            FormGroup {
                Layout.fillWidth: true
                title: page.editing ? "Key (leave empty to keep it)" : "Key"

                FormTextField {
                    id: secretField
                    objectName: "secretField"
                    width: parent.width
                    placeholderText: page.editing ? "Unchanged" : "The key the site shows"
                    inputMethodHints: Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase | Qt.ImhSensitiveData
                    font.family: "Liberation Mono"
                    font.pixelSize: FontUtils.sizeToPixels("16pt")
                    acceptable: page.problems.secret === undefined || (!page.triedSave && text === "")
                    // A whole otpauth:// link pasted here fills in the rest.
                    onTextChanged: {
                        if (OtpAuthUri.isOtpAuth(text)) {
                            var parsed = OtpAuthUri.parse(text);
                            if (parsed.account) {
                                page.fill(parsed.account);
                            } else {
                                appWindow.notice = parsed.error;
                                text = "";
                            }
                        }
                    }
                }
            }

            Label {
                objectName: "secretProblem"
                Layout.fillWidth: true
                visible: page.problems.secret !== undefined && (page.triedSave || secretField.text !== "")
                text: page.problems.secret || ""
                wrapMode: Text.WordWrap
                color: Colors.error
            }

            FormGroup {
                Layout.fillWidth: true

                LabelAndSwitch {
                    id: moreSettings
                    objectName: "moreSettingsSwitch"
                    label: "More settings"
                }
            }

            FormGroup {
                Layout.fillWidth: true
                visible: moreSettings.checked
                title: "Settings from the site"

                LabelAndSelector {
                    id: typeSelector
                    objectName: "typeSelector"
                    label: "Codes"
                    model: ["Time-based", "Counter-based"]
                    values: ["totp", "hotp"]
                    value: "totp"
                    onChosen: (v) => typeSelector.value = v
                }
                LabelAndSelector {
                    id: algorithmSelector
                    objectName: "algorithmSelector"
                    label: "Algorithm"
                    model: ["SHA-1", "SHA-256", "SHA-512"]
                    values: ["SHA1", "SHA256", "SHA512"]
                    value: "SHA1"
                    onChosen: (v) => algorithmSelector.value = v
                }
                LabelAndSelector {
                    id: digitsSelector
                    objectName: "digitsSelector"
                    label: "Digits"
                    model: ["6", "7", "8"]
                    values: [6, 7, 8]
                    value: 6
                    onChosen: (v) => digitsSelector.value = v
                }
                LabelAndTextField {
                    id: periodField
                    objectName: "periodField"
                    visible: typeSelector.value === "totp"
                    label: "Seconds per code"
                    text: "30"
                    fieldWidth: Units.gu(10)
                    inputMethodHints: Qt.ImhDigitsOnly
                    acceptable: page.problems.period === undefined
                }
                LabelAndTextField {
                    id: counterField
                    objectName: "counterField"
                    visible: typeSelector.value === "hotp"
                    label: "Counter"
                    text: "0"
                    fieldWidth: Units.gu(10)
                    inputMethodHints: Qt.ImhDigitsOnly
                    acceptable: page.problems.counter === undefined
                }
            }

            Label {
                Layout.fillWidth: true
                visible: moreSettings.checked && (page.problems.period !== undefined || page.problems.counter !== undefined)
                text: page.problems.period || page.problems.counter || ""
                wrapMode: Text.WordWrap
                color: Colors.error
            }

            ExplanationText {
                Layout.fillWidth: true
                visible: moreSettings.checked
                text: "Change these only if the site says so: nearly every site uses time-based codes of 6 digits, SHA-1, every 30 seconds."
            }

            Button {
                objectName: "deleteButton"
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: Units.gu(2)
                visible: page.editing
                text: "Delete account"
                LuneOSButton.mainColor: LuneOSButton.negativeColor
                onClicked: {
                    deleteDialog.ask({
                        title: "Delete account",
                        message: "Delete this account? Without it you cannot make its codes, so turn off two-step verification at the site first, or keep its recovery codes.",
                        onAccepted: function() {
                            page.store.remove(page.accountId, function(error) {
                                if (error === "")
                                    appWindow.pageStack.pop();
                            });
                        }
                    });
                    // So the back gesture reaches this page and closes it.
                    page.forceActiveFocus();
                }
            }
        }
    }

    /* The back gesture closes the dialog, if one is open, and stays on the
     * page: the window goes back a page when Escape is released, so the
     * release is taken here too. */
    property bool _escapeTaken: false
    Keys.onEscapePressed: function(event) {
        if (deleteDialog.visible) {
            deleteDialog.rejected();
            _escapeTaken = true;
            event.accepted = true;
        } else {
            event.accepted = false;
        }
    }
    Keys.onReleased: function(event) {
        if (event.key === Qt.Key_Escape && _escapeTaken) {
            _escapeTaken = false;
            event.accepted = true;
        }
    }

    ConfirmDialog {
        id: deleteDialog
        objectName: "deleteDialog"

        visible: false
        dialogHeight: Units.gu(25)
        dialogWidth: Math.min(Units.gu(40), page.width - Units.gu(4))
    }
}

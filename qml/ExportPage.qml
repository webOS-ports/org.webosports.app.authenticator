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
import LuneOS.Forms 1.0

import "js/Accounts.js" as Accounts
import "js/Migration.js" as Migration

/*
 * The accounts as QR codes another phone reads, in the form Google
 * Authenticator's "Transfer accounts" uses (js/Migration.js): first which
 * accounts, then the codes, a few accounts in each, one after the other.
 * The codes hold the keys, so they are shown only while the app is in
 * front, and taken off the screen when it goes to the background.
 */
AppPage {
    id: page

    objectName: "exportPage"
    title: "Export accounts"
    focus: true

    readonly property var store: appWindow.store
    // "choose" or "codes".
    property string step: "choose"
    // Account ids left out by the user.
    property var leftOut: ({})
    // compose()'s codes while they are shown, [] otherwise.
    property var codes: []
    property int current: 0

    // Those that fit into a code, and those that do not, with why.
    readonly property var exportable: store.accounts.filter(function(a) {
        return Migration.unexportable(a) === "" && store.keyOf(a.id) !== null;
    })
    readonly property var notExportable: store.accounts.filter(function(a) {
        return Migration.unexportable(a) !== "" || store.keyOf(a.id) === null;
    })
    readonly property var chosen: exportable.filter(function(a) { return leftOut[a.id] !== true; })

    headerAction: step === "choose" ? showAction : doneAction

    Component {
        id: showAction
        Button {
            objectName: "showCodesButton"
            text: "Show codes"
            enabled: page.chosen.length > 0
            LuneOSButton.mainColor: LuneOSButton.affirmativeColor
            onClicked: page.showCodes()
        }
    }
    Component {
        id: doneAction
        Button {
            objectName: "exportDoneButton"
            text: "Done"
            onClicked: appWindow.pageStack.pop()
        }
    }

    function reason(account) {
        return store.keyOf(account.id) === null ? "Its key is missing." : Migration.unexportable(account);
    }

    function setChosen(id, on) {
        var out = Object.assign({}, leftOut);
        if (on)
            delete out[id];
        else
            out[id] = true;
        leftOut = out;
    }

    function showCodes() {
        if (chosen.length === 0)
            return;
        codes = Migration.compose(chosen, function(a) { return store.keyOf(a.id); }).links;
        current = 0;
        step = "codes";
        // Show codes is in the header, outside the page: the back gesture
        // comes to the page only with the focus in it.
        forceActiveFocus();
    }

    // Back to the choice, the codes and their keys let go of.
    function hideCodes() {
        step = "choose";
        codes = [];
        current = 0;
    }

    Connections {
        target: appWindow
        function onInFrontChanged() {
            if (!appWindow.inFront && page.step === "codes")
                page.hideCodes();
        }
    }

    StackView.onActivated: forceActiveFocus()

    /* The back gesture goes from the codes to the choice, and stays on the
     * page: the window goes back a page when Escape is released, so the
     * release is taken here too. */
    property bool _escapeTaken: false
    Keys.onEscapePressed: function(event) {
        if (step === "codes") {
            hideCodes();
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

    // --- which accounts ----------------------------------------------------

    Flickable {
        id: chooseFlick
        anchors.fill: parent
        visible: page.step === "choose"
        contentHeight: chooseContent.implicitHeight + Units.gu(2)
        clip: true

        ColumnLayout {
            id: chooseContent

            x: Units.gu(1)
            y: Units.gu(1)
            width: parent.width - Units.gu(2)
            spacing: Units.gu(1)

            ExplanationText {
                objectName: "exportExplanation"
                Layout.fillWidth: true
                text: "The codes hold the keys of the accounts: whoever reads them can make your codes. "
                      + "Show them only to your own phone, in Google Authenticator's “Import accounts” "
                      + "or another app that reads such codes."
            }

            FormGroup {
                objectName: "exportGroup"
                Layout.fillWidth: true
                visible: page.exportable.length > 0
                title: "Accounts to export"

                Repeater {
                    model: page.exportable
                    delegate: LabelAndSwitch {
                        required property var modelData
                        required property int index
                        objectName: "exportSwitch" + index
                        label: Accounts.title(modelData)
                               + (Accounts.subtitle(modelData) !== "" ? " – " + Accounts.subtitle(modelData) : "")
                        checked: page.leftOut[modelData.id] !== true
                        onToggled: page.setChosen(modelData.id, checked)
                    }
                }
            }

            FormGroup {
                objectName: "notExportableGroup"
                Layout.fillWidth: true
                visible: page.notExportable.length > 0
                title: "Cannot be exported"

                Repeater {
                    model: page.notExportable
                    delegate: Item {
                        required property var modelData
                        width: parent ? parent.width : 0
                        implicitHeight: Math.max(Units.gu(6), leftTexts.implicitHeight + Units.gu(2))
                        height: implicitHeight

                        Column {
                            id: leftTexts
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: Units.gu(0.25)
                            Label {
                                width: parent.width
                                text: Accounts.title(modelData)
                                elide: Text.ElideRight
                                color: Colors.text
                                font.pixelSize: FontUtils.sizeToPixels("16pt")
                            }
                            Label {
                                objectName: "notExportableReason"
                                width: parent.width
                                text: page.reason(modelData)
                                wrapMode: Text.WordWrap
                                color: Colors.secondaryText
                                font.pixelSize: FontUtils.sizeToPixels("small")
                            }
                        }
                    }
                }
            }
        }
    }

    // --- the codes ---------------------------------------------------------

    ColumnLayout {
        id: codesView
        objectName: "codesView"
        anchors.fill: parent
        anchors.margins: Units.gu(1)
        visible: page.step === "codes"
        spacing: Units.gu(1)

        readonly property var shown: page.codes.length > page.current ? page.codes[page.current] : null

        Label {
            objectName: "codeCaption"
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            color: Colors.text
            font.pixelSize: FontUtils.sizeToPixels("medium")
            text: !codesView.shown ? ""
                  : (page.codes.length > 1 ? "Code " + (page.current + 1) + " of " + page.codes.length + ": " : "")
                    + codesView.shown.accounts.map(function(a) { return Accounts.title(a); }).join(", ")
            maximumLineCount: 2
            elide: Text.ElideRight
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            // components/ExportCode.qml: LuneOS.Components' QrCode.
            Loader {
                id: qrLoader
                anchors.centerIn: parent
                width: Math.min(parent.width, parent.height)
                height: width
                source: Qt.resolvedUrl("components/ExportCode.qml")
                // Shown only while there is one to show: the key is in it.
                readonly property string text: page.step === "codes" && codesView.shown ? codesView.shown.link : ""
                readonly property bool drawn: item !== null && item.valid
            }
            Binding {
                target: qrLoader.item
                property: "text"
                value: qrLoader.text
                when: qrLoader.item !== null
            }

            Label {
                objectName: "qrUnavailable"
                anchors.centerIn: parent
                width: parent.width
                visible: qrLoader.text !== "" && !qrLoader.drawn
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                color: Colors.error
                text: qrLoader.item === null
                      ? "This version of LuneOS cannot draw QR codes: luneos-components has no QrCode."
                      : "The QR code cannot be drawn (" + (qrLoader.item.error || "unknown") + ")."
            }
        }

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            visible: page.codes.length > 1
            spacing: Units.gu(1)

            Button {
                objectName: "previousCodeButton"
                text: "Previous"
                enabled: page.current > 0
                onClicked: page.current--
            }
            Button {
                objectName: "nextCodeButton"
                text: "Next"
                enabled: page.current < page.codes.length - 1
                LuneOSButton.mainColor: LuneOSButton.affirmativeColor
                onClicked: page.current++
            }
        }
    }
}

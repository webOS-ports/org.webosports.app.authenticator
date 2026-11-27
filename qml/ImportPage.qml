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

/*
 * The accounts in one code of another authenticator's export (Google
 * Authenticator's "Transfer accounts"), shown before anything is added:
 * which are new, which are here already, and which cannot be used and
 * why. Add stores the new ones together. An export of several codes comes
 * one code at a time, each a launch of its own.
 */
AppPage {
    id: page

    objectName: "importPage"
    title: "Import accounts"
    focus: true

    readonly property var store: appWindow.store
    // Migration.parse()'s entries: { account } or { problem, title }.
    property var entries: []
    // Which code of the export this is, from 0, and how many there are.
    property int batchIndex: 0
    property int batchSize: 1
    property bool saving: false

    // The entries as shown: { title, subtitle, note, problem, account }
    // with account null for those not to add.
    readonly property var rows: {
        var out = [];
        var taken = [];
        var secrets = {};
        for (var i = 0; i < entries.length; i++) {
            var e = entries[i];
            if (!e.account) {
                out.push({ title: e.title !== "" ? e.title : "An account", subtitle: "", note: e.problem,
                           problem: true, account: null });
                continue;
            }
            var a = e.account;
            var shown = { title: Accounts.title(a), subtitle: Accounts.subtitle(a), note: "", problem: false,
                          account: a };
            if (Accounts.isDuplicate(store.accounts, a, a.secret, store._secrets)
                    || Accounts.isDuplicate(taken, a, a.secret, secrets)) {
                shown.note = "Already here";
                shown.account = null;
            } else {
                var id = "import" + taken.length;
                taken.push({ id: id, issuer: a.issuer, label: a.label });
                secrets[id] = a.secret;
            }
            out.push(shown);
        }
        return out;
    }
    readonly property var toAdd: rows.filter(function(r) { return r.account !== null; })
                                     .map(function(r) { return r.account; })

    headerAction: Component {
        Button {
            objectName: "importButton"
            text: "Add"
            enabled: page.toAdd.length > 0 && !page.saving
            LuneOSButton.mainColor: LuneOSButton.affirmativeColor
            onClicked: page.add()
        }
    }

    StackView.onActivated: forceActiveFocus()

    function add() {
        if (toAdd.length === 0 || saving)
            return;
        saving = true;
        var count = toAdd.length;
        var first = Accounts.title(toAdd[0]);
        store.addAll(toAdd, function(error) {
            saving = false;
            if (error !== "")
                return;
            appWindow.showToast(count === 1 ? "Added " + first : "Added " + count + " accounts");
            appWindow.pageStack.pop();
        });
    }

    function explanation() {
        var text = toAdd.length > 0
                ? "From another authenticator's export: check that these are your accounts, then Add."
                : "From another authenticator's export: there is nothing new in it to add.";
        if (batchSize > 1)
            text += " This is code " + (batchIndex + 1) + " of " + batchSize
                    + "; scan the others after this one.";
        return text;
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
                objectName: "importExplanation"
                Layout.fillWidth: true
                text: page.explanation()
            }

            FormGroup {
                objectName: "importGroup"
                Layout.fillWidth: true
                title: page.rows.length === 1 ? "1 account" : page.rows.length + " accounts"

                Repeater {
                    model: page.rows
                    delegate: Item {
                        required property var modelData
                        required property int index

                        objectName: "importRow" + index
                        width: parent ? parent.width : 0
                        implicitHeight: Math.max(Units.gu(6), texts.implicitHeight + Units.gu(2))
                        height: implicitHeight

                        Column {
                            id: texts
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: Units.gu(0.25)

                            Label {
                                objectName: "importTitle"
                                width: parent.width
                                text: modelData.title
                                elide: Text.ElideRight
                                color: Colors.text
                                font.pixelSize: FontUtils.sizeToPixels("16pt")
                            }
                            Label {
                                width: parent.width
                                visible: text !== ""
                                text: modelData.subtitle
                                elide: Text.ElideRight
                                color: Colors.secondaryText
                                font.pixelSize: FontUtils.sizeToPixels("small")
                            }
                            Label {
                                objectName: "importNote"
                                width: parent.width
                                visible: text !== ""
                                text: modelData.note
                                wrapMode: Text.WordWrap
                                color: modelData.problem ? Colors.error : Colors.secondaryText
                                font.pixelSize: FontUtils.sizeToPixels("small")
                            }
                        }
                    }
                }
            }
        }
    }
}

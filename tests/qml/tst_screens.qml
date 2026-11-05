/*
 * Copyright 2026 Herman van Hazendonk <github.com@herrie.org>
 * SPDX-License-Identifier: GPL-3.0-only
 */

import QtQuick
import QtQuick.Controls
import QtTest
import LunaNext.Common 0.1

import "../../qml/js/Accounts.js" as Accounts

/*
 * Every screen of the app on one device's screen per run: the window is the
 * profile's display, with its grid unit (tests/run-qml-tests.sh runs this
 * once per profile in PROFILES). Each screen is reached as a user would,
 * checked for what breaks a layout - shown, not empty, inside the window,
 * nothing running off the side - and saved as
 * build/test-output/ui/<profile>-<screen>.png, with the panel's notch and
 * rounded corners painted over it (PanelShape.qml).
 */
TestCase {
    id: test
    name: "AuthenticatorScreens"
    when: windowShown

    readonly property string shotDir: decodeURIComponent(Qt.resolvedUrl("../../build/test-output/ui").toString()
                                                         .replace(/^file:\/\//, ""))
    readonly property string profile: Settings.profileName
    property var app: null
    property var keymanager: null
    property var auth: null
    property real lockNow: 1000000

    readonly property string rfcSecret: "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ"
    readonly property string otherSecret: "JBSWY3DPEHPK3PXP"

    Component {
        id: panelShape
        PanelShape {}
    }

    function init_data() {
        return [{ tag: profile + " " + Settings.displayWidth + "x" + Settings.displayHeight }];
    }

    function makeKeymanager() {
        var component = Qt.createComponent(Qt.resolvedUrl("FakeKeyManager.qml"));
        if (component.status !== Component.Ready)
            fail(component.errorString());
        keymanager = component.createObject(test);
        return keymanager;
    }

    function makeAuth() {
        var component = Qt.createComponent(Qt.resolvedUrl("FakeAuth.qml"));
        if (component.status !== Component.Ready)
            fail(component.errorString());
        auth = component.createObject(test);
        return auth;
    }

    function seed(accounts, secrets, lock, face) {
        var keys = Object.assign({}, keymanager.keys);
        keys[Accounts.INDEX_KEYS[0]] = {
            keydata: Accounts.serializeIndex(1, accounts, { lock: lock === true, face: face === true }),
            type: "ASCIIBLOB", nohide: true, noexport: true
        };
        for (var id in secrets)
            keys[Accounts.secretKeyName(id)] = { keydata: secrets[id], type: "ASCIIBLOB", nohide: true, noexport: true };
        keymanager.keys = keys;
    }

    function account(id, issuer, label, extra) {
        return Object.assign({ id: id, type: "totp", issuer: issuer, label: label, algorithm: "SHA1",
                               digits: 6, period: 30, counter: 0 }, extra || {});
    }

    // A few accounts of every kind: a long name, eight digits, a counter.
    function seedAccounts(lock, face) {
        seed([account("a1", "Example", "alice@example.com"),
              account("a2", "A very long site name that goes on and on", "someone.with.a.long.address@example.com",
                      { digits: 8 }),
              account("h1", "Counter", "bob", { type: "hotp" }),
              account("a3", "GitHub", "herrie", { algorithm: "SHA256" }),
              account("a4", "Mail", "me@example.org", { period: 60 })],
             { a1: rfcSecret, a2: rfcSecret, h1: otherSecret, a3: otherSecret, a4: rfcSecret }, lock, face);
    }

    function createApp(expectReady) {
        if (!keymanager)
            makeKeymanager();
        if (!auth)
            makeAuth();
        var component = Qt.createComponent(Qt.resolvedUrl("../../qml/main.qml"));
        if (component.status !== Component.Ready)
            fail(component.errorString());
        var t = 59000;
        app = component.createObject(null, { bus: keymanager, authBus: auth, clock: function() { return t; },
                                             lockClock: function() { return test.lockNow; }, inFront: true });
        verify(app !== null, "main.qml did not load");
        app.now = t;
        compare(app.width, Settings.displayWidth);
        compare(app.height, Settings.displayHeight);
        if (expectReady !== false)
            tryCompare(app.store, "status", "ready");
        waitForRendering(app.contentItem);
        return app;
    }

    function cleanup() {
        if (app) {
            app.destroy();
            app = null;
        }
        if (keymanager) {
            keymanager.destroy();
            keymanager = null;
        }
        if (auth) {
            auth.destroy();
            auth = null;
        }
        wait(0);
    }

    function page() {
        return app.pageStack.currentItem;
    }

    function settle() {
        tryVerify(function() { return !app.pageStack.busy; }, 5000, "the page stack stays busy");
    }

    function waitForPage(name) {
        tryVerify(function() { return page() && page().objectName === name; }, 5000, "expected the " + name);
        settle();
    }

    function findChild(item, objectName) {
        if (!item)
            return null;
        if (item.objectName === objectName)
            return item;
        var kids = item.children || [];
        for (var i = 0; i < kids.length; i++) {
            var found = findChild(kids[i], objectName);
            if (found)
                return found;
        }
        if (item.contentItem && item.contentItem !== item)
            return findChild(item.contentItem, objectName);
        return null;
    }

    function flickableIn(item) {
        if (!item)
            return null;
        if (item.contentHeight !== undefined && item.contentY !== undefined && item.flick !== undefined)
            return item;
        var kids = item.children || [];
        for (var i = 0; i < kids.length; i++) {
            var found = flickableIn(kids[i]);
            if (found)
                return found;
        }
        return null;
    }

    function list() {
        return findChild(page(), "accountsList");
    }

    function row(i) {
        var l = list();
        l.forceLayout();
        return l.itemAtIndex(i);
    }

    function lockScreen() {
        return findChild(app.contentItem, "lockScreen");
    }

    // Shown, not empty and inside the window, left to right; top to bottom
    // too unless it may be scrolled to.
    function onScreen(item, label, scrolls) {
        verify(item, "no " + label);
        verify(item.visible, label + " hidden");
        verify(item.width > 0 && item.height > 0, label + " has no size: " + item.width + "x" + item.height);
        var p = item.mapToItem(null, 0, 0);
        verify(p.x >= -0.5 && p.x + item.width <= app.width + 0.5,
               label + " off the side: x " + p.x + ", width " + item.width + " of " + app.width);
        if (!scrolls)
            verify(p.y >= -0.5 && p.y + item.height <= app.height + 0.5,
                   label + " runs off the bottom: y " + p.y + ", height " + item.height + " of " + app.height);
    }

    // The lock screen, the last of it too, in the window without
    // scrolling - on the Q25's square (720x720 at grid unit 16) as well.
    function lockFits(lock, item, label) {
        onScreen(item, label);
        var flick = flickableIn(lock);
        verify(flick.contentHeight <= flick.height + 0.5,
               "the lock screen has to be scrolled: " + flick.contentHeight + " of " + flick.height);
    }

    // contentWidth is -1 unless set, so what the content holds counts too.
    function noSideways(flick, label) {
        verify(flick, "no Flickable in " + label);
        verify(flick.contentWidth <= flick.width + 0.5,
               label + " wider than the window: " + flick.contentWidth + " of " + flick.width);
        var r = flick.contentItem.childrenRect;
        verify(r.x >= -0.5 && r.x + r.width <= flick.width + 0.5,
               label + "'s content runs off the side: x " + r.x + ", width " + r.width + " of " + flick.width);
    }

    // A popup (menu or dialog) inside the window.
    function popupFits(popup, label) {
        verify(popup.width > 0 && popup.height > 0, label + " has no size");
        var p = popup.parent.mapToItem(null, popup.x, popup.y);
        verify(p.x >= -0.5 && p.x + popup.width <= app.width + 0.5,
               label + " off the side: x " + p.x + ", width " + popup.width + " of " + app.width);
        verify(p.y >= -0.5 && p.y + popup.height <= app.height + 0.5,
               label + " off the top or bottom: y " + p.y + ", height " + popup.height + " of " + app.height);
    }

    function shot(name) {
        wait(300);
        waitForRendering(app.contentItem);
        var shape = panelShape.createObject(app.contentItem);
        if (shape.shaped) {
            shape.requestPaint();
            tryVerify(function() { return shape.done; }, 3000, "panel shape painted");
            waitForRendering(app.contentItem);
        }
        var done = false;
        verify(app.contentItem.grabToImage(function(result) {
            verify(result.saveToFile(shotDir + "/" + profile + "-" + name + ".png"), "save " + name);
            done = true;
        }), "grab " + name);
        tryVerify(function() { return done; }, 5000, "saved " + name);
        shape.destroy();
    }

    function backGesture() {
        app.requestActivate();
        tryVerify(function() { return app.active; });
        keyClick(Qt.Key_Escape);
    }

    // Each row: as wide as the list, the code clear of the timer, nothing
    // cut off at the right or the bottom.
    function rowsFit() {
        var l = list();
        onScreen(l, "the list");
        verify(l.contentWidth <= l.width + 0.5, "list wider than the window");
        var shown = 0;
        for (var i = 0; i < l.count; i++) {
            var r = row(i);
            if (!r || r.mapToItem(l, 0, 0).y >= l.height)
                continue;
            shown++;
            compare(r.width, l.width);
            var ring = findChild(r, "countdownRing");
            var next = findChild(r, "nextCodeButton");
            var right = ring.visible ? ring : next;
            verify(right.visible && right.width > 0, "row " + i + ": no timer or next button");
            var p = right.mapToItem(r, 0, 0);
            verify(p.x + right.width <= r.width + 0.5, "row " + i + " runs off the right");
            var code = findChild(r, "codeLabel");
            var c = code.mapToItem(r, 0, 0);
            verify(code.width > 0 && code.height > 0, "row " + i + ": no code");
            verify(c.x + code.width <= p.x + 0.5, "row " + i + ": the code runs under the timer");
            verify(c.y + code.height <= r.height + 0.5, "row " + i + ": the code is cut off");
        }
        verify(shown > 0, "no row shown");
    }

    // --- the accounts --------------------------------------------------

    function test_first_start() {
        createApp();
        var empty = findChild(page(), "emptyState");
        onScreen(empty, "the empty state");
        onScreen(findChild(page(), "scanButton"), "Scan QR code");
        onScreen(findChild(page(), "typeKeyButton"), "Enter a key");
        onScreen(findChild(app.header, "addButton"), "Add");
        shot("first-start");
    }

    function test_accounts() {
        makeKeymanager();
        seedAccounts();
        createApp();
        tryVerify(function() { return row(0) !== null; });
        rowsFit();
        onScreen(findChild(app.header, "addButton"), "Add");
        shot("accounts");

        // A tap copies: the toast at the bottom.
        // Up long enough for the picture, however busy the machine.
        var toast = findChild(app.contentItem, "toast");
        var pill = toast;
        while (pill && pill.duration === undefined)
            pill = pill.parent;
        verify(pill, "no Toast around the toast's label");
        pill.duration = 60000;
        mouseClick(row(0));
        tryVerify(function() { return toast.visible; });
        onScreen(toast, "the toast");
        shot("toast");
    }

    function test_account_menu_and_delete() {
        makeKeymanager();
        seedAccounts();
        createApp();
        tryVerify(function() { return row(0) !== null; });
        mousePress(row(0));
        tryVerify(function() { return page().accountMenu.opened; }, 3000);
        mouseRelease(row(0));
        popupFits(page().accountMenu, "the account menu");
        shot("account-menu");

        mouseClick(page().accountMenu.itemAt(1));
        var dialog = findChild(page(), "deleteDialog");
        tryVerify(function() { return dialog.visible; });
        tryVerify(function() { return !page().accountMenu.visible; });
        onScreen(findChild(dialog, "confirmAcceptButton"), "Delete");
        onScreen(findChild(dialog, "confirmRejectButton"), "Cancel");
        shot("delete-from-list");
    }

    function test_reordering() {
        makeKeymanager();
        seedAccounts();
        createApp();
        app.appMenu.popup(0, 0);
        tryVerify(function() { return app.appMenu.opened; });
        mouseClick(findChild(app.appMenu.contentItem, "reorderMenuItem") || app.appMenu.itemAt(2));
        verify(page().reordering);
        onScreen(findChild(app.header, "doneButton"), "Done");
        tryVerify(function() { return row(0) !== null; });
        verify(row(0).width <= list().width + 0.5);
        shot("reordering");
    }

    function test_app_menu() {
        makeAuth();
        auth.faceEnrolled = true;
        makeKeymanager();
        seedAccounts();
        createApp();
        app.appMenu.popup(0, 0);
        tryVerify(function() { return app.appMenu.opened; });
        popupFits(app.appMenu, "the app menu");
        shot("app-menu");
        app.appMenu.close();
        tryVerify(function() { return !app.appMenu.visible; });
    }

    // With the lock on and a face enrolled, "Also open with a face" too.
    function test_app_menu_locked() {
        unlocked();
        app.appMenu.popup(0, 0);
        tryVerify(function() { return app.appMenu.opened; });
        verify(findChild(app.appMenu.contentItem, "faceMenuItem").visible);
        popupFits(app.appMenu, "the app menu with face");
        shot("app-menu-locked");
    }

    // Locked with a face enrolled, then opened with the PIN.
    function unlocked() {
        makeAuth();
        auth.faceEnrolled = true;
        makeKeymanager();
        seedAccounts(true);
        createApp(false);
        tryCompare(app.store, "status", "locked");
        tryCompare(app.deviceAuth, "lockMode", "pin");
        lockScreen().submit("1357");
        tryCompare(app.store, "status", "ready");
        tryVerify(function() { return !app.locked; });
    }

    function test_face_dialog() {
        unlocked();
        app.toggleFace();
        var dialog = findChild(app.contentItem, "faceDialog");
        tryVerify(function() { return dialog.visible; });
        onScreen(findChild(dialog, "confirmAcceptButton"), "Turn on");
        onScreen(findChild(dialog, "confirmRejectButton"), "Cancel");
        shot("face-dialog");
    }

    function test_notice() {
        makeKeymanager();
        seedAccounts();
        keymanager.failMethods = { "fetchKey": "Denied method call" };
        createApp(false);
        tryCompare(app.store, "status", "failed");
        var notice = findChild(app.contentItem, "statusNotice");
        onScreen(notice, "the notice");
        onScreen(findChild(notice, "noticeCloseButton"), "the notice's close key");
        shot("store-failed");
    }

    // --- the editor ----------------------------------------------------

    function editorFits(label) {
        var flick = flickableIn(page());
        if (flick)
            noSideways(flick, label);
        onScreen(findChild(app.header, "saveButton"), label + ": Save");
        var fields = ["issuerField", "labelField", "secretField"];
        for (var i = 0; i < fields.length; i++)
            onScreen(findChild(page(), fields[i]), label + ": " + fields[i], true);
    }

    // A LabelAndTextField's field shows the first character at its left.
    function startShown(row, label) {
        var field = null;
        for (var i = 0; i < row.children.length && !field; i++)
            if (row.children[i].positionAt !== undefined)
                field = row.children[i];
        verify(field, "no field in " + label);
        verify(field.contentWidth > field.width - field.leftPadding - field.rightPadding,
               label + " is not long enough to test: " + field.contentWidth + " in " + field.width);
        compare(field.positionAt(field.leftPadding + 1, field.height / 2), 0, label + " does not show its start");
    }

    function test_add() {
        createApp();
        mouseClick(findChild(app.header, "addButton"));
        waitForPage("editAccountPage");
        editorFits("adding");
        shot("add");

        // Saved without a name and with a bad key: both say why.
        findChild(page(), "secretField").text = "not base32!";
        mouseClick(findChild(app.header, "saveButton"));
        tryVerify(function() { return findChild(page(), "labelProblem").visible; });
        shot("add-problems");
        onScreen(findChild(page(), "labelProblem"), "the name problem", true);
        onScreen(findChild(page(), "secretProblem"), "the key problem", true);

        var more = findChild(page(), "moreSettingsSwitch");
        more.checked = true;
        more.toggled();
        tryVerify(function() { return findChild(page(), "typeSelector").visible; });
        var settings = ["typeSelector", "algorithmSelector", "digitsSelector", "periodField"];
        for (var i = 0; i < settings.length; i++)
            onScreen(findChild(page(), settings[i]), settings[i], true);
        shot("add-more-settings");
        var flick = flickableIn(page());
        if (flick) {
            flick.contentY = Math.max(0, flick.contentHeight - flick.height);
            waitForRendering(app.contentItem);
            shot("add-more-settings-end");
        }
    }

    function test_from_link() {
        createApp();
        app.launchParams = JSON.stringify({ target: "otpauth://totp/Example:alice%40example.com?secret=" + rfcSecret
                                                    + "&issuer=Example" });
        waitForPage("editAccountPage");
        onScreen(findChild(page(), "linkExplanation"), "the link's explanation", true);
        editorFits("a link");
        shot("from-link");
    }

    function test_edit_and_delete() {
        makeKeymanager();
        seedAccounts();
        createApp();
        app.openEditor({ accountId: "a2" });
        waitForPage("editAccountPage");
        editorFits("editing");
        var flick = flickableIn(page());
        var del = findChild(page(), "deleteButton");
        onScreen(del, "Delete", true);
        // The long site and name from their start, not their end.
        startShown(findChild(page(), "issuerField"), "the site");
        startShown(findChild(page(), "labelField"), "the name");
        shot("edit");
        if (flick) {
            flick.contentY = Math.max(0, flick.contentHeight - flick.height);
            waitForRendering(app.contentItem);
        }
        onScreen(del, "Delete, scrolled to");
        mouseClick(del);
        var dialog = findChild(page(), "deleteDialog");
        tryVerify(function() { return dialog.visible; });
        onScreen(findChild(dialog, "confirmAcceptButton"), "Delete");
        shot("delete-from-editor");
    }

    // --- the lock ------------------------------------------------------

    function createLocked(mode, face) {
        makeAuth();
        auth.lockMode = mode;
        if (mode === "password")
            auth.passcode = "correct horse";
        if (face)
            auth.faceEnrolled = true;
        makeKeymanager();
        seedAccounts(true, face);
        createApp(false);
        tryCompare(app.store, "status", "locked");
        tryCompare(app.deviceAuth, "lockMode", mode);
        waitForRendering(app.contentItem);
        var lock = lockScreen();
        verify(lock.visible);
        compare(lock.width, app.contentItem.width);
        compare(lock.height, app.contentItem.height);
        onScreen(findChild(lock, "lockMessage"), "the lock's message");
        return lock;
    }

    function test_lock_pin() {
        var lock = createLocked("pin");
        shot("lock-pin");
        onScreen(findChild(lock, "pinPad"), "the PIN pad");
        lockFits(lock, findChild(lock, "unlockButton"), "Unlock");

        lock.submit("0000");
        tryVerify(function() { return findChild(lock, "lockMessage").text.indexOf("not") >= 0; }, 3000);
        onScreen(findChild(lock, "lockMessage"), "the wrong-PIN message");
        shot("lock-pin-wrong");
    }

    function test_lock_password() {
        var lock = createLocked("password");
        onScreen(findChild(lock, "passwordField"), "the password field");
        onScreen(findChild(lock, "unlockButton"), "Unlock");
        shot("lock-password");
    }

    function test_lock_pattern() {
        var lock = createLocked("pattern");
        shot("lock-pattern");
        lockFits(lock, findChild(lock, "patternGrid"), "the pattern grid");
    }

    function test_lock_face() {
        var lock = createLocked("pin", true);
        tryVerify(function() { return findChild(lock, "faceStatus").visible; }, 3000);
        shot("lock-face");
        onScreen(findChild(lock, "faceStatus"), "the face status");
        lockFits(lock, findChild(lock, "pinPad"), "the PIN pad");
        lockFits(lock, findChild(lock, "unlockButton"), "Unlock");
    }
}

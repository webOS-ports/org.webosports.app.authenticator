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
 * The app itself - qml/main.qml and its pages - on the build host, with
 * luneos-components' desktop stand-ins for the window and the bus, and
 * FakeKeyManager.qml for com.palm.keymanager, FakeAuth.qml for the screen
 * lock and the fingerprint sensor. Run by tests/run-qml-tests.sh.
 */
TestCase {
    id: test
    name: "AuthenticatorUi"
    when: windowShown

    property var app: null
    property var keymanager: null
    property var auth: null
    // lockClock for the app, by the test.
    property real lockNow: 1000000

    // RFC 6238's SHA1 seed, "12345678901234567890", as Base32.
    readonly property string rfcSecret: "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ"
    readonly property string otherSecret: "JBSWY3DPEHPK3PXP"

    TextEdit {
        id: pasteTarget
        visible: false
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

    // Stored accounts, as the app writes them.
    function seed(accounts, secrets, generation, slot, lock, face) {
        var keys = Object.assign({}, keymanager.keys);
        keys[Accounts.INDEX_KEYS[slot || 0]] = {
            keydata: Accounts.serializeIndex(generation || 1, accounts, { lock: lock === true, face: face === true }),
            type: "ASCIIBLOB",
            nohide: true, noexport: true
        };
        for (var id in secrets)
            keys[Accounts.secretKeyName(id)] = { keydata: secrets[id], type: "ASCIIBLOB", nohide: true, noexport: true };
        keymanager.keys = keys;
    }

    function account(id, issuer, label, extra) {
        return Object.assign({ id: id, type: "totp", issuer: issuer, label: label, algorithm: "SHA1",
                               digits: 6, period: 30, counter: 0 }, extra || {});
    }

    function createApp(timeMs, width, height, expectReady) {
        if (!keymanager)
            makeKeymanager();
        if (!auth)
            makeAuth();
        var component = Qt.createComponent(Qt.resolvedUrl("../../qml/main.qml"));
        if (component.status !== Component.Ready)
            fail(component.errorString());
        var t = timeMs === undefined ? 59000 : timeMs;
        app = component.createObject(null, { bus: keymanager, authBus: auth, clock: function() { return t; },
                                             lockClock: function() { return test.lockNow; }, inFront: true });
        verify(app !== null, "main.qml did not load");
        app.now = t;
        if (width) {
            app.width = width;
            app.height = height;
        }
        if (expectReady !== false)
            tryCompare(app.store, "status", "ready");
        waitForRendering(app.contentItem);
        return app;
    }

    function setTime(ms) {
        app.clock = function() { return ms; };
        app.now = ms;
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

    function waitForPage(name) {
        tryVerify(function() { return page() && page().objectName === name; }, 5000,
                  "expected the " + name);
        settle();
    }

    // Until the page has slid in: a tap during the slide misses.
    function settle() {
        tryVerify(function() { return !app.pageStack.busy; }, 5000, "the page stack stays busy");
    }

    function openEditor(properties) {
        app.openEditor(properties);
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

    function list() {
        return findChild(page(), "accountsList");
    }

    function row(i) {
        var l = list();
        l.forceLayout();
        return l.itemAtIndex(i);
    }

    function storedIndex() {
        var a = keymanager.keys[Accounts.INDEX_KEYS[0]];
        var b = keymanager.keys[Accounts.INDEX_KEYS[1]];
        return Accounts.newerIndex(a ? Accounts.parseIndex(a.keydata) : null,
                                   b ? Accounts.parseIndex(b.keydata) : null);
    }

    function storeCalls() {
        return keymanager.calls.filter(function(c) { return c.method === "store" || c.method === "remove"; });
    }

    function openEditorAndFill(issuer, label, secret) {
        openEditor({});
        waitForPage("editAccountPage");
        findChild(page(), "issuerField").text = issuer;
        findChild(page(), "labelField").text = label;
        findChild(page(), "secretField").text = secret;
    }

    function save() {
        mouseClick(findChild(app.header, "saveButton"));
    }

    // Taps the dialog's OK (accept) or Cancel, as a user would.
    function answer(dialog, accept) {
        var button = findChild(dialog, accept ? "confirmAcceptButton" : "confirmRejectButton");
        verify(button !== null && button.visible, "no " + (accept ? "accept" : "reject") + " button");
        mouseClick(button);
    }

    // The toast's words while it shows, "" when none is up.
    function toastText() {
        var label = findChild(app.contentItem, "toast");
        verify(label !== null, "no toast label");
        return label.visible ? label.text : "";
    }

    // Pictures of the app, for comparing a change by eye; not checked.
    readonly property string shotDir: decodeURIComponent(Qt.resolvedUrl("../../build/test-output/ui").toString()
                                                         .replace(/^file:\/\//, ""))

    function shot(name) {
        waitForRendering(app.contentItem);
        var done = false;
        var ok = app.contentItem.grabToImage(function(result) {
            verify(result.saveToFile(shotDir + "/" + name + ".png"), "save " + name);
            done = true;
        });
        verify(ok, "grab " + name);
        tryVerify(function() { return done; }, 5000, "saved " + name);
    }

    function backGesture() {
        app.requestActivate();
        tryVerify(function() { return app.active; });
        keyClick(Qt.Key_Escape);
    }

    // --- first start ---------------------------------------------------

    function test_first_start_explains_how_to_add() {
        createApp();
        compare(page().title, "Authenticator");
        verify(findChild(page(), "emptyState").visible);
        verify(!list().visible);
        verify(findChild(page(), "typeKeyButton").visible);
        verify(findChild(page(), "scanButton").visible);
        // Read both index keys, wrote nothing.
        compare(keymanager.countOf("fetchKey"), 2);
        compare(storeCalls().length, 0);
    }

    // --- codes ---------------------------------------------------------

    // RFC 6238's first SHA1 example, end to end: the stored Base32 secret,
    // fetched over the (fake) bus, shown at 59 s as 9428 7082.
    function test_shows_the_rfc_code() {
        makeKeymanager();
        seed([account("a1", "Example", "alice@example.com", { digits: 8 })], { a1: rfcSecret });
        createApp(59000);
        compare(list().count, 1);
        var r = row(0);
        compare(findChild(r, "titleLabel").text, "Example");
        compare(findChild(r, "subtitleLabel").text, "alice@example.com");
        compare(findChild(r, "codeLabel").text, "9428 7082");
        var ring = findChild(r, "countdownRing");
        verify(ring.visible);
        compare(ring.secondsLeft, 1);
        verify(ring.ending);
        compare(ring.fraction, 1 / 30);
    }

    function test_code_and_ring_follow_the_clock() {
        makeKeymanager();
        seed([account("a1", "Example", "me", { digits: 8 })], { a1: rfcSecret });
        createApp(1111111109000);
        compare(findChild(row(0), "codeLabel").text, "0708 1804");
        compare(findChild(row(0), "countdownRing").secondsLeft, 1);
        setTime(1111111111000);
        compare(findChild(row(0), "codeLabel").text, "1405 0471");
        compare(findChild(row(0), "countdownRing").secondsLeft, 29);
        verify(!findChild(row(0), "countdownRing").ending);
    }

    function test_sha256_and_sha512_accounts() {
        makeKeymanager();
        // RFC 6238's 32- and 64-byte seeds as Base32.
        seed([account("s2", "Two", "x", { digits: 8, algorithm: "SHA256" }),
              account("s5", "Five", "y", { digits: 8, algorithm: "SHA512" })],
             { s2: "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZA",
               s5: "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNA" });
        createApp(1234567890000);
        compare(findChild(row(0), "codeLabel").text, "9181 9424");
        compare(findChild(row(1), "codeLabel").text, "9344 1116");
    }

    function test_tap_copies_the_code() {
        makeKeymanager();
        seed([account("a1", "Example", "me")], { a1: rfcSecret });
        createApp(59000);
        mouseClick(row(0));
        // 94287082 cut to 6 digits.
        pasteTarget.text = "";
        pasteTarget.paste();
        compare(pasteTarget.text, "287082");
        compare(toastText(), "Copied Example’s code");
        // At the bottom, over the list.
        var toast = findChild(app.contentItem, "toast");
        var bottom = toast.mapToItem(app.contentItem, 0, toast.height).y;
        verify(bottom > app.contentItem.height - Units.gu(6), "toast not at the bottom: " + bottom);
        // And goes by itself.
        tryVerify(function() { return toastText() === ""; }, 4000, "the toast stays");
    }

    function test_account_without_secret_says_so() {
        makeKeymanager();
        seed([account("a1", "Example", "me")], {});
        createApp();
        compare(list().count, 1);
        verify(/No key stored/.test(findChild(row(0), "codeLabel").text));
        verify(!findChild(row(0), "countdownRing").visible);
    }

    // --- adding --------------------------------------------------------

    function test_add_typed_account() {
        createApp(59000);
        mouseClick(findChild(page(), "typeKeyButton"));
        waitForPage("editAccountPage");
        compare(page().title, "Add account");
        findChild(page(), "issuerField").text = "Example";
        findChild(page(), "labelField").text = "alice";
        findChild(page(), "secretField").text = "gezd gnbv gy3t qojq gezd gnbv gy3t qojq";
        save();
        waitForPage("accountsPage");
        compare(list().count, 1);
        compare(findChild(row(0), "codeLabel").text, "287 082");
        compare(toastText(), "Added Example");

        // The secret under its own key, normalized, kept from backups and
        // readable by the app; the index naming it.
        var index = storedIndex();
        compare(index.accounts.length, 1);
        compare(index.accounts[0].issuer, "Example");
        var secret = keymanager.keys[Accounts.secretKeyName(index.accounts[0].id)];
        compare(secret.keydata, rfcSecret);
        compare(secret.type, "ASCIIBLOB");
        verify(secret.nohide);
        verify(secret.noexport);
        // Not in the index.
        verify(JSON.stringify(index).indexOf(rfcSecret) < 0);
    }

    function test_bad_key_is_refused_with_a_reason() {
        createApp();
        openEditorAndFill("Example", "alice", "JBSWY3DPEHPK3PX0");
        var problem = findChild(page(), "secretProblem");
        verify(problem.visible);
        verify(/letter O/.test(problem.text), problem.text);
        save();
        compare(page().objectName, "editAccountPage");
        compare(storeCalls().length, 0);
    }

    function test_name_needed_after_save_tried() {
        createApp();
        openEditorAndFill("", "", otherSecret);
        verify(!findChild(page(), "labelProblem").visible);
        save();
        verify(findChild(page(), "labelProblem").visible);
        compare(storeCalls().length, 0);
    }

    function test_pasted_link_fills_the_form() {
        createApp();
        openEditor({});
        findChild(page(), "secretField").text =
                "otpauth://hotp/Lab:bob?secret=JBSWY3DPEHPK3PXP&counter=5&digits=8&algorithm=SHA256";
        compare(findChild(page(), "issuerField").text, "Lab");
        compare(findChild(page(), "labelField").text, "bob");
        compare(findChild(page(), "secretField").text, "JBSWY3DPEHPK3PXP");
        compare(findChild(page(), "typeSelector").value, "hotp");
        compare(findChild(page(), "algorithmSelector").value, "SHA256");
        compare(findChild(page(), "digitsSelector").value, 8);
        compare(findChild(page(), "counterField").text, "5");
        verify(findChild(page(), "moreSettingsSwitch").checked);
    }

    function test_duplicate_is_not_added_twice() {
        makeKeymanager();
        seed([account("a1", "Example", "alice")], { a1: otherSecret });
        createApp();
        openEditorAndFill("example", "Alice", otherSecret);
        save();
        waitForPage("accountsPage");
        compare(list().count, 1);
        verify(/already there/.test(app.notice), app.notice);
        compare(storeCalls().length, 0);
    }

    // --- otpauth:// launches -------------------------------------------

    function test_launch_with_link_offers_the_account() {
        createApp(59000);
        app.launchParams = JSON.stringify({ target: "otpauth://totp/Example:alice%40example.com?secret=" + rfcSecret + "&issuer=Example" });
        waitForPage("editAccountPage");
        verify(page().fromLink);
        verify(findChild(page(), "linkExplanation").visible);
        compare(findChild(page(), "labelField").text, "alice@example.com");
        // Nothing stored until Save.
        compare(storeCalls().length, 0);
        save();
        waitForPage("accountsPage");
        compare(findChild(row(0), "codeLabel").text, "287 082");
    }

    // The link arrives with the launch, before the accounts are read.
    function test_link_waits_for_the_accounts() {
        makeKeymanager();
        keymanager.silent = true;
        createApp(59000, 0, 0, false);
        app.openLink("otpauth://totp/Late?secret=" + otherSecret);
        compare(page().objectName, "accountsPage");
        compare(app.pendingLink.indexOf("otpauth://"), 0);
        keymanager.silent = false;
        app.store.load();
        waitForPage("editAccountPage");
        compare(findChild(page(), "labelField").text, "Late");
    }

    function test_bad_link_says_why() {
        createApp();
        app.openLink("otpauth://totp/x?secret=JBSWY3DPEHPK3PXP&algorithm=MD5");
        compare(page().objectName, "accountsPage");
        verify(/MD5/.test(app.notice));
        app.openLink("https://example.com");
        verify(/only opens otpauth/.test(app.notice));
    }

    // --- changing ------------------------------------------------------

    function test_edit_keeps_the_secret() {
        makeKeymanager();
        seed([account("a1", "Example", "alice")], { a1: rfcSecret });
        createApp(59000);
        openEditor({ accountId: "a1" });
        compare(page().title, "Edit account");
        compare(findChild(page(), "secretField").text, "");
        compare(findChild(page(), "issuerField").text, "Example");
        findChild(page(), "issuerField").text = "Renamed";
        save();
        waitForPage("accountsPage");
        compare(findChild(row(0), "titleLabel").text, "Renamed");
        compare(findChild(row(0), "codeLabel").text, "287 082");
        // Only the index changed: no secret written or removed.
        var index = storedIndex();
        compare(index.accounts[0].id, "a1");
        compare(index.generation, 2);
        verify(keymanager.keys[Accounts.secretKeyName("a1")] !== undefined);
        compare(storeCalls().filter(function(c) { return c.args.keyname.indexOf("otp.secret.") === 0; }).length, 0);
    }

    function test_edit_with_new_secret() {
        makeKeymanager();
        seed([account("a1", "Example", "alice")], { a1: otherSecret });
        createApp(59000);
        openEditor({ accountId: "a1" });
        findChild(page(), "secretField").text = rfcSecret;
        save();
        waitForPage("accountsPage");
        compare(findChild(row(0), "codeLabel").text, "287 082");
        var index = storedIndex();
        verify(index.accounts[0].id !== "a1");
        compare(keymanager.keys[Accounts.secretKeyName(index.accounts[0].id)].keydata, rfcSecret);
        tryVerify(function() { return keymanager.keys[Accounts.secretKeyName("a1")] === undefined; });
    }

    function test_delete_from_the_menu() {
        makeKeymanager();
        seed([account("a1", "One", "x"), account("a2", "Two", "y")], { a1: otherSecret, a2: rfcSecret });
        createApp();
        mousePress(row(0));
        tryVerify(function() { return page().accountMenu.opened; }, 3000);
        mouseRelease(row(0));
        mouseClick(page().accountMenu.itemAt(1));
        var dialog = findChild(page(), "deleteDialog");
        tryVerify(function() { return dialog.visible; });
        compare(dialog.title, "Delete account");
        verify(/One/.test(dialog.message));
        answer(dialog, true);
        verify(!dialog.visible);
        tryCompare(list(), "count", 1);
        compare(findChild(row(0), "titleLabel").text, "Two");
        compare(storedIndex().accounts.length, 1);
        tryVerify(function() { return keymanager.keys[Accounts.secretKeyName("a1")] === undefined; });
        verify(keymanager.keys[Accounts.secretKeyName("a2")] !== undefined);
    }

    function test_delete_cancelled_keeps_the_account() {
        makeKeymanager();
        seed([account("a1", "One", "x"), account("a2", "Two", "y")], { a1: otherSecret, a2: rfcSecret });
        createApp();
        mousePress(row(1));
        tryVerify(function() { return page().accountMenu.opened; }, 3000);
        mouseRelease(row(1));
        mouseClick(page().accountMenu.itemAt(1));
        var dialog = findChild(page(), "deleteDialog");
        tryVerify(function() { return dialog.visible; });
        verify(/Two/.test(dialog.message), dialog.message);
        answer(dialog, false);
        verify(!dialog.visible);
        wait(50);
        compare(list().count, 2);
        compare(storedIndex().accounts.length, 2);
    }

    function test_delete_from_the_editor() {
        makeKeymanager();
        seed([account("a1", "One", "x")], { a1: otherSecret });
        createApp();
        openEditor({ accountId: "a1" });
        mouseClick(findChild(page(), "deleteButton"));
        var dialog = findChild(page(), "deleteDialog");
        verify(dialog.visible);
        verify(/Delete this account/.test(dialog.message), dialog.message);
        answer(dialog, true);
        waitForPage("accountsPage");
        verify(findChild(page(), "emptyState").visible);
        compare(storedIndex().accounts.length, 0);
    }

    function test_reorder() {
        makeKeymanager();
        seed([account("a1", "One", "x"), account("a2", "Two", "y"), account("a3", "Three", "z")],
             { a1: otherSecret, a2: otherSecret, a3: otherSecret });
        createApp();
        page().reordering = true;
        verify(findChild(row(0), "moveDownButton").visible);
        verify(!findChild(row(0), "moveUpButton").enabled);
        verify(!findChild(row(0), "countdownRing").visible);
        mouseClick(findChild(row(0), "moveDownButton"));
        tryVerify(function() { return storedIndex().accounts[0].id === "a2"; });
        compare(storedIndex().accounts.map(function(a) { return a.id; }), ["a2", "a1", "a3"]);
        tryVerify(function() { return findChild(row(0), "titleLabel").text === "Two"; });
        // Tapping copies nothing while reordering.
        mouseClick(row(2), 10, 10);
        compare(toastText(), "");
        verify(findChild(app.header, "doneButton") !== null);
        mouseClick(findChild(app.header, "doneButton"));
        verify(!page().reordering);
    }

    // --- counter-based -------------------------------------------------

    function test_hotp_counter_goes_up_before_the_code_shows() {
        makeKeymanager();
        // RFC 4226's secret, counter at 3: the codes for 3 and then 4.
        seed([account("h1", "Counter", "x", { type: "hotp", counter: 3 })], { h1: rfcSecret });
        createApp();
        var r = row(0);
        compare(findChild(r, "codeLabel").text, "Tap for a code");
        verify(!findChild(r, "countdownRing").visible);
        mouseClick(findChild(r, "nextCodeButton"));
        tryCompare(findChild(r, "codeLabel"), "text", "969 429");
        compare(storedIndex().accounts[0].counter, 4);
        mouseClick(findChild(r, "nextCodeButton"));
        tryCompare(findChild(r, "codeLabel"), "text", "338 314");
        compare(storedIndex().accounts[0].counter, 5);
    }

    function test_hotp_counter_not_saved_no_code() {
        makeKeymanager();
        seed([account("h1", "Counter", "x", { type: "hotp", counter: 3 })], { h1: rfcSecret });
        createApp();
        keymanager.failMethods = { "store": "Denied method call" };
        mouseClick(findChild(row(0), "nextCodeButton"));
        tryVerify(function() { return /counter could not be saved/.test(app.notice); });
        compare(findChild(row(0), "codeLabel").text, "Tap for a code");
    }

    // --- the key manager going wrong -----------------------------------

    function test_unreadable_store_changes_nothing() {
        makeKeymanager();
        seed([account("a1", "Example", "alice")], { a1: otherSecret });
        keymanager.failMethods = { "fetchKey": "Denied method call" };
        createApp(59000, 0, 0, false);
        tryCompare(app.store, "status", "failed");
        var notice = findChild(app.contentItem, "statusNotice");
        verify(notice.visible);
        verify(/Denied method call/.test(notice.text), notice.text);
        verify(!findChild(page(), "emptyState").visible, "must not look like there are no accounts");
        compare(app.header.actionComponent, null);
        // And nothing can be written over what is stored.
        app.store.add({ type: "totp", issuer: "x", label: "y", secret: otherSecret });
        wait(50);
        compare(storeCalls().length, 0);
        // Dismissing the notice tries again.
        keymanager.failMethods = {};
        notice.dismissed();
        tryCompare(app.store, "status", "ready");
        compare(list().count, 1);
    }

    function test_key_manager_that_never_answers() {
        makeKeymanager();
        keymanager.silent = true;
        createApp(59000, 0, 0, false);
        app.store.timeoutMs = 100;
        app.store.load();
        tryCompare(app.store, "status", "failed");
        verify(/did not answer/.test(app.store.errorText));
    }

    // The index alternates between two keys; the newer one counts, and a
    // damaged one falls back to the other.
    function test_index_alternates_and_survives_damage() {
        makeKeymanager();
        seed([account("a1", "Old", "x")], { a1: otherSecret }, 4, 0);
        seed([account("a1", "New", "x")], { a1: otherSecret }, 5, 1);
        createApp();
        compare(findChild(row(0), "titleLabel").text, "New");
        openEditor({ accountId: "a1" });
        findChild(page(), "issuerField").text = "Newer";
        save();
        waitForPage("accountsPage");
        // Generation 6 went into slot a, over 4; 5 is still in b.
        compare(Accounts.parseIndex(keymanager.keys["otp.index.a"].keydata).generation, 6);
        compare(Accounts.parseIndex(keymanager.keys["otp.index.b"].keydata).generation, 5);

        // Slot a damaged: the next start uses b.
        app.destroy();
        app = null;
        var keys = Object.assign({}, keymanager.keys);
        keys["otp.index.a"] = { keydata: "{garbage", type: "ASCIIBLOB", nohide: true };
        keymanager.keys = keys;
        createApp();
        compare(findChild(row(0), "titleLabel").text, "New");
    }

    function test_failed_index_write_keeps_the_old_one() {
        makeKeymanager();
        seed([account("a1", "Example", "alice")], { a1: otherSecret }, 1, 0);
        createApp();
        // The new secret is stored and slot b cleared, then the index
        // store fails.
        keymanager.failStoreOf = "otp.index.";
        openEditorAndFill("Second", "b", rfcSecret);
        save();
        tryVerify(function() { return /could not be saved/.test(app.notice); });
        compare(app.store.accounts.length, 1);
        compare(storedIndex().generation, 1);
        compare(storedIndex().accounts.length, 1);
        // The secret that no index names is taken out again.
        tryVerify(function() {
            return Object.keys(keymanager.keys).filter(function(k) { return k.indexOf("otp.secret.") === 0; }).length === 1;
        }, 3000, "an unlisted secret was left behind");
    }

    // --- the back gesture ----------------------------------------------

    function test_back_gesture_leaves_the_editor() {
        createApp();
        openEditor({});
        compare(app.pageStack.depth, 2);
        backGesture();
        tryCompare(app.pageStack, "depth", 1);
    }

    function test_back_gesture_closes_the_dialog_first() {
        makeKeymanager();
        seed([account("a1", "One", "x")], { a1: otherSecret });
        createApp();
        openEditor({ accountId: "a1" });
        var editor = page();
        mouseClick(findChild(editor, "deleteButton"));
        verify(findChild(editor, "deleteDialog").visible);
        backGesture();
        verify(!findChild(editor, "deleteDialog").visible);
        wait(50);
        compare(app.pageStack.depth, 2);
        compare(storedIndex().accounts.length, 1);
    }

    function test_back_gesture_ends_reordering() {
        makeKeymanager();
        seed([account("a1", "One", "x"), account("a2", "Two", "y")], { a1: otherSecret, a2: otherSecret });
        createApp();
        page().reordering = true;
        backGesture();
        verify(!page().reordering);
    }

    // --- the app menu --------------------------------------------------

    function test_app_menu() {
        makeKeymanager();
        seed([account("a1", "One", "x"), account("a2", "Two", "y")], { a1: otherSecret, a2: otherSecret });
        createApp();
        app.appMenu.popup(0, 0);
        tryVerify(function() { return app.appMenu.opened; });
        compare(app.appMenu.count, 5);
        mouseClick(app.appMenu.itemAt(2));
        verify(page().reordering);
    }

    // --- the lock ------------------------------------------------------

    function lockScreen() {
        return findChild(app.contentItem, "lockScreen");
    }

    // A locked app with one account, the lock screen up.
    function createLocked() {
        if (!keymanager)
            makeKeymanager();
        seed([account("a1", "Example", "me", { digits: 8 })], { a1: rfcSecret }, 1, 0, true);
        createApp(59000, undefined, undefined, false);
        tryCompare(app.store, "status", "locked");
        tryCompare(app.deviceAuth, "lockMode", auth.lockMode);
        verify(lockScreen().visible);
    }

    function lockMessage() {
        return findChild(lockScreen(), "lockMessage").text;
    }

    function typePin(pin) {
        app.requestActivate();
        tryVerify(function() { return app.active; });
        lockScreen().forceActiveFocus();
        for (var i = 0; i < pin.length; i++)
            keyClick(pin[i]);
    }

    function test_not_locked_unless_asked() {
        makeKeymanager();
        seed([account("a1", "Example", "me")], { a1: rfcSecret });
        createApp();
        verify(!app.locked);
        verify(!lockScreen().visible);
        compare(auth.countOf("identify"), 0);
        app.appMenu.popup(0, 0);
        tryVerify(function() { return app.appMenu.opened; });
        compare(app.appMenu.itemAt(3).text, "Lock with fingerprint or passcode");
    }

    function test_turning_the_lock_on_and_off() {
        makeKeymanager();
        seed([account("a1", "Example", "me")], { a1: rfcSecret });
        createApp();
        tryCompare(app.deviceAuth, "lockMode", "pin");
        app.toggleLock();
        tryCompare(app.store, "lockEnabled", true);
        verify(storedIndex().lock);
        compare(storedIndex().accounts.length, 1);
        compare(toastText(), "Locked when opened");
        // Turned on from inside, it stays open.
        verify(!app.locked);
        compare(list().count, 1);
        app.toggleLock();
        tryCompare(app.store, "lockEnabled", false);
        verify(!storedIndex().lock);
    }

    function test_lock_needs_a_screen_lock_passcode() {
        makeKeymanager();
        makeAuth();
        auth.lockMode = "none";
        seed([account("a1", "Example", "me")], { a1: rfcSecret });
        createApp();
        tryCompare(app.deviceAuth, "lockMode", "none");
        app.toggleLock();
        verify(/Screen & Lock/.test(app.notice));
        verify(!app.store.lockEnabled);
        compare(storeCalls().length, 0);
    }

    // The secrets are not read before the lock is opened.
    function test_locked_start_reads_no_secret() {
        createLocked();
        compare(keymanager.countOf("fetchKey"), 2);
        compare(app.store.accounts.length, 0);
        compare(app.store.keyOf("a1"), null);
        verify(!list().visible);
        verify(/Enter the screen lock PIN/.test(lockMessage()));
        // No sensor set up: nothing armed.
        compare(auth.armed(), 0);
    }

    function test_pin_opens_the_lock() {
        createLocked();
        typePin("1357");
        compare(findChild(lockScreen(), "pinDots").text, "\u25cf\u25cf\u25cf\u25cf");
        mouseClick(findChild(lockScreen(), "unlockButton"));
        tryCompare(app.store, "status", "ready");
        verify(!lockScreen().visible);
        compare(auth.calls.filter(function(c) { return c.method === "matchDevicePasscode"; })[0].args.passCode, "1357");
        compare(findChild(row(0), "codeLabel").text, "9428 7082");
    }

    function test_pin_pad_opens_the_lock() {
        createLocked();
        var pad = findChild(lockScreen(), "pinPad");
        verify(pad.visible);
        "1357".split("").forEach(function(d) { pad.keyAction(d); });
        pad.keyAction("9");
        pad.keyAction("\b");
        compare(lockScreen().pin, "1357");
        mouseClick(findChild(lockScreen(), "unlockButton"));
        tryCompare(app.store, "status", "ready");
    }

    function test_wrong_pin_then_lockout() {
        createLocked();
        auth.lockoutAfter = 2;
        typePin("0000");
        keyClick(Qt.Key_Return);
        tryVerify(function() { return lockMessage() === "That is not the PIN."; });
        compare(app.store.status, "locked");
        compare(lockScreen().pin, "");
        typePin("1111");
        keyClick(Qt.Key_Return);
        tryVerify(function() { return lockScreen().lockedOut; });
        verify(/Too many tries. Try again in 30 seconds/.test(lockMessage()));
        verify(!findChild(lockScreen(), "pinPad").enabled);
        // Not even the right one is sent while locked out.
        var sent = auth.countOf("matchDevicePasscode");
        typePin("1357");
        keyClick(Qt.Key_Return);
        wait(50);
        compare(auth.countOf("matchDevicePasscode"), sent);
        compare(app.store.status, "locked");
    }

    function test_passcode_check_refused() {
        createLocked();
        auth.denyMatch = true;
        typePin("1357");
        keyClick(Qt.Key_Return);
        tryVerify(function() { return /cannot be checked: Denied/.test(lockMessage()); });
        compare(app.store.status, "locked");
    }

    function test_password_opens_the_lock() {
        makeAuth();
        auth.lockMode = "password";
        auth.passcode = "correct horse";
        createLocked();
        var field = findChild(lockScreen(), "passwordField");
        verify(field.visible);
        verify(!findChild(lockScreen(), "pinPad").visible);
        field.text = "wrong horse";
        field.accepted();
        tryVerify(function() { return lockMessage() === "That is not the password."; });
        compare(field.text, "");
        field.text = "correct horse";
        mouseClick(findChild(lockScreen(), "unlockButton"));
        tryCompare(app.store, "status", "ready");
    }

    function test_pattern_opens_the_lock() {
        makeAuth();
        auth.lockMode = "pattern";
        auth.passcode = "0-1-2-5-8";
        createLocked();
        verify(findChild(lockScreen(), "patternGrid").visible);
        verify(!findChild(lockScreen(), "unlockButton").visible);
        findChild(lockScreen(), "patternGrid").patternDrawn("0-3-6-7");
        tryVerify(function() { return lockMessage() === "That is not the pattern."; });
        findChild(lockScreen(), "patternGrid").patternDrawn("0-1-2-5-8");
        tryCompare(app.store, "status", "ready");
    }

    function test_no_passcode_any_more() {
        makeAuth();
        auth.lockMode = "none";
        createLocked();
        verify(/No screen lock passcode is set/.test(lockMessage()));
        verify(!findChild(lockScreen(), "pinPad").visible);
        // Setting one in Settings opens the way.
        auth.lockMode = "pin";
        tryVerify(function() { return findChild(lockScreen(), "pinPad").visible; });
        typePin("1357");
        keyClick(Qt.Key_Return);
        tryCompare(app.store, "status", "ready");
    }

    function test_fingerprint_opens_the_lock() {
        makeAuth();
        auth.fingerprints = ["right-index"];
        createLocked();
        tryVerify(function() { return auth.armed() === 1; });
        compare(lockMessage(), "Touch the fingerprint sensor or enter the screen lock PIN.");
        auth.touch(true);
        tryCompare(app.store, "status", "ready");
        compare(findChild(row(0), "codeLabel").text, "9428 7082");
        // Not left armed.
        tryVerify(function() { return auth.armed() === 0; });
    }

    function test_fingerprint_misses_leave_the_passcode() {
        makeAuth();
        auth.fingerprints = ["right-index"];
        createLocked();
        var cooldown = app.deviceAuth._missCooldown;
        tryVerify(function() { return auth.armed() === 1; });
        auth.touch(false);
        tryVerify(function() { return lockMessage() === "The fingerprint was not recognised."; });
        compare(app.store.status, "locked");
        // Two captures of one press count once.
        auth.touch(false);
        wait(50);
        compare(app.deviceAuth.fingerprintMisses, 1);
        cooldown.interval = 10;
        for (var i = 1; i < 5; i++) {
            tryVerify(function() { return !cooldown.running; });
            auth.touch(false);
            tryCompare(app.deviceAuth, "fingerprintMisses", i + 1);
        }
        compare(lockMessage(), "Too many tries with the fingerprint; use the passcode.");
        tryVerify(function() { return auth.armed() === 0; });
        verify(auth.countOf("abort") >= 1);
        // Away and back does not give more tries.
        app.inFront = false;
        app.inFront = true;
        wait(50);
        compare(app.deviceAuth.fingerprintMisses, 5);
        compare(auth.armed(), 0);
        typePin("1357");
        keyClick(Qt.Key_Return);
        tryCompare(app.store, "status", "ready");
    }

    // The sensor is armed only while the app is in front.
    function test_fingerprint_disarmed_in_the_background() {
        makeAuth();
        auth.fingerprints = ["right-index"];
        createLocked();
        tryVerify(function() { return auth.armed() === 1; });
        app.inFront = false;
        tryVerify(function() { return auth.armed() === 0; });
        verify(auth.countOf("abort") >= 1);
        app.inFront = true;
        tryVerify(function() { return auth.armed() === 1; });
    }

    // The 30 second limit ends an identify; it is asked for again.
    function test_fingerprint_rearmed_after_timeout() {
        makeAuth();
        auth.fingerprints = ["right-index"];
        createLocked();
        tryVerify(function() { return auth.armed() === 1; });
        var before = auth.countOf("identify");
        auth._identifySubs[0].reply({ payload: JSON.stringify({ returnValue: false, finished: true,
                                                                identified: false, errorText: "Aborted" }) });
        tryVerify(function() { return auth.countOf("identify") === before + 1; }, 3000);
        compare(app.store.status, "locked");
    }

    function test_relocks_after_a_minute_away() {
        createLocked();
        typePin("1357");
        keyClick(Qt.Key_Return);
        tryCompare(app.store, "status", "ready");
        openEditor({});
        waitForPage("editAccountPage");
        // Back within the minute: still open.
        app.inFront = false;
        lockNow += 30000;
        app.inFront = true;
        compare(app.store.status, "ready");
        compare(page().objectName, "editAccountPage");
        // Away longer: locked, back on the list, the secrets let go.
        app.inFront = false;
        lockNow += 61000;
        app.inFront = true;
        tryCompare(app.store, "status", "locked");
        verify(lockScreen().visible);
        compare(app.pageStack.depth, 1);
        compare(app.store.keyOf("a1"), null);
        compare(app.store.accounts.length, 0);
        compare(lockScreen().pin, "");
    }

    function test_relocks_in_the_background() {
        createLocked();
        app.relockAfterMs = 50;
        typePin("1357");
        keyClick(Qt.Key_Return);
        tryCompare(app.store, "status", "ready");
        app.inFront = false;
        tryCompare(app.store, "status", "locked");
        compare(app.store.keyOf("a1"), null);
    }

    // A change being saved when the lock comes is finished first.
    function test_relock_waits_for_a_save() {
        createLocked();
        typePin("1357");
        keyClick(Qt.Key_Return);
        tryCompare(app.store, "status", "ready");
        app.store.add({ type: "totp", issuer: "Second", label: "x", secret: otherSecret,
                        algorithm: "SHA1", digits: 6, period: 30 });
        app.lock();
        verify(app.locked);
        tryCompare(app.store, "status", "locked");
        compare(storedIndex().accounts.length, 2);
        verify(storedIndex().lock);
    }

    function test_link_waits_for_the_lock() {
        createLocked();
        app.openLink("otpauth://totp/Linked:me?secret=" + otherSecret + "&issuer=Linked");
        compare(app.pageStack.depth, 1);
        typePin("1357");
        keyClick(Qt.Key_Return);
        waitForPage("editAccountPage");
        verify(page().fromLink);
    }

    function test_back_gesture_does_not_pass_the_lock() {
        createLocked();
        backGesture();
        compare(app.store.status, "locked");
        verify(lockScreen().visible);
    }

    // --- face ----------------------------------------------------------

    function faceItem() {
        return findChild(app.appMenu.contentItem, "faceMenuItem") || app.appMenu.itemAt(4);
    }

    // Until the n-th face identify has been asked for.
    function waitForFaceAttempt(n) {
        tryVerify(function() { return auth.countOf("face:identify") === n; }, 3000, "face attempt " + n);
    }

    // A locked app with face turned on and enrolled.
    function createFaceLocked() {
        makeAuth();
        auth.faceEnrolled = true;
        makeKeymanager();
        seed([account("a1", "Example", "me", { digits: 8 })], { a1: rfcSecret }, 1, 0, true, true);
        createApp(59000, undefined, undefined, false);
        tryCompare(app.store, "status", "locked");
        tryCompare(app.deviceAuth, "lockMode", "pin");
        app.deviceAuth.faceGapMs = 10;
    }

    function test_face_offered_only_where_enrolled_and_locked() {
        makeAuth();
        makeKeymanager();
        seed([account("a1", "Example", "me")], { a1: rfcSecret });
        createApp();
        tryCompare(app.deviceAuth, "lockMode", "pin");
        app.appMenu.popup(0, 0);
        tryVerify(function() { return app.appMenu.opened; });
        verify(!faceItem().visible);
        auth.faceEnrolled = true;
        tryCompare(app.deviceAuth, "faceEnrolled", true);
        // Not without the lock.
        verify(!faceItem().visible);
        app.appMenu.close();
        app.toggleLock();
        tryCompare(app.store, "lockEnabled", true);
        app.appMenu.popup(0, 0);
        tryVerify(function() { return app.appMenu.opened; });
        verify(faceItem().visible);
        compare(faceItem().text, "Also open with a face");
        app.appMenu.close();
    }

    function test_face_asks_first_and_says_why() {
        makeAuth();
        auth.faceEnrolled = true;
        makeKeymanager();
        seed([account("a1", "Example", "me")], { a1: rfcSecret }, 1, 0, true);
        createLocked();
        typePin("1357");
        keyClick(Qt.Key_Return);
        tryCompare(app.store, "status", "ready");
        var dialog = findChild(app.contentItem, "faceDialog");
        app.toggleFace();
        verify(dialog.visible);
        verify(/good photo of you/.test(dialog.message));
        compare(dialog.title, "Open with a face?");
        answer(dialog, false);
        verify(!dialog.visible);
        wait(50);
        verify(!app.store.faceEnabled);
        app.toggleFace();
        answer(dialog, true);
        verify(!dialog.visible);
        tryCompare(app.store, "faceEnabled", true);
        verify(storedIndex().face);
        compare(toastText(), "Opened with a face too");
        app.toggleFace();
        tryCompare(app.store, "faceEnabled", false);
        verify(!storedIndex().face);
    }

    function test_lock_off_takes_face_with_it() {
        createFaceLocked();
        typePin("1357");
        keyClick(Qt.Key_Return);
        tryCompare(app.store, "status", "ready");
        verify(app.store.faceEnabled);
        app.toggleLock();
        tryCompare(app.store, "lockEnabled", false);
        verify(!app.store.faceEnabled);
        verify(!storedIndex().face);
    }

    // Enrolled, but not turned on in the app: the camera is left alone.
    function test_face_not_used_unless_turned_on() {
        makeAuth();
        auth.faceEnrolled = true;
        createLocked();
        tryCompare(app.deviceAuth, "faceEnrolled", true);
        wait(50);
        compare(auth.countOf("face:identify"), 0);
        verify(!/look at the screen/i.test(lockMessage()));
        verify(!findChild(lockScreen(), "faceAgainButton").visible);
    }

    function test_face_opens_the_lock() {
        createFaceLocked();
        tryVerify(function() { return auth.faceArmed() === 1; });
        compare(lockMessage(), "Look at the screen or enter the screen lock PIN.");
        compare(findChild(lockScreen(), "faceStatus").text, "Looking for your face\u2026");
        auth.face({ returnValue: true, scanning: true });
        tryCompare(findChild(lockScreen(), "faceStatus"), "text", "Checking\u2026");
        auth.face({ returnValue: true, recognized: true });
        tryCompare(app.store, "status", "ready");
        compare(findChild(row(0), "codeLabel").text, "9428 7082");
    }

    function test_face_fingerprint_and_pin_together() {
        makeAuth();
        auth.fingerprints = ["right-index"];
        auth.faceEnrolled = true;
        makeKeymanager();
        seed([account("a1", "Example", "me")], { a1: rfcSecret }, 1, 0, true, true);
        createApp(59000, undefined, undefined, false);
        tryCompare(app.store, "status", "locked");
        tryVerify(function() { return auth.armed() === 1 && auth.faceArmed() === 1; });
        compare(lockMessage(), "Look at the screen, touch the fingerprint sensor, or enter the screen lock PIN.");
        auth.touch(true);
        tryCompare(app.store, "status", "ready");
        // The camera let go as well.
        tryVerify(function() { return auth.faceArmed() === 0; });
        verify(auth.countOf("face:abort") >= 1);
    }

    // A few attempts, then the camera is left alone until asked.
    function test_face_tries_are_few() {
        createFaceLocked();
        for (var i = 0; i < 3; i++) {
            waitForFaceAttempt(i + 1);
            auth.face({ returnValue: true, recognized: false, reason: "notRecognized" });
            tryCompare(app.deviceAuth, "faceTries", i + 1);
        }
        wait(50);
        compare(auth.faceArmed(), 0);
        compare(auth.countOf("face:identify"), 3);
        compare(findChild(lockScreen(), "faceStatus").text, "The face was not recognised.");
        var again = findChild(lockScreen(), "faceAgainButton");
        verify(again.visible);
        mouseClick(again);
        tryVerify(function() { return auth.faceArmed() === 1; });
        compare(app.deviceAuth.faceMisses, 3);
    }

    function test_no_face_is_not_a_miss() {
        createFaceLocked();
        tryVerify(function() { return auth.faceArmed() === 1; });
        auth.face({ returnValue: true, recognized: false, reason: "noFace" });
        tryCompare(findChild(lockScreen(), "faceStatus"), "text", "No face seen.");
        compare(app.deviceAuth.faceMisses, 0);
        compare(app.store.status, "locked");
    }

    function test_face_misses_leave_the_passcode() {
        createFaceLocked();
        for (var i = 0; i < 5; i++) {
            if (i === 3)
                app.deviceAuth.tryFaceAgain();
            waitForFaceAttempt(i + 1);
            auth.face({ returnValue: true, recognized: false, reason: "notRecognized" });
            tryCompare(app.deviceAuth, "faceMisses", i + 1);
        }
        compare(lockMessage(), "Too many tries with the face; use the passcode.");
        verify(!findChild(lockScreen(), "faceAgainButton").visible);
        // Coming back does not give more.
        app.inFront = false;
        app.inFront = true;
        wait(50);
        compare(auth.faceArmed(), 0);
        typePin("1357");
        keyClick(Qt.Key_Return);
        tryCompare(app.store, "status", "ready");
    }

    // The Camera app holds the camera: the passcode, without a fuss.
    function test_face_camera_busy() {
        createFaceLocked();
        tryVerify(function() { return auth.faceArmed() === 1; });
        auth.face({ returnValue: false, state: "unavailable", errorText: "camera busy" });
        tryCompare(findChild(lockScreen(), "faceStatus"), "text", "Face unlock cannot be used just now.");
        wait(50);
        compare(auth.countOf("face:identify"), 1);
        compare(app.deviceAuth.faceMisses, 0);
        verify(findChild(lockScreen(), "faceAgainButton").visible);
        // Back in front, it is tried again.
        app.inFront = false;
        app.inFront = true;
        tryVerify(function() { return auth.faceArmed() === 1; });
    }

    function test_face_disarmed_in_the_background() {
        createFaceLocked();
        tryVerify(function() { return auth.faceArmed() === 1; });
        app.inFront = false;
        tryVerify(function() { return auth.faceArmed() === 0; });
        verify(auth.countOf("face:abort") >= 1);
    }

    function test_lock_layout_data() {
        return test_layout_data();
    }
    function test_lock_layout(data) {
        makeKeymanager();
        seed([account("a1", "Example", "me")], { a1: rfcSecret }, 1, 0, true);
        createApp(59000, data.w, data.h, false);
        tryCompare(app.store, "status", "locked");
        tryCompare(app.deviceAuth, "lockMode", "pin");
        waitForRendering(app.contentItem);
        var items = ["pinPad", "unlockButton", "lockMessage"];
        for (var i = 0; i < items.length; i++) {
            var item = findChild(lockScreen(), items[i]);
            var p = item.mapToItem(lockScreen(), 0, 0);
            verify(p.x >= 0 && p.x + item.width <= lockScreen().width, data.tag + ": " + items[i] + " runs off the side");
        }
        verify(lockScreen().width === app.contentItem.width && lockScreen().height === app.contentItem.height);
    }

    // --- pictures ------------------------------------------------------

    // The toast and the dialogs, as they look, into build/test-output/ui.
    function test_shots() {
        makeAuth();
        auth.faceEnrolled = true;
        makeKeymanager();
        seed([account("a1", "Example", "me"), account("a2", "Two", "you")], { a1: rfcSecret, a2: otherSecret },
             1, 0, true);
        createApp(59000, 480, 800, false);
        tryCompare(app.store, "status", "locked");
        typePin("1357");
        keyClick(Qt.Key_Return);
        tryCompare(app.store, "status", "ready");
        tryVerify(function() { return !app.locked; });
        tryVerify(function() { return row(0) !== null; });

        mouseClick(row(0));
        tryVerify(function() { return findChild(app.contentItem, "toast").visible; });
        shot("toast");
        // Gone by itself, before the dialogs.
        tryVerify(function() { return !findChild(app.contentItem, "toast").visible; }, 5000);

        mousePress(row(0));
        tryVerify(function() { return page().accountMenu.opened; }, 3000);
        mouseRelease(row(0));
        mouseClick(page().accountMenu.itemAt(1));
        tryVerify(function() { return findChild(page(), "deleteDialog").visible; });
        tryVerify(function() { return !page().accountMenu.visible; });
        shot("delete-from-list");
        backGesture();
        tryVerify(function() { return !findChild(page(), "deleteDialog").visible; });

        openEditor({ accountId: "a1" });
        mouseClick(findChild(page(), "deleteButton"));
        tryVerify(function() { return findChild(page(), "deleteDialog").visible; });
        shot("delete-from-editor");
        backGesture();
        tryVerify(function() { return !findChild(page(), "deleteDialog").visible; });
        app.pageStack.pop(null);
        settle();

        app.toggleFace();
        tryVerify(function() { return findChild(app.contentItem, "faceDialog").visible; });
        shot("face");
    }

    // --- layout --------------------------------------------------------

    function test_layout_data() {
        return [
            { tag: "320x480", w: 320, h: 480 },
            { tag: "480x800", w: 480, h: 800 },
            { tag: "720x720", w: 720, h: 720 },
            { tag: "1024x768", w: 1024, h: 768 }
        ];
    }
    function test_layout(data) {
        makeKeymanager();
        seed([account("a1", "A very long site name that goes on and on", "someone.with.a.long.address@example.com", { digits: 8 }),
              account("h1", "Counter", "x", { type: "hotp" })],
             { a1: rfcSecret, h1: rfcSecret });
        createApp(59000, data.w, data.h);
        for (var i = 0; i < 2; i++) {
            var r = row(i);
            compare(r.width, list().width);
            var ring = findChild(r, "countdownRing");
            var next = findChild(r, "nextCodeButton");
            var right = ring.visible ? ring : next;
            var p = right.mapToItem(r, 0, 0);
            verify(p.x + right.width <= r.width, data.tag + ": row " + i + " runs off the right");
            var code = findChild(r, "codeLabel");
            var c = code.mapToItem(r, 0, 0);
            verify(c.x + code.width <= p.x, data.tag + ": the code runs under the timer");
            verify(c.y + code.height <= r.height, data.tag + ": the code is cut off");
        }
        // The editor fits its width too.
        openEditor({});
        var saveButton = findChild(app.header, "saveButton");
        verify(saveButton.mapToItem(app.contentItem, 0, 0).x + saveButton.width <= app.width);
        var secret = findChild(page(), "secretField");
        verify(secret.mapToItem(app.contentItem, 0, 0).x + secret.width <= app.width);
    }
}

/*
 * Copyright 2026 Herman van Hazendonk <github.com@herrie.org>
 * SPDX-License-Identifier: Apache-2.0
 */

import QtQuick
import QtQuick.Controls
import QtTest

import "../../qml/js/Accounts.js" as Accounts

/*
 * The app itself - qml/main.qml and its pages - on the build host, with
 * luneos-components' desktop stand-ins for the window and the bus, and
 * FakeKeyManager.qml for com.palm.keymanager. Run by tests/run-qml-tests.sh.
 */
TestCase {
    id: test
    name: "AuthenticatorUi"
    when: windowShown

    property var app: null
    property var keymanager: null

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

    // Stored accounts, as the app writes them.
    function seed(accounts, secrets, generation, slot) {
        var keys = Object.assign({}, keymanager.keys);
        keys[Accounts.INDEX_KEYS[slot || 0]] = {
            keydata: Accounts.serializeIndex(generation || 1, accounts), type: "ASCIIBLOB", nohide: true, noexport: true
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
        var component = Qt.createComponent(Qt.resolvedUrl("../../qml/main.qml"));
        if (component.status !== Component.Ready)
            fail(component.errorString());
        var t = timeMs === undefined ? 59000 : timeMs;
        app = component.createObject(null, { bus: keymanager, clock: function() { return t; } });
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
        compare(app.toast, "Copied Example’s code");
        verify(findChild(app.contentItem, "toast").visible);
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
        compare(app.toast, "Added Example");

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
        verify(/One/.test(dialog.message));
        dialog.accepted();
        tryCompare(list(), "count", 1);
        compare(findChild(row(0), "titleLabel").text, "Two");
        compare(storedIndex().accounts.length, 1);
        tryVerify(function() { return keymanager.keys[Accounts.secretKeyName("a1")] === undefined; });
        verify(keymanager.keys[Accounts.secretKeyName("a2")] !== undefined);
    }

    function test_delete_from_the_editor() {
        makeKeymanager();
        seed([account("a1", "One", "x")], { a1: otherSecret });
        createApp();
        openEditor({ accountId: "a1" });
        mouseClick(findChild(page(), "deleteButton"));
        verify(findChild(page(), "deleteDialog").visible);
        findChild(page(), "deleteDialog").accepted();
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
        compare(app.toast, "");
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
        compare(app.appMenu.count, 3);
        mouseClick(app.appMenu.itemAt(2));
        verify(page().reordering);
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

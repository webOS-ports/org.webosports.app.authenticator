/*
 * Copyright 2026 Herman van Hazendonk <github.com@herrie.org>
 * SPDX-License-Identifier: GPL-3.0-only
 */

import QtQuick
import QtQuick.Controls
import QtTest
import LunaNext.Common 0.1

import "../../qml/js/Accounts.js" as Accounts
import "../../qml/js/Base32.js" as Base32
import "../../qml/js/Migration.js" as Migration

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
        // The app's pill, up at once
        var box = toast.parent;
        compare(box.radius, box.height / 2, "a pill");
        verify(Qt.colorEqual(box.color, "#e0303030"));
        compare(box.opacity, 1, "no fade");
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

    // --- another authenticator's export (otpauth-migration://) ----------

    // An export link of these accounts, with these keys (Base32).
    function exportLink(accounts, secrets, batchIndex, batchSize) {
        var parts = accounts.map(function(a) {
            return Migration.accountBytes(a, Base32.decode(secrets[a.id]));
        });
        return Migration.link(parts, batchSize || 1, batchIndex || 0, 99);
    }

    function importRows() {
        var out = [];
        for (var i = 0; ; i++) {
            var r = findChild(page(), "importRow" + i);
            if (!r)
                return out;
            out.push({ title: findChild(r, "importTitle").text, note: findChild(r, "importNote").text });
        }
    }

    function secretKeys() {
        return Object.keys(keymanager.keys).filter(function(k) { return k.indexOf("otp.secret.") === 0; });
    }

    function test_import_offers_the_exported_accounts() {
        createApp(59000);
        var link = exportLink([account("x", "Example", "alice", { digits: 8 }),
                               account("y", "", "bob"),
                               account("z", "Counter", "carol", { type: "hotp", counter: 7 })],
                              { x: rfcSecret, y: otherSecret, z: rfcSecret });
        app.launchParams = JSON.stringify({ target: link });
        waitForPage("importPage");
        compare(importRows(), [{ title: "Example", note: "" }, { title: "bob", note: "" }, { title: "Counter", note: "" }]);
        verify(/check that these are your accounts/.test(findChild(page(), "importExplanation").text));
        verify(!/QR codes/.test(findChild(page(), "importExplanation").text));
        // Nothing stored until Add.
        compare(storeCalls().length, 0);
        var add = findChild(app.header, "importButton");
        verify(add.enabled);
        mouseClick(add);
        waitForPage("accountsPage");
        compare(toastText(), "Added 3 accounts");
        compare(list().count, 3);
        compare(findChild(row(0), "codeLabel").text, "9428 7082");
        compare(storedIndex().accounts.map(function(a) { return [a.issuer, a.label, a.type, a.counter]; }),
                [["Example", "alice", "totp", 0], ["", "bob", "totp", 0], ["Counter", "carol", "hotp", 7]]);
        // Three secrets, then one index: written once, not once per account.
        var writes = storeCalls().filter(function(c) { return c.method === "store"; });
        compare(writes.length, 4);
        compare(writes.filter(function(c) { return c.args.keyname.indexOf("otp.index.") === 0; }).length, 1);
        compare(writes[3].args.keyname.indexOf("otp.index."), 0, "the index after the secrets");
        writes.forEach(function(c) { verify(c.args.noexport === true && c.args.nohide === true); });
        compare(secretKeys().length, 3);
    }

    function test_import_shows_what_is_there_and_what_cannot_be_used() {
        makeKeymanager();
        seed([account("a1", "Example", "alice")], { a1: rfcSecret });
        createApp(59000);
        var md5 = [];
        Migration.writeBytes(md5, 1, Base32.decode(otherSecret));
        Migration.writeBytes(md5, 2, Migration.utf8Encode("Old"));
        Migration.writeNumber(md5, 4, 4);
        var parts = [Migration.accountBytes(account("x", "example", "Alice"), Base32.decode(rfcSecret)), md5,
                     Migration.accountBytes(account("y", "New", "me"), Base32.decode(otherSecret)),
                     Migration.accountBytes(account("z", "New", "me"), Base32.decode(otherSecret))];
        app.openLink(Migration.link(parts, 3, 1, 5));
        waitForPage("importPage");
        var rows = importRows();
        compare(rows.length, 4);
        compare(rows[0], { title: "example", note: "Already here" });
        compare(rows[1].title, "Old");
        verify(/MD5/.test(rows[1].note), rows[1].note);
        compare(rows[2], { title: "New", note: "" });
        // The same account twice in one export: added once.
        compare(rows[3], { title: "New", note: "Already here" });
        verify(/3 QR codes, at most 10 accounts in each; this is code 2\. Scan codes 1 and 3 after this one\./
               .test(findChild(page(), "importExplanation").text), findChild(page(), "importExplanation").text);
        mouseClick(findChild(app.header, "importButton"));
        waitForPage("accountsPage");
        compare(toastText(), "Added New; now scan code 1 of 3");
        compare(list().count, 2);
        compare(secretKeys().length, 2);
    }

    function test_import_with_nothing_new() {
        makeKeymanager();
        seed([account("a1", "Example", "alice")], { a1: rfcSecret });
        createApp();
        app.openLink(exportLink([account("x", "Example", "alice")], { x: rfcSecret }));
        waitForPage("importPage");
        verify(!findChild(app.header, "importButton").enabled);
        verify(/nothing new/.test(findChild(page(), "importExplanation").text));
        page().add();
        wait(50);
        compare(storeCalls().length, 0);
    }

    // The index cannot be written: no account added, and no secret left.
    function test_import_not_saved_adds_nothing() {
        makeKeymanager();
        seed([account("a1", "Example", "alice")], { a1: rfcSecret });
        createApp();
        keymanager.failStoreOf = "otp.index.";
        app.openLink(exportLink([account("x", "One", "a"), account("y", "Two", "b")], { x: rfcSecret, y: otherSecret }));
        waitForPage("importPage");
        mouseClick(findChild(app.header, "importButton"));
        tryVerify(function() { return /could not be saved/.test(app.notice); });
        compare(page().objectName, "importPage");
        tryVerify(function() { return secretKeys().length === 1; }, 5000, "the stored secrets removed again");
        compare(storedIndex().accounts.length, 1);
        compare(app.store.accounts.length, 1);
        // A secret that cannot be stored: nothing after it is tried.
        keymanager.failStoreOf = "otp.secret.";
        var before = storeCalls().length;
        mouseClick(findChild(app.header, "importButton"));
        tryVerify(function() { return !page().saving; });
        compare(storeCalls().length, before + 1);
        compare(secretKeys().length, 1);
    }

    function test_import_link_waits_for_the_lock() {
        createLocked();
        app.openLink(exportLink([account("x", "Linked", "me")], { x: otherSecret }));
        compare(app.pageStack.depth, 1);
        typePin("1357");
        keyClick(Qt.Key_Return);
        waitForPage("importPage");
        compare(importRows()[0].title, "Linked");
    }

    function test_pasted_export_link_opens_the_import() {
        createApp();
        openEditor({});
        findChild(page(), "secretField").text = exportLink([account("x", "Pasted", "me")], { x: otherSecret });
        waitForPage("importPage");
        compare(importRows()[0].title, "Pasted");
        compare(app.pageStack.depth, 2, "the editor is left, not kept under the import");
    }

    // Google Authenticator puts at most 10 accounts in a code: an export of
    // 25 is three codes, each imported on its own; the app says which are
    // still to come.
    function test_import_of_several_codes() {
        createApp();
        var accounts = [], secrets = {};
        for (var i = 0; i < 25; i++) {
            accounts.push(account("x" + i, "Site " + i, "me"));
            secrets["x" + i] = i % 2 ? rfcSecret : otherSecret;
        }
        function code(index) {
            return exportLink(accounts.slice(index * 10, index * 10 + 10), secrets, index, 3);
        }
        function explanation() {
            return findChild(page(), "importExplanation").text;
        }
        app.openLink(code(0));
        waitForPage("importPage");
        verify(/this is code 1\. Scan codes 2 and 3 after this one\./.test(explanation()), explanation());
        compare(importRows().length, 10);
        mouseClick(findChild(app.header, "importButton"));
        waitForPage("accountsPage");
        compare(toastText(), "Added 10 accounts; now scan code 2 of 3");
        app.openLink(code(2));
        waitForPage("importPage");
        verify(/this is code 3\. Code 1 is in already\. Scan code 2 after this one\./.test(explanation()), explanation());
        mouseClick(findChild(app.header, "importButton"));
        waitForPage("accountsPage");
        compare(toastText(), "Added 5 accounts; now scan code 2 of 3");
        app.openLink(code(1));
        waitForPage("importPage");
        verify(/this is code 2\. Codes 1 and 3 are in already\.$/.test(explanation()), explanation());
        mouseClick(findChild(app.header, "importButton"));
        waitForPage("accountsPage");
        compare(toastText(), "Added 10 accounts; all 3 codes of the export are in");
        compare(list().count, 25);
        compare(storedIndex().accounts.map(function(a) { return a.issuer; }).sort(),
                accounts.map(function(a) { return a.issuer; }).sort());
        // A code again: nothing new, and the others still counted as in.
        app.openLink(code(1));
        waitForPage("importPage");
        verify(!findChild(app.header, "importButton").enabled);
        verify(/nothing new.*Codes 1 and 3 are in already\.$/.test(explanation()), explanation());
    }

    // Another export (another batch id) starts its own count.
    function test_import_codes_counted_per_export() {
        createApp();
        app.openLink(Migration.link([Migration.accountBytes(account("x", "A", "me"), Base32.decode(rfcSecret))], 2, 0, 1));
        waitForPage("importPage");
        mouseClick(findChild(app.header, "importButton"));
        waitForPage("accountsPage");
        app.openLink(Migration.link([Migration.accountBytes(account("y", "B", "me"), Base32.decode(rfcSecret))], 2, 1, 2));
        waitForPage("importPage");
        verify(!/in already/.test(findChild(page(), "importExplanation").text));
        verify(/Scan code 1 after this one/.test(findChild(page(), "importExplanation").text));
    }

    function clickImportFromClipboard() {
        app.appMenu.popup(0, 0);
        tryVerify(function() { return app.appMenu.opened; });
        var item = findChild(app.appMenu.contentItem, "importClipboardMenuItem") || app.appMenu.itemAt(6);
        compare(item.text, "Import from clipboard");
        verify(item.enabled);
        mouseClick(item);
    }

    // The Camera's Copy, then the app menu.
    function test_import_from_clipboard() {
        createApp();
        app.copyText(exportLink([account("x", "Copied", "me")], { x: otherSecret }));
        clickImportFromClipboard();
        waitForPage("importPage");
        compare(importRows()[0].title, "Copied");
        // An otpauth:// link goes to the editor, as a launch would.
        app.pageStack.pop(null);
        settle();
        app.copyText("  otpauth://totp/Single:me?secret=" + otherSecret + "  ");
        clickImportFromClipboard();
        waitForPage("editAccountPage");
        compare(findChild(page(), "issuerField").text, "Single");
        // Anything else says what to do.
        app.pageStack.pop(null);
        settle();
        app.copyText("hello");
        clickImportFromClipboard();
        compare(page().objectName, "accountsPage");
        verify(/no export to import/.test(app.notice), app.notice);
        // The clipboard is left as it was.
        pasteTarget.text = "";
        pasteTarget.paste();
        compare(pasteTarget.text, "hello");
    }

    function test_bad_export_link_says_why() {
        createApp();
        app.openLink("otpauth-migration://offline?data=!!!");
        compare(page().objectName, "accountsPage");
        verify(/garbled/.test(app.notice), app.notice);
        app.openLink("otpauth-migration://offline?data=");
        verify(/no accounts/.test(app.notice), app.notice);
    }

    // --- export --------------------------------------------------------

    function openExport() {
        app.appMenu.popup(0, 0);
        tryVerify(function() { return app.appMenu.opened; });
        var item = findChild(app.appMenu.contentItem, "exportMenuItem") || app.appMenu.itemAt(5);
        verify(item.enabled);
        mouseClick(item);
        waitForPage("exportPage");
    }

    function test_export_needs_accounts() {
        createApp();
        app.appMenu.popup(0, 0);
        tryVerify(function() { return app.appMenu.opened; });
        verify(!app.appMenu.itemAt(5).enabled);
        compare(app.appMenu.itemAt(5).text, "Export accounts");
    }

    function test_export_shows_the_chosen_accounts_as_codes() {
        makeKeymanager();
        var accounts = [account("a1", "Example", "alice", { digits: 8 }), account("a2", "Mail", "me", { algorithm: "SHA256" }),
                        account("h1", "Counter", "bob", { type: "hotp", counter: 12 }),
                        account("s1", "Slow", "x", { period: 60 }), account("d7", "Seven", "x", { digits: 7 }),
                        account("g1", "Gone", "x")];
        seed(accounts, { a1: rfcSecret, a2: otherSecret, h1: rfcSecret, s1: rfcSecret, d7: rfcSecret });
        createApp();
        openExport();
        verify(/whoever reads them can make your codes/.test(findChild(page(), "exportExplanation").text));
        compare(page().exportable.map(function(a) { return a.id; }), ["a1", "a2", "h1"]);
        compare(page().notExportable.map(function(a) { return a.id; }), ["s1", "d7", "g1"]);
        compare(page().reason(accounts[3]), "Codes that change every 60 seconds cannot be exported.");
        compare(page().reason(accounts[4]), "Codes of 7 digits cannot be exported.");
        compare(page().reason(accounts[5]), "Its key is missing.");
        // Leave Mail out.
        var mail = findChild(page(), "exportSwitch1");
        verify(mail.checked);
        mouseClick(mail);
        verify(!mail.checked);
        compare(page().chosen.map(function(a) { return a.id; }), ["a1", "h1"]);
        compare(page().codes.length, 0, "no code before Show codes");
        mouseClick(findChild(app.header, "showCodesButton"));
        tryCompare(page(), "step", "codes");
        var qr = findChild(page(), "qrCode");
        verify(qr.visible);
        compare(page().codes.length, 1);
        var parsed = Migration.parse(qr.text);
        compare(parsed.entries.map(function(e) { return [e.account.issuer, e.account.label, e.account.secret,
                                                          e.account.type, e.account.digits, e.account.counter]; }),
                [["Example", "alice", rfcSecret, "totp", 8, 0], ["Counter", "bob", rfcSecret, "hotp", 6, 12]]);
        compare(findChild(page(), "codeCaption").text, "Example, Counter");
        verify(!findChild(page(), "nextCodeButton").visible, "one code: no Next");
        // Nothing written by exporting.
        compare(storeCalls().length, 0);
        // The back gesture goes back to the choice and drops the codes.
        backGesture();
        compare(page().objectName, "exportPage");
        compare(page().step, "choose");
        compare(page().codes.length, 0);
        compare(qr.text, "");
    }

    function test_export_of_many_accounts_in_several_codes() {
        makeKeymanager();
        var accounts = [], secrets = {};
        for (var i = 0; i < 23; i++) {
            accounts.push(account("a" + i, "Site " + i, "user" + i + "@example.com"));
            secrets["a" + i] = i % 2 ? rfcSecret : otherSecret;
        }
        seed(accounts, secrets);
        createApp();
        openExport();
        mouseClick(findChild(app.header, "showCodesButton"));
        tryCompare(page(), "step", "codes");
        var n = page().codes.length;
        verify(n >= 3, n + " codes");
        var qr = findChild(page(), "qrCode");
        var next = findChild(page(), "nextCodeButton");
        var previous = findChild(page(), "previousCodeButton");
        verify(next.visible && next.enabled && !previous.enabled);
        var seen = [];
        for (var c = 0; c < n; c++) {
            var parsed = Migration.parse(qr.text);
            compare(parsed.batchIndex, c);
            compare(parsed.batchSize, n);
            verify(new RegExp("^Code " + (c + 1) + " of " + n + ": ").test(findChild(page(), "codeCaption").text));
            seen = seen.concat(parsed.entries.map(function(e) { return e.account.issuer; }));
            if (c < n - 1)
                mouseClick(next);
        }
        verify(!next.enabled && previous.enabled);
        compare(seen, accounts.map(function(a) { return a.issuer; }));
        mouseClick(previous);
        compare(page().current, n - 2);
    }

    // Taken off the screen when the app goes to the background.
    function test_export_codes_hidden_in_the_background() {
        makeKeymanager();
        seed([account("a1", "Example", "alice")], { a1: rfcSecret });
        createApp();
        openExport();
        mouseClick(findChild(app.header, "showCodesButton"));
        tryCompare(page(), "step", "codes");
        verify(findChild(page(), "qrCode").text !== "");
        app.inFront = false;
        compare(page().step, "choose");
        compare(page().codes.length, 0);
        compare(findChild(page(), "qrCode").text, "");
        app.inFront = true;
        compare(page().step, "choose", "not shown again by itself");
    }

    // Out of one app and into another, as from one phone to the next.
    function test_export_and_import_again() {
        makeKeymanager();
        var accounts = [account("a1", "Example", "alice@example.com", { digits: 8 }),
                        account("a2", "Ünïcødé 日本", "me", { algorithm: "SHA512" }),
                        account("h1", "Counter", "bob", { type: "hotp", counter: 3 })];
        seed(accounts, { a1: rfcSecret, a2: otherSecret, h1: rfcSecret });
        createApp(59000);
        var codesBefore = [findChild(row(0), "codeLabel").text, findChild(row(1), "codeLabel").text];
        openExport();
        mouseClick(findChild(app.header, "showCodesButton"));
        tryCompare(page(), "step", "codes");
        var link = findChild(page(), "qrCode").text;
        cleanup();
        createApp(59000);
        app.openLink(link);
        waitForPage("importPage");
        mouseClick(findChild(app.header, "importButton"));
        waitForPage("accountsPage");
        compare(list().count, 3);
        compare([findChild(row(0), "codeLabel").text, findChild(row(1), "codeLabel").text], codesBefore);
        compare(storedIndex().accounts.map(function(a) {
            return [a.issuer, a.label, a.algorithm, a.digits, a.type, a.counter]; }),
                accounts.map(function(a) { return [a.issuer, a.label, a.algorithm, a.digits, a.type, a.counter]; }));
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

    // --- swipe to delete ------------------------------------------------

    function swipeRow(r, fraction) {
        mouseDrag(r, r.width * 0.2, r.height / 2, r.width * fraction, 0, Qt.LeftButton, Qt.NoModifier, 5);
    }

    function test_swipe_far_asks_then_deletes() {
        makeKeymanager();
        seed([account("a1", "One", "x"), account("a2", "Two", "y")], { a1: otherSecret, a2: rfcSecret });
        createApp();
        var r = row(0);
        swipeRow(r, 0.6);
        var del = findChild(r, "swipeDeleteButton");
        tryVerify(function() { return del.visible; }, 2000, "no Delete after a long swipe");
        compare(storeCalls().length, 0, "deleted before confirming");
        compare(toastText(), "", "the swipe copied the code");
        mouseClick(del);
        tryCompare(list(), "count", 1);
        compare(storedIndex().accounts.map(function(a) { return a.id; }), ["a2"]);
        verify(keymanager.keys[Accounts.secretKeyName("a1")] === undefined, "the secret is left");
        compare(toastText(), "Deleted One");
    }

    function test_swipe_then_cancel_keeps_it() {
        makeKeymanager();
        seed([account("a1", "One", "x")], { a1: otherSecret });
        createApp();
        var r = row(0);
        swipeRow(r, -0.6);
        var cancel = findChild(r, "swipeCancelButton");
        tryVerify(function() { return cancel.visible; }, 2000);
        mouseClick(cancel);
        tryVerify(function() { return !cancel.visible; });
        verify(findChild(r, "codeLabel").visible);
        compare(storeCalls().length, 0);
        compare(list().count, 1);
        // And a tap copies again.
        mouseClick(r);
        compare(toastText(), "Copied One’s code");
    }

    function test_short_swipe_springs_back() {
        makeKeymanager();
        seed([account("a1", "One", "x")], { a1: otherSecret });
        createApp();
        var r = row(0);
        // Short of 4 grid units.
        mouseDrag(r, r.width * 0.2, r.height / 2, Units.gu(3), 0, Qt.LeftButton, Qt.NoModifier, 5);
        tryCompare(findChild(r, "rowSlide"), "x", 0);
        verify(!findChild(r, "swipeDeleteButton").visible);
        compare(toastText(), "", "the swipe copied the code");
        compare(storeCalls().length, 0);
    }

    function test_no_swipe_while_reordering() {
        makeKeymanager();
        seed([account("a1", "One", "x"), account("a2", "Two", "y")], { a1: otherSecret, a2: rfcSecret });
        createApp();
        page().reordering = true;
        var r = row(0);
        swipeRow(r, 0.6);
        wait(300);
        verify(!findChild(r, "swipeDeleteButton").visible);
        compare(findChild(r, "rowSlide").x, 0);
        // Asked, then reordering: the question goes.
        page().reordering = false;
        swipeRow(r, 0.6);
        tryVerify(function() { return findChild(r, "swipeDeleteButton").visible; }, 2000);
        page().reordering = true;
        verify(!findChild(r, "swipeDeleteButton").visible);
        compare(storeCalls().length, 0);
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
        mouseClick(findChild(notice, "noticeCloseButton"));
        tryCompare(app.store, "status", "ready");
        compare(list().count, 1);
        verify(!notice.visible);
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
        compare(app.appMenu.count, 7);
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

    // --- layout --------------------------------------------------------

    // The device screens are tst_screens.qml's, once per profile; this is
    // a window narrower than any of them, where long names must still fit.
    function test_layout_data() {
        return [
            { tag: "320x480", w: 320, h: 480 }
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

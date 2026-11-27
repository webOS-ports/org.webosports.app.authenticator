/*
 * Copyright 2026 Herman van Hazendonk <github.com@herrie.org>
 * SPDX-License-Identifier: GPL-3.0-only
 *
 * The export's QR codes as tst_screens.qml saved them
 * (build/test-output/ui/<profile>-export-code.png and -export-codes.png),
 * read off the pictures with zbar (tests/read-qr.py) - as another phone's
 * camera would - and taken apart with Migration.js: the accounts and keys
 * tst_screens.qml seeded have to come back.
 *
 *     node tests/js/read-qr-shots.js
 *
 * Exits 77 when zbar or PIL is missing, and fails when there are no
 * pictures to read.
 */
"use strict";

const fs = require("fs");
const path = require("path");
const vm = require("vm");
const child = require("child_process");

const root = path.join(__dirname, "..", "..");
const shots = path.join(root, "build/test-output/ui");

function load(file) {
    const sandbox = {};
    vm.createContext(sandbox);
    const body = fs.readFileSync(file, "utf8").split("\n").map(function (line) {
        if (/^\.pragma\s+library/.test(line))
            return "";
        const m = /^\.import\s+"([^"]+)"\s+as\s+(\w+)/.exec(line);
        if (m) {
            sandbox[m[2]] = load(path.join(path.dirname(file), m[1]));
            return "";
        }
        return line;
    }).join("\n");
    vm.runInContext(body, sandbox, { filename: file });
    return sandbox;
}
const Migration = load(path.join(root, "qml/js/Migration.js"));

const rfcSecret = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ";
const otherSecret = "JBSWY3DPEHPK3PXP";
// What tst_screens.qml's seedAccounts() holds that fits into a code.
const one = [
    ["Example", "alice@example.com", rfcSecret, "totp", "SHA1", 6, 0],
    ["A very long site name that goes on and on", "someone.with.a.long.address@example.com", rfcSecret, "totp", "SHA1", 8, 0],
    ["Counter", "bob", otherSecret, "hotp", "SHA1", 6, 0],
    ["GitHub", "herrie", otherSecret, "totp", "SHA256", 6, 0]
];
// test_export_several_codes: the first code of 23 accounts.
function several(i) {
    return ["Site number " + i, "user" + i + "@example.com", i % 2 ? rfcSecret : otherSecret, "totp", "SHA1", 6, 0];
}

const files = fs.existsSync(shots) ? fs.readdirSync(shots).filter((f) => /-export-codes?\.png$/.test(f)).sort() : [];
if (files.length === 0) {
    console.log("FAIL qr: no export pictures in " + shots + "; run tst_screens.qml first");
    process.exit(1);
}
const run = child.spawnSync("python3", ["-I", path.join(root, "tests/read-qr.py")].concat(files.map((f) => path.join(shots, f))),
                            { encoding: "utf8" });
if (run.status === 77) {
    console.log("SKIP qr: " + run.stderr.trim() + "; the pictures were not read back");
    process.exit(77);
}
if (run.status !== 0) {
    console.log("FAIL qr: tests/read-qr.py: " + run.stderr);
    process.exit(1);
}
const results = run.stdout.trim().split("\n").map((l) => JSON.parse(l));

let passed = 0, failed = 0;
files.forEach(function (file, i) {
    const texts = results[i];
    const what = (t) => file + ": " + t;
    if (texts.length !== 1) {
        failed++;
        console.log("FAIL " + what("zbar found " + texts.length + " codes"));
        return;
    }
    const parsed = Migration.parse(texts[0]);
    if (parsed.error) {
        failed++;
        console.log("FAIL " + what(parsed.error));
        return;
    }
    const got = parsed.entries.map(function (e) {
        const a = e.account;
        return [a.issuer, a.label, a.secret, a.type, a.algorithm, a.digits, a.counter];
    });
    const want = /-export-code\.png$/.test(file) ? one : got.map((_, n) => several(n));
    const severalOk = /-export-codes\.png$/.test(file) ? parsed.batchIndex === 0 && parsed.batchSize > 1 : true;
    if (JSON.stringify(got) === JSON.stringify(want) && severalOk && got.length > 0) {
        passed++;
    } else {
        failed++;
        console.log("FAIL " + what("got " + JSON.stringify(got) + " (code " + parsed.batchIndex + " of " + parsed.batchSize
                                   + "), expected " + JSON.stringify(want)));
    }
});
console.log((failed === 0 ? "PASS" : "FAIL") + " qr: " + passed + " pictures read back, " + failed + " failed");
process.exit(failed === 0 ? 0 : 1);

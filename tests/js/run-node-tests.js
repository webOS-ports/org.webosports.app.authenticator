/*
 * Copyright 2026 Herman van Hazendonk <github.com@herrie.org>
 * SPDX-License-Identifier: GPL-3.0-only
 *
 * The app's JavaScript (qml/js) under Node, as a second engine next to
 * QML's: the published vectors (vectors.js), each vector also recomputed
 * with Node's crypto (OpenSSL), and random inputs compared against OpenSSL
 * - every length from 0 to 300 bytes, which crosses each padding boundary
 * of both block sizes, and random keys, counters and times. The export
 * format (Migration.js): the sample link of the otpauth tools that read
 * Google Authenticator's exports, base64 and UTF-8 against Node's own,
 * and round trips of random accounts.
 *
 *     node tests/js/run-node-tests.js
 *
 * The files are QML JavaScript libraries (".pragma library", ".import");
 * load() reads them into a sandbox the way QML would.
 */
"use strict";

const fs = require("fs");
const path = require("path");
const vm = require("vm");
const crypto = require("crypto");

const root = path.join(__dirname, "..", "..");
const cache = {};

function load(file) {
    const full = path.resolve(file);
    if (cache[full])
        return cache[full];
    const sandbox = {};
    vm.createContext(sandbox);
    cache[full] = sandbox;
    const lines = fs.readFileSync(full, "utf8").split("\n");
    const body = lines.map(function (line) {
        if (/^\.pragma\s+library/.test(line))
            return "";
        const m = /^\.import\s+"([^"]+)"\s+as\s+(\w+)/.exec(line);
        if (m) {
            sandbox[m[2]] = load(path.join(path.dirname(full), m[1]));
            return "";
        }
        return line;
    }).join("\n");
    vm.runInContext(body, sandbox, { filename: full });
    return sandbox;
}

const Sha = load(path.join(root, "qml/js/Sha.js"));
const Base32 = load(path.join(root, "qml/js/Base32.js"));
const Otp = load(path.join(root, "qml/js/Otp.js"));
const Uri = load(path.join(root, "qml/js/OtpAuthUri.js"));
const Accounts = load(path.join(root, "qml/js/Accounts.js"));
const Migration = load(path.join(root, "qml/js/Migration.js"));
const V = load(path.join(__dirname, "vectors.js"));

let passed = 0, failed = 0;
function check(ok, what) {
    if (ok) {
        passed++;
    } else {
        failed++;
        console.log("FAIL " + what);
    }
}
function eq(actual, expected, what) {
    const a = JSON.stringify(actual), e = JSON.stringify(expected);
    check(a === e, what + ": got " + a + ", expected " + e);
}

const nodeAlg = { SHA1: "sha1", SHA256: "sha256", SHA512: "sha512" };
const bytes = (s) => Array.from(Buffer.from(s, "utf8"));
const asciiBytes = (s) => Array.from(Buffer.from(s, "latin1"));

// Published hashes, and OpenSSL agreeing with the vector itself.
V.hashes.forEach(function (v) {
    eq(Sha.toHex(Sha.hash(v.alg, bytes(v.text))), v.hex, v.alg + "(" + JSON.stringify(v.text) + ")");
    eq(crypto.createHash(nodeAlg[v.alg]).update(v.text).digest("hex"), v.hex, "vector " + v.alg + " vs OpenSSL");
});

V.hmacs.forEach(function (v, i) {
    const key = v.keyHex !== undefined ? Sha.fromHex(v.keyHex) : bytes(v.keyText);
    eq(Sha.toHex(Sha.hmac(v.alg, key, bytes(v.text))), v.hex, "HMAC-" + v.alg + " case " + i);
    eq(crypto.createHmac(nodeAlg[v.alg], Buffer.from(key)).update(v.text).digest("hex"), v.hex,
       "vector HMAC-" + v.alg + " case " + i + " vs OpenSSL");
});

// One million "a": the long FIPS example, many blocks.
const million = new Array(1000000).fill(0x61);
["SHA1", "SHA256", "SHA512"].forEach(function (alg) {
    eq(Sha.toHex(Sha.hash(alg, million)),
       crypto.createHash(nodeAlg[alg]).update(Buffer.from(million)).digest("hex"), alg + "(a x 10^6)");
});

// Every length across the padding boundaries, against OpenSSL.
for (let n = 0; n <= 300; n++) {
    const data = crypto.randomBytes(n);
    ["SHA1", "SHA256", "SHA512"].forEach(function (alg) {
        const ours = Sha.toHex(Sha.hash(alg, Array.from(data)));
        const theirs = crypto.createHash(nodeAlg[alg]).update(data).digest("hex");
        check(ours === theirs, alg + " of " + n + " random bytes " + data.toString("hex"));
    });
}

// HMAC with keys shorter, equal to and longer than the block.
for (let i = 0; i < 300; i++) {
    const key = crypto.randomBytes(i % 200);
    const msg = crypto.randomBytes((i * 7) % 150);
    ["SHA1", "SHA256", "SHA512"].forEach(function (alg) {
        const ours = Sha.toHex(Sha.hmac(alg, Array.from(key), Array.from(msg)));
        const theirs = crypto.createHmac(nodeAlg[alg], key).update(msg).digest("hex");
        check(ours === theirs, "HMAC-" + alg + " key " + key.toString("hex") + " msg " + msg.toString("hex"));
    });
}

// RFC 4226 and RFC 6238.
V.hotp.forEach(function (code, counter) {
    eq(Otp.hotp(asciiBytes(V.hotpSecret), counter, 6, "SHA1"), code, "HOTP counter " + counter);
});
V.totp.forEach(function (row) {
    ["SHA1", "SHA256", "SHA512"].forEach(function (alg) {
        eq(Otp.totp(asciiBytes(V.totpSeeds[alg]), row.time * 1000, 30, 8, alg), row[alg],
           "TOTP " + alg + " at " + row.time);
    });
});

// The truncation against a reference written from RFC 4226 5.3 with OpenSSL.
function refHotp(alg, key, counter, digits) {
    const msg = Buffer.alloc(8);
    msg.writeBigUInt64BE(BigInt(counter));
    const mac = crypto.createHmac(nodeAlg[alg], key).update(msg).digest();
    const off = mac[mac.length - 1] & 15;
    const bin = mac.readUInt32BE(off) & 0x7fffffff;
    return String(bin % Math.pow(10, digits)).padStart(digits, "0");
}
for (let i = 0; i < 500; i++) {
    const key = crypto.randomBytes(10 + (i % 60));
    const counter = i < 250 ? i : Math.floor(Math.random() * Number.MAX_SAFE_INTEGER);
    const digits = 6 + (i % 3);
    ["SHA1", "SHA256", "SHA512"].forEach(function (alg) {
        eq(Otp.hotp(Array.from(key), counter, digits, alg), refHotp(alg, key, counter, digits),
           "HOTP-" + alg + " counter " + counter + " key " + key.toString("hex"));
    });
}

eq(Otp.secondsLeft(0, 30), 30, "secondsLeft at a boundary");
eq(Otp.secondsLeft(29999, 30), 1, "secondsLeft just before");
eq(Otp.secondsLeft(59000, 60), 1, "secondsLeft, 60 s period");
eq(Otp.timeStep(59999, 30), 1, "timeStep");
eq(Otp.format("123456"), "123 456", "format 6");
eq(Otp.format("1234567"), "123 4567", "format 7");
eq(Otp.format("12345678"), "1234 5678", "format 8");
eq(Otp.counterBytes(0x0102030405), [0, 0, 0, 1, 2, 3, 4, 5], "counterBytes");

// Base32.
V.base32.forEach(function (v) {
    eq(Base32.encode(asciiBytes(v.text)), v.b32, "encode " + v.text);
    eq(Base32.decode(v.b32), asciiBytes(v.text), "decode " + v.b32);
});
for (let i = 0; i < 200; i++) {
    const data = Array.from(crypto.randomBytes(i % 70));
    eq(Base32.decode(Base32.encode(data)), data, "round trip " + data.length);
}
eq(Base32.decode("mzxw 6ytb-oi======"), asciiBytes("foobar"), "spaces, dashes, case, padding");
eq(Base32.decode("MZXW6YTB0I"), null, "0 is not Base32");
eq(Base32.decode("MZXW6YTBO"), null, "a left-over character");
eq(Base32.problem("JBSWY3DPEHPK3PXP"), "", "a 16-character key");
eq(Base32.problem("jbsw y3dp ehpk 3pxp"), "", "typed in groups");
check(Base32.problem("") !== "", "empty key refused");
check(/letter O/.test(Base32.problem("JBSWY3DPEHPK3PX0")), "0 hints at O");
check(/too short/.test(Base32.problem("JBSWY3DPEHPK3P")), "14 characters too short");
check(/too short or too long/.test(Base32.problem("JBSWY3DPEHPK3PXPA")), "17 characters");
check(/digits 2 to 7/.test(Base32.problem("JBSWY3DPEHPK3PX!")), "punctuation");

// otpauth://
let r = Uri.parse("otpauth://totp/Example:alice@example.com?secret=JBSWY3DPEHPK3PXP&issuer=Example");
eq(r.account, { type: "totp", issuer: "Example", label: "alice@example.com", secret: "JBSWY3DPEHPK3PXP",
                algorithm: "SHA1", digits: 6, period: 30, counter: 0 }, "the usual link");
r = Uri.parse("otpauth://totp/ACME%20Co:john.doe%40email.com?secret=HXDMVJECJJWSRB3HWIZR4IFUGFTMXBOZ&issuer=ACME%20Co&algorithm=SHA256&digits=8&period=60");
eq([r.account.issuer, r.account.label, r.account.algorithm, r.account.digits, r.account.period],
   ["ACME Co", "john.doe@email.com", "SHA256", 8, 60], "escaped label, SHA256, 8 digits, 60 s");
r = Uri.parse("otpauth://hotp/Lab?secret=jbsw%20y3dp%20ehpk%203pxp&counter=42&algorithm=sha512");
eq([r.account.type, r.account.issuer, r.account.label, r.account.secret, r.account.counter, r.account.algorithm],
   ["hotp", "", "Lab", "JBSWY3DPEHPK3PXP", 42, "SHA512"], "hotp with counter, lower case");
r = Uri.parse("otpauth://totp/Old:me?secret=JBSWY3DPEHPK3PXP&issuer=New");
eq(r.account.issuer, "New", "issuer parameter wins over the label's");
r = Uri.parse("  OTPAUTH://TOTP/%20Spaced%20:%20me%20?SECRET=JBSWY3DPEHPK3PXP");
eq([r.account.issuer, r.account.label], ["Spaced", "me"], "trimmed, upper-case scheme and keys");
check(/no key/.test(Uri.parse("otpauth://totp/x?issuer=y").error), "no secret");
check(/not usable/.test(Uri.parse("otpauth://totp/x?secret=ABC1").error), "bad secret");
check(/MD5/.test(Uri.parse("otpauth://totp/x?secret=JBSWY3DPEHPK3PXP&algorithm=MD5").error), "unknown algorithm");
check(/5-digit/.test(Uri.parse("otpauth://totp/x?secret=JBSWY3DPEHPK3PXP&digits=5").error), "5 digits");
check(/every 0 seconds/.test(Uri.parse("otpauth://totp/x?secret=JBSWY3DPEHPK3PXP&period=0").error), "period 0");
check(/not supported/.test(Uri.parse("otpauth://steam/x?secret=JBSWY3DPEHPK3PXP").error), "other types");
check(/not an otpauth/.test(Uri.parse("https://example.com").error), "not otpauth");
check(/garbled/.test(Uri.parse("otpauth://totp/%E0%A4%A?secret=JBSWY3DPEHPK3PXP").error), "bad escape");
eq(Uri.isOtpAuth(" otpauth://totp/x"), true, "isOtpAuth");
eq(Uri.isOtpAuth("http://x"), false, "isOtpAuth http");

// Accounts: the stored index and the checks before saving.
const fields = { type: "totp", issuer: " Example ", label: "alice ", secret: "jbsw y3dp ehpk 3pxp",
                 algorithm: "SHA1", digits: 6, period: 30, counter: 0 };
eq(Accounts.problems(fields), {}, "valid fields");
eq(Object.keys(Accounts.problems(Object.assign({}, fields, { secret: "" }))), ["secret"], "missing secret");
eq(Object.keys(Accounts.problems(Object.assign({}, fields, { issuer: "", label: "" }))), ["label"], "needs a name");
eq(Object.keys(Accounts.problems(Object.assign({}, fields, { period: 0 }))), ["period"], "period 0");
eq(Object.keys(Accounts.problems(Object.assign({}, fields, { type: "hotp", counter: -1 }))), ["counter"], "negative counter");
eq(Accounts.problems(Object.assign({}, fields, { secret: "" }), true), {}, "editing keeps the secret");
const meta = Accounts.metaFrom(fields, "abc");
eq(meta, { id: "abc", type: "totp", issuer: "Example", label: "alice", algorithm: "SHA1", digits: 6, period: 30, counter: 0 },
   "metaFrom trims and keeps no secret");
const index = Accounts.serializeIndex(7, [meta]);
eq(Accounts.parseIndex(index), { generation: 7, lock: false, face: false, accounts: [meta] }, "index round trip");
eq(JSON.parse(index).lock, undefined, "no lock key when off");
eq(Accounts.parseIndex(Accounts.serializeIndex(8, [meta], { lock: true })),
   { generation: 8, lock: true, face: false, accounts: [meta] }, "index round trip with the lock");
eq(Accounts.parseIndex(Accounts.serializeIndex(9, [meta], { lock: true, face: true })),
   { generation: 9, lock: true, face: true, accounts: [meta] }, "index round trip with the lock and face");
eq(JSON.parse(Accounts.serializeIndex(9, [meta], { face: true })).face, undefined, "no face without the lock");
eq(Accounts.parseIndex(JSON.stringify({ generation: 1, face: true, accounts: [] })).face, false,
   "a stored face without the lock does not count");
eq(Accounts.parseIndex(JSON.stringify({ generation: 1, lock: "yes", accounts: [] })).lock, false,
   "only true locks");
eq(Accounts.parseIndex("{nonsense"), null, "garbled index");
eq(Accounts.parseIndex(JSON.stringify({ generation: 1, accounts: [{ id: "x", type: "foo" }] })), null, "bad account in index");
eq(Accounts.newerIndex({ generation: 3 }, { generation: 4 }).generation, 4, "newer index wins");
eq(Accounts.newerIndex(null, { generation: 1 }).generation, 1, "one index");
eq(Accounts.newerIndex(null, null), null, "no index");
eq(Accounts.moved([1, 2, 3, 4], 0, 2), [2, 3, 1, 4], "move down");
eq(Accounts.moved([1, 2, 3, 4], 3, 0), [4, 1, 2, 3], "move up");
eq(Accounts.moved([1, 2], 0, 5), [1, 2], "move out of range");
eq(Accounts.title({ issuer: "Ex", label: "me" }), "Ex", "title is the issuer");
eq(Accounts.title({ issuer: "", label: "me" }), "me", "title falls back to the label");
eq(Accounts.subtitle({ issuer: "", label: "me" }), "", "no subtitle without issuer");
check(/^[0-9a-f]{16}$/.test(Accounts.newId()), "newId");
eq(Accounts.secretKeyName("abc"), "otp.secret.abc", "secret key name");
eq(Accounts.isDuplicate([{ id: "1", issuer: "Ex", label: "me" }], { issuer: "ex", label: "ME" }, "JBSW", { "1": "JBSW" }), true, "duplicate");
eq(Accounts.isDuplicate([{ id: "1", issuer: "Ex", label: "me" }], { issuer: "Ex", label: "me" }, "OTHER", { "1": "JBSW" }), false, "same name, other key");

// otpauth-migration://: Google Authenticator's export.
// The sample in the otpauth tools that read the format (dim13/otpauth):
// "Hello!" and 0xdeadbeef as the key, "Example:alice@google.com".
r = Migration.parse("otpauth-migration://offline?data=CjEKCkhlbGxvId6tvu8SGEV4YW1wbGU6YWxpY2VAZ29vZ2xlLmNvbRoHRXhhbXBsZTAC");
eq(r.entries, [{ account: { type: "totp", issuer: "Example", label: "alice@google.com", secret: "JBSWY3DPEHPK3PXP",
                            algorithm: "SHA1", digits: 6, period: 30, counter: 0 } }], "the published sample");
eq([r.batchIndex, r.batchSize], [0, 1], "one code");
eq(Migration.base64Encode(Migration.base64Decode("CjEKCkhlbGxvId6tvu8SGEV4YW1wbGU6YWxpY2VAZ29vZ2xlLmNvbRoHRXhhbXBsZTAC")),
   "CjEKCkhlbGxvId6tvu8SGEV4YW1wbGU6YWxpY2VAZ29vZ2xlLmNvbRoHRXhhbXBsZTAC", "base64 round trip of the sample");

for (let i = 0; i < 300; i++) {
    const data = Array.from(crypto.randomBytes(i % 90));
    const b64 = Buffer.from(data).toString("base64");
    eq(Migration.base64Encode(data), b64, "base64 of " + data.length + " bytes as Node's");
    eq(Migration.base64Decode(b64), data, "base64 back, " + data.length + " bytes");
    eq(Migration.base64Decode(b64.replace(/=+$/, "")), data, "base64 without padding");
    eq(Migration.base64Decode(Buffer.from(data).toString("base64url")), data, "URL-safe base64");
}
eq(Migration.base64Decode("abc!"), null, "not base64");
eq(Migration.base64Decode("abcde"), null, "a dangling base64 character");

const texts = ["", "plain", "Zürich", "日本語", "emoji 😀 and more 🎉", "\u00ff\u0100\u07ff\u0800\uffff", "a\u0000b"];
texts.forEach(function (t) {
    eq(Migration.utf8Encode(t), Array.from(Buffer.from(t, "utf8")), "UTF-8 of " + JSON.stringify(t) + " as Node's");
    eq(Migration.utf8Decode(Array.from(Buffer.from(t, "utf8"))), t, "UTF-8 back " + JSON.stringify(t));
});
for (let i = 0; i < 300; i++) {
    let t = "";
    for (let n = 0; n < 12; n++) {
        const cp = [0x41 + (i * 7 + n) % 50, 0xa0 + i * 13 + n, 0x900 + i * 31 + n, 0x1f300 + i + n][n % 4];
        t += String.fromCodePoint(cp);
    }
    eq(Migration.utf8Decode(Migration.utf8Encode(t)), t, "UTF-8 round trip " + i);
    eq(Migration.utf8Encode(t), Array.from(Buffer.from(t, "utf8")), "UTF-8 as Node's " + i);
}
eq(Migration.utf8Decode([0xc0, 0x80]), null, "overlong UTF-8");
eq(Migration.utf8Decode([0xe0, 0x80, 0xaf]), null, "overlong UTF-8 in three bytes");
eq(Migration.utf8Decode([0xf0, 0x80, 0x80, 0xaf]), null, "overlong UTF-8 in four bytes");
eq(Migration.utf8Decode([0xf4, 0x90, 0x80, 0x80]), null, "past U+10FFFF");
eq(Migration.utf8Decode([0xe2, 0x82]), null, "cut-off UTF-8");
eq(Migration.utf8Decode([0xed, 0xa0, 0x80]), null, "a surrogate in UTF-8");
eq(Migration.utf8Decode([0x80]), null, "a stray continuation byte");

// A payload built by hand, field by field.
function pb(fields) {
    const out = [];
    fields.forEach(function (f) {
        if (Array.isArray(f[1]))
            Migration.writeBytes(out, f[0], f[1]);
        else if (typeof f[1] === "string")
            Migration.writeBytes(out, f[0], bytes(f[1]));
        else
            Migration.writeNumber(out, f[0], f[1]);
    });
    return out;
}
function migrationLink(payload) {
    return "otpauth-migration://offline?data=" + encodeURIComponent(Buffer.from(payload).toString("base64"));
}
const key20 = asciiBytes("12345678901234567890");
r = Migration.parse(migrationLink(pb([
    [1, pb([[1, key20], [2, "Lab:bob"], [4, 3], [5, 2], [6, 1], [7, 2 ** 40 + 5]])],
    [1, pb([[1, key20], [2, "carol"], [3, "Mail"], [4, 2]])],
    [1, pb([[1, key20], [2, "old"], [4, 4]])],
    [1, pb([[1, [1, 2, 3]], [2, "short"]])],
    [1, pb([[1, key20], [2, "seven"], [5, 3]])],
    [1, pb([[2, "nokey"]])],
    [1, pb([[1, key20], [2, "steam"], [6, 7]])],
    [1, pb([[1, key20], [2, [0xff, 0xfe]]])],
    [1, pb([[1, key20]])],
    [2, 1], [3, 3], [4, 2], [5, 12345]])));
eq(r.entries[0].account, { type: "hotp", issuer: "Lab", label: "bob", secret: Base32.encode(key20), algorithm: "SHA512",
                           digits: 8, period: 30, counter: 2 ** 40 + 5 }, "HOTP, SHA-512, 8 digits, a 41-bit counter");
eq(r.entries[1].account, { type: "totp", issuer: "Mail", label: "carol", secret: Base32.encode(key20), algorithm: "SHA256",
                           digits: 6, period: 30, counter: 0 }, "type left out is time-based");
check(/MD5/.test(r.entries[2].problem) && r.entries[2].title === "old", "MD5 refused, by name");
check(/too short/.test(r.entries[3].problem), "a 3-byte key refused");
check(/digits/.test(r.entries[4].problem), "an unknown digit count refused");
check(/no key/.test(r.entries[5].problem), "no key");
check(/kind of code/.test(r.entries[6].problem), "an unknown type refused");
check(/garbled/.test(r.entries[7].problem), "a name that is not UTF-8");
check(/no name/.test(r.entries[8].problem), "no name");
eq([r.batchIndex, r.batchSize, r.batchId], [2, 3, 12345], "the batch fields");

r = Migration.parse(migrationLink(pb([[1, pb([[1, key20], [2, "Other:me"], [3, "Mine"]])]])));
eq([r.entries[0].account.issuer, r.entries[0].account.label], ["Mine", "Other:me"], "another site's prefix stays in the name");
r = Migration.parse(migrationLink(pb([[1, pb([[1, key20], [2, "mine: me "], [3, "Mine"]])]])));
eq([r.entries[0].account.issuer, r.entries[0].account.label], ["Mine", "me"], "the issuer's own prefix goes");
// Unknown fields, of every wire type, are passed over.
r = Migration.parse(migrationLink(pb([[1, pb([[1, key20], [2, "x"], [9, 4], [10, "more"]])], [7, 99]]).concat([0x5d, 1, 2, 3, 4, 0x61, 1, 2, 3, 4, 5, 6, 7, 8])));
eq(r.entries.length, 1, "unknown fields skipped");
eq(r.entries[0].account.label, "x", "unknown fields skipped, account kept");
// A "+" that became a space, and the base64 left unescaped.
let plain = "";
for (let n = 0; !/\+/.test(plain) && n < 1000; n++)
    plain = Buffer.from(pb([[1, pb([[1, Array.from(crypto.randomBytes(20))], [2, "x"]])]])).toString("base64");
check(/\+/.test(plain), "the test data has a + in it");
eq(Migration.parse("otpauth-migration://offline?data=" + plain.replace(/\+/g, " ")).entries[0].account.label, "x", "a + as a space");
eq(Migration.parse("OTPAUTH-MIGRATION://offline?data=" + plain).entries[0].account.label, "x", "unescaped, upper-case scheme");
// Batch fields out of range do not count.
r = Migration.parse(migrationLink(pb([[1, pb([[1, key20], [2, "x"]])], [3, 2], [4, 5]])));
eq([r.batchIndex, r.batchSize], [0, 2], "an index past the size");

check(/no accounts/.test(Migration.parse("otpauth-migration://offline?data=").error), "no data");
check(/no accounts/.test(Migration.parse("otpauth-migration://offline?x=1").error), "no data parameter");
check(/no accounts/.test(Migration.parse(migrationLink(pb([[2, 1]]))).error), "no accounts");
check(/garbled/.test(Migration.parse("otpauth-migration://offline?data=%E0%A4%A").error), "bad escape");
check(/garbled/.test(Migration.parse("otpauth-migration://offline?data=!!!!").error), "not base64");
check(/garbled/.test(Migration.parse(migrationLink([0x0a, 0x20, 1, 2])).error), "a field longer than the data");
check(/garbled/.test(Migration.parse(migrationLink([0x0b, 0])).error), "wire type 3");
check(/garbled/.test(Migration.parse(migrationLink([0x08, 0xff])).error), "a cut-off varint");
check(/garbled/.test(Migration.parse(migrationLink([0x08].concat(new Array(11).fill(0xff)))).error), "an endless varint");
check(/not an otpauth-migration/.test(Migration.parse("otpauth://totp/x?secret=JBSWY3DPEHPK3PXP").error), "otpauth:// is not one");
eq(Migration.isMigration(" otpauth-migration://offline?data=x"), true, "isMigration");
eq(Migration.isMigration("otpauth://totp/x"), false, "isMigration otpauth");
// Every cut of a good payload is refused or read, never thrown on.
const whole = pb([[1, pb([[1, key20], [2, "Lab:bob"], [3, "Lab"], [6, 1], [7, 300]])], [3, 1]]);
let cuts = 0;
for (let n = 0; n < whole.length; n++) {
    try {
        Migration.parse(migrationLink(whole.slice(0, n)));
        cuts++;
    } catch (e) {
        check(false, "cut at " + n + " threw " + e);
    }
}
eq(cuts, whole.length, "every cut handled");

// Our export, read back: random accounts in every shape that fits.
const exported = [];
const exportedKeys = {};
for (let i = 0; i < 37; i++) {
    const a = { id: "x" + i, type: i % 5 === 0 ? "hotp" : "totp", issuer: i % 3 === 0 ? "" : "Site " + i + " Zürich",
                label: "user" + i + "@example.com", algorithm: ["SHA1", "SHA256", "SHA512"][i % 3],
                digits: i % 2 ? 8 : 6, period: 30, counter: i % 5 === 0 ? i * 1000003 : 0 };
    exported.push(a);
    exportedKeys[a.id] = Array.from(crypto.randomBytes(10 + (i % 4) * 11));
}
exported.push({ id: "p60", type: "totp", issuer: "Slow", label: "x", algorithm: "SHA1", digits: 6, period: 60, counter: 0 });
exported.push({ id: "d7", type: "totp", issuer: "Seven", label: "x", algorithm: "SHA1", digits: 7, period: 30, counter: 0 });
exported.push({ id: "gone", type: "totp", issuer: "Gone", label: "x", algorithm: "SHA1", digits: 6, period: 30, counter: 0 });
exportedKeys.p60 = key20;
exportedKeys.d7 = key20;
const out = Migration.compose(exported, (a) => exportedKeys[a.id], 777);
eq(out.left.map((l) => l.account.id), ["p60", "d7", "gone"], "60 s, 7 digits and a missing key left out");
check(/60 seconds/.test(out.left[0].reason) && /7 digits/.test(out.left[1].reason) && /missing/.test(out.left[2].reason),
      "and why");
check(out.links.length >= 4, "37 accounts in several codes: " + out.links.length);
let back = [];
out.links.forEach(function (l, index) {
    check(l.link.length <= Migration.MAX_LINK_LENGTH || l.accounts.length === 1,
          "code " + index + " is " + l.link.length + " characters");
    check(l.accounts.length <= Migration.MAX_PER_CODE, "code " + index + " holds " + l.accounts.length);
    check(/^otpauth-migration:\/\/offline\?data=[A-Za-z0-9%]+$/.test(l.link), "code " + index + " is escaped");
    const p = Migration.parse(l.link);
    eq([p.batchIndex, p.batchSize, p.batchId], [index, out.links.length, 777], "code " + index + "'s batch fields");
    eq(p.entries.length, l.accounts.length, "code " + index + " holds what it says");
    back = back.concat(p.entries.map((e) => e.account));
});
eq(back.length, 37, "every account read back");
back.forEach(function (b, i) {
    const a = exported[i];
    eq(b, { type: a.type, issuer: a.issuer, label: a.label, secret: Base32.encode(exportedKeys[a.id]),
            algorithm: a.algorithm, digits: a.digits, period: 30, counter: a.counter }, "account " + i + " back");
});
// A name without a site goes as the name; a site without a name as the name too.
r = Migration.parse(Migration.compose([{ id: "s", type: "totp", issuer: "OnlySite", label: "", algorithm: "SHA1",
                                         digits: 6, period: 30, counter: 0 }], () => key20, 1).links[0].link);
eq([r.entries[0].account.issuer, r.entries[0].account.label], ["OnlySite", "OnlySite"], "a site without a name");
// One very long account still goes, in a code of its own.
const long = { id: "l", type: "totp", issuer: "L".repeat(300), label: "n".repeat(300), algorithm: "SHA1", digits: 6,
               period: 30, counter: 0 };
const lo = Migration.compose([long, exported[1]], (a) => a.id === "l" ? key20 : exportedKeys[a.id], 1);
eq(lo.links.map((l) => l.accounts.length), [1, 1], "a long account in a code of its own");
eq(Migration.compose([], () => key20).links, [], "nothing to export");
// Small accounts: the length would let more in, the count does not.
const tiny = [];
for (let i = 0; i < 25; i++)
    tiny.push({ id: "t" + i, type: "totp", issuer: "", label: "t" + i, algorithm: "SHA1", digits: 6, period: 30, counter: 0 });
const tinyOut = Migration.compose(tiny, () => key20.slice(0, 10), 1);
eq(tinyOut.links.map((l) => l.accounts.length), [10, 10, 5], "at most 10 accounts in a code");
check(Migration.link(tiny.slice(0, 11).map((a) => Migration.accountBytes(a, key20.slice(0, 10))), 1000, 1000, 1).length
      <= Migration.MAX_LINK_LENGTH, "and not for the length: 11 would fit");
check(Migration.compose(exported.slice(0, 1), (a) => exportedKeys[a.id]).links[0].link !==
      Migration.compose(exported.slice(0, 1), (a) => exportedKeys[a.id]).links[0].link, "a new batch id each export");

console.log((failed === 0 ? "PASS" : "FAIL") + " node: " + passed + " passed, " + failed + " failed");
process.exit(failed === 0 ? 0 : 1);

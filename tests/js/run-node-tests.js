/*
 * Copyright 2026 Herman van Hazendonk <github.com@herrie.org>
 * SPDX-License-Identifier: GPL-3.0-only
 *
 * The app's JavaScript (qml/js) under Node, as a second engine next to
 * QML's: the published vectors (vectors.js), each vector also recomputed
 * with Node's crypto (OpenSSL), and random inputs compared against OpenSSL
 * - every length from 0 to 300 bytes, which crosses each padding boundary
 * of both block sizes, and random keys, counters and times.
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
eq(Accounts.parseIndex(index), { generation: 7, accounts: [meta] }, "index round trip");
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

console.log((failed === 0 ? "PASS" : "FAIL") + " node: " + passed + " passed, " + failed + " failed");
process.exit(failed === 0 ? 0 : 1);

.pragma library
.import "Base32.js" as Base32
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

/*
 * otpauth-migration:// links, what Google Authenticator's "Transfer
 * accounts" QR codes hold - several accounts in one code:
 *
 *     otpauth-migration://offline?data=<base64, URL-escaped>
 *
 * The data is a protocol buffer, MigrationPayload:
 *
 *     message MigrationPayload {
 *       repeated OtpParameters otp_parameters = 1;
 *       int32 version = 2;      // 1
 *       int32 batch_size = 3;   // how many codes the export is
 *       int32 batch_index = 4;  // which of them this is, from 0
 *       int32 batch_id = 5;     // the same in each code of one export
 *     }
 *     message OtpParameters {
 *       bytes secret = 1;       // the key's bytes, not Base32
 *       string name = 2;        // the account, sometimes "issuer:account"
 *       string issuer = 3;
 *       Algorithm algorithm = 4;  // 0 unset, 1 SHA1, 2 SHA256, 3 SHA512, 4 MD5
 *       DigitCount digits = 5;    // 0 unset, 1 six, 2 eight
 *       OtpType type = 6;         // 0 unset, 1 HOTP, 2 TOTP
 *       int64 counter = 7;
 *     }
 *
 * There is no period: every time-based code in it changes every 30
 * seconds, and there are no 7-digit codes. Accounts that are not like that
 * cannot go into one (see compose).
 */

var SCHEME = "otpauth-migration://";

// Accounts in one code and the longest link: a code of about 100 modules
// a side (version 20 at error correction M), which a phone's camera reads
// off another phone's screen. Google's own codes hold up to 10 accounts.
var MAX_PER_CODE = 10;
var MAX_LINK_LENGTH = 600;

var ALGORITHMS = { 0: "SHA1", 1: "SHA1", 2: "SHA256", 3: "SHA512" };
var ALGORITHM_NUMBERS = { "SHA1": 1, "SHA256": 2, "SHA512": 3 };

function isMigration(text) {
    return /^\s*otpauth-migration:\/\//i.test(String(text));
}

// --- base64 -------------------------------------------------------------

var B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

// Bytes from base64, the URL-safe alphabet and missing padding taken too;
// null when it is not base64.
function base64Decode(text) {
    var s = String(text).replace(/=+$/, "").replace(/-/g, "+").replace(/_/g, "/");
    if (s.length % 4 === 1)
        return null;
    var out = [];
    var buffer = 0, bits = 0;
    for (var i = 0; i < s.length; i++) {
        var v = B64.indexOf(s.charAt(i));
        if (v < 0)
            return null;
        buffer = ((buffer << 6) | v) & 0xffffff;
        bits += 6;
        if (bits >= 8) {
            bits -= 8;
            out.push((buffer >>> bits) & 0xff);
        }
    }
    return out;
}

function base64Encode(bytes) {
    var out = "";
    for (var i = 0; i < bytes.length; i += 3) {
        var n = (bytes[i] << 16) | ((i + 1 < bytes.length ? bytes[i + 1] : 0) << 8)
                | (i + 2 < bytes.length ? bytes[i + 2] : 0);
        out += B64.charAt((n >>> 18) & 63) + B64.charAt((n >>> 12) & 63)
                + (i + 1 < bytes.length ? B64.charAt((n >>> 6) & 63) : "=")
                + (i + 2 < bytes.length ? B64.charAt(n & 63) : "=");
    }
    return out;
}

// --- UTF-8 --------------------------------------------------------------

// A string from UTF-8 bytes, or null when they are not UTF-8.
function utf8Decode(bytes) {
    var out = "";
    for (var i = 0; i < bytes.length; ) {
        var b = bytes[i];
        var need, cp, min;
        if (b < 0x80) {
            out += String.fromCharCode(b);
            i++;
            continue;
        } else if (b >= 0xc2 && b <= 0xdf) {
            need = 1; cp = b & 0x1f; min = 0x80;
        } else if (b >= 0xe0 && b <= 0xef) {
            need = 2; cp = b & 0x0f; min = 0x800;
        } else if (b >= 0xf0 && b <= 0xf4) {
            need = 3; cp = b & 0x07; min = 0x10000;
        } else {
            return null;
        }
        if (i + need >= bytes.length)
            return null;
        for (var k = 1; k <= need; k++) {
            var c = bytes[i + k];
            if (c === undefined || (c & 0xc0) !== 0x80)
                return null;
            cp = cp * 64 + (c & 0x3f);
        }
        if (cp < min || cp > 0x10ffff || (cp >= 0xd800 && cp <= 0xdfff))
            return null;
        if (cp >= 0x10000) {
            cp -= 0x10000;
            out += String.fromCharCode(0xd800 + (cp >> 10), 0xdc00 + (cp & 0x3ff));
        } else {
            out += String.fromCharCode(cp);
        }
        i += need + 1;
    }
    return out;
}

// UTF-8 bytes of a string; a lone surrogate becomes U+FFFD.
function utf8Encode(text) {
    var s = String(text);
    var out = [];
    for (var i = 0; i < s.length; i++) {
        var cp = s.charCodeAt(i);
        if (cp >= 0xd800 && cp <= 0xdbff && i + 1 < s.length) {
            var lo = s.charCodeAt(i + 1);
            if (lo >= 0xdc00 && lo <= 0xdfff) {
                cp = 0x10000 + ((cp - 0xd800) << 10) + (lo - 0xdc00);
                i++;
            }
        }
        if (cp >= 0xd800 && cp <= 0xdfff)
            cp = 0xfffd;
        if (cp < 0x80) {
            out.push(cp);
        } else if (cp < 0x800) {
            out.push(0xc0 | (cp >> 6), 0x80 | (cp & 63));
        } else if (cp < 0x10000) {
            out.push(0xe0 | (cp >> 12), 0x80 | ((cp >> 6) & 63), 0x80 | (cp & 63));
        } else {
            out.push(0xf0 | (cp >> 18), 0x80 | ((cp >> 12) & 63), 0x80 | ((cp >> 6) & 63), 0x80 | (cp & 63));
        }
    }
    return out;
}

// --- protocol buffers ---------------------------------------------------

/*
 * The fields of a message: [{ number, wire, value }], value a number for a
 * varint (exact up to 2^53, larger ones only roughly) and the bytes for a
 * length-delimited field; fixed 32- and 64-bit fields are skipped. null
 * when the bytes run out or hold a wire type that does not exist.
 */
function readFields(bytes, start, end) {
    var fields = [];
    var pos = start;

    function varint() {
        var value = 0, scale = 1;
        for (var n = 0; n < 10; n++) {
            if (pos >= end)
                return -1;
            var b = bytes[pos++];
            value += (b & 0x7f) * scale;
            scale *= 128;
            if ((b & 0x80) === 0)
                return value;
        }
        return -1;
    }

    while (pos < end) {
        var key = varint();
        if (key < 0)
            return null;
        var number = Math.floor(key / 8);
        var wire = key % 8;
        if (number === 0)
            return null;
        if (wire === 0) {
            var v = varint();
            if (v < 0)
                return null;
            fields.push({ number: number, wire: 0, value: v });
        } else if (wire === 2) {
            var length = varint();
            if (length < 0 || length > end - pos)
                return null;
            fields.push({ number: number, wire: 2, value: bytes.slice(pos, pos + length) });
            pos += length;
        } else if (wire === 1 || wire === 5) {
            var size = wire === 1 ? 8 : 4;
            if (end - pos < size)
                return null;
            pos += size;
        } else {
            return null;
        }
    }
    return fields;
}

function writeVarint(out, value) {
    var v = value;
    while (v >= 128) {
        out.push((v % 128) | 0x80);
        v = Math.floor(v / 128);
    }
    out.push(v);
}

function writeKey(out, number, wire) {
    writeVarint(out, number * 8 + wire);
}

function writeBytes(out, number, bytes) {
    writeKey(out, number, 2);
    writeVarint(out, bytes.length);
    for (var i = 0; i < bytes.length; i++)
        out.push(bytes[i]);
}

function writeNumber(out, number, value) {
    writeKey(out, number, 0);
    writeVarint(out, value);
}

// --- reading ------------------------------------------------------------

function title(issuer, label) {
    return issuer !== "" ? issuer : label;
}

/*
 * One OtpParameters as { account: {...} } in OtpAuthUri.parse's shape, or
 * { problem: "...", title: "..." } for one that cannot be added, in words
 * for the user.
 */
function readAccount(bytes) {
    var fields = readFields(bytes, 0, bytes.length);
    if (fields === null)
        return { problem: "This account is garbled.", title: "" };
    var secret = [], name = "", issuer = "";
    var algorithm = 0, digits = 0, type = 0, counter = 0;
    var garbled = false;
    for (var i = 0; i < fields.length; i++) {
        var f = fields[i];
        var text;
        if (f.wire === 2 && f.number === 1) {
            secret = f.value;
        } else if (f.wire === 2 && (f.number === 2 || f.number === 3)) {
            text = utf8Decode(f.value);
            if (text === null)
                garbled = true;
            else if (f.number === 2)
                name = text;
            else
                issuer = text;
        } else if (f.wire === 0 && f.number === 4) {
            algorithm = f.value;
        } else if (f.wire === 0 && f.number === 5) {
            digits = f.value;
        } else if (f.wire === 0 && f.number === 6) {
            type = f.value;
        } else if (f.wire === 0 && f.number === 7) {
            counter = f.value;
        }
    }

    issuer = issuer.trim();
    var label = name;
    // "issuer:account" in the name, as an otpauth:// label has it.
    var colon = label.indexOf(":");
    if (colon >= 0) {
        var prefix = label.substr(0, colon).trim();
        if (issuer === "" || prefix.toLowerCase() === issuer.toLowerCase()) {
            if (issuer === "")
                issuer = prefix;
            label = label.substr(colon + 1);
        }
    }
    label = label.trim();
    var shown = title(issuer, label);

    if (garbled)
        return { problem: "Its name is garbled.", title: shown };
    if (type !== 0 && type !== 1 && type !== 2)
        return { problem: "Its kind of code is not supported, only time- and counter-based ones.", title: shown };
    if (ALGORITHMS[algorithm] === undefined)
        return { problem: algorithm === 4 ? "It uses MD5, which is not supported."
                                          : "It uses an algorithm that is not supported.", title: shown };
    if (digits !== 0 && digits !== 1 && digits !== 2)
        return { problem: "Its codes have a number of digits that is not supported.", title: shown };
    if (type === 1 && counter > 9007199254740991)
        return { problem: "Its counter is too large.", title: shown };
    var key = Base32.encode(secret);
    var keyProblem = Base32.problem(key);
    if (secret.length === 0)
        return { problem: "It has no key.", title: shown };
    if (keyProblem !== "")
        return { problem: "Its key is not usable. " + keyProblem, title: shown };
    if (shown === "")
        return { problem: "It has no name.", title: "" };

    return {
        account: {
            type: type === 1 ? "hotp" : "totp",
            issuer: issuer,
            label: label,
            secret: key,
            algorithm: ALGORITHMS[algorithm],
            digits: digits === 2 ? 8 : 6,
            period: 30,
            counter: type === 1 ? counter : 0
        }
    };
}

/*
 * { entries: [ { account } or { problem, title } ], batchIndex,
 *   batchSize, batchId }, batchIndex from 0 and batchSize at least 1; or
 * { error: "..." } in words for the user.
 */
function parse(text) {
    var s = String(text).trim();
    var m = /^otpauth-migration:\/\/([^\/?#]*)\/?\?([^#]*)/i.exec(s);
    if (!m)
        return { error: "This is not an otpauth-migration:// link." };
    var data = null;
    var pairs = m[2].split("&");
    for (var i = 0; i < pairs.length && data === null; i++) {
        var eq = pairs[i].indexOf("=");
        if (eq >= 0 && pairs[i].substr(0, eq).toLowerCase() === "data")
            data = pairs[i].substr(eq + 1);
    }
    if (data === null || data === "")
        return { error: "The export has no accounts in it." };
    try {
        data = decodeURIComponent(data);
    } catch (e) {
        return { error: "The export is garbled." };
    }
    // A "+" left unescaped may have become a space on the way.
    var bytes = base64Decode(data.replace(/ /g, "+"));
    if (bytes === null)
        return { error: "The export is garbled." };
    var fields = readFields(bytes, 0, bytes.length);
    if (fields === null)
        return { error: "The export is garbled." };

    var entries = [];
    var batchSize = 1, batchIndex = 0, batchId = 0;
    for (i = 0; i < fields.length; i++) {
        var f = fields[i];
        if (f.number === 1 && f.wire === 2)
            entries.push(readAccount(f.value));
        else if (f.number === 3 && f.wire === 0)
            batchSize = f.value;
        else if (f.number === 4 && f.wire === 0)
            batchIndex = f.value;
        else if (f.number === 5 && f.wire === 0)
            batchId = f.value;
    }
    if (entries.length === 0)
        return { error: "The export has no accounts in it." };
    if (!(batchSize >= 1 && batchSize <= 1000))
        batchSize = 1;
    if (!(batchIndex >= 0 && batchIndex < batchSize))
        batchIndex = 0;
    return { entries: entries, batchIndex: batchIndex, batchSize: batchSize, batchId: batchId };
}

// --- writing ------------------------------------------------------------

// Why an account cannot go into a code, or "" when it can.
function unexportable(account) {
    if (account.digits !== 6 && account.digits !== 8)
        return "Codes of " + account.digits + " digits cannot be exported.";
    if (account.type === "totp" && account.period !== 30)
        return "Codes that change every " + account.period + " seconds cannot be exported.";
    if (ALGORITHM_NUMBERS[account.algorithm] === undefined)
        return "Its algorithm cannot be exported.";
    return "";
}

function accountBytes(account, secret) {
    var out = [];
    writeBytes(out, 1, secret);
    var name = account.label !== "" ? account.label : account.issuer;
    writeBytes(out, 2, utf8Encode(name));
    if (account.issuer !== "")
        writeBytes(out, 3, utf8Encode(account.issuer));
    writeNumber(out, 4, ALGORITHM_NUMBERS[account.algorithm]);
    writeNumber(out, 5, account.digits === 8 ? 2 : 1);
    writeNumber(out, 6, account.type === "hotp" ? 1 : 2);
    if (account.type === "hotp")
        writeNumber(out, 7, account.counter);
    return out;
}

function link(parts, batchSize, batchIndex, batchId) {
    var out = [];
    for (var i = 0; i < parts.length; i++)
        writeBytes(out, 1, parts[i]);
    writeNumber(out, 2, 1);
    writeNumber(out, 3, batchSize);
    writeNumber(out, 4, batchIndex);
    writeNumber(out, 5, batchId);
    return SCHEME + "offline?data=" + encodeURIComponent(base64Encode(out));
}

/*
 * The codes for accounts (stored ones, without their secrets) as links,
 * a few accounts in each: { links: [ { link, accounts } ], left: [ {
 * account, reason } ] }, left for those that cannot go into one.
 * secretOf(account) gives an account's key as bytes. batchId is the same
 * in each code of one export, random when left out.
 */
function compose(accounts, secretOf, batchId) {
    var id = batchId !== undefined ? batchId : 1 + Math.floor(Math.random() * 0x7ffffffe);
    var left = [];
    var groups = [];
    var group = [];
    var groupAccounts = [];
    for (var i = 0; i < accounts.length; i++) {
        var a = accounts[i];
        var reason = unexportable(a);
        var secret = reason === "" ? secretOf(a) : null;
        if (reason === "" && (!secret || secret.length === 0))
            reason = "Its key is missing.";
        if (reason !== "") {
            left.push({ account: a, reason: reason });
            continue;
        }
        var part = accountBytes(a, secret);
        // The batch fields take the most room with the largest numbers.
        if (group.length > 0 && (group.length >= MAX_PER_CODE
                                 || link(group.concat([part]), 1000, 1000, id).length > MAX_LINK_LENGTH)) {
            groups.push({ parts: group, accounts: groupAccounts });
            group = [];
            groupAccounts = [];
        }
        group.push(part);
        groupAccounts.push(a);
    }
    if (group.length > 0)
        groups.push({ parts: group, accounts: groupAccounts });
    var links = groups.map(function(g, index) {
        return { link: link(g.parts, groups.length, index, id), accounts: g.accounts };
    });
    return { links: links, left: left };
}

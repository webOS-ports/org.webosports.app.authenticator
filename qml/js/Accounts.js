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
 * Accounts as the app keeps them. Each has its secret in the key manager
 * under its own name (secretKeyName), written once and never changed, and
 * everything else - issuer, name, algorithm, digits, period, counter and
 * the order - in an index, also in the key manager:
 *
 *     { "generation": 7, "lock": true, "face": true, "accounts": [ { "id",
 *       "type", "issuer", "label", "algorithm", "digits", "period",
 *       "counter" }, ... ] }
 *
 * "lock" says the app asks for a fingerprint or the device passcode before
 * it reads the secrets; "face" that a face opens it too, which counts only
 * with "lock". Each is left out when off.
 *
 * The key manager will not overwrite a key, so the index goes in turn to
 * one of two keys (INDEX_KEYS); the higher generation is the current one,
 * and the other is the one before it, there if a write goes wrong half way.
 */

var INDEX_KEYS = ["otp.index.a", "otp.index.b"];

function secretKeyName(id) {
    return "otp.secret." + id;
}

// 64 random bits as hex: a name for the account's secret, not a secret.
function newId() {
    var id = "";
    for (var i = 0; i < 16; i++)
        id += Math.floor(Math.random() * 16).toString(16);
    return id;
}

function isWholeNumber(v) {
    return typeof v === "number" && isFinite(v) && Math.floor(v) === v;
}

/*
 * What is wrong with an account's fields, by field: { secret: "...",
 * label: "...", period: "...", counter: "..." }, empty when it can be
 * saved. Editing an account, an empty secret keeps the stored one.
 */
function problems(fields, editing) {
    var out = {};
    var secret = fields.secret === undefined ? "" : String(fields.secret);
    if (!(editing && secret.trim() === "")) {
        var p = Base32.problem(secret);
        if (p !== "")
            out.secret = p;
    }
    if (String(fields.issuer || "").trim() === "" && String(fields.label || "").trim() === "")
        out.label = "Give the account a name, or the site's.";
    if (fields.type === "totp" && !(isWholeNumber(fields.period) && fields.period >= 1 && fields.period <= 3600))
        out.period = "The code changes every 1 to 3600 seconds; 30 is usual.";
    if (fields.type === "hotp" && !(isWholeNumber(fields.counter) && fields.counter >= 0
                                    && fields.counter <= 9007199254740991))
        out.counter = "The counter is a whole number from 0.";
    return out;
}

// The stored part of an account (everything but the secret), tidied.
function metaFrom(fields, id) {
    return {
        id: id,
        type: fields.type === "hotp" ? "hotp" : "totp",
        issuer: String(fields.issuer || "").trim(),
        label: String(fields.label || "").trim(),
        algorithm: fields.algorithm || "SHA1",
        digits: fields.digits || 6,
        period: fields.type === "hotp" ? 30 : (fields.period || 30),
        counter: fields.type === "hotp" ? (fields.counter || 0) : 0
    };
}

function validMeta(a) {
    return a && typeof a.id === "string" && /^[0-9a-zA-Z]+$/.test(a.id)
            && (a.type === "totp" || a.type === "hotp")
            && typeof a.issuer === "string" && typeof a.label === "string"
            && (a.algorithm === "SHA1" || a.algorithm === "SHA256" || a.algorithm === "SHA512")
            && (a.digits === 6 || a.digits === 7 || a.digits === 8)
            && isWholeNumber(a.period) && a.period >= 1
            && isWholeNumber(a.counter) && a.counter >= 0;
}

// options: { lock, face }, both off when left out.
function serializeIndex(generation, accounts, options) {
    var index = { generation: generation };
    if (options && options.lock === true) {
        index.lock = true;
        if (options.face === true)
            index.face = true;
    }
    index.accounts = accounts.map(function(a) {
        return metaFrom(a, a.id);
    });
    return JSON.stringify(index);
}

// The index from its stored text, or null when it is not one.
function parseIndex(text) {
    var index;
    try {
        index = JSON.parse(text);
    } catch (e) {
        return null;
    }
    if (!index || !isWholeNumber(index.generation) || !Array.isArray(index.accounts))
        return null;
    for (var i = 0; i < index.accounts.length; i++) {
        if (!validMeta(index.accounts[i]))
            return null;
    }
    return { generation: index.generation, lock: index.lock === true,
             face: index.lock === true && index.face === true, accounts: index.accounts };
}

function newerIndex(a, b) {
    if (!a)
        return b || null;
    if (!b)
        return a;
    return b.generation > a.generation ? b : a;
}

// The list with the item at `from` moved to `to`; unchanged when either is
// out of range.
function moved(list, from, to) {
    var out = list.slice(0);
    if (from < 0 || from >= out.length || to < 0 || to >= out.length)
        return out;
    var item = out.splice(from, 1)[0];
    out.splice(to, 0, item);
    return out;
}

function title(account) {
    return account.issuer !== "" ? account.issuer : account.label;
}

function subtitle(account) {
    return account.issuer !== "" ? account.label : "";
}

// Already there: the same name and the same key.
function isDuplicate(accounts, fields, secret, secretsById) {
    var issuer = String(fields.issuer || "").trim().toLowerCase();
    var label = String(fields.label || "").trim().toLowerCase();
    var key = Base32.normalize(secret);
    for (var i = 0; i < accounts.length; i++) {
        var a = accounts[i];
        if (a.issuer.toLowerCase() === issuer && a.label.toLowerCase() === label
                && secretsById[a.id] === key)
            return true;
    }
    return false;
}

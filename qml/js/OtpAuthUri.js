.pragma library
.import "Base32.js" as Base32
/*
 * Copyright 2026 Herman van Hazendonk <github.com@herrie.org>
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

/*
 * otpauth:// links, what a site's QR code holds:
 *
 *     otpauth://totp/Example:alice@example.com?secret=JBSWY3DPEHPK3PXP&issuer=Example
 *     otpauth://hotp/Example:alice?secret=...&counter=0
 *
 * with algorithm (SHA1, SHA256, SHA512), digits and period optional. The
 * label is "issuer:account" or just "account"; an issuer parameter wins
 * over the label's.
 */

function decodePart(text) {
    try {
        return decodeURIComponent(String(text).replace(/\+/g, " "));
    } catch (e) {
        return null;
    }
}

function isOtpAuth(text) {
    return /^\s*otpauth:\/\//i.test(String(text));
}

/*
 * { account: {...} } with type, issuer, label, secret (Base32, normalized),
 * algorithm, digits, period and counter; or { error: "..." } in words for
 * the user.
 */
function parse(text) {
    var s = String(text).trim();
    var m = /^otpauth:\/\/([^\/?#]*)\/?([^?#]*)(\?[^#]*)?/i.exec(s);
    if (!m)
        return { error: "This is not an otpauth:// link." };
    var type = m[1].toLowerCase();
    if (type !== "totp" && type !== "hotp")
        return { error: "“" + m[1] + "” codes are not supported, only time- and counter-based ones." };

    var label = decodePart(m[2]);
    if (label === null)
        return { error: "The link's name is garbled." };
    var issuer = "";
    var account = label;
    var colon = label.indexOf(":");
    if (colon >= 0) {
        issuer = label.substr(0, colon).trim();
        account = label.substr(colon + 1);
    }
    account = account.trim();

    var params = {};
    var query = m[3] ? m[3].substr(1) : "";
    var pairs = query.length > 0 ? query.split("&") : [];
    for (var i = 0; i < pairs.length; i++) {
        if (pairs[i] === "")
            continue;
        var eq = pairs[i].indexOf("=");
        var key = (eq >= 0 ? pairs[i].substr(0, eq) : pairs[i]).toLowerCase();
        var value = decodePart(eq >= 0 ? pairs[i].substr(eq + 1) : "");
        if (value === null)
            return { error: "The link's " + key + " is garbled." };
        // The first wins, as a site would have meant it.
        if (!Object.prototype.hasOwnProperty.call(params, key))
            params[key] = value;
    }

    if (params.issuer !== undefined && params.issuer.trim() !== "")
        issuer = params.issuer.trim();

    if (params.secret === undefined || params.secret === "")
        return { error: "The link has no key in it." };
    var keyProblem = Base32.problem(params.secret);
    if (keyProblem !== "")
        return { error: "The link's key is not usable. " + keyProblem };

    var algorithm = "SHA1";
    if (params.algorithm !== undefined) {
        algorithm = params.algorithm.toUpperCase().replace("-", "");
        if (algorithm !== "SHA1" && algorithm !== "SHA256" && algorithm !== "SHA512")
            return { error: "The link asks for " + params.algorithm + ", which is not supported." };
    }

    var digits = 6;
    if (params.digits !== undefined) {
        if (!/^[0-9]+$/.test(params.digits) || +params.digits < 6 || +params.digits > 8)
            return { error: "The link asks for " + params.digits + "-digit codes; 6, 7 or 8 are supported." };
        digits = +params.digits;
    }

    var period = 30;
    if (params.period !== undefined && type === "totp") {
        if (!/^[0-9]+$/.test(params.period) || +params.period < 1 || +params.period > 3600)
            return { error: "The link asks for codes that change every " + params.period + " seconds, which is not supported." };
        period = +params.period;
    }

    var counter = 0;
    if (type === "hotp" && params.counter !== undefined) {
        if (!/^[0-9]+$/.test(params.counter) || +params.counter > 9007199254740991)
            return { error: "The link's counter " + params.counter + " is not a number." };
        counter = +params.counter;
    }

    return {
        account: {
            type: type,
            issuer: issuer,
            label: account,
            secret: Base32.normalize(params.secret),
            algorithm: algorithm,
            digits: digits,
            period: period,
            counter: counter
        }
    };
}

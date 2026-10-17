.pragma library
.import "Sha.js" as Sha
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
 * One-time codes: HOTP (RFC 4226), from a counter, and TOTP (RFC 6238),
 * from the time.
 */

// The counter as 8 bytes, big-endian. Counters past 2^53 cannot be told
// apart in a JavaScript number; no counter gets anywhere near.
function counterBytes(counter) {
    var c = Math.floor(counter);
    var high = Math.floor(c / 0x100000000);
    var low = c - high * 0x100000000;
    return [(high >>> 24) & 0xff, (high >>> 16) & 0xff, (high >>> 8) & 0xff, high & 0xff,
            (low >>> 24) & 0xff, (low >>> 16) & 0xff, (low >>> 8) & 0xff, low & 0xff];
}

/*
 * The code for a counter, as a string of `digits` digits with the leading
 * zeros kept. key: the secret's bytes. algorithm: "SHA1", "SHA256" or
 * "SHA512".
 */
function hotp(key, counter, digits, algorithm) {
    var mac = Sha.hmac(algorithm || "SHA1", key, counterBytes(counter));
    // Dynamic truncation (RFC 4226, 5.3): the low 4 bits of the last byte
    // say where to take 31 bits from.
    var offset = mac[mac.length - 1] & 0x0f;
    var binary = ((mac[offset] & 0x7f) * 0x1000000) + (mac[offset + 1] << 16)
               + (mac[offset + 2] << 8) + mac[offset + 3];
    var n = digits || 6;
    var code = String(binary % Math.pow(10, n));
    while (code.length < n)
        code = "0" + code;
    return code;
}

// The time step a moment falls in: whole periods since the Unix epoch.
function timeStep(timeMs, period) {
    return Math.floor(Math.floor(timeMs / 1000) / (period || 30));
}

function totp(key, timeMs, period, digits, algorithm) {
    return hotp(key, timeStep(timeMs, period), digits, algorithm);
}

// Seconds until the code changes, 1 to period.
function secondsLeft(timeMs, period) {
    var p = period || 30;
    return p - Math.floor(timeMs / 1000) % p;
}

// "123 456", "1234 5678", "123 4567": easier to read off and type.
function format(code) {
    var s = String(code);
    if (s.length < 6)
        return s;
    var split = Math.floor(s.length / 2);
    return s.substr(0, split) + " " + s.substr(split);
}

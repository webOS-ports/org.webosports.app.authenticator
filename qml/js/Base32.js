.pragma library
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
 * Base32 (RFC 4648, section 6), the form sites hand out their keys in.
 * People type them from a screen, so spaces and dashes between the groups
 * and lower case are taken, and the "=" padding may be left off.
 */

var ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";

// The shortest key taken: 80 bits (16 characters). RFC 4226 asks for at
// least 128; 80 is what many sites still hand out. Anything shorter is far
// more likely half a key than a key.
var MIN_BYTES = 10;

// Upper case, with the separators and the padding taken out.
function normalize(text) {
    return String(text).replace(/[\s-]/g, "").replace(/=+$/, "").toUpperCase();
}

/*
 * Why a key cannot be used, in words for the user, or "" when it can.
 * Characters left over that make no whole byte are a typo: 1, 3 or 6 of
 * them can only come from a key that lost or gained a character.
 */
function problem(text) {
    var s = normalize(text);
    if (s.length === 0)
        return "Enter the key the site shows.";
    for (var i = 0; i < s.length; i++) {
        if (ALPHABET.indexOf(s.charAt(i)) < 0) {
            var c = s.charAt(i);
            if (c === "0" || c === "1" || c === "8")
                return "“" + c + "” is not used in keys; it may be the letter "
                        + ({ "0": "O", "1": "I or L", "8": "B" })[c] + ".";
            if (c === "=")
                return "“=” can only come at the end.";
            return "“" + c + "” is not used in keys: only letters and the digits 2 to 7.";
        }
    }
    var rest = s.length % 8;
    if (rest === 1 || rest === 3 || rest === 6)
        return "The key is a character too short or too long.";
    if (Math.floor(s.length * 5 / 8) < MIN_BYTES)
        return "The key is too short: it has at least 16 characters.";
    return "";
}

// The bytes a key stands for, or null when it is not Base32.
function decode(text) {
    var s = normalize(text);
    var rest = s.length % 8;
    if (rest === 1 || rest === 3 || rest === 6)
        return null;
    var out = [];
    var buffer = 0, bits = 0;
    for (var i = 0; i < s.length; i++) {
        var v = ALPHABET.indexOf(s.charAt(i));
        if (v < 0)
            return null;
        buffer = ((buffer << 5) | v) & 0xffff;
        bits += 5;
        if (bits >= 8) {
            bits -= 8;
            out.push((buffer >>> bits) & 0xff);
        }
    }
    return out;
}

// Bytes as Base32, without padding.
function encode(bytes) {
    var out = "";
    var buffer = 0, bits = 0;
    for (var i = 0; i < bytes.length; i++) {
        buffer = ((buffer << 8) | (bytes[i] & 0xff)) & 0xffff;
        bits += 8;
        while (bits >= 5) {
            bits -= 5;
            out += ALPHABET.charAt((buffer >>> bits) & 31);
        }
    }
    if (bits > 0)
        out += ALPHABET.charAt((buffer << (5 - bits)) & 31);
    return out;
}

.pragma library
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
 * SHA-1, SHA-256 and SHA-512 (FIPS 180-4) and HMAC (RFC 2104) over byte
 * arrays, for the one-time codes. QML's JavaScript has neither WebCrypto nor
 * any HMAC of its own, and the key manager does not compute one either, so
 * the app does it here. Plain arrays of numbers 0-255 in and out; the inputs
 * are a key and an 8-byte counter, so speed does not matter.
 *
 * SHA-512 works on 64-bit words, which JavaScript numbers cannot hold
 * exactly; each is kept as a pair of 32-bit halves, high and low.
 */

// The bytes of a string as UTF-8.
function utf8Bytes(text) {
    var out = [];
    var s = String(text);
    for (var i = 0; i < s.length; i++) {
        var c = s.charCodeAt(i);
        if (c >= 0xd800 && c <= 0xdbff && i + 1 < s.length) {
            var d = s.charCodeAt(i + 1);
            if (d >= 0xdc00 && d <= 0xdfff) {
                c = 0x10000 + ((c - 0xd800) << 10) + (d - 0xdc00);
                i++;
            }
        }
        if (c < 0x80) {
            out.push(c);
        } else if (c < 0x800) {
            out.push(0xc0 | (c >> 6), 0x80 | (c & 0x3f));
        } else if (c < 0x10000) {
            out.push(0xe0 | (c >> 12), 0x80 | ((c >> 6) & 0x3f), 0x80 | (c & 0x3f));
        } else {
            out.push(0xf0 | (c >> 18), 0x80 | ((c >> 12) & 0x3f),
                     0x80 | ((c >> 6) & 0x3f), 0x80 | (c & 0x3f));
        }
    }
    return out;
}

function toHex(bytes) {
    var hex = "";
    for (var i = 0; i < bytes.length; i++)
        hex += (bytes[i] < 16 ? "0" : "") + bytes[i].toString(16);
    return hex;
}

function fromHex(hex) {
    var out = [];
    for (var i = 0; i + 1 < hex.length; i += 2)
        out.push(parseInt(hex.substr(i, 2), 16));
    return out;
}

/*
 * The message padded as both hashes want it: 0x80, zeros, then the length in
 * bits, big-endian, in lengthBytes bytes, to a multiple of blockBytes. Read
 * back as big-endian 32-bit words.
 */
function paddedWords(bytes, blockBytes, lengthBytes) {
    var length = bytes.length;
    var total = length + 1 + lengthBytes;
    total += (blockBytes - total % blockBytes) % blockBytes;
    var padded = new Array(total);
    var i;
    for (i = 0; i < length; i++)
        padded[i] = bytes[i] & 0xff;
    padded[length] = 0x80;
    for (i = length + 1; i < total; i++)
        padded[i] = 0;
    // The bit length: below 2^53 bits, which is all a number holds anyway.
    var bitsHigh = Math.floor(length / 0x20000000);
    var bitsLow = (length * 8) >>> 0;
    padded[total - 8] = (bitsHigh >>> 24) & 0xff;
    padded[total - 7] = (bitsHigh >>> 16) & 0xff;
    padded[total - 6] = (bitsHigh >>> 8) & 0xff;
    padded[total - 5] = bitsHigh & 0xff;
    padded[total - 4] = (bitsLow >>> 24) & 0xff;
    padded[total - 3] = (bitsLow >>> 16) & 0xff;
    padded[total - 2] = (bitsLow >>> 8) & 0xff;
    padded[total - 1] = bitsLow & 0xff;

    var words = new Array(total / 4);
    for (i = 0; i < words.length; i++) {
        words[i] = (padded[4 * i] << 24) | (padded[4 * i + 1] << 16)
                 | (padded[4 * i + 2] << 8) | padded[4 * i + 3];
    }
    return words;
}

function wordsToBytes(words) {
    var out = [];
    for (var i = 0; i < words.length; i++) {
        var w = words[i];
        out.push((w >>> 24) & 0xff, (w >>> 16) & 0xff, (w >>> 8) & 0xff, w & 0xff);
    }
    return out;
}

function rotl(x, n) {
    return (x << n) | (x >>> (32 - n));
}

function rotr(x, n) {
    return (x >>> n) | (x << (32 - n));
}

function sha1(bytes) {
    var words = paddedWords(bytes, 64, 8);
    var h0 = 0x67452301, h1 = 0xefcdab89, h2 = 0x98badcfe, h3 = 0x10325476, h4 = 0xc3d2e1f0;
    var w = new Array(80);
    for (var block = 0; block < words.length; block += 16) {
        var t;
        for (t = 0; t < 16; t++)
            w[t] = words[block + t];
        for (t = 16; t < 80; t++)
            w[t] = rotl(w[t - 3] ^ w[t - 8] ^ w[t - 14] ^ w[t - 16], 1);
        var a = h0, b = h1, c = h2, d = h3, e = h4;
        for (t = 0; t < 80; t++) {
            var f, k;
            if (t < 20) {
                f = (b & c) | (~b & d);
                k = 0x5a827999;
            } else if (t < 40) {
                f = b ^ c ^ d;
                k = 0x6ed9eba1;
            } else if (t < 60) {
                f = (b & c) | (b & d) | (c & d);
                k = 0x8f1bbcdc;
            } else {
                f = b ^ c ^ d;
                k = 0xca62c1d6;
            }
            var temp = (rotl(a, 5) + f + e + k + w[t]) | 0;
            e = d;
            d = c;
            c = rotl(b, 30);
            b = a;
            a = temp;
        }
        h0 = (h0 + a) | 0;
        h1 = (h1 + b) | 0;
        h2 = (h2 + c) | 0;
        h3 = (h3 + d) | 0;
        h4 = (h4 + e) | 0;
    }
    return wordsToBytes([h0, h1, h2, h3, h4]);
}

var K256 = [
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
];

function sha256(bytes) {
    var words = paddedWords(bytes, 64, 8);
    var h = [0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
             0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19];
    var w = new Array(64);
    for (var block = 0; block < words.length; block += 16) {
        var t;
        for (t = 0; t < 16; t++)
            w[t] = words[block + t];
        for (t = 16; t < 64; t++) {
            var s0 = rotr(w[t - 15], 7) ^ rotr(w[t - 15], 18) ^ (w[t - 15] >>> 3);
            var s1 = rotr(w[t - 2], 17) ^ rotr(w[t - 2], 19) ^ (w[t - 2] >>> 10);
            w[t] = (w[t - 16] + s0 + w[t - 7] + s1) | 0;
        }
        var a = h[0], b = h[1], c = h[2], d = h[3], e = h[4], f = h[5], g = h[6], hh = h[7];
        for (t = 0; t < 64; t++) {
            var S1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25);
            var ch = (e & f) ^ (~e & g);
            var temp1 = (hh + S1 + ch + K256[t] + w[t]) | 0;
            var S0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22);
            var maj = (a & b) ^ (a & c) ^ (b & c);
            var temp2 = (S0 + maj) | 0;
            hh = g;
            g = f;
            f = e;
            e = (d + temp1) | 0;
            d = c;
            c = b;
            b = a;
            a = (temp1 + temp2) | 0;
        }
        h[0] = (h[0] + a) | 0;
        h[1] = (h[1] + b) | 0;
        h[2] = (h[2] + c) | 0;
        h[3] = (h[3] + d) | 0;
        h[4] = (h[4] + e) | 0;
        h[5] = (h[5] + f) | 0;
        h[6] = (h[6] + g) | 0;
        h[7] = (h[7] + hh) | 0;
    }
    return wordsToBytes(h);
}

// SHA-512's constants, each as its high and low 32 bits.
var K512 = [
    0x428a2f98, 0xd728ae22, 0x71374491, 0x23ef65cd, 0xb5c0fbcf, 0xec4d3b2f, 0xe9b5dba5, 0x8189dbbc,
    0x3956c25b, 0xf348b538, 0x59f111f1, 0xb605d019, 0x923f82a4, 0xaf194f9b, 0xab1c5ed5, 0xda6d8118,
    0xd807aa98, 0xa3030242, 0x12835b01, 0x45706fbe, 0x243185be, 0x4ee4b28c, 0x550c7dc3, 0xd5ffb4e2,
    0x72be5d74, 0xf27b896f, 0x80deb1fe, 0x3b1696b1, 0x9bdc06a7, 0x25c71235, 0xc19bf174, 0xcf692694,
    0xe49b69c1, 0x9ef14ad2, 0xefbe4786, 0x384f25e3, 0x0fc19dc6, 0x8b8cd5b5, 0x240ca1cc, 0x77ac9c65,
    0x2de92c6f, 0x592b0275, 0x4a7484aa, 0x6ea6e483, 0x5cb0a9dc, 0xbd41fbd4, 0x76f988da, 0x831153b5,
    0x983e5152, 0xee66dfab, 0xa831c66d, 0x2db43210, 0xb00327c8, 0x98fb213f, 0xbf597fc7, 0xbeef0ee4,
    0xc6e00bf3, 0x3da88fc2, 0xd5a79147, 0x930aa725, 0x06ca6351, 0xe003826f, 0x14292967, 0x0a0e6e70,
    0x27b70a85, 0x46d22ffc, 0x2e1b2138, 0x5c26c926, 0x4d2c6dfc, 0x5ac42aed, 0x53380d13, 0x9d95b3df,
    0x650a7354, 0x8baf63de, 0x766a0abb, 0x3c77b2a8, 0x81c2c92e, 0x47edaee6, 0x92722c85, 0x1482353b,
    0xa2bfe8a1, 0x4cf10364, 0xa81a664b, 0xbc423001, 0xc24b8b70, 0xd0f89791, 0xc76c51a3, 0x0654be30,
    0xd192e819, 0xd6ef5218, 0xd6990624, 0x5565a910, 0xf40e3585, 0x5771202a, 0x106aa070, 0x32bbd1b8,
    0x19a4c116, 0xb8d2d0c8, 0x1e376c08, 0x5141ab53, 0x2748774c, 0xdf8eeb99, 0x34b0bcb5, 0xe19b48a8,
    0x391c0cb3, 0xc5c95a63, 0x4ed8aa4a, 0xe3418acb, 0x5b9cca4f, 0x7763e373, 0x682e6ff3, 0xd6b2b8a3,
    0x748f82ee, 0x5defb2fc, 0x78a5636f, 0x43172f60, 0x84c87814, 0xa1f0ab72, 0x8cc70208, 0x1a6439ec,
    0x90befffa, 0x23631e28, 0xa4506ceb, 0xde82bde9, 0xbef9a3f7, 0xb2c67915, 0xc67178f2, 0xe372532b,
    0xca273ece, 0xea26619c, 0xd186b8c7, 0x21c0c207, 0xeada7dd6, 0xcde0eb1e, 0xf57d4f7f, 0xee6ed178,
    0x06f067aa, 0x72176fba, 0x0a637dc5, 0xa2c898a6, 0x113f9804, 0xbef90dae, 0x1b710b35, 0x131c471b,
    0x28db77f5, 0x23047d84, 0x32caab7b, 0x40c72493, 0x3c9ebe0a, 0x15c9bebc, 0x431d67c4, 0x9c100d4c,
    0x4cc5d4be, 0xcb3e42b6, 0x597f299c, 0xfc657e2a, 0x5fcb6fab, 0x3ad6faec, 0x6c44198c, 0x4a475817
];

/*
 * 64-bit helpers on (high, low) halves. The results go into out[0] (high)
 * and out[1] (low) so the inner loop makes no garbage.
 */
function rotr64(out, hi, lo, n) {
    if (n < 32) {
        out[0] = (hi >>> n) | (lo << (32 - n));
        out[1] = (lo >>> n) | (hi << (32 - n));
    } else {
        var m = n - 32;
        if (m === 0) {
            out[0] = lo;
            out[1] = hi;
        } else {
            out[0] = (lo >>> m) | (hi << (32 - m));
            out[1] = (hi >>> m) | (lo << (32 - m));
        }
    }
}

function shr64(out, hi, lo, n) {
    // n < 32 is all SHA-512 asks for.
    out[0] = hi >>> n;
    out[1] = (lo >>> n) | (hi << (32 - n));
}

// Adds a list of (high, low) pairs: [h0, l0, h1, l1, ...].
function add64(out, pairs) {
    var lo = 0, hi = 0;
    for (var i = 0; i < pairs.length; i += 2) {
        lo += pairs[i + 1] >>> 0;
        hi += pairs[i] >>> 0;
    }
    hi += Math.floor(lo / 0x100000000);
    out[0] = hi | 0;
    out[1] = lo | 0;
}

function sha512(bytes) {
    var words = paddedWords(bytes, 128, 16);
    var h = [0x6a09e667, 0xf3bcc908, 0xbb67ae85, 0x84caa73b, 0x3c6ef372, 0xfe94f82b,
             0xa54ff53a, 0x5f1d36f1, 0x510e527f, 0xade682d1, 0x9b05688c, 0x2b3e6c1f,
             0x1f83d9ab, 0xfb41bd6b, 0x5be0cd19, 0x137e2179];
    var w = new Array(160);
    var r1 = [0, 0], r2 = [0, 0], r3 = [0, 0], sum = [0, 0];
    for (var block = 0; block < words.length; block += 32) {
        var t;
        for (t = 0; t < 32; t++)
            w[t] = words[block + t];
        for (t = 16; t < 80; t++) {
            var xh = w[2 * (t - 15)], xl = w[2 * (t - 15) + 1];
            rotr64(r1, xh, xl, 1);
            rotr64(r2, xh, xl, 8);
            shr64(r3, xh, xl, 7);
            var s0h = r1[0] ^ r2[0] ^ r3[0], s0l = r1[1] ^ r2[1] ^ r3[1];
            var yh = w[2 * (t - 2)], yl = w[2 * (t - 2) + 1];
            rotr64(r1, yh, yl, 19);
            rotr64(r2, yh, yl, 61);
            shr64(r3, yh, yl, 6);
            var s1h = r1[0] ^ r2[0] ^ r3[0], s1l = r1[1] ^ r2[1] ^ r3[1];
            add64(sum, [w[2 * (t - 16)], w[2 * (t - 16) + 1], s0h, s0l,
                        w[2 * (t - 7)], w[2 * (t - 7) + 1], s1h, s1l]);
            w[2 * t] = sum[0];
            w[2 * t + 1] = sum[1];
        }
        var ah = h[0], al = h[1], bh = h[2], bl = h[3], ch = h[4], cl = h[5], dh = h[6], dl = h[7];
        var eh = h[8], el = h[9], fh = h[10], fl = h[11], gh = h[12], gl = h[13], hh = h[14], hl = h[15];
        for (t = 0; t < 80; t++) {
            rotr64(r1, eh, el, 14);
            rotr64(r2, eh, el, 18);
            rotr64(r3, eh, el, 41);
            var S1h = r1[0] ^ r2[0] ^ r3[0], S1l = r1[1] ^ r2[1] ^ r3[1];
            var chh = (eh & fh) ^ (~eh & gh), chl = (el & fl) ^ (~el & gl);
            add64(sum, [hh, hl, S1h, S1l, chh, chl, K512[2 * t], K512[2 * t + 1], w[2 * t], w[2 * t + 1]]);
            var t1h = sum[0], t1l = sum[1];
            rotr64(r1, ah, al, 28);
            rotr64(r2, ah, al, 34);
            rotr64(r3, ah, al, 39);
            var S0h = r1[0] ^ r2[0] ^ r3[0], S0l = r1[1] ^ r2[1] ^ r3[1];
            var majh = (ah & bh) ^ (ah & ch) ^ (bh & ch), majl = (al & bl) ^ (al & cl) ^ (bl & cl);
            add64(sum, [S0h, S0l, majh, majl]);
            var t2h = sum[0], t2l = sum[1];
            hh = gh; hl = gl;
            gh = fh; gl = fl;
            fh = eh; fl = el;
            add64(sum, [dh, dl, t1h, t1l]);
            eh = sum[0]; el = sum[1];
            dh = ch; dl = cl;
            ch = bh; cl = bl;
            bh = ah; bl = al;
            add64(sum, [t1h, t1l, t2h, t2l]);
            ah = sum[0]; al = sum[1];
        }
        var finals = [ah, al, bh, bl, ch, cl, dh, dl, eh, el, fh, fl, gh, gl, hh, hl];
        for (var i = 0; i < 16; i += 2) {
            add64(sum, [h[i], h[i + 1], finals[i], finals[i + 1]]);
            h[i] = sum[0];
            h[i + 1] = sum[1];
        }
    }
    return wordsToBytes(h);
}

var algorithms = {
    "SHA1": { hash: sha1, blockBytes: 64 },
    "SHA256": { hash: sha256, blockBytes: 64 },
    "SHA512": { hash: sha512, blockBytes: 128 }
};

function isAlgorithm(name) {
    return Object.prototype.hasOwnProperty.call(algorithms, name);
}

function hash(algorithm, bytes) {
    if (!isAlgorithm(algorithm))
        throw new Error("Unknown hash " + algorithm);
    return algorithms[algorithm].hash(bytes);
}

// HMAC (RFC 2104) with SHA1, SHA256 or SHA512.
function hmac(algorithm, key, message) {
    if (!isAlgorithm(algorithm))
        throw new Error("Unknown hash " + algorithm);
    var alg = algorithms[algorithm];
    var k = key.length > alg.blockBytes ? alg.hash(key) : key.slice(0);
    var inner = new Array(alg.blockBytes);
    var outer = new Array(alg.blockBytes);
    for (var i = 0; i < alg.blockBytes; i++) {
        var b = i < k.length ? k[i] & 0xff : 0;
        inner[i] = b ^ 0x36;
        outer[i] = b ^ 0x5c;
    }
    var innerHash = alg.hash(inner.concat(Array.prototype.slice.call(message)));
    return alg.hash(outer.concat(innerHash));
}

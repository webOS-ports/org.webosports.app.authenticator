/*
 * Copyright 2026 Herman van Hazendonk <github.com@herrie.org>
 * SPDX-License-Identifier: Apache-2.0
 */

import QtQuick
import QtTest

import "../../qml/js/Sha.js" as Sha
import "../../qml/js/Base32.js" as Base32
import "../../qml/js/Otp.js" as Otp
import "../../qml/js/OtpAuthUri.js" as OtpAuthUri
import "../js/vectors.js" as V

/*
 * The one-time code JavaScript in QML's own engine, the one it runs in on
 * the device: the published vectors of FIPS 180-4, RFC 2202, RFC 4231,
 * RFC 4226, RFC 6238 and RFC 4648 (tests/js/vectors.js). The Node run
 * (tests/js/run-node-tests.js) has the same and compares random inputs
 * with OpenSSL.
 */
TestCase {
    name: "Otp"

    function ascii(text) {
        var out = [];
        for (var i = 0; i < text.length; i++)
            out.push(text.charCodeAt(i));
        return out;
    }

    function test_hashes_data() {
        return V.hashes.map(function(v) {
            return { tag: v.alg + " " + JSON.stringify(v.text).substr(0, 20), alg: v.alg, text: v.text, hex: v.hex };
        });
    }
    function test_hashes(data) {
        compare(Sha.toHex(Sha.hash(data.alg, Sha.utf8Bytes(data.text))), data.hex);
    }

    function test_million_a() {
        var bytes = new Array(1000000);
        for (var i = 0; i < bytes.length; i++)
            bytes[i] = 0x61;
        // FIPS 180-4's long example.
        compare(Sha.toHex(Sha.sha1(bytes)), "34aa973cd4c4daa4f61eeb2bdbad27316534016f");
    }

    function test_hmac_data() {
        return V.hmacs.map(function(v, i) {
            return { tag: "HMAC-" + v.alg + " " + i, v: v };
        });
    }
    function test_hmac(data) {
        var v = data.v;
        var key = v.keyHex !== undefined ? Sha.fromHex(v.keyHex) : Sha.utf8Bytes(v.keyText);
        compare(Sha.toHex(Sha.hmac(v.alg, key, Sha.utf8Bytes(v.text))), v.hex);
    }

    function test_hotp_rfc4226_data() {
        return V.hotp.map(function(code, counter) {
            return { tag: "counter " + counter, counter: counter, code: code };
        });
    }
    function test_hotp_rfc4226(data) {
        compare(Otp.hotp(ascii(V.hotpSecret), data.counter, 6, "SHA1"), data.code);
    }

    function test_totp_rfc6238_data() {
        var rows = [];
        V.totp.forEach(function(row) {
            ["SHA1", "SHA256", "SHA512"].forEach(function(alg) {
                rows.push({ tag: alg + " at " + row.time, alg: alg, time: row.time, code: row[alg] });
            });
        });
        return rows;
    }
    function test_totp_rfc6238(data) {
        compare(Otp.totp(ascii(V.totpSeeds[data.alg]), data.time * 1000, 30, 8, data.alg), data.code);
    }

    function test_base32_data() {
        return V.base32.map(function(v) { return { tag: v.text === "" ? "empty" : v.text, text: v.text, b32: v.b32 }; });
    }
    function test_base32(data) {
        compare(Base32.encode(ascii(data.text)), data.b32);
        compare(JSON.stringify(Base32.decode(data.b32)), JSON.stringify(ascii(data.text)));
    }

    function test_secret_typed_in_groups() {
        compare(Base32.problem("jbsw y3dp ehpk 3pxp"), "");
        compare(Base32.normalize("jbsw y3dp-ehpk 3pxp=="), "JBSWY3DPEHPK3PXP");
        verify(Base32.problem("JBSWY3DPEHPK3PX0").indexOf("letter O") >= 0);
        verify(Base32.problem("JBSW") !== "");
    }

    function test_otpauth_link() {
        var r = OtpAuthUri.parse("otpauth://totp/ACME%20Co:john%40example.com?secret=HXDMVJECJJWSRB3HWIZR4IFUGFTMXBOZ&issuer=ACME%20Co&algorithm=SHA512&digits=8&period=60");
        verify(!r.error, r.error);
        compare(r.account.issuer, "ACME Co");
        compare(r.account.label, "john@example.com");
        compare(r.account.algorithm, "SHA512");
        compare(r.account.digits, 8);
        compare(r.account.period, 60);
        verify(OtpAuthUri.parse("otpauth://totp/x?secret=JBSWY3DPEHPK3PXP&digits=9").error !== undefined);
    }

    // The 64-bit arithmetic of SHA-512 with every bit set, where a sign or
    // carry slip would show. The digest is OpenSSL's (Node's crypto).
    function test_sha512_all_ones() {
        var bytes = [];
        for (var i = 0; i < 200; i++)
            bytes.push(0xff);
        compare(Sha.toHex(Sha.sha512(bytes)),
                "dcd0044a15b62bc8ebdc4ac9d14063c0b0aec2f4951230fc960fbe70ccb1b91cf12782d8e3734d445c108a33e8b5ce5a79cd73aa547ecdaaf26bce2cc81a80c0");
    }
}

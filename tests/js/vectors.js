.pragma library
/*
 * Copyright 2026 Herman van Hazendonk <github.com@herrie.org>
 * SPDX-License-Identifier: Apache-2.0
 *
 * Published test vectors, shared by the QML tests (tests/qml/tst_otp.qml,
 * in the app's own JavaScript engine) and the Node run
 * (tests/js/run-node-tests.js), which also recomputes every one of them
 * with Node's crypto (OpenSSL), so a vector copied wrong shows up too.
 */

// FIPS 180-4 examples ("abc", the empty message, the two-block message).
var hashes = [
    { alg: "SHA1", text: "abc", hex: "a9993e364706816aba3e25717850c26c9cd0d89d" },
    { alg: "SHA1", text: "", hex: "da39a3ee5e6b4b0d3255bfef95601890afd80709" },
    { alg: "SHA1", text: "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq",
      hex: "84983e441c3bd26ebaae4aa1f95129e5e54670f1" },
    { alg: "SHA256", text: "abc", hex: "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad" },
    { alg: "SHA256", text: "", hex: "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855" },
    { alg: "SHA256", text: "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq",
      hex: "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1" },
    { alg: "SHA512", text: "abc",
      hex: "ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f" },
    { alg: "SHA512", text: "",
      hex: "cf83e1357eefb8bdf1542850d66d8007d620e4050b5715dc83f4a921d36ce9ce47d0d13c5d85f2b0ff8318d2877eec2f63b931bd47417a81a538327af927da3e" },
    { alg: "SHA512", text: "abcdefghbcdefghicdefghijdefghijkefghijklfghijklmghijklmnhijklmnoijklmnopjklmnopqklmnopqrlmnopqrsmnopqrstnopqrstu",
      hex: "8e959b75dae313da8cf4f72814fc143f8f7779c6eb9f7fa17299aeadb6889018501d289e4900f7e4331b99dec4b5433ac7d329eeb6dd26545e96e55b874be909" }
];

// RFC 2202 (HMAC-SHA1) and RFC 4231 (HMAC-SHA256/512) cases 1, 2 and 6
// (6: a key longer than the block, hashed first).
var hmacs = [
    { alg: "SHA1", keyHex: "0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b", text: "Hi There",
      hex: "b617318655057264e28bc0b6fb378c8ef146be00" },
    { alg: "SHA1", keyText: "Jefe", text: "what do ya want for nothing?",
      hex: "effcdf6ae5eb2fa2d27416d5f184df9c259a7c79" },
    { alg: "SHA1", keyHex: "aa".repeat(80), text: "Test Using Larger Than Block-Size Key - Hash Key First",
      hex: "aa4ae5e15272d00e95705637ce8a3b55ed402112" },
    { alg: "SHA256", keyHex: "0b".repeat(20), text: "Hi There",
      hex: "b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7" },
    { alg: "SHA256", keyText: "Jefe", text: "what do ya want for nothing?",
      hex: "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843" },
    { alg: "SHA256", keyHex: "aa".repeat(131), text: "Test Using Larger Than Block-Size Key - Hash Key First",
      hex: "60e431591ee0b67f0d8a26aacbf5b77f8e0bc6213728c5140546040f0ee37f54" },
    { alg: "SHA512", keyHex: "0b".repeat(20), text: "Hi There",
      hex: "87aa7cdea5ef619d4ff0b4241a1d6cb02379f4e2ce4ec2787ad0b30545e17cdedaa833b7d6b8a702038b274eaea3f4e4be9d914eeb61f1702e696c203a126854" },
    { alg: "SHA512", keyText: "Jefe", text: "what do ya want for nothing?",
      hex: "164b7a7bfcf819e2e395fbe73b56e0a387bd64222e831fd610270cd7ea2505549758bf75c05a994a6d034f65f8f0e6fdcaeab1a34d4a6b4b636e070a38bce737" },
    { alg: "SHA512", keyHex: "aa".repeat(131), text: "Test Using Larger Than Block-Size Key - Hash Key First",
      hex: "80b24263c7c1a3ebb71493c1dd7be8b49b46d1f41b4aeec1121b013783f8f3526b56d037e05f2598bd0fd2215d6a1e5295e64f73f63f0aec8b915a985d786598" }
];

// RFC 4226, Appendix D: the secret "12345678901234567890", counters 0 to 9.
var hotpSecret = "12345678901234567890";
var hotp = ["755224", "287082", "359152", "969429", "338314",
            "254676", "287922", "162583", "399871", "520489"];

// RFC 6238, Appendix B: 8 digits, 30 s, a seed per hash.
var totpSeeds = {
    "SHA1": "12345678901234567890",
    "SHA256": "12345678901234567890123456789012",
    "SHA512": "1234567890123456789012345678901234567890123456789012345678901234"
};
var totp = [
    { time: 59, SHA1: "94287082", SHA256: "46119246", SHA512: "90693936" },
    { time: 1111111109, SHA1: "07081804", SHA256: "68084774", SHA512: "25091201" },
    { time: 1111111111, SHA1: "14050471", SHA256: "67062674", SHA512: "99943326" },
    { time: 1234567890, SHA1: "89005924", SHA256: "91819424", SHA512: "93441116" },
    { time: 2000000000, SHA1: "69279037", SHA256: "90698825", SHA512: "38618901" },
    { time: 20000000000, SHA1: "65353130", SHA256: "77737706", SHA512: "47863826" }
];

// RFC 4648, section 10.
var base32 = [
    { text: "", b32: "" },
    { text: "f", b32: "MY" },
    { text: "fo", b32: "MZXQ" },
    { text: "foo", b32: "MZXW6" },
    { text: "foob", b32: "MZXW6YQ" },
    { text: "fooba", b32: "MZXW6YTB" },
    { text: "foobar", b32: "MZXW6YTBOI" }
];

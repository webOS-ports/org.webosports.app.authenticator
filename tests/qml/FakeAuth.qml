/*
 * Copyright 2026 Herman van Hazendonk <github.com@herrie.org>
 * SPDX-License-Identifier: GPL-3.0-only
 */

import QtQuick

/*
 * com.webos.service.auth, com.webos.service.fingerprint and
 * com.webos.service.faceunlock, answering as luna-authmanager,
 * webos-fingerprint-adapter and luneos-faced do, for main.qml's authBus.
 * The face service's methods are recorded as "face:<method>".
 *
 * Knobs: lockMode and passcode; fingerprints (names; empty for none) and
 * available; lockoutAfter wrong passcodes, then lockedOut answers;
 * denyMatch answers matchDevicePasscode as ls-hubd does for a caller
 * without the group. touch(matched) is a finger on the sensor.
 * faceAvailable and faceEnrolled; face(payload) answers the running face
 * identify, as luneos-faced does at the end of its attempt.
 */
QtObject {
    id: fake

    property string lockMode: "pin"
    property string passcode: "1357"
    property var fingerprints: []
    property bool available: true
    property int lockoutAfter: 5
    property bool denyMatch: false
    property bool faceAvailable: true
    property bool faceEnrolled: false

    property var calls: []
    property int wrong: 0
    property var _lockModeSubs: []
    property var _statusSubs: []
    property var _identifySubs: []
    property var _faceStatusSubs: []
    property var _faceSubs: []

    function countOf(method) {
        return calls.filter(function(c) { return c.method === method; }).length;
    }

    // The identify subscriptions not cancelled.
    function armed() {
        return _identifySubs.filter(function(s) { return !s.cancelled; }).length;
    }

    function _answer(callback, payload) {
        Qt.callLater(function() { callback({ payload: JSON.stringify(payload) }); });
    }

    // The face identify subscriptions not cancelled.
    function faceArmed() {
        return _faceSubs.filter(function(s) { return !s.cancelled; }).length;
    }

    function _method(uri) {
        if (/^luna:\/\/com\.webos\.service\.faceunlock\//.test(uri))
            return "face:" + uri.replace(/^luna:\/\/com\.webos\.service\.faceunlock\//, "");
        return uri.replace(/^luna:\/\/com\.webos\.service\.(auth|fingerprint)\//, "");
    }

    function call(uri, json, reply, error) {
        var method = _method(uri);
        var args = JSON.parse(json);
        calls.push({ method: method, args: args });
        if (method === "matchDevicePasscode") {
            if (denyMatch) {
                _answer(reply, { returnValue: false, errorCode: -1,
                                 errorText: "Denied method call \"matchDevicePasscode\"" });
            } else if (wrong >= lockoutAfter) {
                _answer(reply, { returnValue: false, lockedOut: true, retriesLeft: 0, lockoutSeconds: 30 });
            } else if (args.passCode === passcode) {
                wrong = 0;
                _answer(reply, { returnValue: true });
            } else {
                wrong++;
                if (wrong >= lockoutAfter)
                    _answer(reply, { returnValue: false, lockedOut: true, retriesLeft: 0, lockoutSeconds: 30 });
                else
                    _answer(reply, { returnValue: false, lockedOut: false, retriesLeft: 0 });
            }
        } else if (method === "face:abort") {
            _faceSubs.forEach(function(s) {
                if (!s.cancelled)
                    _answer(s.reply, { returnValue: true, recognized: false, reason: "aborted" });
            });
            _answer(reply, { returnValue: true });
        } else if (method === "abort") {
            _identifySubs.forEach(function(s) {
                if (!s.cancelled)
                    _answer(s.reply, { returnValue: false, finished: true, identified: false, errorText: "Aborted" });
            });
            _answer(reply, { returnValue: true });
        } else {
            error("unrecognized call: " + uri);
        }
        return {};
    }

    function _status() {
        return { returnValue: true, available: available, state: available ? "FPSTATE_IDLE" : "FPSTATE_UNKNOWN",
                 fingerprints: available ? fingerprints : [] };
    }

    function subscribe(uri, json, reply, error) {
        var method = _method(uri);
        calls.push({ method: method, args: JSON.parse(json) });
        var sub = { reply: reply, cancelled: false };
        sub.cancel = function() { sub.cancelled = true; };
        if (method === "getDeviceLockMode") {
            _lockModeSubs.push(sub);
            _answer(reply, { returnValue: true, subscribed: true, lockMode: lockMode, policyState: "none",
                             retriesLeft: 0, policyRequiresPassword: false });
        } else if (method === "getStatus") {
            _statusSubs.push(sub);
            var status = _status();
            status.subscribed = true;
            _answer(reply, status);
        } else if (method === "face:getStatus") {
            _faceStatusSubs.push(sub);
            _answer(reply, { returnValue: true, subscribed: true, available: faceAvailable,
                             enrolled: faceEnrolled, state: "idle" });
        } else if (method === "face:identify") {
            _faceSubs.push(sub);
        } else if (method === "identify") {
            if (!available || fingerprints.length === 0) {
                _answer(reply, { returnValue: false, errorText: available ? "No fingerprints are enrolled"
                                                                          : "Fingerprint daemon not available" });
            } else {
                _identifySubs.push(sub);
                _answer(reply, { returnValue: true, subscribed: true });
            }
        } else {
            error("unrecognized call: " + uri);
        }
        return { cancel: sub.cancel };
    }

    onLockModeChanged: _lockModeSubs.forEach(function(s) {
        if (!s.cancelled)
            _answer(s.reply, { returnValue: true, lockMode: lockMode });
    })
    onFingerprintsChanged: _statusSubs.forEach(function(s) {
        if (!s.cancelled)
            _answer(s.reply, _status());
    })

    onFaceEnrolledChanged: _faceStatusSubs.forEach(function(s) {
        if (!s.cancelled)
            _answer(s.reply, { returnValue: true, available: faceAvailable, enrolled: faceEnrolled, state: "idle" });
    })

    function face(payload) {
        _faceSubs.forEach(function(s) {
            if (!s.cancelled)
                _answer(s.reply, payload);
        });
    }

    function touch(matched) {
        _identifySubs.forEach(function(s) {
            if (s.cancelled)
                return;
            if (matched) {
                s.done = true;
                _answer(s.reply, { returnValue: true, finished: true, identified: true, finger: fingerprints[0] });
            } else {
                _answer(s.reply, { returnValue: true, finished: false, identified: false,
                                   errorText: "FINGER_NOT_RECOGNIZED" });
            }
        });
    }
}

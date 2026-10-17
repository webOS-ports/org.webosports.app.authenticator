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

import QtQuick

/*
 * Who is holding the device: a fingerprint, through
 * com.webos.service.fingerprint (webos-fingerprint-adapter, biomd), or the
 * screen lock passcode, through com.webos.service.auth (luna-authmanager).
 * The passcode is checked there, against the same count of wrong tries and
 * the same lockout as the lock screen's.
 *
 * Needs "auth.query" (the lock mode), "auth.verify" (matching the
 * passcode) and "fingerprint.identify".
 *
 * bus: anything with LunaService's call() and subscribe(). The tests give
 * it a stand-in.
 */
QtObject {
    id: auth

    property var bus: null

    // The screen lock: "" until known, then "none", "pin", "password",
    // "pattern" or "face".
    property string lockMode: ""
    readonly property bool hasPasscode: lockMode === "pin" || lockMode === "password"
                                        || lockMode === "pattern"

    property bool fingerprintAvailable: false
    property int fingerprintCount: 0
    readonly property bool fingerprintEnrolled: fingerprintAvailable && fingerprintCount > 0

    // Set while the lock is shown and the app is in front: the sensor is
    // armed only then.
    property bool listening: false
    // Touches that did not match since the lock was shown; after
    // maxFingerprintMisses only the passcode opens it.
    property int fingerprintMisses: 0
    readonly property int maxFingerprintMisses: 5
    readonly property bool fingerprintActive: listening && fingerprintEnrolled
                                              && fingerprintMisses < maxFingerprintMisses

    signal fingerprintMatched()
    signal fingerprintMissed()

    readonly property string authService: "luna://com.webos.service.auth/"
    readonly property string fingerprintService: "luna://com.webos.service.fingerprint/"

    property var _lockModeCall: null
    property var _statusCall: null
    property var _identifyCall: null
    // Identify calls that failed in a row; the sensor is given up on after
    // a few, until the lock is next shown.
    property int _identifyErrors: 0

    property var _restartTimer: Timer {
        interval: 500
        onTriggered: auth._arm()
    }
    // Several captures of one press come as several misses; they count as
    // one.
    property var _missCooldown: Timer {
        interval: 1200
    }

    Component.onCompleted: watch()

    onFingerprintActiveChanged: {
        if (fingerprintActive)
            _arm();
        else
            _disarm();
    }

    function _parse(message) {
        try {
            return JSON.parse(message.payload);
        } catch (e) {
            return null;
        }
    }

    // Follows the lock mode and the enrolled fingerprints.
    function watch() {
        if (!bus)
            return;
        if (_lockModeCall)
            _lockModeCall.cancel();
        _lockModeCall = bus.subscribe(authService + "getDeviceLockMode", '{"subscribe":true}',
                                      function(message) {
            var reply = _parse(message);
            if (reply && reply.returnValue !== false && typeof reply.lockMode === "string")
                lockMode = reply.lockMode;
        }, function(error) {
            console.warn("Authenticator: the screen lock mode cannot be read: " + error);
        });
        if (_statusCall)
            _statusCall.cancel();
        _statusCall = bus.subscribe(fingerprintService + "getStatus", '{"subscribe":true}',
                                    function(message) {
            var reply = _parse(message);
            if (!reply || reply.returnValue === false) {
                fingerprintAvailable = false;
                return;
            }
            fingerprintAvailable = reply.available === true;
            fingerprintCount = Array.isArray(reply.fingerprints) ? reply.fingerprints.length : 0;
        }, function(error) {
            // No sensor, or no fingerprint service on this device.
            fingerprintAvailable = false;
        });
    }

    // The lock is shown anew: a full count of fingerprint tries.
    function reset() {
        fingerprintMisses = 0;
        _identifyErrors = 0;
    }

    function _arm() {
        if (_identifyCall || !fingerprintActive || !bus)
            return;
        _identifyCall = bus.subscribe(fingerprintService + "identify", '{"subscribe":true}',
                                      _identifyReply, _identifyError);
    }

    function _disarm() {
        _restartTimer.stop();
        if (_identifyCall) {
            var call = _identifyCall;
            _identifyCall = null;
            call.cancel();
            // Not left armed for whoever asks next.
            bus.call(fingerprintService + "abort", "{}", function() {}, function() {});
        }
    }

    // The subscription is not cancelled from inside its own reply.
    function _endIdentify() {
        var call = _identifyCall;
        _identifyCall = null;
        if (call)
            Qt.callLater(function() { call.cancel(); });
    }

    function _identifyReply(message) {
        var reply = _parse(message);
        if (!reply)
            return;
        if (reply.returnValue === false && reply.finished !== true && reply.identified === undefined) {
            // Refused to start: busy, or the daemon went away.
            _identifyError(reply.errorText || "refused");
            return;
        }
        _identifyErrors = 0;
        if (reply.identified === true) {
            _endIdentify();
            fingerprintMatched();
        } else if (reply.identified === false && reply.finished === false) {
            // One touch that did not match; the sensor stays armed.
            if (!_missCooldown.running) {
                _missCooldown.restart();
                fingerprintMisses++;
                fingerprintMissed();
            }
        } else if (reply.finished === true) {
            // Over without a match: cancelled, or the 30 second limit.
            _endIdentify();
            if (fingerprintActive)
                _restartTimer.restart();
        }
    }

    function _identifyError(error) {
        console.warn("Authenticator: fingerprint: " + error);
        _endIdentify();
        if (fingerprintActive && ++_identifyErrors < 3)
            _restartTimer.restart();
    }

    /*
     * Checks a passcode. done({ matched, lockedOut, lockoutSeconds,
     * error }): error is set when it could not be checked at all.
     */
    function checkPasscode(passcode, done) {
        if (!bus) {
            done({ matched: false, error: "The passcode cannot be checked." });
            return;
        }
        bus.call(authService + "matchDevicePasscode", JSON.stringify({ "passCode": passcode }),
                 function(message) {
            var reply = _parse(message);
            if (!reply) {
                done({ matched: false, error: "The passcode cannot be checked." });
            } else if (reply.returnValue === true) {
                done({ matched: true });
            } else if (reply.lockedOut === true) {
                done({ matched: false, lockedOut: true,
                       lockoutSeconds: reply.lockoutSeconds > 0 ? reply.lockoutSeconds : 15 });
            } else if (reply.errorText !== undefined) {
                // Not an answer about the passcode: the call was refused.
                done({ matched: false, error: "The passcode cannot be checked: " + reply.errorText });
            } else {
                done({ matched: false });
            }
        }, function(error) {
            done({ matched: false, error: "The passcode cannot be checked: " + error });
        });
    }
}

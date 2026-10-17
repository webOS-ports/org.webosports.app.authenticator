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
 * com.webos.service.fingerprint (webos-fingerprint-adapter, biomd), a face
 * when faceAllowed, through com.webos.service.faceunlock (luneos-faced), or
 * the screen lock passcode, through com.webos.service.auth
 * (luna-authmanager). The passcode is checked there, against the same
 * count of wrong tries and the same lockout as the lock screen's.
 *
 * Needs "auth.query" (the lock mode), "auth.verify" (matching the
 * passcode), "fingerprint.identify" and "faceunlock.identify".
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

    /*
     * A face: weaker than the others (an RGB camera only; a good photo can
     * pass), so only when the user turned it on. Each identify is one
     * attempt of a few seconds that holds the camera, so there are at most
     * maxFaceTries of them, faceGapMs apart, each time the app comes to the
     * front; tryFaceAgain() gives more. Only a face that did not match
     * counts as a miss, not an empty frame.
     */
    property bool faceAllowed: false
    property bool faceAvailable: false
    property bool faceEnrolled: false
    readonly property bool faceReady: faceAllowed && faceAvailable && faceEnrolled
                                      && faceMisses < maxFaceMisses
    property int faceMisses: 0
    readonly property int maxFaceMisses: 5
    property int faceTries: 0
    readonly property int maxFaceTries: 3
    property int faceGapMs: 2500
    // The camera could not be had (the Camera app holds it): not tried
    // again until asked, or until the app comes back to the front.
    property bool faceBlocked: false
    readonly property bool faceActive: listening && faceReady && faceTries < maxFaceTries && !faceBlocked
    // What the camera is doing, in words; "" when nothing to say.
    property string faceStatus: ""

    signal faceMatched()
    signal faceMissed()

    readonly property string authService: "luna://com.webos.service.auth/"
    readonly property string fingerprintService: "luna://com.webos.service.fingerprint/"
    readonly property string faceService: "luna://com.webos.service.faceunlock/"

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

    property var _faceCall: null
    property var _faceGap: Timer {
        interval: auth.faceGapMs
        onTriggered: auth._armFace()
    }

    Component.onCompleted: watch()

    onFingerprintActiveChanged: {
        if (fingerprintActive)
            _arm();
        else
            _disarm();
    }

    onFaceActiveChanged: {
        if (faceActive)
            _armFace();
        else
            _disarmFace();
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
        if (_faceStatusCall)
            _faceStatusCall.cancel();
        _faceStatusCall = bus.subscribe(faceService + "getStatus", '{"subscribe":true}',
                                        function(message) {
            var reply = _parse(message);
            if (!reply || reply.returnValue === false) {
                faceAvailable = false;
                return;
            }
            faceAvailable = reply.available === true;
            faceEnrolled = reply.enrolled === true;
        }, function(error) {
            // No face unlock on this device.
            faceAvailable = false;
        });
    }

    property var _faceStatusCall: null

    // The lock is shown anew: a full count of fingerprint and face tries.
    function reset() {
        fingerprintMisses = 0;
        _identifyErrors = 0;
        faceMisses = 0;
        cameBack();
    }

    // Back in front: the camera may be tried again, the misses stay.
    function cameBack() {
        faceTries = 0;
        faceBlocked = false;
        faceStatus = "";
    }

    function tryFaceAgain() {
        cameBack();
    }

    function _armFace() {
        if (_faceCall || !faceActive || !bus)
            return;
        // The camera takes a moment to start; say so, or it looks broken.
        faceStatus = "Looking for your face\u2026";
        var call = bus.subscribe(faceService + "identify", '{"subscribe":true}',
                                 function(message) { if (_faceCall === call) _faceReply(message); },
                                 function(error) { if (_faceCall === call) _faceError(error); });
        _faceCall = call;
    }

    function _disarmFace() {
        _faceGap.stop();
        if (_faceCall) {
            var call = _faceCall;
            _faceCall = null;
            call.cancel();
            // The camera released, not left streaming.
            bus.call(faceService + "abort", "{}", function() {}, function() {});
            faceStatus = "";
        }
    }

    function _endFace() {
        var call = _faceCall;
        _faceCall = null;
        if (call)
            Qt.callLater(function() { call.cancel(); });
    }

    function _faceReply(message) {
        var reply = _parse(message);
        if (!reply)
            return;
        if (reply.scanning === true) {
            faceStatus = "Checking\u2026";
            return;
        }
        if (reply.recognized === true) {
            _endFace();
            faceStatus = "";
            faceMatched();
            return;
        }
        if (reply.recognized === false) {
            _endFace();
            var reason = reply.reason || "";
            if (reason === "notEnrolled") {
                faceEnrolled = false;
                faceStatus = "";
                return;
            }
            faceStatus = reason === "noFace" ? "No face seen."
                       : reason === "multipleFaces" ? "More than one face seen."
                       : reason === "aborted" ? ""
                       : "The face was not recognised.";
            // An empty frame is someone not looking yet, not a try.
            if (reason !== "noFace" && reason !== "aborted") {
                faceMisses++;
                faceMissed();
            }
            if (reason !== "aborted")
                faceTries++;
            if (faceActive)
                _faceGap.restart();
            return;
        }
        if (reply.returnValue === false)
            _faceError(reply.errorText || "refused");
    }

    function _faceError(error) {
        console.warn("Authenticator: face: " + error);
        _endFace();
        faceBlocked = true;
        faceStatus = "Face unlock cannot be used just now.";
    }

    function _arm() {
        if (_identifyCall || !fingerprintActive || !bus)
            return;
        // A reply for a call let go of (cancelled, not yet gone) is not
        // this one's.
        var call = bus.subscribe(fingerprintService + "identify", '{"subscribe":true}',
                                 function(message) { if (_identifyCall === call) _identifyReply(message); },
                                 function(error) { if (_identifyCall === call) _identifyError(error); });
        _identifyCall = call;
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

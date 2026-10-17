# Authenticator

One-time codes for two-step verification on LuneOS: time-based (TOTP,
RFC 6238) and counter-based (HOTP, RFC 4226).

- Accounts from a site's QR code: the Camera reads it and opens the
  otpauth:// link here. Any app that opens an otpauth:// link through the
  application manager does the same. The app shows what the link holds;
  nothing is added until you tap Save.
- Accounts typed in: the site's key (Base32, spaces and lower case are
  fine). Pasting a whole otpauth:// link into the key field fills in
  everything else. A key with a typo, such as a 0 where an O belongs or a
  character too many, is refused with the reason.
- SHA-1, SHA-256 and SHA-512; 6, 7 or 8 digits; any period from 1 to
  3600 seconds; the counter for counter-based codes.
- Tap a code to copy it. A ring shows how long the code has left and turns
  red for the last five seconds.
- A counter-based code is made only when asked ("Show code" / "Next
  code"), and the counter is saved before the code is shown.
- Touch and hold an account to edit or delete it. "Change the order" in
  the app menu puts Up and Down on the rows.
- The back gesture leaves the editor, closes a dialog and ends reordering.

## Screenshots

The accounts are the RFC 6238 and RFC 4226 test keys.

| mindphone (480x800) | | | Q25 (720x720) |
|---|---|---|---|
| ![Accounts](docs/screenshots/mindphone-accounts.png) | ![From a link](docs/screenshots/mindphone-from-link.png) | ![Edit and Delete](docs/screenshots/mindphone-menu.png) | ![Accounts](docs/screenshots/q25-accounts.png) |

## Where the accounts are kept

In the key manager (`com.palm.keymanager`), which encrypts what it stores
(AES-256-GCM under a device key, `/var/palm/keystore`) and keeps every
app's keys apart by the app id of the caller.

- Each account's key is stored under a name of its own
  (`otp.secret.<id>`), written once and never changed.
- Everything else (site, name, algorithm, digits, period, counter and the
  order) is in an index, also in the key manager. The key manager will not
  overwrite a key, so the index goes in turn to `otp.index.a` and
  `otp.index.b`, each with a generation number. The newer one counts; the
  other is the one before it, there if a write fails half way. A key is
  stored before the index that names it, and removed only after the index
  that drops it.
- If the key manager cannot be read when the app starts, the app says so
  and changes nothing: it never starts over with an empty list and writes
  that back.
- All keys are stored with `noexport`, so they stay on the device and are
  not part of a key manager backup. Moving to another device means adding
  the accounts again from the sites.

The site and account names are kept in the key manager rather than in
db8 or a settings file because they say which services the account
holder uses, and so that everything the app keeps is in one encrypted
place.

What this does not protect against: QML apps run as root, and the device
key sits next to the store, so anything running as root can read the
keys. A caller allowed to name another app id (`luna-send -a`) can fetch
that app's keys. The key manager in images up to now also writes stored
keys to the system log; a fix is on keymanager's
`herrie/no-key-material-in-logs` branch.

## Permissions

`requiredPermissions` in appinfo.json:

- `keymanager-service.operation`: store, fetch and remove keys.
- `application.launcher`: open the Camera from "Scan a QR code".
- `appmanager.management`: the application manager's handler table.

`"mimeTypes": [{ "scheme": "otpauth" }]` registers the app for
otpauth:// links; it is opened with `{"target": "otpauth://..."}`.

## Install for development

The app is QML and JavaScript only, so one package serves every device:

    tools/install.sh <adb serial>

It builds an "Architecture: all" ipk and installs it through
`com.webos.appInstallService`.

## Tests

    tools/run-tests.sh [path to luneos-components]

- `tests/js/run-node-tests.js` (Node): the published vectors (FIPS 180-4
  SHA-1/256/512, RFC 2202 and RFC 4231 HMAC, RFC 4226 HOTP, RFC 6238 TOTP
  with all three hashes, RFC 4648 Base32), each also recomputed with
  OpenSSL, then random inputs against OpenSSL: every message length from
  0 to 300 bytes, keys shorter and longer than the block, random counters
  and digits. Then otpauth:// parsing and the account checks.
- `tests/qml/tst_otp.qml` (qmltestrunner): the same vectors in QML's own
  JavaScript engine, the one the app runs in.
- `tests/qml/tst_ui.qml` (qmltestrunner, with luneos-components' desktop
  build and stand-ins): the app with `FakeKeyManager.qml` in place of the
  key manager, answering as the real one does. First start; RFC 6238
  codes shown end to end and following the clock; copying; adding typed
  and pasted keys; refused keys; duplicates; otpauth:// launches, also
  before the accounts are read; editing with and without a new key;
  deleting; reordering; counter-based codes; a key manager that refuses
  or never answers; the two index keys and a damaged one; a failed write;
  the back gesture; the app menu; the layout at 320x480, 480x800, 720x720
  and 1024x768.

`tools/mutation-check.sh` breaks the code in 21 ways, one at a time (the
hashes, the truncation, Base32, the index, the order of writes, the back
gesture and more), and checks that the tests fail for each.

On a device:

    [TAPS=1] [AWAKE=1] tools/test-device.sh <adb serial> <name>

It checks that otpauth:// links go to the app, puts the RFC test
accounts into the key manager, reads the codes off a screenshot with
tesseract and compares them with OpenSSL's for the device's time, opens a
link and checks the editor shows it, and with `TAPS=1` taps Save and
checks the key manager has the account. It removes its accounts at the
end and refuses to run where the app holds accounts of its own.

Passed on the Q25 (aarch64, without taps) on 2026-10-16. On the
mindphone (armv7, with taps) every check passed but the editor's, whose
screen reading missed the title; that check now also takes the
editor's "From a link" line, and has not been run there since.

## A recipe

A meta-webos-ports recipe would need what other QML apps have: install
appinfo.json, the icons, LICENSE and `qml/` to
`/usr/palm/applications/org.webosports.app.authenticator`, and luna-service2
role, manifest and client-permission files granting the groups above
(see Sound Recorder's `sysbus/`). It has nothing to build and no
architecture-specific files. RDEPENDS: qml-runner, luneos-components
(LuneOS.Forms, LuneOS.Components, LuneOS.Service, LuneOS.System), Qt
Quick Controls, Qt Quick Shapes and the key manager.

## Licence

GNU General Public License version 3; see LICENSE.

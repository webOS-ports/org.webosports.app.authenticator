#!/bin/bash
# Packs the app into an ipk and installs it through
# com.webos.appInstallService, as Preware does: opkg with its own root
# (/media/cryptofs/apps), so system packages are left alone, and the app's
# bus permissions come from requiredPermissions in appinfo.json. For
# development; a recipe does the real install.
#
#   tools/install.sh <adb serial> [build dir]
#
# The app is QML and JavaScript only, so one package serves every device.
set -e
cd "$(dirname "$0")/.."
SERIAL=${1:?usage: tools/install.sh <adb serial> [build dir]}
BUILD=${2:-build}
ADB="adb -s $SERIAL"

ID=$(python3 -I -c 'import json; print(json.load(open("appinfo.json"))["id"])')
VERSION=$(python3 -I -c 'import json; print(json.load(open("appinfo.json"))["version"])')

WORK=$BUILD/ipk
rm -rf "$WORK"
APP=$WORK/data/usr/palm/applications/$ID
mkdir -p "$WORK/control" "$APP"
cp -r appinfo.json icon.png icon-256x256.png LICENSE qml "$APP/"

cat > "$WORK/control/control" <<CONTROL
Package: $ID
Version: $VERSION
Section: misc
Priority: optional
Architecture: all
Installed-Size: $(du -sk "$WORK/data" | cut -f1)
Maintainer: Herman van Hazendonk <github.com@herrie.org>
Description: Authenticator
 One-time codes for two-step verification (TOTP and HOTP).
webOS-Package-Format-Version: 2
webOS-Packager-Version: x.y.x
CONTROL

echo "2.0" > "$WORK/debian-binary"
TAROPTS="--owner=0 --group=0 --numeric-owner --sort=name"
tar $TAROPTS -czf "$WORK/control.tar.gz" -C "$WORK/control" ./control
tar $TAROPTS -czf "$WORK/data.tar.gz" -C "$WORK/data" ./usr
IPK=${ID}_${VERSION}_all.ipk
rm -f "$BUILD/$IPK"
(cd "$WORK" && ar rc "../$IPK" debian-binary control.tar.gz data.tar.gz)
echo "built $BUILD/$IPK"

$ADB push "$BUILD/$IPK" /tmp/ >/dev/null
# luna-send prints nothing on an adb pipe; results go through a file.
$ADB shell "luna-send -w 90000 -i luna://com.webos.appInstallService/install '{\"id\":\"$ID\",\"ipkUrl\":\"/tmp/$IPK\",\"subscribe\":true}' > /tmp/auth-inst.out 2>&1 & P=\$!; \
    for i in \$(seq 1 60); do sleep 1; grep -qE '\"installed\"|failed|errorCode' /tmp/auth-inst.out && break; done; kill \$P 2>/dev/null; \
    rm -f /tmp/$IPK; grep -oE '\"state\":\"installed\"|errorText\":\"[^\"]*\"' /tmp/auth-inst.out | tail -n 1"

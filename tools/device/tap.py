#!/usr/bin/env python3
# Taps the touchscreen, for driving the app in tools/test-device.sh: writes
# a touch and its release straight into the touchscreen's event device, as
# the panel would (multi-touch protocol A, which the test devices' panels
# speak). Runs on the device.
#
#   python3 tap.py info                   the panel's ranges
#   python3 tap.py tap <x> <y> [hold ms]  in the panel's own coordinates
#   python3 tap.py swipe <x1> <y1> <x2> <y2> [ms]
import fcntl
import glob
import os
import struct
import sys
import time

EV_SYN, EV_KEY, EV_ABS = 0, 1, 3
SYN_REPORT, SYN_MT_REPORT = 0, 2
BTN_TOUCH = 0x14a
ABS_X, ABS_Y, ABS_PRESSURE = 0, 1, 0x18
ABS_MT_TOUCH_MAJOR, ABS_MT_POSITION_X, ABS_MT_POSITION_Y = 0x30, 0x35, 0x36
ABS_MT_TRACKING_ID, ABS_MT_PRESSURE = 0x39, 0x3a
# struct input_event: a timeval (two longs) and type, code, value.
EVENT = struct.Struct("llHHi")


def bits(path):
    # Hex words, the highest first, each an unsigned long.
    words = open(path).read().split()
    value = 0
    for w in words:
        value = (value << (8 * struct.calcsize("l"))) | int(w, 16)
    return value


def find_panel():
    for dev in sorted(glob.glob("/sys/class/input/event*")):
        abs_bits = bits(dev + "/device/capabilities/abs")
        if abs_bits >> ABS_MT_POSITION_X & 1 and abs_bits >> ABS_MT_POSITION_Y & 1:
            return "/dev/input/" + os.path.basename(dev), abs_bits, bits(dev + "/device/capabilities/key")
    sys.exit("no touchscreen")


def absinfo(fd, code):
    # EVIOCGABS(code): value, minimum, maximum, fuzz, flat, resolution
    request = (2 << 30) | (24 << 16) | (ord("E") << 8) | (0x40 + code)
    return struct.unpack("6i", fcntl.ioctl(fd, request, b"\0" * 24))


def main():
    path, abs_bits, key_bits = find_panel()
    fd = os.open(path, os.O_RDWR)
    if sys.argv[1] == "info":
        x, y = absinfo(fd, ABS_MT_POSITION_X), absinfo(fd, ABS_MT_POSITION_Y)
        print(path, "x", x[1], x[2], "y", y[1], y[2])
        return

    def emit(type_, code, value):
        now = time.time()
        os.write(fd, EVENT.pack(int(now), int(now % 1 * 1e6), type_, code, value))

    def touch(x, y, down):
        if down:
            emit(EV_ABS, ABS_MT_TRACKING_ID, 1)
            if abs_bits >> ABS_MT_TOUCH_MAJOR & 1:
                emit(EV_ABS, ABS_MT_TOUCH_MAJOR, 5)
            if abs_bits >> ABS_MT_PRESSURE & 1:
                emit(EV_ABS, ABS_MT_PRESSURE, 50)
            emit(EV_ABS, ABS_MT_POSITION_X, x)
            emit(EV_ABS, ABS_MT_POSITION_Y, y)
            emit(EV_SYN, SYN_MT_REPORT, 0)
            if key_bits >> BTN_TOUCH & 1:
                emit(EV_KEY, BTN_TOUCH, 1)
            if abs_bits >> ABS_X & 1:
                emit(EV_ABS, ABS_X, x)
                emit(EV_ABS, ABS_Y, y)
            if abs_bits >> ABS_PRESSURE & 1:
                emit(EV_ABS, ABS_PRESSURE, 50)
        else:
            emit(EV_SYN, SYN_MT_REPORT, 0)
            if key_bits >> BTN_TOUCH & 1:
                emit(EV_KEY, BTN_TOUCH, 0)
            if abs_bits >> ABS_PRESSURE & 1:
                emit(EV_ABS, ABS_PRESSURE, 0)
        emit(EV_SYN, SYN_REPORT, 0)

    if sys.argv[1] == "tap":
        x, y = int(sys.argv[2]), int(sys.argv[3])
        hold = int(sys.argv[4]) if len(sys.argv) > 4 else 80
        touch(x, y, True)
        end = time.time() + hold / 1000.0
        while time.time() < end:
            time.sleep(0.05)
            touch(x, y, True)
        touch(x, y, False)
    elif sys.argv[1] == "swipe":
        x1, y1, x2, y2 = (int(v) for v in sys.argv[2:6])
        ms = int(sys.argv[6]) if len(sys.argv) > 6 else 300
        steps = max(2, ms // 16)
        for i in range(steps + 1):
            touch(x1 + (x2 - x1) * i // steps, y1 + (y2 - y1) * i // steps, True)
            time.sleep(ms / 1000.0 / steps)
        touch(x2, y2, False)


main()

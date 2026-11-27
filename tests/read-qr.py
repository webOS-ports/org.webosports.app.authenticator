#!/usr/bin/env python3
# Copyright 2026 Herman van Hazendonk <github.com@herrie.org>
# SPDX-License-Identifier: GPL-3.0-only
#
# Prints the text of every QR code zbar finds in each picture, one JSON
# list per picture, for tests/js/read-qr-shots.js. Needs libzbar (through
# ctypes, no Python binding) and PIL; exits 77 when either is missing.
#
#   tests/read-qr.py picture.png ...
import ctypes
import ctypes.util
import json
import sys

try:
    from PIL import Image
except ImportError:
    print("PIL is missing", file=sys.stderr)
    sys.exit(77)
name = ctypes.util.find_library("zbar")
if not name:
    print("libzbar is missing", file=sys.stderr)
    sys.exit(77)
zbar = ctypes.CDLL(name)
for f, res, args in [
        ("zbar_image_scanner_create", ctypes.c_void_p, []),
        ("zbar_image_scanner_set_config", ctypes.c_int, [ctypes.c_void_p, ctypes.c_int, ctypes.c_int, ctypes.c_int]),
        ("zbar_image_scanner_destroy", None, [ctypes.c_void_p]),
        ("zbar_image_create", ctypes.c_void_p, []),
        ("zbar_image_destroy", None, [ctypes.c_void_p]),
        ("zbar_image_set_format", None, [ctypes.c_void_p, ctypes.c_ulong]),
        ("zbar_image_set_size", None, [ctypes.c_void_p, ctypes.c_uint, ctypes.c_uint]),
        ("zbar_image_set_data", None, [ctypes.c_void_p, ctypes.c_void_p, ctypes.c_ulong, ctypes.c_void_p]),
        ("zbar_scan_image", ctypes.c_int, [ctypes.c_void_p, ctypes.c_void_p]),
        ("zbar_image_first_symbol", ctypes.c_void_p, [ctypes.c_void_p]),
        ("zbar_symbol_next", ctypes.c_void_p, [ctypes.c_void_p]),
        ("zbar_symbol_get_data", ctypes.c_void_p, [ctypes.c_void_p]),
        ("zbar_symbol_get_data_length", ctypes.c_uint, [ctypes.c_void_p])]:
    getattr(zbar, f).restype = res
    getattr(zbar, f).argtypes = args

Y800 = ord("Y") | ord("8") << 8 | ord("0") << 16 | ord("0") << 24
ZBAR_NONE, ZBAR_CFG_ENABLE = 0, 0


def read(path):
    picture = Image.open(path).convert("L")
    data = picture.tobytes()
    buffer = ctypes.create_string_buffer(data, len(data))
    scanner = zbar.zbar_image_scanner_create()
    zbar.zbar_image_scanner_set_config(scanner, ZBAR_NONE, ZBAR_CFG_ENABLE, 1)
    image = zbar.zbar_image_create()
    zbar.zbar_image_set_format(image, Y800)
    zbar.zbar_image_set_size(image, picture.width, picture.height)
    zbar.zbar_image_set_data(image, ctypes.cast(buffer, ctypes.c_void_p), len(data), None)
    texts = []
    if zbar.zbar_scan_image(scanner, image) > 0:
        symbol = zbar.zbar_image_first_symbol(image)
        while symbol:
            texts.append(ctypes.string_at(zbar.zbar_symbol_get_data(symbol),
                                          zbar.zbar_symbol_get_data_length(symbol)).decode("utf-8", "replace"))
            symbol = zbar.zbar_symbol_next(symbol)
    zbar.zbar_image_destroy(image)
    zbar.zbar_image_scanner_destroy(scanner)
    return texts


for path in sys.argv[1:]:
    print(json.dumps(read(path)))

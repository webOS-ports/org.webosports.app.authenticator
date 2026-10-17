#!/usr/bin/env python3
# (c) 2026 Herman van Hazendonk <github.com@herrie.org>
# SPDX-License-Identifier: GPL-3.0-only
#
# Draws the icon designs considered for Authenticator, in the legacy app icon
# style (an object on the translucent app plate), into tools/icon/variants/.
# images/icon.svg is the chosen one, D3a-lock-numbers.
#
#   python3 tools/icon/make-variants.py
#
# No SVG filters anywhere: Qt's renderer, which the launcher uses, has none,
# so every shadow is one gradient.
import math
import os

class Svg:
    def __init__(s): s.defs=[]; s.body=[]; s.n=0
    def id(s,p): s.n+=1; return f"{p}{s.n}"
    def lin(s,stops,x1=0,y1=0,x2=0,y2=1):
        i=s.id("l"); st="".join(f'<stop offset="{o}" stop-color="{c}" stop-opacity="{a}"/>' for o,c,a in stops)
        s.defs.append(f'<linearGradient id="{i}" x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}">{st}</linearGradient>'); return f"url(#{i})"
    def rad(s,stops,cx,cy,r,fx=None,fy=None,user=True):
        i=s.id("r"); st="".join(f'<stop offset="{o}" stop-color="{c}" stop-opacity="{a}"/>' for o,c,a in stops)
        f=f' fx="{fx}" fy="{fy}"' if fx is not None else ""
        s.defs.append(f'<radialGradient id="{i}" cx="{cx}" cy="{cy}" r="{r}"{f} gradientUnits="userSpaceOnUse">{st}</radialGradient>'); return f"url(#{i})"
    def add(s,x): s.body.append(x)
    def out(s):
        body=s.body[:4]+['<g transform="translate(128 126) scale(1.14) translate(-128 -128)">']+s.body[4:]+['</g>']
        return ('<svg xmlns="http://www.w3.org/2000/svg" width="256" height="256" viewBox="0 0 256 256">\n<defs>'
                        + "".join(s.defs) + "</defs>\n" + "\n".join(body) + "\n</svg>\n")
def plate(s):
    # The legacy app plate: translucent white, brightest at the top, a faint dark rim.
    s.add(f'<circle cx="128" cy="129" r="121" fill="{s.rad([(0.93,"#000",0),(0.975,"#000",0.16),(1,"#000",0)],128,129,121)}"/>')
    s.add(f'<circle cx="128" cy="128" r="117" fill="{s.lin([(0,"#fff",0.5),(0.38,"#fff",0.2),(0.62,"#fff",0.03),(1,"#fff",0.06)])}"/>')
    s.add(f'<circle cx="128" cy="128" r="117" fill="{s.rad([(0.55,"#fff",0),(1,"#fff",0.22)],128,128,117)}"/>')
    s.add('<circle cx="128" cy="128" r="117" fill="none" stroke="#000" stroke-opacity="0.13" stroke-width="1.5"/>')
def ground_shadow(s,cx,cy,rx,ry,a=0.32):
    s.add(f'<ellipse cx="{cx}" cy="{cy}" rx="{rx}" ry="{ry}" fill="{s.rad([(0,"#000",a),(1,"#000",0)],cx,cy,rx)}" transform="translate({cx} {cy}) scale(1 {ry/rx}) translate({-cx} {-cy})"/>'.replace(f'rx="{rx}" ry="{ry}"',f'rx="{rx}" ry="{rx}"'))

# --- First round: a code token, a padlock with a code window, a dial ---

SEG = {  # seven segments a..g
    "0": "abcdef", "1": "bc", "2": "abged", "3": "abgcd", "4": "fgbc", "5": "afgcd",
    "6": "afgedc", "7": "abc", "8": "abcdefg", "9": "abcdfg"}
def digit(s, x, y, w, h, ch, on, off, t=None):
    t = t or w * 0.2
    segs = {
        "a": (x + t * 0.6, y, w - t * 1.2, t, 0), "d": (x + t * 0.6, y + h - t, w - t * 1.2, t, 0),
        "g": (x + t * 0.6, y + h / 2 - t / 2, w - t * 1.2, t, 0),
        "f": (x, y + t * 0.6, t, h / 2 - t * 0.9, 1), "b": (x + w - t, y + t * 0.6, t, h / 2 - t * 0.9, 1),
        "e": (x, y + h / 2 + t * 0.3, t, h / 2 - t * 0.9, 1), "c": (x + w - t, y + h / 2 + t * 0.3, t, h / 2 - t * 0.9, 1)}
    for k, (sx, sy, sw, sh, v) in segs.items():
        c = on if k in SEG[ch] else off
        s.add(f'<rect x="{sx:.2f}" y="{sy:.2f}" width="{sw:.2f}" height="{sh:.2f}" rx="{min(sw, sh) / 2:.2f}" fill="{c}" transform="skewX(-6)" />')
def lcd(s, x, y, w, h, text, digits_h):
    s.add(f'<rect x="{x - 3}" y="{y - 3}" width="{w + 6}" height="{h + 6}" rx="7" fill="{s.lin([(0, "#1b1d20", 1), (1, "#4a4e55", 1)])}"/>')
    s.add(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="5" fill="{s.lin([(0, "#b9c7a3", 1), (1, "#97a882", 1)])}"/>')
    s.add(f'<rect x="{x}" y="{y}" width="{w}" height="{h * 0.45}" rx="5" fill="{s.lin([(0, "#000", 0.16), (1, "#000", 0)])}"/>')
    n = len(text.replace(" ", "")); gaps = text.count(" ")
    dw = digits_h * 0.5; sp = dw * 0.28; total = n * dw + (n - 1) * sp + gaps * dw * 0.5
    xx = x + (w - total) / 2 + 3; yy = y + (h - digits_h) / 2
    for ch in text:
        if ch == " ": xx += dw * 0.5; continue
        digit(s, xx, yy, dw, digits_h, ch, "#23281e", "#000000" if False else "#a6b590")
        xx += dw + sp

def concept_token():
    s = Svg(); plate(s); ground_shadow(s, 128, 220, 96, 12)
    # A key-fob token: dark plastic body, a ring hole, an LCD and a countdown bar.
    s.add('<g transform="translate(10 0) scale(0.93) translate(9 9) rotate(-8 128 128)">')
    body = s.lin([(0, "#5d6168", 1), (0.5, "#33363b", 1), (1, "#1e2024", 1)])
    s.add(f'<path d="M40,92 Q40,70 62,70 H196 Q222,70 224,96 V164 Q222,190 196,190 H62 Q40,190 40,168 Z" fill="{body}" stroke="#141518" stroke-width="1.5"/>')
    s.add(f'<path d="M44,92 Q44,74 62,74 H196 Q218,74 220,96" fill="none" stroke="#fff" stroke-opacity="0.28" stroke-width="2"/>')
    # ring loop on the left
    s.add(f'<circle cx="34" cy="130" r="20" fill="none" stroke="{s.lin([(0, "#e8eaed", 1), (1, "#8d939b", 1)])}" stroke-width="7"/>')
    s.add(f'<circle cx="54" cy="130" r="9" fill="#1a1c1f" stroke="#0e0f11" stroke-width="1"/>')
    lcd(s, 72, 98, 136, 50, "482913", 30)
    # countdown: segments along the bottom, partly drained
    for i in range(10):
        on = i < 6
        s.add(f'<rect x="{78 + i * 12.6:.1f}" y="160" width="9" height="9" rx="2" fill="{"#7fd36a" if on else "#3b3f45"}"/>')
    s.add('</g>')
    return s.out()

def concept_padlock():
    s = Svg(); plate(s); ground_shadow(s, 128, 222, 86, 12)
    s.add('<g transform="translate(0 6)">')
    shackle = s.lin([(0, "#f2f4f6", 1), (0.5, "#a9b0b8", 1), (1, "#6e757e", 1)], 0, 0, 1, 0)
    s.add(f'<path d="M78,118 V84 a50,50 0 0 1 100,0 V118" fill="none" stroke="#5b6168" stroke-width="24"/>')
    s.add(f'<path d="M78,118 V84 a50,50 0 0 1 100,0 V118" fill="none" stroke="{shackle}" stroke-width="20"/>')
    brass = s.lin([(0, "#f6d77a", 1), (0.45, "#d8a93c", 1), (1, "#a8741e", 1)])
    s.add(f'<rect x="50" y="110" width="156" height="112" rx="18" fill="{brass}" stroke="#8a5d14" stroke-width="2"/>')
    s.add(f'<rect x="56" y="115" width="144" height="30" rx="14" fill="{s.lin([(0, "#fff", 0.45), (1, "#fff", 0)])}"/>')
    lcd(s, 70, 132, 116, 40, "482913", 24)
    # six dots draining: the seconds left for this code
    for i in range(6):
        cx = 88 + i * 16
        s.add(f'<circle cx="{cx}" cy="196" r="5.5" fill="{"#3a2a0c" if i < 4 else "#c99a3c"}" stroke="#8a5d14" stroke-width="1"/>')
    s.add('</g>')
    return s.out()

def concept_dial():
    s = Svg(); plate(s); ground_shadow(s, 128, 220, 90, 12)
    # countdown arc behind the dial
    s.add(f'<circle cx="128" cy="124" r="96" fill="none" stroke="#2c3036" stroke-opacity="0.35" stroke-width="12"/>')
    a0, a1 = -90, -90 + 250
    def pt(a, r): return 128 + r * math.cos(math.radians(a)), 124 + r * math.sin(math.radians(a))
    x0, y0 = pt(a0, 96); x1, y1 = pt(a1, 96)
    s.add(f'<path d="M{x0:.1f},{y0:.1f} A96,96 0 1 1 {x1:.1f},{y1:.1f}" fill="none" stroke="{s.lin([(0, "#6fd05c", 1), (1, "#2f9a3a", 1)])}" stroke-width="12" stroke-linecap="round"/>')
    chrome = s.rad([(0, "#fbfcfd", 1), (0.6, "#c7ccd2", 1), (1, "#7d848c", 1)], 112, 100, 110)
    s.add(f'<circle cx="128" cy="124" r="82" fill="{chrome}" stroke="#5d646c" stroke-width="2"/>')
    s.add(f'<circle cx="128" cy="124" r="66" fill="{s.lin([(0, "#3a3e44", 1), (1, "#15171a", 1)])}"/>')
    for i in range(60):
        a = -90 + i * 6; long = i % 5 == 0
        xa, ya = pt(a, 64); xb, yb = pt(a, 54 if long else 59)
        s.add(f'<line x1="{xa:.1f}" y1="{ya:.1f}" x2="{xb:.1f}" y2="{yb:.1f}" stroke="#e9ecef" stroke-width="{2.2 if long else 1.2}"/>')
    s.add(f'<circle cx="128" cy="124" r="40" fill="{s.rad([(0, "#f5f6f8", 1), (1, "#9aa1a9", 1)], 118, 112, 48)}" stroke="#4d535a" stroke-width="1.5"/>')
    s.add(f'<path d="M128,62 l-7,-14 h14 Z" fill="#d23b2e"/>')
    s.add(f'<rect x="124" y="92" width="8" height="26" rx="4" fill="#4d535a"/>')
    return s.out()


# --- Second round: the dial as a lock, on a safe, numbered; today's icon redrawn ---

def pt(cx, cy, a, r): return cx + r * math.cos(math.radians(a)), cy + r * math.sin(math.radians(a))

def dial_first(s, cx, cy, R, numbers=False, metal="chrome"):
    if metal == "chrome":
        rim = s.rad([(0, "#fbfcfd", 1), (0.6, "#c7ccd2", 1), (1, "#7d848c", 1)], cx - R * 0.2, cy - R * 0.3, R * 1.35)
        knob = s.rad([(0, "#f5f6f8", 1), (1, "#9aa1a9", 1)], cx - R * 0.12, cy - R * 0.15, R * 0.6)
    else:
        rim = s.rad([(0, "#fbe7a6", 1), (0.6, "#d4a541", 1), (1, "#8d6118", 1)], cx - R * 0.2, cy - R * 0.3, R * 1.35)
        knob = s.rad([(0, "#fff1c2", 1), (1, "#b78630", 1)], cx - R * 0.12, cy - R * 0.15, R * 0.6)
    s.add(f'<circle cx="{cx}" cy="{cy}" r="{R}" fill="{rim}" stroke="#5d646c" stroke-width="2"/>')
    face = R * 0.8
    s.add(f'<circle cx="{cx}" cy="{cy}" r="{face}" fill="{s.lin([(0, "#3a3e44", 1), (1, "#15171a", 1)])}"/>')
    for i in range(40 if numbers else 60):
        step = 9 if numbers else 6
        a = -90 + i * step; long = (i % 5 == 0)
        xa, ya = pt(cx, cy, a, face - 2); xb, yb = pt(cx, cy, a, face - (11 if long else 6))
        s.add(f'<line x1="{xa:.1f}" y1="{ya:.1f}" x2="{xb:.1f}" y2="{yb:.1f}" stroke="#e9ecef" stroke-width="{2.2 if long else 1.2}"/>')
        if numbers and long:
            xt, yt = pt(cx, cy, a, face - 20)
            s.add(f'<text x="{xt:.1f}" y="{yt + 3.5:.1f}" font-family="Prelude, Helvetica, Arial, sans-serif" font-size="{R * 0.13:.1f}" font-weight="bold" fill="#e9ecef" text-anchor="middle">{i * 9 // 9 * 1 if False else (i // 5) * 10}</text>')
    kr = R * (0.36 if numbers else 0.48)
    s.add(f'<circle cx="{cx}" cy="{cy}" r="{kr}" fill="{knob}" stroke="#4d535a" stroke-width="1.5"/>')
    s.add(f'<rect x="{cx - R * 0.05}" y="{cy - kr * 0.8}" width="{R * 0.1}" height="{kr * 0.6}" rx="{R * 0.05}" fill="#4d535a"/>')
    s.add(f'<path d="M{cx},{cy - R + 4} l{-R * 0.085},{-R * 0.17} h{R * 0.17} Z" fill="#d23b2e"/>')

def countdown_first(s, cx, cy, r, w, frac=250 / 360):
    s.add(f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="none" stroke="#2c3036" stroke-opacity="0.35" stroke-width="{w}"/>')
    x0, y0 = pt(cx, cy, -90, r); x1, y1 = pt(cx, cy, -90 + 360 * frac, r)
    s.add(f'<path d="M{x0:.1f},{y0:.1f} A{r},{r} 0 {1 if frac > 0.5 else 0} 1 {x1:.1f},{y1:.1f}" fill="none" stroke="{s.lin([(0, "#6fd05c", 1), (1, "#2f9a3a", 1)])}" stroke-width="{w}" stroke-linecap="round"/>')

def d1_combination_padlock():
    s = Svg(); plate(s); ground_shadow(s, 128, 224, 84, 12)
    shackle = s.lin([(0, "#f2f4f6", 1), (0.5, "#a9b0b8", 1), (1, "#6e757e", 1)], 0, 0, 1, 0)
    s.add(f'<path d="M86,120 V78 a42,42 0 0 1 84,0 V120" fill="none" stroke="#5b6168" stroke-width="22"/>')
    s.add(f'<path d="M86,120 V78 a42,42 0 0 1 84,0 V120" fill="none" stroke="{shackle}" stroke-width="18"/>')
    dial_first(s, 128, 150, 74)
    return s.out()

def d2_safe_door():
    s = Svg(); plate(s); ground_shadow(s, 128, 226, 96, 12)
    steel = s.lin([(0, "#8a929b", 1), (0.5, "#5c636b", 1), (1, "#3c4248", 1)])
    s.add(f'<rect x="34" y="34" width="188" height="188" rx="18" fill="{steel}" stroke="#2a2e33" stroke-width="2"/>')
    s.add(f'<rect x="44" y="44" width="168" height="168" rx="12" fill="none" stroke="#fff" stroke-opacity="0.18" stroke-width="2"/>')
    for x, y in ((50, 50), (206, 50), (50, 206), (206, 206)):
        s.add(f'<circle cx="{x}" cy="{y}" r="5" fill="{s.rad([(0, "#e3e6ea", 1), (1, "#6d747c", 1)], x - 1.5, y - 1.5, 6)}"/>')
    dial_first(s, 112, 128, 62)
    # handle
    s.add(f'<rect x="184" y="98" width="16" height="60" rx="8" fill="{s.lin([(0, "#f0f2f4", 1), (1, "#8b9199", 1)], 0, 0, 1, 0)}" stroke="#4d535a" stroke-width="1.5"/>')
    s.add(f'<rect x="174" y="122" width="14" height="12" rx="3" fill="#4d535a"/>')
    return s.out()

def d3_numbered():
    s = Svg(); plate(s); ground_shadow(s, 128, 222, 90, 12)
    countdown_first(s, 128, 126, 98, 12)
    dial_first(s, 128, 126, 84, numbers=True)
    return s.out()

def padlock_first(s, cx, cy, sc, metal="chrome"):
    w, h = 80 * sc, 62 * sc; r = 26 * sc; sw = 13 * sc
    shk = s.lin([(0, "#f2f4f6", 1), (0.5, "#a9b0b8", 1), (1, "#6e757e", 1)], 0, 0, 1, 0)
    top = cy - h / 2
    s.add(f'<path d="M{cx - r},{top + 4} V{top - 6 * sc} a{r},{r} 0 0 1 {2 * r},0 V{top + 4}" fill="none" stroke="#5b6168" stroke-width="{sw + 3}"/>')
    s.add(f'<path d="M{cx - r},{top + 4} V{top - 6 * sc} a{r},{r} 0 0 1 {2 * r},0 V{top + 4}" fill="none" stroke="{shk}" stroke-width="{sw}"/>')
    body = s.lin([(0, "#fbfcfd", 1), (0.5, "#d3d8de", 1), (1, "#9aa2ab", 1)])
    s.add(f'<rect x="{cx - w / 2}" y="{top}" width="{w}" height="{h}" rx="{9 * sc}" fill="{body}" stroke="#6b737c" stroke-width="1.5"/>')
    s.add(f'<rect x="{cx - w / 2 + 4}" y="{top + 3}" width="{w - 8}" height="{h * 0.3}" rx="{7 * sc}" fill="{s.lin([(0, "#fff", 0.7), (1, "#fff", 0)])}"/>')
    s.add(f'<circle cx="{cx}" cy="{top + h * 0.45}" r="{8 * sc}" fill="#2d3238"/>')
    s.add(f'<path d="M{cx - 3.5 * sc},{top + h * 0.5} L{cx - 5 * sc},{top + h * 0.78} H{cx + 5 * sc} L{cx + 3.5 * sc},{top + h * 0.5} Z" fill="#2d3238"/>')

def o1_plate():
    s = Svg(); plate(s); ground_shadow(s, 128, 220, 84, 11)
    ring = s.lin([(0, "#5aa5ee", 1), (1, "#1f5fae", 1)])
    s.add(f'<circle cx="128" cy="126" r="90" fill="none" stroke="#163f73" stroke-width="22"/>')
    s.add(f'<circle cx="128" cy="126" r="90" fill="none" stroke="{ring}" stroke-width="18"/>')
    x0, y0 = pt(128, 126, -90, 90); x1, y1 = pt(128, 126, -90 + 290, 90)
    s.add(f'<path d="M{x0:.1f},{y0:.1f} A90,90 0 1 1 {x1:.1f},{y1:.1f}" fill="none" stroke="#ffffff" stroke-width="8" stroke-linecap="round"/>')
    padlock_first(s, 128, 140, 1.25)
    return s.out()

def o2_badge():
    s = Svg(); ground_shadow(s, 128, 232, 104, 12, a=0.4)
    s.add(f'<circle cx="128" cy="128" r="116" fill="{s.rad([(0, "#f4f6f8", 1), (0.7, "#b8bfc7", 1), (1, "#6f7780", 1)], 104, 92, 150)}" stroke="#4f565e" stroke-width="2"/>')
    s.add(f'<circle cx="128" cy="128" r="102" fill="{s.rad([(0, "#4f9be8", 1), (0.7, "#2a6dbd", 1), (1, "#1a4c8c", 1)], 116, 96, 130)}"/>')
    s.add(f'<circle cx="128" cy="128" r="101" fill="none" stroke="#0f325e" stroke-width="2"/>')
    x0, y0 = pt(128, 128, -90, 84); x1, y1 = pt(128, 128, -90 + 290, 84)
    s.add(f'<circle cx="128" cy="128" r="84" fill="none" stroke="#ffffff" stroke-opacity="0.22" stroke-width="10"/>')
    s.add(f'<path d="M{x0:.1f},{y0:.1f} A84,84 0 1 1 {x1:.1f},{y1:.1f}" fill="none" stroke="#ffffff" stroke-width="10" stroke-linecap="round"/>')
    padlock_first(s, 128, 142, 1.2)
    return s.out()


# --- Third round: variations on the combination padlock (D1) and the numbered dial (D3) ---

METAL = {"chrome": [("#fbfcfd", "#c7ccd2", "#7d848c"), ("#f5f6f8", "#9aa1a9"), "#5d646c"],
         "brass": [("#fbe7a6", "#d4a541", "#8d6118"), ("#fff1c2", "#b78630"), "#7a5414"]}
FACE = {"black": ("#3a3e44", "#15171a", "#e9ecef"), "blue": ("#3f86d8", "#16457e", "#ffffff")}
ARC = {"green": ("#6fd05c", "#2f9a3a"), "blue": ("#64b0f2", "#1f63b5")}

def dial(s, cx, cy, R, metal="chrome", face="black", labels=False, big=False):
    (r0, r1, r2), (k0, k1), edge = METAL[metal]; f0, f1, ink = FACE[face]
    s.add(f'<circle cx="{cx}" cy="{cy}" r="{R}" fill="{s.rad([(0, r0, 1), (0.6, r1, 1), (1, r2, 1)], cx - R * 0.2, cy - R * 0.3, R * 1.35)}" stroke="{edge}" stroke-width="2"/>')
    fr = R * 0.8
    s.add(f'<circle cx="{cx}" cy="{cy}" r="{fr}" fill="{s.lin([(0, f0, 1), (1, f1, 1)])}"/>')
    n = 40 if labels else 60
    for i in range(n):
        a = -90 + i * 360 / n; long = i % 5 == 0
        xa, ya = pt(cx, cy, a, fr - 2); xb, yb = pt(cx, cy, a, fr - (R * 0.13 if long else R * 0.07))
        s.add(f'<line x1="{xa:.1f}" y1="{ya:.1f}" x2="{xb:.1f}" y2="{yb:.1f}" stroke="{ink}" stroke-width="{R * 0.028 if long else R * 0.015:.2f}"/>')
        if labels and long:
            fs = R * (0.17 if big else 0.13)
            xt, yt = pt(cx, cy, a, fr - R * (0.27 if big else 0.24))
            s.add(f'<text x="{xt:.1f}" y="{yt + fs * 0.36:.1f}" font-family="Prelude, Helvetica, Arial, sans-serif" font-size="{fs:.1f}" font-weight="bold" fill="{ink}" text-anchor="middle">{i}</text>')
    kr = R * (0.34 if labels else 0.48)
    s.add(f'<circle cx="{cx}" cy="{cy}" r="{kr}" fill="{s.rad([(0, k0, 1), (1, k1, 1)], cx - R * 0.12, cy - R * 0.15, R * 0.6)}" stroke="{edge}" stroke-width="1.5"/>')
    s.add(f'<rect x="{cx - R * 0.05}" y="{cy - kr * 0.8}" width="{R * 0.1}" height="{kr * 0.6}" rx="{R * 0.05}" fill="{edge}"/>')
    s.add(f'<path d="M{cx},{cy - R + 4} l{-R * 0.085},{-R * 0.17} h{R * 0.17} Z" fill="#d23b2e"/>')

def arc(s, cx, cy, r, w, col="green", frac=250 / 360, segments=0):
    a0, a1 = ARC[col]; g = s.lin([(0, a0, 1), (1, a1, 1)])
    if segments:
        for i in range(segments):
            on = i < round(segments * frac)
            aa = -90 + i * 360 / segments + 2; ab = aa + 360 / segments - 4
            x0, y0 = pt(cx, cy, aa, r); x1, y1 = pt(cx, cy, ab, r)
            s.add(f'<path d="M{x0:.1f},{y0:.1f} A{r},{r} 0 0 1 {x1:.1f},{y1:.1f}" fill="none" stroke="{g if on else "#2c3036"}" stroke-opacity="{1 if on else 0.3}" stroke-width="{w}"/>')
        return
    s.add(f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="none" stroke="#2c3036" stroke-opacity="0.35" stroke-width="{w}"/>')
    x0, y0 = pt(cx, cy, -90, r); x1, y1 = pt(cx, cy, -90 + 360 * frac, r)
    s.add(f'<path d="M{x0:.1f},{y0:.1f} A{r},{r} 0 {1 if frac > 0.5 else 0} 1 {x1:.1f},{y1:.1f}" fill="none" stroke="{g}" stroke-width="{w}" stroke-linecap="round"/>')

def padlock_dial(metal="chrome", face="black", labels=False, with_arc=False):
    s = Svg(); plate(s); ground_shadow(s, 128, 224, 84, 12)
    shk = s.lin([(0, "#f2f4f6", 1), (0.5, "#a9b0b8", 1), (1, "#6e757e", 1)], 0, 0, 1, 0)
    s.add(f'<path d="M86,120 V78 a42,42 0 0 1 84,0 V120" fill="none" stroke="#5b6168" stroke-width="22"/>')
    s.add(f'<path d="M86,120 V78 a42,42 0 0 1 84,0 V120" fill="none" stroke="{shk}" stroke-width="18"/>')
    R = 66 if with_arc else 74
    if with_arc: arc(s, 128, 150, 78, 9)
    dial(s, 128, 150, R, metal, face, labels)
    return s.out()

def numbered(metal="chrome", face="black", col="green", segments=0, big=True):
    s = Svg(); plate(s); ground_shadow(s, 128, 222, 90, 12)
    arc(s, 128, 126, 98, 12, col, segments=segments)
    dial(s, 128, 126, 84, metal, face, labels=True, big=big)
    return s.out()

VARIANTS = [
    ("D1a-brass", lambda: padlock_dial(metal="brass")),
    ("D1b-countdown", lambda: padlock_dial(with_arc=True)),
    ("D1c-numbers", lambda: padlock_dial(labels=True)),
    ("D1d-blue-face", lambda: padlock_dial(face="blue")),
    ("D3a-lock-numbers", lambda: numbered()),
    ("D3b-brass-blue-arc", lambda: numbered(metal="brass", col="blue")),
    ("D3c-blue-face", lambda: numbered(face="blue")),
    ("D3d-segments", lambda: numbered(segments=30)),
]

VARIANTS = [
    ("1-token", concept_token), ("2-padlock", concept_padlock), ("3-dial", concept_dial),
    ("D1-combination-padlock", d1_combination_padlock), ("D2-safe-door", d2_safe_door),
    ("D3-numbered-dial", d3_numbered), ("O1-ring-on-plate", o1_plate), ("O2-enamel-badge", o2_badge),
] + VARIANTS

if __name__ == "__main__":
    out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "variants")
    os.makedirs(out, exist_ok=True)
    for n, f in VARIANTS:
        with open(os.path.join(out, n + ".svg"), "w") as fh:
            fh.write("<!-- Authenticator icon design " + n + ", on the app plate.\n"
                     "     Copyright 2026 Herman van Hazendonk <github.com@herrie.org>\n"
                     "     SPDX-License-Identifier: GPL-3.0-only\n"
                     "     Drawn by tools/icon/make-variants.py. -->\n" + f())

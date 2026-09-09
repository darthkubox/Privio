#!/usr/bin/env python3
"""Generuje semantyczne color-sety w Assets.xcassets (light + dark).
Uruchamiane raz przy scaffoldingu; katalog jest źródłem prawdy kolorów Privio.
Paleta bazowa wg Instrukcja.md sekcja 21."""
import json, os

ASSETS = os.path.join(os.path.dirname(__file__), "..",
                      "Sources/PrivioApp/Resources/Assets.xcassets")

def comp(hexstr):
    h = hexstr.lstrip("#")
    return {"red": f"0x{h[0:2].upper()}",
            "green": f"0x{h[2:4].upper()}",
            "blue": f"0x{h[4:6].upper()}",
            "alpha": "1.000"}

def colorset(light, dark):
    return {
        "colors": [
            {"idiom": "universal",
             "color": {"color-space": "srgb", "components": comp(light)}},
            {"idiom": "universal",
             "appearances": [{"appearance": "luminosity", "value": "dark"}],
             "color": {"color-space": "srgb", "components": comp(dark)}},
        ],
        "info": {"author": "xcode", "version": 1},
    }

# nazwa -> (light, dark)
COLORS = {
    "AccentColor":            ("#146EF5", "#3185FF"),
    "PrivioPrimary":          ("#146EF5", "#3185FF"),
    "PrivioBright":           ("#3185FF", "#5AA0FF"),
    "PrivioDeep":             ("#073B8C", "#0A2A6E"),
    "PrivioBackground":       ("#F5F8FD", "#0B101F"),
    "PrivioBackgroundRaised": ("#ECF1FA", "#11182B"),
    "PrivioSurface":          ("#FFFFFF", "#151D32"),
    "PrivioSurfaceSelected":  ("#E8F0FE", "#1C2742"),
    "PrivioSeparator":        ("#E2E8F2", "#242F4A"),
    "PrivioTextPrimary":      ("#071A3D", "#ECF1FB"),
    "PrivioTextSecondary":    ("#64748C", "#93A4C2"),
    "PrivioTextTertiary":     ("#8A98AE", "#66748F"),
    "PrivioUnlocked":         ("#1F9D55", "#3BD17A"),
    "PrivioLockedTint":       ("#64748C", "#93A4C2"),
    "PrivioDanger":           ("#E53E3E", "#FF6B6B"),
    "PrivioIconTop":          ("#3E8BFF", "#3E8BFF"),
    "PrivioIconBottom":       ("#0E52D6", "#0E52D6"),
    "PrivioAuthCardTop":      ("#0A2A6E", "#0A2A6E"),
    "PrivioAuthCardBottom":   ("#05122E", "#05122E"),
}

os.makedirs(ASSETS, exist_ok=True)
# root Contents.json
with open(os.path.join(ASSETS, "Contents.json"), "w") as f:
    json.dump({"info": {"author": "xcode", "version": 1}}, f, indent=2)

for name, (light, dark) in COLORS.items():
    d = os.path.join(ASSETS, f"{name}.colorset")
    os.makedirs(d, exist_ok=True)
    with open(os.path.join(d, "Contents.json"), "w") as f:
        json.dump(colorset(light, dark), f, indent=2)

print(f"Wygenerowano {len(COLORS)} color-setów w {os.path.relpath(ASSETS)}")

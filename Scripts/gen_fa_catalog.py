#!/usr/bin/env python3
"""Generuje Sources/PrivioApp/UI/Components/FontAwesomeCatalog.swift.

Mapuje nazwy symboli SF używane w UI na glify **Font Awesome Free 6.7.2**
(styl Solid, oprócz marek). Katalog tłumaczy SF→FA w miejscu renderowania
(`FAIcon`), więc producenci nazw (enumy/modele) pozostają bez zmian.

Wymaga metadanych Font Awesome `icons.json` w wersji 6.7.2:

    curl -sSL -o /tmp/fa-icons.json \\
      https://raw.githubusercontent.com/FortAwesome/Font-Awesome/6.7.2/metadata/icons.json
    python3 Scripts/gen_fa_catalog.py /tmp/fa-icons.json

Każda wybrana ikona MUSI mieć styl w wersji Free (skrypt to weryfikuje) -
nie używamy ikon Pro. Licencja: Font Awesome Free (CC BY 4.0 / OFL 1.1 / MIT);
zob. THIRD-PARTY-NOTICES.md i Resources/Fonts/LICENSE-FontAwesome.txt.
"""
import json, sys, os

# SF Symbol name -> Font Awesome canonical name (Free).
MAPPING = {
    "lock.fill": "lock", "lock.open.fill": "lock-open",
    "lock.open.trianglebadge.exclamationmark": "lock-open",
    "lock.app.dashed": "lock", "lock.rectangle.dashed": "lock",
    "lock.rectangle.stack.fill": "vault", "lock.rotation": "arrows-rotate",
    "checkmark.shield.fill": "shield-halved", "checkmark.shield": "shield-halved",
    "shield.slash.fill": "ban", "exclamationmark.shield.fill": "shield-halved",
    "bolt.shield": "shield-halved", "checkmark.seal.fill": "circle-check",
    "exclamationmark.triangle.fill": "triangle-exclamation",
    "xmark": "xmark", "xmark.circle.fill": "circle-xmark", "minus": "minus",
    "plus": "plus", "plus.circle.fill": "circle-plus",
    "chevron.right": "chevron-right", "chevron.down": "chevron-down", "chevron.up": "chevron-up",
    "chevron.left.forwardslash.chevron.right": "code", "arrow.up.right": "up-right-from-square",
    "arrow.clockwise": "arrows-rotate", "arrow.triangle.2.circlepath": "arrows-rotate",
    "arrow.down.doc.fill": "file-arrow-down", "bell.fill": "bell", "bell.badge": "bell",
    "calendar": "calendar-days", "calendar.badge.clock": "calendar-days",
    "clock": "clock", "clock.badge.questionmark": "clock", "gearshape": "gear",
    "info.circle": "circle-info", "globe": "globe", "eye.slash.fill": "eye-slash",
    "key.fill": "key", "trash": "trash-can", "square.and.pencil": "pen-to-square",
    "doc.fill": "file", "doc.text.fill": "file-lines", "note.text": "note-sticky",
    "folder.fill": "folder", "folder": "folder", "magnifyingglass": "magnifying-glass",
    "qrcode": "qrcode", "qrcode.viewfinder": "qrcode", "photo.badge.exclamationmark": "image",
    "puzzlepiece.extension.fill": "puzzle-piece", "storefront.fill": "store",
    "shippingbox.fill": "box", "cart.fill": "cart-shopping", "hand.raised.fill": "hand",
    "hand.point.up.left": "hand-pointer", "star.circle.fill": "star", "star.circle": "star",
    "link.circle.fill": "link", "apple.logo": "apple", "touchid": "fingerprint",
    "power": "power-off", "bluetooth.slash": "ban",
    "dot.radiowaves.left.and.right": "tower-broadcast", "iphone": "mobile-screen-button",
    "apps.iphone": "mobile-screen", "applewatch": "clock", "watch.analog": "clock",
    "headphones": "headphones", "magicmouse": "computer-mouse", "keyboard": "keyboard",
    "battery.0": "battery-empty", "battery.25": "battery-quarter", "battery.50": "battery-half",
    "battery.75": "battery-three-quarters", "battery.100": "battery-full",
    "app.dashed": "window-maximize", "macwindow": "window-maximize",
    "envelope": "envelope", "externaldrive": "hard-drive", "lifepreserver": "life-ring",
    "chart.line.uptrend.xyaxis": "chart-line", "icloud.slash": "cloud",
    "nosign": "ban",
}

def main():
    icons_path = sys.argv[1] if len(sys.argv) > 1 else "/tmp/fa-icons.json"
    data = json.load(open(icons_path))
    rows = []
    for sf, fa in MAPPING.items():
        e = data.get(fa)
        if not e or not e.get("free"):
            sys.exit(f"ERROR: '{fa}' (for '{sf}') is missing or not Free - pick another icon.")
        free = e["free"]
        style = "brands" if "brands" in free else ("solid" if "solid" in free else free[0])
        rows.append((sf, fa, e["unicode"], style))

    out = []
    out.append("// FontAwesomeCatalog.swift - GENERATED, do not edit by hand.")
    out.append("// Maps the SF Symbol names used across the UI to Font Awesome Free 6.7.2 glyphs.")
    out.append("// Regenerate via Scripts/gen_fa_catalog.py after adding an icon. Font Awesome Free is")
    out.append("// CC BY 4.0 (icons) - see THIRD-PARTY-NOTICES.md and Resources/Fonts/LICENSE-FontAwesome.txt.")
    out.append("import Foundation")
    out.append("")
    out.append("enum FAStyle { case solid, regular, brands")
    out.append("    var postScriptName: String {")
    out.append("        switch self {")
    out.append('        case .solid:   return "FontAwesome6Free-Solid"')
    out.append('        case .regular: return "FontAwesome6Free-Regular"')
    out.append('        case .brands:  return "FontAwesome6Brands-Regular"')
    out.append("        } } }")
    out.append("")
    out.append("struct FAGlyph { let scalar: Unicode.Scalar; let style: FAStyle")
    out.append("    var string: String { String(scalar) } }")
    out.append("")
    out.append("enum FontAwesomeCatalog {")
    out.append("    /// SF-Symbol-name → Font Awesome glyph. Keys are the legacy SF names still")
    out.append("    /// returned by view models/enums, translated to FA at render time.")
    out.append("    static let map: [String: FAGlyph] = [")
    for sf, fa, uni, style in sorted(rows):
        out.append(f'        "{sf}": FAGlyph(scalar: Unicode.Scalar(0x{uni})!, style: .{style}), // fa-{fa}')
    out.append("    ]")
    out.append("}")

    dst = os.path.join(os.path.dirname(__file__), "..",
                       "Sources/PrivioApp/UI/Components/FontAwesomeCatalog.swift")
    with open(os.path.normpath(dst), "w") as f:
        f.write("\n".join(out) + "\n")
    print(f"wrote {os.path.normpath(dst)} ({len(rows)} icons)")

if __name__ == "__main__":
    main()

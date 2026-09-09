// FontAwesomeCatalog.swift - GENERATED, do not edit by hand.
// Maps the SF Symbol names used across the UI to Font Awesome Free 6.7.2 glyphs.
// Regenerate via Scripts/gen_fa_catalog.py after adding an icon. Font Awesome Free is
// CC BY 4.0 (icons) - see THIRD-PARTY-NOTICES.md and Resources/Fonts/LICENSE-FontAwesome.txt.
import Foundation

enum FAStyle { case solid, regular, brands
    var postScriptName: String {
        switch self {
        case .solid:   return "FontAwesome6Free-Solid"
        case .regular: return "FontAwesome6Free-Regular"
        case .brands:  return "FontAwesome6Brands-Regular"
        } } }

struct FAGlyph { let scalar: Unicode.Scalar; let style: FAStyle
    var string: String { String(scalar) } }

enum FontAwesomeCatalog {
    /// SF-Symbol-name → Font Awesome glyph. Keys are the legacy SF names still
    /// returned by view models/enums, translated to FA at render time.
    static let map: [String: FAGlyph] = [
        "app.dashed": FAGlyph(scalar: Unicode.Scalar(0xf2d0)!, style: .solid), // fa-window-maximize
        "apple.logo": FAGlyph(scalar: Unicode.Scalar(0xf179)!, style: .brands), // fa-apple
        "applewatch": FAGlyph(scalar: Unicode.Scalar(0xf017)!, style: .solid), // fa-clock
        "apps.iphone": FAGlyph(scalar: Unicode.Scalar(0xf3cf)!, style: .solid), // fa-mobile-screen
        "arrow.clockwise": FAGlyph(scalar: Unicode.Scalar(0xf021)!, style: .solid), // fa-arrows-rotate
        "arrow.down.doc.fill": FAGlyph(scalar: Unicode.Scalar(0xf56d)!, style: .solid), // fa-file-arrow-down
        "arrow.triangle.2.circlepath": FAGlyph(scalar: Unicode.Scalar(0xf021)!, style: .solid), // fa-arrows-rotate
        "arrow.up.right": FAGlyph(scalar: Unicode.Scalar(0xf35d)!, style: .solid), // fa-up-right-from-square
        "battery.0": FAGlyph(scalar: Unicode.Scalar(0xf244)!, style: .solid), // fa-battery-empty
        "battery.100": FAGlyph(scalar: Unicode.Scalar(0xf240)!, style: .solid), // fa-battery-full
        "battery.25": FAGlyph(scalar: Unicode.Scalar(0xf243)!, style: .solid), // fa-battery-quarter
        "battery.50": FAGlyph(scalar: Unicode.Scalar(0xf242)!, style: .solid), // fa-battery-half
        "battery.75": FAGlyph(scalar: Unicode.Scalar(0xf241)!, style: .solid), // fa-battery-three-quarters
        "bell.badge": FAGlyph(scalar: Unicode.Scalar(0xf0f3)!, style: .solid), // fa-bell
        "bell.fill": FAGlyph(scalar: Unicode.Scalar(0xf0f3)!, style: .solid), // fa-bell
        "bluetooth.slash": FAGlyph(scalar: Unicode.Scalar(0xf05e)!, style: .solid), // fa-ban
        "bolt.shield": FAGlyph(scalar: Unicode.Scalar(0xf3ed)!, style: .solid), // fa-shield-halved
        "calendar": FAGlyph(scalar: Unicode.Scalar(0xf073)!, style: .solid), // fa-calendar-days
        "calendar.badge.clock": FAGlyph(scalar: Unicode.Scalar(0xf073)!, style: .solid), // fa-calendar-days
        "cart.fill": FAGlyph(scalar: Unicode.Scalar(0xf07a)!, style: .solid), // fa-cart-shopping
        "chart.line.uptrend.xyaxis": FAGlyph(scalar: Unicode.Scalar(0xf201)!, style: .solid), // fa-chart-line
        "checkmark.seal.fill": FAGlyph(scalar: Unicode.Scalar(0xf058)!, style: .solid), // fa-circle-check
        "checkmark.shield": FAGlyph(scalar: Unicode.Scalar(0xf3ed)!, style: .solid), // fa-shield-halved
        "checkmark.shield.fill": FAGlyph(scalar: Unicode.Scalar(0xf3ed)!, style: .solid), // fa-shield-halved
        "chevron.down": FAGlyph(scalar: Unicode.Scalar(0xf078)!, style: .solid), // fa-chevron-down
        "chevron.left.forwardslash.chevron.right": FAGlyph(scalar: Unicode.Scalar(0xf121)!, style: .solid), // fa-code
        "chevron.right": FAGlyph(scalar: Unicode.Scalar(0xf054)!, style: .solid), // fa-chevron-right
        "chevron.up": FAGlyph(scalar: Unicode.Scalar(0xf077)!, style: .solid), // fa-chevron-up
        "clock": FAGlyph(scalar: Unicode.Scalar(0xf017)!, style: .solid), // fa-clock
        "clock.badge.questionmark": FAGlyph(scalar: Unicode.Scalar(0xf017)!, style: .solid), // fa-clock
        "doc.fill": FAGlyph(scalar: Unicode.Scalar(0xf15b)!, style: .solid), // fa-file
        "doc.text.fill": FAGlyph(scalar: Unicode.Scalar(0xf15c)!, style: .solid), // fa-file-lines
        "dot.radiowaves.left.and.right": FAGlyph(scalar: Unicode.Scalar(0xf519)!, style: .solid), // fa-tower-broadcast
        "envelope": FAGlyph(scalar: Unicode.Scalar(0xf0e0)!, style: .solid), // fa-envelope
        "exclamationmark.shield.fill": FAGlyph(scalar: Unicode.Scalar(0xf3ed)!, style: .solid), // fa-shield-halved
        "exclamationmark.triangle.fill": FAGlyph(scalar: Unicode.Scalar(0xf071)!, style: .solid), // fa-triangle-exclamation
        "externaldrive": FAGlyph(scalar: Unicode.Scalar(0xf0a0)!, style: .solid), // fa-hard-drive
        "eye.slash.fill": FAGlyph(scalar: Unicode.Scalar(0xf070)!, style: .solid), // fa-eye-slash
        "folder": FAGlyph(scalar: Unicode.Scalar(0xf07b)!, style: .solid), // fa-folder
        "folder.fill": FAGlyph(scalar: Unicode.Scalar(0xf07b)!, style: .solid), // fa-folder
        "gearshape": FAGlyph(scalar: Unicode.Scalar(0xf013)!, style: .solid), // fa-gear
        "globe": FAGlyph(scalar: Unicode.Scalar(0xf0ac)!, style: .solid), // fa-globe
        "hand.point.up.left": FAGlyph(scalar: Unicode.Scalar(0xf25a)!, style: .solid), // fa-hand-pointer
        "hand.raised.fill": FAGlyph(scalar: Unicode.Scalar(0xf256)!, style: .solid), // fa-hand
        "headphones": FAGlyph(scalar: Unicode.Scalar(0xf025)!, style: .solid), // fa-headphones
        "icloud.slash": FAGlyph(scalar: Unicode.Scalar(0xf0c2)!, style: .solid), // fa-cloud
        "info.circle": FAGlyph(scalar: Unicode.Scalar(0xf05a)!, style: .solid), // fa-circle-info
        "iphone": FAGlyph(scalar: Unicode.Scalar(0xf3cd)!, style: .solid), // fa-mobile-screen-button
        "key.fill": FAGlyph(scalar: Unicode.Scalar(0xf084)!, style: .solid), // fa-key
        "keyboard": FAGlyph(scalar: Unicode.Scalar(0xf11c)!, style: .solid), // fa-keyboard
        "lifepreserver": FAGlyph(scalar: Unicode.Scalar(0xf1cd)!, style: .solid), // fa-life-ring
        "link.circle.fill": FAGlyph(scalar: Unicode.Scalar(0xf0c1)!, style: .solid), // fa-link
        "lock.app.dashed": FAGlyph(scalar: Unicode.Scalar(0xf023)!, style: .solid), // fa-lock
        "lock.fill": FAGlyph(scalar: Unicode.Scalar(0xf023)!, style: .solid), // fa-lock
        "lock.open.fill": FAGlyph(scalar: Unicode.Scalar(0xf3c1)!, style: .solid), // fa-lock-open
        "lock.open.trianglebadge.exclamationmark": FAGlyph(scalar: Unicode.Scalar(0xf3c1)!, style: .solid), // fa-lock-open
        "lock.rectangle.dashed": FAGlyph(scalar: Unicode.Scalar(0xf023)!, style: .solid), // fa-lock
        "lock.rectangle.stack.fill": FAGlyph(scalar: Unicode.Scalar(0xe2c5)!, style: .solid), // fa-vault
        "lock.rotation": FAGlyph(scalar: Unicode.Scalar(0xf021)!, style: .solid), // fa-arrows-rotate
        "macwindow": FAGlyph(scalar: Unicode.Scalar(0xf2d0)!, style: .solid), // fa-window-maximize
        "magicmouse": FAGlyph(scalar: Unicode.Scalar(0xf8cc)!, style: .solid), // fa-computer-mouse
        "magnifyingglass": FAGlyph(scalar: Unicode.Scalar(0xf002)!, style: .solid), // fa-magnifying-glass
        "minus": FAGlyph(scalar: Unicode.Scalar(0xf068)!, style: .solid), // fa-minus
        "nosign": FAGlyph(scalar: Unicode.Scalar(0xf05e)!, style: .solid), // fa-ban
        "note.text": FAGlyph(scalar: Unicode.Scalar(0xf249)!, style: .solid), // fa-note-sticky
        "photo.badge.exclamationmark": FAGlyph(scalar: Unicode.Scalar(0xf03e)!, style: .solid), // fa-image
        "plus": FAGlyph(scalar: Unicode.Scalar(0x2b)!, style: .solid), // fa-plus
        "plus.circle.fill": FAGlyph(scalar: Unicode.Scalar(0xf055)!, style: .solid), // fa-circle-plus
        "power": FAGlyph(scalar: Unicode.Scalar(0xf011)!, style: .solid), // fa-power-off
        "puzzlepiece.extension.fill": FAGlyph(scalar: Unicode.Scalar(0xf12e)!, style: .solid), // fa-puzzle-piece
        "qrcode": FAGlyph(scalar: Unicode.Scalar(0xf029)!, style: .solid), // fa-qrcode
        "qrcode.viewfinder": FAGlyph(scalar: Unicode.Scalar(0xf029)!, style: .solid), // fa-qrcode
        "shield.slash.fill": FAGlyph(scalar: Unicode.Scalar(0xf05e)!, style: .solid), // fa-ban
        "shippingbox.fill": FAGlyph(scalar: Unicode.Scalar(0xf466)!, style: .solid), // fa-box
        "square.and.pencil": FAGlyph(scalar: Unicode.Scalar(0xf044)!, style: .solid), // fa-pen-to-square
        "star.circle": FAGlyph(scalar: Unicode.Scalar(0xf005)!, style: .solid), // fa-star
        "star.circle.fill": FAGlyph(scalar: Unicode.Scalar(0xf005)!, style: .solid), // fa-star
        "storefront.fill": FAGlyph(scalar: Unicode.Scalar(0xf54e)!, style: .solid), // fa-store
        "touchid": FAGlyph(scalar: Unicode.Scalar(0xf577)!, style: .solid), // fa-fingerprint
        "trash": FAGlyph(scalar: Unicode.Scalar(0xf2ed)!, style: .solid), // fa-trash-can
        "watch.analog": FAGlyph(scalar: Unicode.Scalar(0xf017)!, style: .solid), // fa-clock
        "xmark": FAGlyph(scalar: Unicode.Scalar(0xf00d)!, style: .solid), // fa-xmark
        "xmark.circle.fill": FAGlyph(scalar: Unicode.Scalar(0xf057)!, style: .solid), // fa-circle-xmark
    ]
}

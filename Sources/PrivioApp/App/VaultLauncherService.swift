import AppKit
import Foundation
import UniformTypeIdentifiers

/// Tworzy przenośny skrót `.inetloc` prowadzący do sejfu. Wygląda jak folder,
/// ale nie udaje katalogu z danymi: właściwe pliki istnieją wyłącznie w
/// zaszyfrowanym obrazie i pojawiają się dopiero po uwierzytelnieniu.
@MainActor
enum VaultLauncherService {
    static func install() throws -> URL? {
        let panel = NSSavePanel()
        panel.title = NSLocalizedString("Add Privio Vault Shortcut", comment: "Vault launcher panel")
        panel.nameFieldStringValue = NSLocalizedString("Privio Vault.inetloc", comment: "Vault launcher filename")
        panel.canCreateDirectories = true
        panel.isExtensionHidden = true
        if let type = UTType(filenameExtension: "inetloc") { panel.allowedContentTypes = [type] }
        guard panel.runModal() == .OK, let url = panel.url else { return nil }

        let payload = ["URL": "privio://vault/open"]
        let data = try PropertyListSerialization.data(fromPropertyList: payload, format: .xml, options: 0)
        try data.write(to: url, options: .atomic)
        NSWorkspace.shared.setIcon(folderIcon(), forFile: url.path, options: [])
        return url
    }

    static func folderIcon() -> NSImage {
        let size = NSSize(width: 512, height: 512)
        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }

        let base = NSWorkspace.shared.icon(for: .folder)
        base.size = size
        base.draw(in: NSRect(origin: .zero, size: size),
                  from: .zero, operation: .sourceOver, fraction: 1)

        // Proporcja MUSI odpowiadać projektowej (211:310) - `path(in:)` rozciąga
        // geometrię niezależnie w X/Y, więc niedopasowany prostokąt spłaszczał znak.
        // Wysokość dobrana tak, by znak miał zbliżoną masę wizualną do glifów
        // systemowych folderów (Aplikacje/Pobrane).
        let markHeight: CGFloat = 268
        let markWidth = markHeight * PrivioSmallLogoGeometry.aspect
        // Wyśrodkowany na froncie folderu (front zajmuje ok. 14-74% wysokości ikony).
        let badgeRect = NSRect(
            x: (size.width - markWidth) / 2,
            y: size.height * 0.438 - markHeight / 2,
            width: markWidth,
            height: markHeight
        )
        let markPath = PrivioSmallLogoGeometry.path(in: badgeRect.size)
        let lineWidth = badgeRect.width * PrivioSmallLogoGeometry.designLineWidthRatio

        // Ścieżka SVG ma początek w lewym górnym rogu, a NSImage rysuje od
        // lewego dolnego - stąd odbicie w pionie. `dy` przesuwa całą kopię znaku
        // (dodatnie = w górę), co pozwala rysować warstwy wytłoczenia.
        func mark(offsetY dy: CGFloat) -> NSBezierPath {
            let bezier = NSBezierPath(cgPath: markPath.cgPath)
            var placement = AffineTransform.identity
            placement.translate(x: badgeRect.minX, y: badgeRect.maxY + dy)
            placement.scale(x: 1, y: -1)
            bezier.transform(using: placement)
            bezier.lineWidth = lineWidth
            bezier.lineCapStyle = .round
            bezier.lineJoinStyle = .round
            return bezier
        }

        // Znak jak systemowe glify (Aplikacje/Pobrane): wtopiony w niebieski front
        // folderu, a nie płaska naklejka. Cień u góry + jasny rant u dołu dają
        // wrażenie wygrawerowania. Kolor to TEN SAM odcień co front folderu
        // (~209°), tylko ciemniejszy i mocniej nasycony - nie fioletowy granat.
        NSColor(srgbRed: 0.16, green: 0.30, blue: 0.46, alpha: 0.40).setStroke()  // cień (góra)
        mark(offsetY: 1.1).stroke()
        NSColor.white.withAlphaComponent(0.42).setStroke()                        // rant (dół)
        mark(offsetY: -1.1).stroke()
        NSColor(srgbRed: 0.32, green: 0.53, blue: 0.74, alpha: 1.0).setStroke()   // powierzchnia
        mark(offsetY: 0).stroke()

        image.isTemplate = false
        return image
    }

    /// Pomocniczy eksport do kontroli wizualnej podczas developmentu.
    static func writeIconSnapshot(to url: URL) throws {
        guard let tiff = folderIcon().tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try png.write(to: url, options: .atomic)
    }
}

import AppKit
import CoreGraphics

/// Wspólne, bezuprawnieniowe wyliczanie ramek okien aplikacji z `CGWindowListCopyWindowInfo`.
///
/// Używa TYLKO geometrii (pozycja + PID właściciela), bez obrazów okien - nie wymaga
/// uprawnień Screen Recording ani Accessibility. Jedno źródło prawdy dla:
/// - `PrivacyCurtainController` (sytuacyjna Zasłona prywatności) oraz
/// - `LockCoverController` (zasłona blokady - druga warstwa ochrony okien).
/// Trzymanie konwersji Quartz→AppKit i filtrów okien w jednym miejscu zapobiega
/// rozjechaniu się obu kontrolerów.
enum WindowGeometry {

    /// Widoczne okna procesu (warstwa 0, niepuste, sensowny rozmiar) → ramki AppKit.
    static func windowFrames(pid: pid_t) -> [NSRect] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                    kCGNullWindowID) as? [[String: Any]] else { return [] }
        return list.compactMap { info -> NSRect? in
            guard (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid,
                  (info[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1 > 0,
                  let boundsDictionary = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDictionary as CFDictionary),
                  bounds.width >= 80, bounds.height >= 60 else { return nil }
            return appKitFrame(fromQuartzBounds: bounds)
        }
    }

    /// Quartz (globalny, lewy-górny róg, +y w dół) → AppKit (globalny, lewy-dolny róg, +y w górę).
    static func appKitFrame(fromQuartzBounds bounds: CGRect) -> NSRect {
        let primaryTop = NSScreen.screens.first?.frame.maxY ?? 0
        return NSRect(x: bounds.minX,
                      y: primaryTop - bounds.maxY,
                      width: bounds.width,
                      height: bounds.height)
    }
}

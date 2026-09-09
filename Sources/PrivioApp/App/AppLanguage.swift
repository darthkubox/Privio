import AppKit
import SwiftUI

/// Język interfejsu Privio. Domyślnie „System" (język Maca); użytkownik może wymusić
/// polski lub angielski w Ustawieniach. Zmiana wymaga restartu aplikacji, bo język
/// ładuje się przy starcie (`applyStartupOverride`) - ustawiamy `AppleLanguages`, więc
/// zarówno `LocalizedStringKey`, jak i `Locale.preferredLanguages` mówią wybranym
/// językiem (spójnie z istniejącą logiką promptów/licencji).
enum AppLanguage: String, CaseIterable, Identifiable {
    case system, pl, en

    var id: String { rawValue }

    /// Nazwa w języku własnym (nie tłumaczymy „Polski"/„English").
    var displayName: String {
        switch self {
        case .system: return "System"
        case .pl:     return "Polski"
        case .en:     return "English"
        }
    }

    /// Kod dla `AppleLanguages`; nil = podążaj za systemem.
    private var code: String? {
        switch self {
        case .system: return nil
        case .pl:     return "pl"
        case .en:     return "en"
        }
    }

    private static let defaultsKey = "privio.appLanguage"

    static var current: AppLanguage {
        AppLanguage(rawValue: UserDefaults.standard.string(forKey: defaultsKey) ?? "") ?? .system
    }

    /// Efektywny kod języka UI ("pl"/"en") - rozwija „System" na podstawie
    /// preferencji systemowych. Używane m.in. przez rozszerzenie (tryb „Auto").
    static var effectiveCode: String {
        if let code = current.code { return code }
        return (Locale.preferredLanguages.first ?? "en").hasPrefix("pl") ? "pl" : "en"
    }

    /// MUSI być wołane najwcześniej (PrivioApp.init), zanim UI wczyta jakikolwiek tekst.
    static func applyStartupOverride() {
        let ud = UserDefaults.standard
        if let code = current.code {
            ud.set([code], forKey: "AppleLanguages")
        } else {
            ud.removeObject(forKey: "AppleLanguages")
        }
    }

    /// Zapisuje wybór i restartuje Privio, żeby język zastosował się w całej aplikacji.
    @MainActor static func select(_ lang: AppLanguage) {
        guard lang != current else { return }
        UserDefaults.standard.set(lang.rawValue, forKey: defaultsKey)
        applyStartupOverride()
        relaunch()
    }

    @MainActor private static func relaunch() {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        proc.arguments = ["-n", Bundle.main.bundlePath]
        try? proc.run()
        NSApp.terminate(nil)
    }
}

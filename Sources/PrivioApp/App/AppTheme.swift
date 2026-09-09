import AppKit

/// Motyw interfejsu Privio: „System" (podąża za Makiem), jasny lub ciemny.
/// W odróżnieniu od języka zmiana motywu działa NATYCHMIAST (bez restartu) -
/// ustawiamy `NSApp.appearance`, więc całe UI (okno ustawień, panel w pasku menu,
/// arkusze) przerysowuje się od razu. `nil` = brak wymuszenia = wygląd systemowy.
enum AppTheme: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    /// Klucz lokalizacji nazwy (angielski tekst = klucz, tłumaczony w `Localizable.xcstrings`).
    var titleKey: String {
        switch self {
        case .system: return "System"
        case .light:  return "Light"
        case .dark:   return "Dark"
        }
    }

    /// Nazwa wyglądu AppKit; nil = podążaj za systemem.
    private var appearanceName: NSAppearance.Name? {
        switch self {
        case .system: return nil
        case .light:  return .aqua
        case .dark:   return .darkAqua
        }
    }

    private static let defaultsKey = "privio.appTheme"

    static var current: AppTheme {
        AppTheme(rawValue: UserDefaults.standard.string(forKey: defaultsKey) ?? "") ?? .system
    }

    /// Stosuje bieżący motyw do całej aplikacji. Wołane przy starcie i po każdej zmianie.
    @MainActor static func apply() {
        NSApp.appearance = current.appearanceName.map { NSAppearance(named: $0) } ?? nil
    }

    /// Zapisuje wybór i stosuje go natychmiast.
    @MainActor static func select(_ theme: AppTheme) {
        guard theme != current else { return }
        UserDefaults.standard.set(theme.rawValue, forKey: defaultsKey)
        apply()
    }
}

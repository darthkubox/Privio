import SwiftUI
import AppKit
import CoreText

/// Rejestracja i użycie krojów marki: **Nunito** (SIL OFL 1.1) dla całego tekstu UI
/// oraz **Font Awesome Free 6.7.2** (CC BY 4.0 / OFL 1.1 / MIT) dla wszystkich ikon -
/// te same kroje co na stronie priviolock.com. Pliki fontów i pełne teksty licencji
/// są w `Resources/Fonts/`; noty prawne w [THIRD-PARTY-NOTICES.md]. Nie usuwać
/// osadzonej atrybucji z plików fontów (wymóg licencji).
enum PrivioFonts {
    /// Rodzina typograficzna Nunito (name ID 16 zmiennego kroju). Wagę zawsze
    /// podajemy jawnie, bo domyślną instancją pliku zmiennego jest ExtraLight.
    static let nunitoFamily = "Nunito"

    private static let fontFileNames = [
        "Nunito-VariableFont_wght",
        "Nunito-Italic-VariableFont_wght",
        "FontAwesome6Free-Solid-900",
        "FontAwesome6Free-Regular-400",
        "FontAwesome6Brands-Regular-400",
    ]

    private static var didRegister = false

    /// Rejestruje wszystkie dołączone kroje w CoreText. Idempotentne; wołane raz przy
    /// starcie (`PrivioApp.init`) oraz w trybie snapshot, ZANIM UI cokolwiek narysuje.
    static func registerAll() {
        guard !didRegister else { return }
        didRegister = true
        for name in fontFileNames {
            let ext = name.hasPrefix("FontAwesome") ? "otf" : "ttf"
            guard let url = Bundle.main.url(forResource: name, withExtension: ext) else { continue }
            var error: Unmanaged<CFError>?
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
            // Błąd „already registered" jest nieszkodliwy (np. drugi proces snapshot).
        }
    }
}

extension Font {
    /// Zamiennik `Font.system(size:weight:design:)` renderujący **Nunito** dla całego
    /// tekstu UI. Wariant `.monospaced` zostaje systemowy (kody/hex/skróty) - Nunito nie
    /// ma kroju o stałej szerokości. Rozmiar jest stały (fixedSize), by zachować
    /// dotychczasową, dopracowaną metrykę układu.
    static func privioSystem(size: CGFloat,
                             weight: Font.Weight = .regular,
                             design: Font.Design = .default) -> Font {
        if design == .monospaced {
            return .system(size: size, weight: weight, design: .monospaced)
        }
        return .custom(PrivioFonts.nunitoFamily, fixedSize: size).weight(weight)
    }
}

extension View {
    /// Ustawia bazowy krój Nunito dla całego poddrzewa, żeby zwykłe `Text` bez własnego
    /// `.font` też dziedziczyło markę. Zakładane na korzeniach scen.
    func privioFontEnvironment() -> some View {
        environment(\.font, .privioSystem(size: NSFont.systemFontSize))
    }
}

/// Ikona interfejsu rysowana krojem **Font Awesome Free**. Przyjmuje *starą nazwę
/// symbolu SF* (te same klucze, które nadal zwracają enumy/modele) i tłumaczy ją na
/// glif FA przez `FontAwesomeCatalog`. Sam ustawia swój font, więc otaczające `.font`
/// (Nunito) nie zaburza glifu; kolor dziedziczy z `.foregroundStyle`.
struct FAIcon: View {
    private let glyph: FAGlyph
    private let size: CGFloat

    /// - Parameters:
    ///   - name: nazwa symbolu (klucz SF, np. `"lock.fill"`), zwykle z modelu/enuma.
    ///   - size: rozmiar w punktach; domyślnie zbliżony do wysokości tekstu.
    init(_ name: String, size: CGFloat = 14) {
        self.glyph = FontAwesomeCatalog.map[name] ?? FAIcon.fallback
        self.size = size
    }

    /// Fallback (`fa-question`), gdy klucz nie ma mapowania - widoczny, nie wywala buildu.
    private static let fallback = FAGlyph(scalar: Unicode.Scalar(0xf128)!, style: .solid)

    var body: some View {
        Text(glyph.string)
            .font(.custom(glyph.style.postScriptName, fixedSize: size))
    }
}

extension Label where Title == Text, Icon == FAIcon {
    /// `Label("Tytuł", fa: "lock.fill")` - etykieta z tekstem (Nunito) i ikoną Font
    /// Awesome. Odpowiednik dawnego `Label(_:systemImage:)`; klucz jest lokalizowany.
    init(_ titleKey: LocalizedStringKey, fa name: String) {
        self.init { Text(titleKey) } icon: { FAIcon(name) }
    }

    /// Wariant dla wartości `String` z modelu (np. nazwa pozycji sejfu) - bez lokalizacji.
    /// Wymaga etykiety `verbatim:`, inaczej dla literałów wygrywałby z wariantem
    /// `LocalizedStringKey` i teksty nie byłyby tłumaczone.
    init<S: StringProtocol>(verbatim title: S, fa name: String) {
        self.init { Text(title) } icon: { FAIcon(name) }
    }

    /// `Label(fa: "gearshape", verbatim: "1.2.3")` - tytuł dosłowny (bez lokalizacji),
    /// np. numer wersji lub identyfikator; ikona Font Awesome.
    init(fa name: String, verbatim title: String) {
        self.init { Text(verbatim: title) } icon: { FAIcon(name) }
    }
}

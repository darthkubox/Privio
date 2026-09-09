import Foundation

/// Umowa licencyjna / warunki (podsumowanie polityki z dokumentów projektu).
/// To NIE porada prawna - pełna, wiążąca EULA to EULA.md (PL) / EULA.en.md (EN).
/// `version` bumpujemy, gdy treść wymaga ponownego zatwierdzenia.
enum LicenseAgreement {
    static let version = 11

    static func title(for lang: Lang) -> String {
        lang == .pl ? "Privio - licencje i dokumenty" : "Privio - Licences & Documents"
    }

    static let text = """
    Privio legal documents could not be loaded from the application bundle.

    The binding Polish EULA, Privacy Policy, Direct Sales Terms, source-code license and third-party
    notices are distributed with Privio and published in its official repository. Do not accept terms
    shown from this fallback screen; reinstall an official, complete build and open the documents
    again.
    """

    enum Lang: String, CaseIterable, Identifiable {
        case pl, en
        var id: String { rawValue }
        var title: String { self == .pl ? "Polski" : "English" }
    }

    /// Domyślny język wg ustawień systemu.
    static var defaultLang: Lang {
        (Locale.preferredLanguages.first ?? "en").hasPrefix("pl") ? .pl : .en
    }

    /// Jeden dokument prawny dostępny do wglądu w aplikacji. `resources` mapuje język
    /// na nazwę zasobu w bundlu (bez rozszerzenia `.md`). Nowe tłumaczenie pojawi się
    /// automatycznie po dodaniu pliku i wpisu tutaj - bez zmian w UI.
    struct Document: Identifiable, Hashable {
        let id: String
        let titles: [Lang: String]
        let subtitles: [Lang: String]
        let symbol: String
        let resources: [Lang: String]

        /// Języki, w których dokument faktycznie istnieje (kolejność jak w `Lang`).
        var languages: [Lang] { Lang.allCases.filter { resources[$0] != nil } }

        func title(for lang: Lang) -> String {
            titles[lang] ?? titles[.pl] ?? titles[.en] ?? id
        }

        func subtitle(for lang: Lang) -> String {
            subtitles[lang] ?? subtitles[.pl] ?? subtitles[.en] ?? ""
        }
    }

    struct DocumentDestination {
        let document: Document
        let language: Lang
    }

    /// Wszystkie licencje, jakie mamy. `.eula` jest dokumentem akceptowanym na starcie.
    static let documents: [Document] = [
        Document(id: "eula",
                 titles: [.pl: "Umowa EULA", .en: "EULA"],
                 subtitles: [.pl: "Wiążąca umowa licencyjna i regulamin usług",
                             .en: "Binding licence agreement and service terms"],
                 symbol: "doc.text.fill",
                 resources: [.pl: "EULA", .en: "EULA.en"]),
        Document(id: "privacy",
                 titles: [.pl: "Polityka prywatności", .en: "Privacy Policy"],
                 subtitles: [.pl: "Dane lokalne, uprawnienia i prywatność",
                             .en: "Local data, permissions and privacy"],
                 symbol: "hand.raised.fill",
                 resources: [.pl: "PRIVACY", .en: "PRIVACY.en"]),
        Document(id: "sales",
                 titles: [.pl: "Warunki sprzedaży", .en: "Sales Terms"],
                 subtitles: [.pl: "Warunki bezpośredniej sprzedaży Licencji Pro",
                             .en: "Direct Pro Licence sales terms"],
                 symbol: "cart.fill",
                 resources: [.pl: "SALES", .en: "SALES.en"]),
        Document(id: "source",
                 titles: [.pl: "Licencja kodu", .en: "Source Code Licence"],
                 subtitles: [.pl: "Licencja kodu źródłowego dostępnego do wglądu",
                             .en: "Source-available code licence"],
                 symbol: "chevron.left.forwardslash.chevron.right",
                 resources: [.pl: "LICENSE", .en: "LICENSE.en"]),
        Document(id: "third-party",
                 titles: [.pl: "Komponenty zewnętrzne", .en: "Third-Party Licences"],
                 subtitles: [.pl: "Licencje i noty komponentów użytych w Privio",
                             .en: "Licences and notices for components used by Privio"],
                 symbol: "shippingbox.fill",
                 resources: [.pl: "THIRD-PARTY-NOTICES", .en: "THIRD-PARTY-NOTICES"]),
        Document(id: "security",
                 titles: [.pl: "Model bezpieczeństwa", .en: "Security Model"],
                 subtitles: [.pl: "Sposób działania zabezpieczeń i ich granice",
                             .en: "How Privio protection works and where its limits are"],
                 symbol: "checkmark.shield.fill",
                 resources: [.pl: "Security-Model"]),
    ]

    /// Rozpoznaje odnośniki do plików Markdown użyte wewnątrz dokumentów prawnych.
    /// Takie linki są nawigacją w oknie Privio, a nie plikami do otwarcia przez Finder.
    static func destination(for url: URL, currentLang: Lang) -> DocumentDestination? {
        guard url.scheme == nil || url.scheme?.isEmpty == true else { return nil }

        let fileName = (url.lastPathComponent.removingPercentEncoding ?? url.lastPathComponent)
            .lowercased()
        guard !fileName.isEmpty else { return nil }

        for document in documents {
            let matchingLanguages = document.resources.compactMap { language, resource -> Lang? in
                "\(resource).md".lowercased() == fileName ? language : nil
            }
            guard !matchingLanguages.isEmpty else { continue }

            let language = matchingLanguages.contains(currentLang)
                ? currentLang
                : (matchingLanguages.first ?? currentLang)
            return DocumentDestination(document: document, language: language)
        }

        return nil
    }

    /// Pełna treść danego dokumentu w danym języku. Gdy brak wybranego języka - bierze
    /// pierwszy dostępny; gdy brak pliku w bundlu - fallback do streszczenia.
    static func text(for doc: Document, lang: Lang) -> String {
        let resource = doc.resources[lang] ?? doc.languages.first.flatMap { doc.resources[$0] }
        if let resource,
           let url = Bundle.main.url(forResource: resource, withExtension: "md"),
           let contents = try? String(contentsOf: url, encoding: .utf8) {
            return contents
        }
        return text
    }
}

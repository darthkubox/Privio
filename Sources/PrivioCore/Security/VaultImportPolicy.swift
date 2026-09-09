import Foundation

/// Czyste, deterministyczne reguły importu plików do sejfu - bez dostępu do dysku,
/// żeby dały się w pełni pokryć testami. Wywołujący (`VaultController`) najpierw
/// kanonizuje ścieżki (`resolvingSymlinksInPath().standardizedFileURL`) i odczytuje
/// z systemu, czy wpis jest dowiązaniem, a następnie pyta o werdykt tę enum.
public enum VaultImportPolicy {
    /// Powód, dla którego źródła NIE wolno zaimportować.
    public enum Rejection: Equatable, Sendable {
        /// Alias/dowiązanie symboliczne - kopiowalibyśmy cel, a nie dane użytkownika.
        case symbolicLink
        /// Ktoś próbuje wrzucić do sejfu sam plik obrazu sejfu.
        case vaultImageItself
        /// Źródło leży wewnątrz obrazu sejfu (kopiowanie w kółko / rekurencja).
        case insideVaultImage
    }

    /// Zwraca `nil`, gdy import jest bezpieczny, albo powód odrzucenia.
    /// - Parameters:
    ///   - canonicalSource: skanonizowana ścieżka źródła.
    ///   - canonicalImage: skanonizowana ścieżka pliku obrazu sejfu (`.sparsebundle`).
    ///   - isSymbolicLink: czy sam wpis źródłowy jest dowiązaniem symbolicznym.
    public static func rejection(
        canonicalSource: URL,
        canonicalImage: URL,
        isSymbolicLink: Bool
    ) -> Rejection? {
        if isSymbolicLink { return .symbolicLink }
        let source = canonicalSource.path
        let image = canonicalImage.path
        if source == image { return .vaultImageItself }
        if source.hasPrefix(image + "/") { return .insideVaultImage }
        return nil
    }

    /// Nazwa docelowa w wolumenie sejfu, która nie nadpisze istniejącego wpisu.
    /// Przy kolizji dokleja rosnący sufiks: `plik.txt` → `plik 2.txt` → `plik 3.txt`
    /// (dla wpisów bez rozszerzenia: `folder` → `folder 2`).
    /// - Parameter exists: predykat sprawdzający, czy nazwa jest już zajęta.
    public static func uniqueDestinationName(
        for source: URL,
        exists: (String) -> Bool
    ) -> String {
        let original = source.lastPathComponent
        if !exists(original) { return original }
        let base = source.deletingPathExtension().lastPathComponent
        let ext = source.pathExtension
        var suffix = 2
        while true {
            let candidate = ext.isEmpty ? "\(base) \(suffix)" : "\(base) \(suffix).\(ext)"
            if !exists(candidate) { return candidate }
            suffix += 1
        }
    }
}

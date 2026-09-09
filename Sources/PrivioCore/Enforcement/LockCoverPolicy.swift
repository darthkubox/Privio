import Foundation

/// Czysta logika decyzji dla „zasłony blokady" - drugiej warstwy ochrony okien.
///
/// Gdy `NSRunningApplication.hide()` zawiedzie (np. aplikacja w trybie pełnoekranowym
/// we własnym Space, której publiczne API nie potrafi ukryć), okno chronionej apki
/// zostaje widoczne, a systemowy prompt Touch ID pojawia się nad czytelną treścią.
/// Warstwa aplikacji rysuje wtedy nieprzezroczystą nakładkę nad oknami tych apek.
/// Tu (w rdzeniu, bez AppKit) decydujemy WYŁĄCZNIE, które apki należy zakryć - żeby
/// tę decyzję dało się przetestować jednostkowo. Rozwiązanie bundleID→PID→ramki
/// okien należy do warstwy aplikacji.
public enum LockCoverPolicy {
    /// bundleID aplikacji, których okna należy zakryć zasłoną blokady.
    ///
    /// Kryteria: ochrona globalnie aktywna, moduł blokowania aplikacji włączony,
    /// apka chroniona i w stanie `.locked` lub `.authenticating` (podczas promptu
    /// treść też musi pozostać zakryta).
    public static func bundleIDsToCover(_ state: EnforcementState) -> Set<String> {
        guard state.protectionActive, state.configuration.appBlockingEnabled else { return [] }
        return Set(
            state.apps
                .filter { $0.app.protectionEnabled && ($0.status == .locked || $0.status == .authenticating) }
                .map { $0.app.bundleIdentifier }
        )
    }
}

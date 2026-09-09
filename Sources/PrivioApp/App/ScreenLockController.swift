import Foundation

/// Wąski seam blokady ekranu - oddzielony od kontroli aplikacji, żeby jego brak
/// (snapshot/testy) nie mieszał się z resztą. Nie ma wpływu na ODBLOKOWANIE:
/// to zawsze normalny auth macOS. Urządzenie Bluetooth jest tylko wyzwalaczem.
protocol ScreenLockControlling: Sendable {
    func lockScreen()
}

/// Publiczna, nieprywatna blokada ekranu (bez prywatnych API i uprawnienia
/// Dostępności - zasada projektu). Zależne od ustawień systemowych - patrz
/// Post-MVP §3 (ograniczenia macOS).
struct SystemScreenLock: ScreenLockControlling {
    /// Starsze macOS: bezpośrednia blokada do okna logowania (fast user switching).
    /// Nowsze systemy usunęły tę binarkę - patrz fallback niżej.
    private static let legacyCGSession =
        "/System/Library/CoreServices/Menu Extras/User.menu/Contents/Resources/CGSession"
    /// Wygaszacz systemowy - jego start wyzwala blokadę „Wymagaj hasła".
    private static let screenSaver =
        "/System/Library/CoreServices/ScreenSaverEngine.app/Contents/MacOS/ScreenSaverEngine"

    func lockScreen() {
        // 0) Natychmiastowa blokada do okna logowania - jak menu Apple → „Zablokuj
        //    ekran" (⌃⌘Q). Blokuje OD RAZU, niezależnie od zwłoki „Wymagaj hasła".
        if lockViaLoginFramework() { return }
        // 1) Starsza, bezpośrednia ścieżka, jeśli istnieje na tym systemie.
        if FileManager.default.isExecutableFile(atPath: Self.legacyCGSession) {
            run(Self.legacyCGSession, ["-suspend"])
            return
        }
        // 2) Nowsze macOS (binarka CGSession usunięta): uruchom wygaszacz - to
        //    najpewniej wyzwala blokadę sesji. UWAGA: sesja zablokuje się tylko, gdy
        //    w Ustawieniach → Ekran blokady „Wymagaj hasła" ustawiono „natychmiast";
        //    przy zwłoce (np. 5 min) macOS nie poprosi o hasło przez ten czas. To
        //    ograniczenie macOS - brak publicznego API blokującego natychmiast mimo
        //    zwłoki. UI o tym informuje. Bez prywatnych API / Dostępności (zasada projektu).
        if FileManager.default.isExecutableFile(atPath: Self.screenSaver) {
            run(Self.screenSaver, [])
            return
        }
        // 3) Ostateczny fallback: uśpij wyświetlacz.
        run("/usr/bin/pmset", ["displaysleepnow"])
    }

    /// Natychmiastowa blokada przez `SACLockScreenImmediate` z login.framework.
    /// Symbol prywatny (świadomy wyjątek - patrz nagłówek), ale nie wymaga żadnego
    /// entitlementu ani uprawnienia Dostępności. Zwraca false, gdy symbol jest
    /// niedostępny - wtedy używamy publicznych ścieżek niżej.
    private func lockViaLoginFramework() -> Bool {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/login.framework/login", RTLD_NOW) else {
            return false
        }
        defer { dlclose(handle) }
        guard let sym = dlsym(handle, "SACLockScreenImmediate") else { return false }
        typealias LockFn = @convention(c) () -> Int32
        _ = unsafeBitCast(sym, to: LockFn.self)()
        return true
    }

    private func run(_ path: String, _ arguments: [String]) {
        guard FileManager.default.isExecutableFile(atPath: path) else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        try? process.run()
    }
}

/// Bez efektu - tryb snapshot / testy.
struct NoopScreenLock: ScreenLockControlling {
    func lockScreen() {}
}

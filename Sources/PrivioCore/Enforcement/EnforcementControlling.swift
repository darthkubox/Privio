import Foundation

/// Jedyna granica (seam) między warstwą enforcement a UI.
///
/// UI i menu bar rozmawiają z enforcementem WYŁĄCZNIE przez ten protokół oraz
/// strumień `EnforcementState`. Żadnego bezpośredniego sięgania UI do
/// `AppMonitor`/`LockManager`. Wszystkie parametry są Codable/Sendable, dzięki
/// czemu dzisiejszą implementację in‑process można później zastąpić proxy XPC
/// (`PrivioAgent`) bez zmian po stronie UI ani w rdzeniu logiki (decyzja
/// architektoniczna użytkownika).
public protocol EnforcementControlling: AnyObject, Sendable {

    // MARK: Odczyt stanu
    /// Bieżąca migawka (jednorazowo).
    func currentState() async -> EnforcementState
    /// Strumień kolejnych migawek. UI subskrybuje i renderuje na bieżąco.
    /// Async, by implementacja aktorowa mogła zarejestrować subskrybenta
    /// w swoim izolowanym kontekście (i by proxy XPC mogło otworzyć kanał).
    func stateUpdates() async -> AsyncStream<EnforcementState>

    // MARK: Lista chronionych apek
    func addProtectedApp(_ app: ProtectedApp) async
    func removeProtectedApp(id: UUID) async
    func updateProtectedApp(_ app: ProtectedApp) async
    func setProtectionEnabled(_ enabled: Bool, forAppID id: UUID) async

    // MARK: Sterowanie blokadą
    func lock(appID: UUID, reason: ActivityEvent.Reason) async
    func lockAll(reason: ActivityEvent.Reason) async
    /// Uruchamia realne uwierzytelnienie (Touch ID/hasło) dla apki i - po sukcesie -
    /// ją odblokowuje. Zwraca, czy się powiodło. To preferowana ścieżka z UI.
    /// `preferPassword` wymusza prompt z opcją hasła Maca (`deviceOwnerAuthentication`),
    /// niezależnie od ustawienia apki - obsługuje przycisk „Use Password".
    @discardableResult
    func authenticate(appID: UUID, preferPassword: Bool) async -> Bool
    /// Zgłoszenie pomyślnego uwierzytelnienia → wydanie krótkotrwałej autoryzacji.
    /// (Niższego poziomu; `authenticate` sam je wywołuje po sukcesie.)
    func markUnlocked(appID: UUID) async
    /// Oznaczenie rozpoczętego uwierzytelniania (UI pokazuje okno/prompt).
    func beginAuthentication(appID: UUID) async
    /// Anulowanie uwierzytelniania - apka wraca do stanu zablokowanego.
    func cancelAuthentication(appID: UUID) async

    // MARK: Chronione strony WWW (Pro) - blokada /etc/hosts
    func addWebTarget(_ target: WebTarget) async
    func removeWebTarget(id: UUID) async
    func updateWebTarget(_ target: WebTarget) async
    func setProtectionEnabled(_ enabled: Bool, forWebID id: UUID) async
    /// Uwierzytelnia i - po sukcesie - odblokowuje stronę (zdejmuje wpis z hosts na
    /// czas sesji; re-lock po bezczynności). Zwraca, czy się powiodło.
    @discardableResult
    func authenticateWebTarget(id: UUID, preferPassword: Bool) async -> Bool
    func lockWebTarget(id: UUID, reason: ActivityEvent.Reason) async
    func beginWebAuthentication(id: UUID) async
    func cancelWebAuthentication(id: UUID) async
    /// Przełącznik MODUŁU blokowania stron. Włączenie ustawia systemowe proxy
    /// (jednorazowy admin); zwraca, czy się powiodło (admin mógł być anulowany).
    @discardableResult
    func setWebsiteBlockingEnabled(_ enabled: Bool) async -> Bool
    /// Przełącznik MODUŁU blokowania aplikacji (całkowite włącz/wyłącz).
    func setAppBlockingEnabled(_ enabled: Bool) async
    /// Wstrzymuje ochronę stron na `minutes` (snooze); 0 = do ręcznego wznowienia.
    /// Wołane po Touch ID/haśle; nie rusza systemowego proxy.
    func pauseWebsiteProtection(minutes: Int) async
    /// Wznawia wstrzymaną ochronę stron (auto po czasie lub ręcznie).
    func resumeWebsiteProtection() async
    /// Zamyka żądanie wstrzymania z rozszerzenia (po auth albo anulowaniu).
    func clearPendingPauseRequest(id: UUID) async
    /// Zamyka żądanie usunięcia strony z ochrony zainicjowane przez rozszerzenie.
    func clearPendingWebRemovalRequest(id: UUID) async
    /// Sprząta blokadę stron (systemowe proxy) - np. przy deinstalacji.
    func clearWebsiteBlocks() async

    // MARK: Akcje wrażliwe (sekcja 18)
    /// Uwierzytelnienie wymagane przed wyłączeniem ochrony / zamknięciem Privio.
    /// Zwraca, czy się powiodło. `reason` to gotowy, zlokalizowany opis.
    func authenticateForAction(reason: String) async -> Bool

    // MARK: Ustawienia globalne
    func updateConfiguration(_ config: AppConfiguration) async
    /// Globalny wyłącznik ochrony. Wyłączenie w produkcji będzie wymagało
    /// uwierzytelnienia (egzekwowane w warstwie wyżej - sekcja 18).
    func setProtectionActive(_ active: Bool) async

    // MARK: Activity
    func clearActivityHistory() async
}

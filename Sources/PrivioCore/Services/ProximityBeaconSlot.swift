import Foundation

/// Czysta, testowalna logika okna czasowego tokenu obecności Privio Beacon (PV02).
///
/// Zegarek rozgłasza token podpisany numerem **slotu** (czas / `slotSeconds`), a Mac
/// akceptuje advert tylko gdy slot mieści się w tolerowanym oknie względem własnego
/// zegara. Wcześniej tolerancja była symetryczna `±1 slot` (±30 s) - przy dryfie
/// zegarów zegarek↔Mac powyżej 30 s **każdy** advert był odrzucany, więc bliskie
/// urządzenie wyglądało jak „odeszło" i Mac blokował się losowo.
///
/// Tolerancja jest teraz **asymetryczna**:
/// - szeroko w przeszłość - powtórzony/stary token może co najwyżej *opóźnić*
///   auto-blokadę (beacon **wyłącznie wyzwala** blokadę, nigdy nie odblokowuje),
///   więc szersze okno w przeszłość nie osłabia bezpieczeństwa (HMAC dalej
///   uwierzytelnia payload);
/// - wąsko w przyszłość - token „z przyszłości" oznacza źle ustawiony zegar i nie
///   ma powodu, by akceptować go szeroko.
public enum ProximityBeaconSlot {
    /// Długość slotu tokenu obecności w sekundach. **MUSI** być zgodna z zegarkiem
    /// (WearOS `BeaconService.kt`, dzielnik `currentTimeMillis() / (slotSeconds * 1000)`).
    /// Zmiana tej wartości wymaga skoordynowanego wydania po obu stronach.
    public static let slotSeconds: UInt32 = 30

    /// Tolerancja rozjazdu zegarów w slotach (patrz opis typu).
    public static let pastToleranceSlots: Int64 = 4     // ≈ 2 min w przeszłość
    public static let futureToleranceSlots: Int64 = 2   // ≈ 1 min w przyszłość

    /// Bieżący numer slotu wg zegara Maca.
    public static func currentSlot(at date: Date = Date()) -> UInt32 {
        UInt32(date.timeIntervalSince1970 / Double(slotSeconds))
    }

    /// Czy advertowany slot mieści się w tolerowanym oknie względem bieżącego slotu.
    public static func isSlotAcceptable(
        advertisedSlot: UInt32,
        currentSlot: UInt32,
        pastTolerance: Int64 = pastToleranceSlots,
        futureTolerance: Int64 = futureToleranceSlots
    ) -> Bool {
        let delta = Int64(advertisedSlot) - Int64(currentSlot)
        return delta >= -pastTolerance && delta <= futureTolerance
    }
}

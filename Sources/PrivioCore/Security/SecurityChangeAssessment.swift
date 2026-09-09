import Foundation

/// Klasyfikuje zmianę ustawień wyłącznie pod kątem tego, czy obniża poziom
/// ochrony. Warstwa UI używa wyniku do wymagania systemowego uwierzytelnienia.
public enum SecurityChangeAssessment {
    public static func weakensProtection(from old: AppConfiguration,
                                         to new: AppConfiguration) -> Bool {
        (old.lockAllAfterScreenLock && !new.lockAllAfterScreenLock)
            || (old.lockAllAfterSleep && !new.lockAllAfterSleep)
            || (old.defaultRequireTouchID && !new.defaultRequireTouchID)
            || (!old.defaultAllowPasswordFallback && new.defaultAllowPasswordFallback)
            || timeoutIsWeaker(old: old.defaultLockTimeout, new: new.defaultLockTimeout)
    }

    public static func weakensProtection(from old: ProtectedApp,
                                         to new: ProtectedApp) -> Bool {
        (old.protectionEnabled && !new.protectionEnabled)
            || (old.lockAfterScreenLock && !new.lockAfterScreenLock)
            || (old.lockAfterSleep && !new.lockAfterSleep)
            || (old.requireTouchID && !new.requireTouchID)
            || (!old.allowPasswordFallback && new.allowPasswordFallback)
            || timeoutIsWeaker(old: old.lockAfterInactivity, new: new.lockAfterInactivity)
    }

    /// `nil` oznacza „nigdy”, czyli najsłabszą wartość. Krótszy czas wzmacnia
    /// ochronę, dłuższy ją osłabia.
    private static func timeoutIsWeaker(old: TimeInterval?, new: TimeInterval?) -> Bool {
        switch (old, new) {
        case (nil, _): return false
        case (_, nil): return true
        case let (old?, new?): return new > old
        }
    }
}

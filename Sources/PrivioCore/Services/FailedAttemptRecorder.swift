import Foundation

/// Opcjonalny, lokalny zapis dowodu po nieudanym uwierzytelnieniu. Implementacja
/// produkcyjna żyje w targetcie aplikacji, ponieważ korzysta z AVFoundation.
public protocol FailedAttemptRecording: Sendable {
    /// Zwraca lokalną nazwę pliku dowodu, którą można trwale powiązać z logiem.
    func recordFailedAttempt(bundleID: String, appName: String) async -> String?
}

import Foundation
import os

/// Cienka nakładka na `os.Logger` z jednym subsystemem Privio.
/// Świadomie NIE logujemy treści chronionych aplikacji ani danych wrażliwych -
/// tylko zdarzenia stanu (sekcje 19 i 24 specyfikacji).
public enum PrivioLog {
    private static let subsystem = "com.privio.Privio"

    public static let enforcement = Logger(subsystem: subsystem, category: "enforcement")
    public static let auth        = Logger(subsystem: subsystem, category: "auth")
    public static let monitor     = Logger(subsystem: subsystem, category: "monitor")
    public static let persistence = Logger(subsystem: subsystem, category: "persistence")
    public static let ui          = Logger(subsystem: subsystem, category: "ui")
}

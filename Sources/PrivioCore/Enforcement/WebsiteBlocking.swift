import Foundation

/// Czysta (testowalna) logika zarządzania sekcją Privio w `/etc/hosts`.
///
/// Blokada = zmapowanie zablokowanych hostów na `0.0.0.0` w wyznaczonym, oznaczonym
/// bloku. Resztę pliku zostawiamy nietkniętą. Zapis do `/etc/hosts` (root) robi
/// osobna, uprzywilejowana warstwa - tu jest tylko generowanie treści.
public enum PrivioHostsBlock {
    public static let begin = "# BEGIN PRIVIO - zarządzane automatycznie, nie edytuj ręcznie"
    public static let end = "# END PRIVIO"

    /// Zwraca sekcję Privio dla podanych hostów (posortowane, bez duplikatów), albo
    /// pusty string gdy brak hostów.
    public static func section(for hostnames: [String]) -> String {
        let hosts = Array(Set(hostnames.map { $0.lowercased() })).sorted()
        guard !hosts.isEmpty else { return "" }
        var lines = [begin]
        for host in hosts {
            lines.append("0.0.0.0\t\(host)")
            lines.append("::1\t\(host)")
        }
        lines.append(end)
        return lines.joined(separator: "\n")
    }

    /// Usuwa istniejącą sekcję Privio (jeśli jest) z treści `/etc/hosts`.
    public static func removed(from contents: String) -> String {
        guard let beginRange = contents.range(of: begin) else { return contents }
        // Znajdź koniec bloku (linia z `end`); usuń łącznie z ewentualną poprzedzającą
        // pustą linią i znakiem nowej linii po `end`.
        let afterBeginToEnd = contents.range(of: end, range: beginRange.upperBound..<contents.endIndex)
        let blockEnd = afterBeginToEnd?.upperBound ?? contents.endIndex
        var start = beginRange.lowerBound
        // zjedz pojedynczy `\n` przed blokiem, by nie zostawiać podwójnych pustych linii
        if start > contents.startIndex {
            let prev = contents.index(before: start)
            if contents[prev] == "\n" { start = prev }
        }
        var end = blockEnd
        if end < contents.endIndex, contents[end] == "\n" { end = contents.index(after: end) }
        var result = contents
        result.removeSubrange(start..<end)
        return result
    }

    /// Zwraca nową treść `/etc/hosts`: bez starej sekcji Privio, z nową sekcją dla
    /// `hostnames` dopiętą na końcu (jeśli niepusta). Idempotentne.
    public static func apply(hostnames: [String], to contents: String) -> String {
        let base = removed(from: contents)
        let sec = section(for: hostnames)
        guard !sec.isEmpty else { return base }
        let trimmed = base.hasSuffix("\n") ? String(base.dropLast()) : base
        return trimmed.isEmpty ? sec + "\n" : trimmed + "\n\n" + sec + "\n"
    }
}

/// Seam do egzekwowania blokady stron (docelowo za XPC/uprzywilejowanym helperem).
/// Implementacja produkcyjna edytuje `/etc/hosts` z autoryzacją administratora i
/// odświeża cache DNS; testy używają atrapy operującej na stringu w pamięci.
public protocol WebsiteBlocking: Sendable {
    /// Ustawia dokładnie ten zestaw zablokowanych hostów (pełna synchronizacja stanu).
    /// Rzuca, jeśli autoryzacja administratora się nie powiodła.
    func setBlockedHosts(_ hostnames: [String]) async throws

    /// Zdejmuje całą blokadę Privio (np. przy wyłączeniu ochrony / deinstalacji).
    func clearAll() async throws
}

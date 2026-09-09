import Foundation

/// Konfiguruje systemowe proxy jako **auto‑proxy (PAC)** wskazujący na plik PAC
/// serwowany przez Privio po **HTTP** (`http://127.0.0.1:PORT/privio.pac`).
///
/// PAC kieruje przez Privio **tylko wybrane, chronione domeny** (reszta → DIRECT) i
/// NIE ma fallbacku DIRECT dla nich - dzięki temu przeglądarka nie omija blokady.
/// Skutek: gdy Privio nie działa, chronione strony są nieosiągalne (reszta internetu
/// działa) - wracają, gdy Privio wystartuje. Świadomy kompromis; pełny fail‑open da
/// dopiero NetworkExtension (Developer ID).
///
/// (Wcześniej próbowaliśmy `file://` PAC - macOS go NIE honoruje ze względów
/// bezpieczeństwa; stąd serwowanie po HTTP z lokalnego serwera Privio.)
public enum SystemWebProxy {

    /// Treść PAC dla podanych chronionych domen (serwowana przez `WebProxyServer`).
    public static func pacContents(port: UInt16, domains: [String]) -> String {
        let list = domains.map { "\"\($0.lowercased())\"" }.joined(separator: ",")
        return """
        var PRIVIO=[\(list)];
        function FindProxyForURL(url, host){
          host=host.toLowerCase();
          for(var i=0;i<PRIVIO.length;i++){
            var d=PRIVIO[i];
            if(host==d||dnsDomainIs(host,"."+d)) return "PROXY 127.0.0.1:\(port)";
          }
          return "DIRECT";
        }
        """
    }

    /// Ustawia URL auto‑proxy (PAC po HTTP) na wszystkich aktywnych usługach.
    /// Jednorazowy admin.
    public static func enable(port: UInt16) throws {
        let url = "http://127.0.0.1:\(port)\(pacPath)"
        try PrivilegedShell.run(scriptEnable(pacURL: url))
    }

    public static func disable() throws {
        try PrivilegedShell.run(scriptDisable)
    }

    private static let pacPath = "/privio.pac"

    // MARK: - Skrypty networksetup

    private static func scriptEnable(pacURL: String) -> String {
        """
        /usr/sbin/networksetup -listallnetworkservices | /usr/bin/tail -n +2 | /usr/bin/grep -v '^\\*' | while IFS= read -r s; do
          /usr/sbin/networksetup -setautoproxyurl "$s" "\(pacURL)"
          /usr/sbin/networksetup -setautoproxystate "$s" on
        done
        """
    }

    private static let scriptDisable = """
        /usr/sbin/networksetup -listallnetworkservices | /usr/bin/tail -n +2 | /usr/bin/grep -v '^\\*' | while IFS= read -r s; do
          /usr/sbin/networksetup -setautoproxystate "$s" off
        done
        """
}

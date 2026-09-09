#!/usr/bin/env swift
// Wydaje podpisaną licencję Privio Pro (dla developera / systemu wydawania licencji).
// Klucz prywatny NIGDY nie jest w repo - skrypt czyta go z pliku poza repo
// (domyślnie ~/.privio-license-signing-key.txt) lub ze zmiennej środowiskowej.
//
// Użycie:
//   swift Scripts/sign_license.swift [license_id]
//   PRIVIO_LICENSE_PRIVATE_KEY_FILE=/secure/path/key swift Scripts/sign_license.swift [license_id]
//
// Wynik (stdout): łańcuch licencji do wklejenia w Privio ("Activate Pro").
import CryptoKit
import Foundation

let environment = ProcessInfo.processInfo.environment
let defaultKeyURL = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".privio-license-signing-key.txt")
let keyURL = environment["PRIVIO_LICENSE_PRIVATE_KEY_FILE"].map {
    URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath)
} ?? defaultKeyURL
let fileKey = try? String(contentsOf: keyURL, encoding: .utf8)
let keyFromFile: String? = fileKey.flatMap { contents in
    let trimmed = contents.trimmingCharacters(in: .whitespacesAndNewlines)
    if Data(base64Encoded: trimmed) != nil { return trimmed }
    guard let privateLine = contents.components(separatedBy: .newlines)
        .first(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("PRIVATE") }),
          let separator = privateLine.firstIndex(of: ":") else { return nil }
    return String(privateLine[privateLine.index(after: separator)...])
        .trimmingCharacters(in: .whitespacesAndNewlines)
}
let privateKeyBase64 = environment["PRIVIO_LICENSE_PRIVATE_KEY"]
    ?? keyFromFile

guard let privB64 = privateKeyBase64,
      let privData = Data(base64Encoded: privB64),
      let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: privData) else {
    FileHandle.standardError.write(Data("Brak poprawnego prywatnego klucza Ed25519: \(keyURL.path)\n".utf8))
    exit(1)
}

// Fail closed: nie wydawaj pozornie poprawnych licencji kluczem, którego aktualna
// aplikacja nie rozpoznaje. Wartość musi odpowiadać LicenseVerifier.
let embeddedPublicKeyBase64 = "SOrOsc1nJoDo6FSNaBVKcbojunCwLlsVhxy76i0NsmI="
guard key.publicKey.rawRepresentation.base64EncodedString() == embeddedPublicKeyBase64 else {
    FileHandle.standardError.write(Data("Klucz prywatny nie pasuje do publicznego klucza w aplikacji.\n".utf8))
    exit(2)
}

let licenseID = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "PRIVIO-TEST-" + UUID().uuidString.prefix(8)

let dateFmt = ISO8601DateFormatter()
dateFmt.formatOptions = [.withFullDate]
let issuedAt = dateFmt.string(from: Date())

struct Payload: Codable {
    var schema = 1
    var product = "privio"
    var edition = "pro"
    var license_id: String
    var issued_at: String
}

let payload = Payload(license_id: String(licenseID), issued_at: issuedAt)
let encoder = JSONEncoder()
encoder.outputFormatting = [.sortedKeys]
let payloadData = try! encoder.encode(payload)
let signature = try! key.signature(for: payloadData)

func b64url(_ d: Data) -> String {
    d.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}

print(b64url(payloadData) + "." + b64url(signature))

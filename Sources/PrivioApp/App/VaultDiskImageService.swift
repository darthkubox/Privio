import Foundation

struct VaultMount: Sendable, Equatable {
    let device: String
    let url: URL
}

/// Obsługa szyfrowanego obrazu dysku przez publiczne narzędzie macOS `hdiutil`.
/// Hasło jest zawsze podawane przez stdin - nigdy jako argument procesu ani log.
actor VaultDiskImageService {
    enum DiskError: LocalizedError {
        case alreadyExists
        case missingImage
        case commandFailed(String)
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .alreadyExists: return "A private vault already exists."
            case .missingImage: return "The encrypted vault image could not be found."
            case .commandFailed(let message): return message
            case .invalidResponse: return "macOS mounted the vault but returned an invalid response."
            }
        }
    }

    let imageURL: URL

    init(imageURL: URL = VaultPaths.imageURL) {
        self.imageURL = imageURL
    }

    func exists() -> Bool {
        FileManager.default.fileExists(atPath: imageURL.path)
    }

    func create(password: String, capacityGB: Int = 20) throws {
        guard !exists() else { throw DiskError.alreadyExists }
        try FileManager.default.createDirectory(
            at: imageURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        _ = try run(
            arguments: [
                "create", "-size", "\(capacityGB)g",
                "-type", "SPARSEBUNDLE",
                "-fs", "APFS",
                "-volname", "Privio Vault",
                "-encryption", "AES-256",
                "-nospotlight",
                "-stdinpass", "-quiet",
                imageURL.path
            ],
            password: password
        )
    }

    func attach(password: String) throws -> VaultMount {
        guard exists() else { throw DiskError.missingImage }
        if let current = try currentMount() { return current }
        let data = try run(
            arguments: ["attach", "-plist", "-stdinpass", "-noautoopen", "-owners", "on", imageURL.path],
            password: password
        )
        return try parseMount(from: data)
    }

    func detach(_ mount: VaultMount) throws {
        _ = try run(arguments: ["detach", mount.device, "-quiet"], password: nil)
    }

    /// Permanently removes the encrypted image. Refuse to touch it while macOS
    /// still reports this exact image as mounted.
    func delete() throws {
        guard exists() else { throw DiskError.missingImage }
        guard try currentMount() == nil else {
            throw DiskError.commandFailed("The vault is still mounted. Lock it before deleting it.")
        }
        try FileManager.default.removeItem(at: imageURL)
    }

    /// Odnajduje zamontowany egzemplarz tego konkretnego obrazu (np. po awarii apki).
    func currentMount() throws -> VaultMount? {
        let data = try run(arguments: ["info", "-plist"], password: nil)
        guard let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
              let images = plist["images"] as? [[String: Any]] else { return nil }

        let canonicalImage = imageURL.resolvingSymlinksInPath().standardizedFileURL.path
        for image in images {
            guard let path = image["image-path"] as? String,
                  URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path == canonicalImage,
                  let entities = image["system-entities"] as? [[String: Any]] else { continue }
            if let mount = mount(from: entities) { return mount }
        }
        return nil
    }

    private func parseMount(from data: Data) throws -> VaultMount {
        guard let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
              let entities = plist["system-entities"] as? [[String: Any]],
              let mount = mount(from: entities) else { throw DiskError.invalidResponse }
        return mount
    }

    private func mount(from entities: [[String: Any]]) -> VaultMount? {
        for entity in entities {
            guard let path = entity["mount-point"] as? String,
                  let device = entity["dev-entry"] as? String else { continue }
            return VaultMount(device: device, url: URL(fileURLWithPath: path, isDirectory: true))
        }
        return nil
    }

    private func run(arguments: [String], password: String?) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = arguments

        let output = Pipe()
        let errors = Pipe()
        let input = Pipe()
        process.standardOutput = output
        process.standardError = errors
        if password != nil { process.standardInput = input }

        try process.run()
        if let password {
            input.fileHandleForWriting.write(Data((password + "\n").utf8))
            try? input.fileHandleForWriting.close()
        }
        process.waitUntilExit()

        let outputData = output.fileHandleForReading.readDataToEndOfFile()
        let errorData = errors.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0 else {
            let raw = String(data: errorData, encoding: .utf8) ?? ""
            let message = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            throw DiskError.commandFailed(message.isEmpty ? "The encrypted vault operation failed." : message)
        }
        return outputData
    }
}

enum VaultPaths {
    static var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        // Osobny katalog: standardowe odinstalowanie Privio nie może skasować
        // zaszyfrowanych plików użytkownika razem z ustawieniami aplikacji.
        return base.appendingPathComponent("Privio Vault", isDirectory: true)
    }

    static var imageURL: URL {
        supportDirectory.appendingPathComponent("Privio Vault.sparsebundle", isDirectory: true)
    }
}

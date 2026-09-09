import AVFoundation
import Foundation
import PrivioCore

/// Jawny, opt-in recorder zdjęć po nieudanym uwierzytelnieniu. Niczego nie
/// wysyła; pliki zostają lokalnie i są ograniczone retencją.
actor CameraFailedAttemptRecorder: FailedAttemptRecording {
    static let maximumPhotoCount = 20

    static var photosDirectory: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Privio/Failed Attempts", isDirectory: true)
    }

    static func requestAuthorization() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video)
        case .denied, .restricted: return false
        @unknown default: return false
        }
    }

    func recordFailedAttempt(bundleID: String, appName: String) async -> String? {
        // Nie pokazujemy systemowego promptu w chwili nieudanej próby. Uprawnienie
        // jest proszone wcześniej, bezpośrednio przy włączaniu funkcji w Ustawieniach.
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized,
              let jpeg = await captureJPEG() else { return nil }

        let directory = Self.photosDirectory
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            let timestamp = Self.filenameFormatter.string(from: Date())
            let safeBundleID = bundleID.replacingOccurrences(of: "/", with: "-")
            let file = directory.appendingPathComponent("\(timestamp)-\(safeBundleID).jpg")
            try jpeg.write(to: file, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
            enforceRetention(in: directory)
            return file.lastPathComponent
        } catch {
            PrivioLog.persistence.error("Nie udało się zapisać zdjęcia nieudanej próby: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func captureJPEG() async -> Data? {
        guard let camera = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: camera) else { return nil }

        let session = AVCaptureSession()
        let output = AVCapturePhotoOutput()
        session.sessionPreset = .photo
        guard session.canAddInput(input), session.canAddOutput(output) else { return nil }
        session.addInput(input)
        session.addOutput(output)
        session.startRunning()
        defer { session.stopRunning() }

        // Rozgrzewka: pierwsza klatka po `startRunning` jest ciemna, bo auto-ekspozycja
        // i balans bieli jeszcze się nie ustawiły. Dajemy sensorowi chwilę na zbieżność,
        // inaczej zdjęcie z nieudanej próby wychodzi niedoświetlone.
        try? await Task.sleep(for: .milliseconds(800))

        return await withCheckedContinuation { continuation in
            let delegate = PhotoCaptureDelegate(continuation: continuation)
            output.capturePhoto(with: AVCapturePhotoSettings(), delegate: delegate)
            delegate.retainUntilCompletion()
        }
    }

    private func enforceRetention(in directory: URL) {
        let keys: Set<URLResourceKey> = [.creationDateKey, .isRegularFileKey]
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else { return }
        let photos = files.filter { $0.pathExtension.lowercased() == "jpg" }.sorted {
            let left = (try? $0.resourceValues(forKeys: keys).creationDate) ?? .distantPast
            let right = (try? $1.resourceValues(forKeys: keys).creationDate) ?? .distantPast
            return left > right
        }
        for oldFile in photos.dropFirst(Self.maximumPhotoCount) {
            try? FileManager.default.removeItem(at: oldFile)
        }
    }

    private static let filenameFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter
    }()
}

private final class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    private var continuation: CheckedContinuation<Data?, Never>?
    private var retainedSelf: PhotoCaptureDelegate?

    init(continuation: CheckedContinuation<Data?, Never>) {
        self.continuation = continuation
    }

    func retainUntilCompletion() { retainedSelf = self }

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        continuation?.resume(returning: error == nil ? photo.fileDataRepresentation() : nil)
        continuation = nil
        retainedSelf = nil
    }
}

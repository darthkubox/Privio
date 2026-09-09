@preconcurrency import AVFoundation
import AppKit
import SwiftUI
import Vision

struct PrivioQRScannerView: NSViewRepresentable {
    let onCode: (String) -> Void
    let onFailure: (String) -> Void
    /// Odrębny sygnał: brak zgody na kamerę → UI pokazuje przycisk do Ustawień systemowych.
    var onCameraDenied: () -> Void = {}
    /// Widoczny status kroków (żeby użytkownik widział, co się dzieje bez zaglądania do logów).
    var onStatus: (String) -> Void = { _ in }

    func makeCoordinator() -> Coordinator {
        Coordinator(onCode: onCode, onFailure: onFailure, onCameraDenied: onCameraDenied, onStatus: onStatus)
    }

    func makeNSView(context: Context) -> CameraPreviewView {
        let view = CameraPreviewView()
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ nsView: CameraPreviewView, context: Context) {}

    static func dismantleNSView(_ nsView: CameraPreviewView, coordinator: Coordinator) {
        coordinator.stop()
    }

    final class Coordinator: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
        private let onCode: (String) -> Void
        private let onFailure: (String) -> Void
        private let onCameraDenied: () -> Void
        private let onStatus: (String) -> Void
        private let queue = DispatchQueue(label: "com.privio.pairing-camera")
        private var session: AVCaptureSession?
        private var delivered = false
        private var analyzingFrame = false

        init(onCode: @escaping (String) -> Void, onFailure: @escaping (String) -> Void,
             onCameraDenied: @escaping () -> Void, onStatus: @escaping (String) -> Void) {
            self.onCode = onCode
            self.onFailure = onFailure
            self.onCameraDenied = onCameraDenied
            self.onStatus = onStatus
        }

        func attach(to view: CameraPreviewView) {
            Task { @MainActor in
                let status = AVCaptureDevice.authorizationStatus(for: .video)
                onStatus(String(localized: "Checking camera access…"))
                let allowed: Bool
                switch status {
                case .authorized: allowed = true
                case .notDetermined:
                    // Prompt systemowy TCC gubi się dla aplikacji pomocniczej (accessory) bez
                    // aktywnego okna - tak jak Touch ID. Na czas pytania podnosimy politykę do
                    // .regular i aktywujemy Privio, żeby systemowy dialog kamery na pewno wyskoczył.
                    let previousPolicy = NSApp.activationPolicy()
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate(ignoringOtherApps: true)
                    onStatus(String(localized: "Waiting for your permission…"))
                    allowed = await AVCaptureDevice.requestAccess(for: .video)
                    if previousPolicy != .regular { NSApp.setActivationPolicy(previousPolicy) }
                default: allowed = false
                }
                guard allowed else {
                    onStatus(String(localized: "Camera access is off."))
                    onCameraDenied()
                    return
                }
                // Creating AVCaptureDeviceInput may synchronously contact the camera service.
                // Never do that on the main actor: immediately after the first TCC prompt it can
                // block the UI before the preview layer and status are updated.
                configure(view)
            }
        }

        private func configure(_ view: CameraPreviewView) {
            queue.async { [weak self, weak view] in
                guard let self else { return }
                let devices = AVCaptureDevice.DiscoverySession(
                    deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
                    mediaType: .video, position: .unspecified).devices
                guard let camera = AVCaptureDevice.default(for: .video) ?? devices.first,
                      let input = try? AVCaptureDeviceInput(device: camera) else {
                    self.fail(String(localized: "No camera is available on this Mac."))
                    return
                }
                let session = AVCaptureSession()
                // AVCaptureMetadataOutput crashes on macOS 26.5 (Tundra camera stack)
                // when `.qr` is assigned, raising an Objective-C exception that Swift
                // cannot catch. Feed camera frames to Vision instead.
                let output = AVCaptureVideoDataOutput()
                output.alwaysDiscardsLateVideoFrames = true
                guard session.canAddInput(input), session.canAddOutput(output) else {
                    self.fail(String(localized: "The camera could not be started."))
                    return
                }
                session.beginConfiguration()
                session.addInput(input)
                session.addOutput(output)
                output.setSampleBufferDelegate(self, queue: self.queue)
                session.commitConfiguration()
                self.session = session
                DispatchQueue.main.async {
                    view?.previewLayer.session = session
                    self.onStatus(String(localized: "Point the camera at the QR code."))
                }
                session.startRunning()
            }
        }

        private func fail(_ message: String) {
            DispatchQueue.main.async { [onStatus, onFailure] in
                onStatus(message)
                onFailure(message)
            }
        }

        func captureOutput(_ output: AVCaptureOutput,
                           didOutput sampleBuffer: CMSampleBuffer,
                           from connection: AVCaptureConnection) {
            guard !delivered, !analyzingFrame,
                  let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
            analyzingFrame = true
            defer { analyzingFrame = false }

            let request = VNDetectBarcodesRequest()
            request.symbologies = [.qr]
            do {
                try VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up).perform([request])
                guard let value = request.results?.first(where: { $0.symbology == .qr })?.payloadStringValue,
                      !value.isEmpty else { return }
                delivered = true
                DispatchQueue.main.async { [onCode] in onCode(value) }
            } catch {
            }
        }

        func stop() {
            let session = session
            queue.async { session?.stopRunning() }
        }
    }
}

final class CameraPreviewView: NSView {
    let previewLayer = AVCaptureVideoPreviewLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        previewLayer.videoGravity = .resizeAspectFill
        layer?.addSublayer(previewLayer)
    }

    required init?(coder: NSCoder) { nil }
    override func layout() { super.layout(); previewLayer.frame = bounds }
}

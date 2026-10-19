//
//  CameraView.swift
//  ray
//
//  The camera command. One shared capture session that is built ahead of time, so opening the
//  camera is only "start the hardware", and stopped the moment the launcher closes (camera light off).
//

import SwiftUI
import AVFoundation
import AppKit

/// Everything slow happens on its own queue, never on the main thread
/// nonisolated because the project's default isolation is the main actor
nonisolated final class CameraSession: @unchecked Sendable {
    static let shared = CameraSession()
    let session = AVCaptureSession()

    private let queue = DispatchQueue(label: "ray.camera", qos: .userInteractive)
    private var configured = false
    private var pendingStop: DispatchWorkItem?

    private init() {}

    /// Call once at launch. Finds the built-in camera and adds it as an input, but does NOT start it,
    /// so the light stays off. Does nothing until camera access has been granted
    func prepare() {
        queue.async { [self] in configureIfNeeded() }
    }

    /// Safe to call as often as you like, a running session is left alone and a pending stop is cancelled
    func start() {
        queue.async { [self] in
            pendingStop?.cancel()
            pendingStop = nil
            configureIfNeeded()
            guard configured, !session.isRunning else { return }

            #if DEBUG
            let t0 = ContinuousClock.now
            #endif
            session.startRunning() // blocks until the hardware is actually streaming
            #if DEBUG
            print("camera startRunning took:", ContinuousClock.now - t0)
            #endif
        }
    }

    /// A delay lets a warm-up that wasn't used turn itself off, and a start() before then cancels it
    func stop(after delay: TimeInterval = 0) {
        queue.async { [self] in
            pendingStop?.cancel()
            let work = DispatchWorkItem { [self] in
                if session.isRunning { session.stopRunning() }
            }
            pendingStop = work
            queue.asyncAfter(deadline: .now() + delay, execute: work)
        }
    }

    private func configureIfNeeded() {
        guard !configured, AVCaptureDevice.authorizationStatus(for: .video) == .authorized else { return }

        // The built-in camera specifically, not an iPhone that Continuity Camera happens to offer
        let discovery = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera],
                                                         mediaType: .video,
                                                         position: .unspecified)
        guard let device = discovery.devices.first,
              let input = try? AVCaptureDeviceInput(device: device) else { return }

        session.beginConfiguration()
        if session.canSetSessionPreset(.hd1280x720) { session.sessionPreset = .hd1280x720 }
        if session.canAddInput(input) { session.addInput(input) }
        session.commitConfiguration()
        configured = true
    }
}

/// The live picture. A plain layer-backed view, so there's no SwiftUI overhead per frame
final class CameraPreviewView: NSView {
    init(session: AVCaptureSession) {
        super.init(frame: .zero)
        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        layer = preview // set the layer first, then wantsLayer, so AppKit keeps this layer instead of making its own
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> CameraPreviewView { CameraPreviewView(session: session) }
    func updateNSView(_ view: CameraPreviewView, context: Context) {}
}

/// What fills the launchpad while the camera command is open
/// Disappearing stops the camera, so closing the launcher always turns the light off
struct CameraTile: View {
    @State private var status = AVCaptureDevice.authorizationStatus(for: .video)
    // A warmed-up session started before this view existed, so its "did start" notification has already gone by
    @State private var live = CameraSession.shared.session.isRunning

    var body: some View {
        ZStack {
            Color.black

            switch status {
            case .authorized:
                CameraPreview(session: CameraSession.shared.session)
                    .scaleEffect(x: -1, y: 1) // mirrored, like a mirror
                    .opacity(live ? 1 : 0)
                    .animation(.easeOut(duration: 0.2), value: live)

                if !live { placeholder }

            case .notDetermined:
                placeholder

            default:
                deniedView
            }
        }
        .task { await start() }
        .onDisappear { CameraSession.shared.stop() }
        .onReceive(NotificationCenter.default.publisher(for: AVCaptureSession.didStartRunningNotification,
                                                        object: CameraSession.shared.session)) { _ in live = true }
        .onReceive(NotificationCenter.default.publisher(for: AVCaptureSession.didStopRunningNotification,
                                                        object: CameraSession.shared.session)) { _ in live = false }
    }

    private var placeholder: some View {
        Image(systemName: "web.camera")
            .font(.system(size: 34, weight: .light))
            .foregroundStyle(.tertiary)
    }

    private var deniedView: some View {
        VStack(spacing: 10) {
            Image(systemName: "video.slash")
                .font(.system(size: 30, weight: .light))
            Text("Camera access is off")
                .font(.system(size: 13, weight: .medium))
            Button("Open Settings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.white.opacity(0.12)))
        }
        .foregroundStyle(.secondary)
    }

    private func start() async {
        if status == .notDetermined {
            _ = await AVCaptureDevice.requestAccess(for: .video) // the system prompt, only ever shown once
            status = AVCaptureDevice.authorizationStatus(for: .video)
        }
        if status == .authorized {
            CameraSession.shared.start()
            live = CameraSession.shared.session.isRunning
        }
    }
}

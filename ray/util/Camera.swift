//
//  Camera.swift
//  ray
//
//  Created by Dylan Karunanayake on 25/10/2026.
//

import SwiftUI
import AVFoundation

final class CameraSession: @unchecked Sendable {
    static let shared = CameraSession()
    
    private var lastStop = Date.distantPast
    private let minRestartGap: TimeInterval = 0.5
    
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "ray.camera")
    private var generation = 0 // this is to prevent an old delayed stop can't kill a newer start
    
    // Get permission to take output from camera if not yet given
    func prepare() {
        if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
            AVCaptureDevice.requestAccess(for: .video) { _ in }
        }
    }
    
    func start() {
        queue.async {
            self.generation += 1
            let gen = self.generation
            guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized, !self.session.isRunning else { return }
            
            // This was giving me issues with restarting the camera after stopping
            // We need to give  CMIO time to finish tearing down the previous graph
            let wait = self.minRestartGap - Date().timeIntervalSince(self.lastStop)
            if wait > 0 { Thread.sleep(forTimeInterval: wait) }
            
            guard gen == self.generation else  { return }
            self.rebuildInput()
            self.session.startRunning()
        }
    }
    
    func stop(after delay: Double = 0) {
        queue.async {
            self.generation += 1
            let gen = self.generation
            self.queue.asyncAfter(deadline: .now() + delay) {
                guard gen == self.generation, self.session.isRunning else { return }
                self.session.stopRunning()
                self.lastStop = Date()
            }
        }
    }
    
    // A fresh input each time the session starts, so a broken graph from an earlier run can't stick around
    private func rebuildInput() {
        guard let device = AVCaptureDevice.default(for: .video), let input = try? AVCaptureDeviceInput(device: device) else { return }
        session.beginConfiguration()
        session.inputs.forEach { session.removeInput($0) }
        session.sessionPreset = .medium
        if session.canAddInput(input) { session.addInput(input) }
        session.commitConfiguration()
    }
}


final class PreviewView: NSView {
    private var observer: NSObjectProtocol?

    override func makeBackingLayer() -> CALayer {
        let layer = AVCaptureVideoPreviewLayer(session: CameraSession.shared.session)
        layer.videoGravity = .resizeAspectFill
        return layer
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        observer = NotificationCenter.default.addObserver(
            forName: AVCaptureSession.didStartRunningNotification,
            object: CameraSession.shared.session, queue: .main
        ) { [weak self] _ in self?.applyMirroring(retries: 3) }
    }
    required init?(coder: NSCoder) { fatalError() }

    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyMirroring(retries: 3)
    }

    override func layout() {
        super.layout()
        applyMirroring(retries: 0)
    }

    // The connection can be missing or replaced while the session starts and restards, so try a few times
    private func applyMirroring(retries: Int) {
        if let conn = (layer as? AVCaptureVideoPreviewLayer)?.connection, conn.isVideoMirroringSupported {
            conn.automaticallyAdjustsVideoMirroring = false
            conn.isVideoMirrored = false
        } else if retries > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.applyMirroring(retries: retries - 1)
            }
        }
    }
}

struct CameraTile: NSViewRepresentable {
    func makeNSView(context: Context) -> PreviewView { PreviewView() }
    func updateNSView(_ nsView: PreviewView, context: Context) {}
}

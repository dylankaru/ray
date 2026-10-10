//
//  LauncherPanel.swift
//  ray
//
//  Created by Dylan Karunanayake on 8/10/2026.
//

import AppKit
import SwiftUI

extension Notification.Name {
    /// Posted when the launcher shows or hides. ContentView wipes its state.
    static let rayReset = Notification.Name("ray.reset")
}

final class LauncherPanel: NSPanel {
    init<V: View>(rootView: V) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 800),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false               // shadows are drawn in SwiftUI
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        contentView = NSHostingView(rootView: rootView)
    }

    override var canBecomeKey: Bool { true }

    override func resignKey() {        // click away = hide
        super.resignKey()
        orderOut(nil)
    }

    override func orderOut(_ sender: Any?) {
        super.orderOut(sender)
        NotificationCenter.default.post(name: .rayReset, object: nil)
    }

    func positionOnActiveScreen() {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let f = screen.visibleFrame
        setFrameOrigin(NSPoint(x: f.midX - frame.width / 2,
                               y: f.maxY - frame.height - f.height * 0.2))
    }
}

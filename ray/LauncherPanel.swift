//
//  LauncherPanel.swift
//  ray
//
//  Created by Dylan Karunanayake on 8/10/2026.
//

import AppKit
import SwiftUI

extension Notification.Name {
    // Posted when the launcher shows or hides. ContentView wipes its state.
    static let rayReset = Notification.Name("ray.reset")
    // Asks ContentView to (re)focus its text field once the panel is really key.
    static let rayFocus = Notification.Name("ray.focus")
}

final class LauncherPanel: NSPanel {
    static let size = NSSize(width: 520, height: 900)

    init<V: View>(rootView: V) {
        super.init(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let hosting = NSHostingView(rootView: rootView)
        hosting.sizingOptions = [] // the hosting view never drives the window size
        contentView = hosting

        contentMinSize = Self.size
        contentMaxSize = Self.size
    }

    override var canBecomeKey: Bool { true }

    /// In app mode the launcher stays up when you click away.
    var pinned = false

    override func resignKey() {        // click away = hide
        super.resignKey()
        if !pinned { orderOut(nil) }
    }

    override func orderOut(_ sender: Any?) {
        super.orderOut(sender)
        NotificationCenter.default.post(name: .rayReset, object: nil)
    }

    // The system is not allowed to nudge the panel back onto the screen
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }

    func positionOnActiveScreen() {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let f = screen.visibleFrame
        let size = Self.size

        // The content is top-aligned, so anchor the window by its top edge
        // This is the same top edge a centered 800pt window had, so the launchpad sits where it always did
        let top = min(f.midY + 400, f.maxY)
        let origin = NSPoint(x: f.midX - size.width / 2, y: top - size.height)

        setFrame(NSRect(origin: origin, size: size), display: false)
    }
}

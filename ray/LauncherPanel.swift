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
    static let size = NSSize(width: 2000, height: 910)

    init<V: View>(rootView: V) {
        super.init(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .screenSaver
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

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
    
    override func noResponder(for eventSelector: Selector) {
        if eventSelector == #selector(NSResponder.keyDown(with:)) {
            NotificationCenter.default.post(name: .rayFocus, object: nil)
            return
        }
        super.noResponder(for: eventSelector)
    }

    override func sendEvent(_ event: NSEvent) {
        if (event.type == .leftMouseDown || event.type == .rightMouseDown), !isKeyWindow {
            makeKeyAndOrderFront(nil)
        }
        super.sendEvent(event)
    }

    func positionOnActiveScreen() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main ?? NSScreen.screens[0]

        let full = screen.frame
        let visible = screen.visibleFrame
        let size = Self.size

        // Centred horizontally on the whole screen and vertically in the area below the menu bar
        let origin = NSPoint(x: full.midX - size.width / 2,
                             y: visible.midY - size.height / 2)

        setFrame(NSRect(origin: origin, size: size), display: false)
    }
}

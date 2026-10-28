//
//  LauncherPanel.swift
//  ray
//
//  Created by Dylan Karunanayake on 8/10/2026.
//

import AppKit
import SwiftUI

extension Notification.Name {
    // Posted when the launcher shows or hides. ContentView wipes its state
    static let rayReset = Notification.Name("ray.reset")
    // Asks ContentView to focus and refocus its text field once the panel is really key
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
        level = .screenSaver // nvm couldn't see it in fullscreen apps :/
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        
        let hosting = NSHostingView(rootView: rootView)
        hosting.sizingOptions = [] // the hosting view never drives the window size
        contentView = hosting
        
        // when trying to reopen the camera there was a bug that caused the whole app to crash due to stacking of passed constraints
        // so this just makes it so that hosting view isn't the window's content view
        let container = NSView(frame: NSRect(origin: .zero, size: Self.size))
        hosting.frame = container.bounds
        hosting.autoresizingMask = [.width, .height]
        container.addSubview(hosting)
        contentView = container
        
        contentMinSize = Self.size
        contentMaxSize = Self.size
        observeBar()
    }
    
    override var canBecomeKey: Bool { true }
    
    var pinned = false
    
    override func resignKey() {
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
        // There's a swiftui error i have no idea how to fix
        // Some sort of quality of service thing
        // and sometimes it doesnt show up so idek :/
    }
    
    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        super.setFrame(NSRect(origin: frameRect.origin, size: Self.size), display: flag)
    }
    
    func positionOnActiveScreen() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
        ?? NSScreen.main ?? NSScreen.screens[0]
        
        let full = screen.frame
        let visible = screen.visibleFrame
        let size = Self.size
        
        let yOffset: CGFloat = UtilityBarManager.shared.isVisible ? 0 : 50
        
        let origin = NSPoint(x: full.midX - size.width / 2,
                             y: visible.midY - size.height / 2 - yOffset)
        
        setFrame(NSRect(origin: origin, size: size), display: false)
    }
    
    func observeBar() {
        withObservationTracking {
            _ = UtilityBarManager.shared.isVisible
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.positionOnActiveScreen()
                self?.observeBar()
            }
        }
    }
}

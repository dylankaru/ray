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
    init<V: View>(rootView: V) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 900),
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
        hosting.sizingOptions = []
        contentView = hosting
    }
    
    override var canBecomeKey: Bool { true }
    
    var pinned = false
    
    override func resignKey() {        // click away = hide
        super.resignKey()
        if !pinned { orderOut(nil) }
    }
    
    override func orderOut(_ sender: Any?) {
        super.orderOut(sender)
        NotificationCenter.default.post(name: .rayReset, object: nil)
    }
    
    func positionOnActiveScreen() {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let f = screen.visibleFrame
        
        let x = f.midX - (frame.width / 2)
        let y = f.midY - (frame.height / 2)
        
        setFrameOrigin(NSPoint(x: x, y: y))
    }
    
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
    
    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        print("frame ->", frameRect)
        super.setFrame(frameRect, display: flag)
    }
}

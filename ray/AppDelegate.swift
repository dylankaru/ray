//
//  AppDelegate.swift
//  ray
//
//  Created by Dylan Karunanayake on 8/10/2026.
//

import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: LauncherPanel!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)   // no Dock icon

        panel = LauncherPanel(rootView: ContentView())
        HotKey.register { [weak self] in self?.toggle() }
        toggle()
    }

    private func toggle() {
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            NotificationCenter.default.post(name: .rayReset, object: nil)   // open empty
            panel.positionOnActiveScreen()
            panel.makeKeyAndOrderFront(nil)
        }
    }
}

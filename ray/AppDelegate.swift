//
//  AppDelegate.swift
//  ray
//
//  Created by Dylan Karunanayake on 8/10/2026.
//

import AppKit
import SwiftUI

enum Presence { case app, background }

final class AppDelegate: NSObject, NSApplicationDelegate {
    static var current: AppDelegate?

    private var panel: LauncherPanel!
    private var presence: Presence = .background
    private var statusItem: NSStatusItem?
    private static var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.current = self

        panel = LauncherPanel(rootView: ContentView())
        HotKey.register { [weak self] in self?.togglePanel() }
        setUpMenuBar()

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(windowWillClose(_:)),
                                               name: NSWindow.willCloseNotification,
                                               object: nil)

        enterAppMode() // opening the app shows the launcher as a proper app
    }

    // Clicking Ray in Finder / Dock / Spotlight while it runs in the background
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // The Dock icon is only there because settings is open, so clicking it should just bring settings forward
        if let w = AppDelegate.settingsWindow, w.isVisible {
            NSApp.activate()
            w.makeKeyAndOrderFront(nil)
            return false
        }

        if panel.isVisible {
            NSApp.activate()
            panel.makeKeyAndOrderFront(nil)
        } else {
            enterAppMode()
        }
        return false
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        guard presence == .app, panel.isVisible else { return }
        panel.makeKeyAndOrderFront(nil)
        refocusSoon()
    }

    private func enterAppMode() {
        presence = .app
        panel.pinned = true // doesn't vanish on click-away
        NotificationCenter.default.post(name: .rayReset, object: nil)
        panel.positionOnActiveScreen()
        panel.makeKeyAndOrderFront(nil)

        showInDock { [weak self] in
            NSApp.activate()
            self?.panel.makeKeyAndOrderFront(nil)
            self?.refocusSoon()
        }
    }

    private func enterBackground() {
        presence = .background
        panel.pinned = false
        panel.orderOut(nil)
        NSApp.setActivationPolicy(.accessory) // no Dock icon, hotkey only
    }

    private func showTransient() {
        NotificationCenter.default.post(name: .rayReset, object: nil) // open fully empty
        panel.positionOnActiveScreen()
        panel.makeKeyAndOrderFront(nil) // no NSApp.activate, skips the app switch
    }

    private func togglePanel() {
        if panel.isVisible {
            dismissPanel()
        } else {
            showTransient()
        }
    }

    // Closing the launcher from app mode drops Ray into the background
    private func dismissPanel() {
        if presence == .app {
            enterBackground()
        } else {
            panel.orderOut(nil)
        }
    }

    static func dismiss() {
        current?.dismissPanel()
    }

    // Switches to a regular app
    private func showInDock(then done: @escaping () -> Void) {
        let ok = NSApp.setActivationPolicy(.regular)
        print("Ray: setActivationPolicy(.regular) ->", ok, "policy:", NSApp.activationPolicy().rawValue)

        DispatchQueue.main.async {
            NSApp.setActivationPolicy(.accessory)
            DispatchQueue.main.async {
                NSApp.setActivationPolicy(.regular)
            }
        }
    }

    // The first show can finish before SwiftUI has mounted the text field, so one focus request gets lost
    private func refocusSoon() {
        for delay in [0.1, 0.35] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                NotificationCenter.default.post(name: .rayFocus, object: nil)
            }
        }
    }

    private func setUpMenuBar() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = item.button {
            let image = NSImage(resource: .ray)
            image.accessibilityDescription = "Ray"
            image.isTemplate = true
            button.image = image
        }

        let menu = NSMenu()
        
        let version = menu.addItem(withTitle: "ray Version \(AppVersionManager.currentVersion)", action: nil, keyEquivalent: "")
        version.target = self
        version.isEnabled = false

        let open = menu.addItem(withTitle: "Open Ray", action: #selector(openFromMenu), keyEquivalent: "")
        open.target = self
 
        let settings = menu.addItem(withTitle: "Settings…", action: #selector(settingsFromMenu), keyEquivalent: ",")
        settings.target = self

        menu.addItem(.separator())

        let quit = menu.addItem(withTitle: "Quit Ray", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp

        item.menu = menu
        statusItem = item
    }

    @objc private func openFromMenu() {
        DispatchQueue.main.async { [weak self] in self?.showTransient() }
    }

    @objc private func settingsFromMenu() {
        AppDelegate.openSettings()
    }

    static func openSettings() {
        NSApp.setActivationPolicy(.regular)

        if settingsWindow == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
            w.title = "Ray Settings"
            w.styleMask = [.titled, .closable, .miniaturizable]
            w.isReleasedWhenClosed = false
            w.center()
            settingsWindow = w
        }

        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func windowWillClose(_ note: Notification) {
        guard !(note.object is LauncherPanel), presence == .background else { return }
        NSApp.setActivationPolicy(.accessory)
    }
}

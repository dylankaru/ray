//
//  MenuHandler.swift
//  ray
//
//  Created by Dylan Karunanayake on 12/10/2026.
//

import AppKit

/// Keeps a menu item's action alive, NSMenuItem only holds its target weakly
private final class MenuHandler: NSObject {
    let run: () -> Void
    init(_ run: @escaping () -> Void) { self.run = run }
    @objc func fire() { run() }
}

/// The native "Open With" pop-up, every app that can open the file with the default one first
enum OpenWith {

    /// Pops the menu at a point in screen coordinates and returns once it has closed
    /// Returns true if an app was picked (and the file was opened with it)
    @discardableResult
    static func show(for path: String, at screenPoint: NSPoint) -> Bool {
        let ws = NSWorkspace.shared
        let url = URL(fileURLWithPath: path)

        let found: [URL] = ws.urlsForApplications(toOpen: url)
        guard !found.isEmpty else {
            NSSound.beep()
            return false
        }

        let def: URL? = ws.urlForApplication(toOpen: url)
        let fm = FileManager.default
        let apps = found
            .map { (url: $0, name: fm.displayName(atPath: $0.path)) }
            .sorted { a, b in
                let aDef = (a.url == def)
                let bDef = (b.url == def)
                if aDef != bDef { return aDef } // the default app goes first
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }

        var picked = false
        var handlers: [MenuHandler] = []
        let menu = NSMenu()
        menu.autoenablesItems = false

        for (n, app) in apps.enumerated() {
            let handler = MenuHandler {
                picked = true
                ws.open([url], withApplicationAt: app.url,
                        configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
            }
            handlers.append(handler)

            let isDefault = (app.url == def)
            let item = NSMenuItem(title: isDefault ? "\(app.name) (default)" : app.name,
                                  action: #selector(MenuHandler.fire),
                                  keyEquivalent: "")
            item.target = handler
            if let icon = ws.icon(forFile: app.url.path).copy() as? NSImage {
                icon.size = NSSize(width: 16, height: 16)
                item.image = icon
            }
            menu.addItem(item)
            if n == 0 && isDefault && apps.count > 1 { menu.addItem(.separator()) }
        }

        // The launcher normally hides when it loses focus, hold it open while the menu is up
        let panel = NSApp.windows.compactMap { $0 as? LauncherPanel }.first
        let wasPinned = panel?.pinned ?? false
        panel?.pinned = true
        defer { panel?.pinned = wasPinned }

        menu.popUp(positioning: nil, at: screenPoint, in: nil) // blocks until the menu closes
        withExtendedLifetime(handlers) {}
        return picked
    }
}

//
//  LauncherActionModel.swift
//  ray
//
//  Created by Dylan Karunanayake on 1/11/2026.
//

import SwiftUI

extension LauncherModel {

    func actions(for item: Item) -> [PaneAction] {
        if mode == .calc {
            return [PaneAction(title: "Copy", icon: "doc.on.doc", run: item.action)]
        }
        if mode == .note {
            return [PaneAction(title: "Save to \(noteDestination.title)", icon: "square.and.pencil", run: item.action)]
        }
        if item.id.hasPrefix("clip:") || item.id.hasPrefix("emoji:") {
            return [PaneAction(title: "Copy", icon: "doc.on.doc", run: item.action)]
        }
        if item.id == "cmd:clipboard" {
            return [PaneAction(title: "Open", icon: "list.bullet.clipboard", keepsOpen: true, run: item.action)]
        }
        if item.id == "cmd:camera" || item.id == "cmd:emoji" {
            return [PaneAction(title: "Open", icon: "arrow.up.right", keepsOpen: true, run: item.action)]
        }
        if item.id.hasPrefix("web:") {
            return [PaneAction(title: "Search", icon: "arrow.up.right", run: item.action)]
        }
        if let path = item.iconPath {
            let url = URL(fileURLWithPath: path)
            return [
                PaneAction(title: "Open", icon: "arrowshape.turn.up.right", run: item.action),
                PaneAction(title: "Reveal in Finder", icon: "folder") {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                },
                PaneAction(title: "Copy Path", icon: "doc.on.clipboard") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(path, forType: .string)
                },
            ]
        }
        return [PaneAction(title: "Run", icon: "arrowshape.turn.up.right", run: item.action)]
    }

    func cycleAction(_ d: Int) {
        if isNote {
            switchNoteDestination()
            return
        }
        let n = currentActions.count
        guard n > 1 else { return }
        actionIndex = (actionIndex + d + n) % n
    }

    func isApp(_ item: Item) -> Bool {
        item.iconPath?.hasSuffix(".app") == true
    }

    func sideAction(_ side: Side, for item: Item, at index: Int?) -> SideAction? {
        guard mode == .find, !doOnboarding, !showingClipboardHistory, !showingEmoji else { return nil }

        if item.id.hasPrefix("cmd:") {
            return side == .trailing ? aliasAction(for: item, at: index) : nil
        }

        // web searches, calc, notes and clipboard rows have no path and get nothing
        guard let path = item.iconPath else { return nil }
        let url = URL(fileURLWithPath: path)

        switch side {
        case .leading:
            return SideAction(title: "Reveal in Finder", icon: "folder") { [weak self] in
                self?.hide()
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }

        case .trailing:
            if isApp(item) { return aliasAction(for: item, at: index) }

            return SideAction(title: "Open With…", icon: "ellipsis.circle") { [weak self] in
                DispatchQueue.main.async {
                    guard let self else { return }
                    let picked = OpenWith.show(for: path, at: self.menuAnchor(forRow: index))
                    if picked { self.hide() } else { self.restoreKeyboard() } // closing the menu with esc leaves the launcher up
                }
            }
        }
    }

    func quitSelectedApp() {
        guard mode == .find, !doOnboarding, aliasTarget == nil, dropdownVisible, results.indices.contains(selection) else { return }
        let item = results[selection]
        guard isApp(item), let path = item.iconPath,
              runningPaths.contains(path), path != Bundle.main.bundleURL.path else { return }
        hide()
        NSWorkspace.shared.runningApplications.first { $0.bundleURL?.path == path }?.terminate()
    }

    func restoreKeyboard() {
        if let panel = NSApp.windows.compactMap({ $0 as? LauncherPanel }).first, panel.isVisible {
            panel.makeKeyAndOrderFront(nil)
        }
        for delay in [0.05, 0.25] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                NotificationCenter.default.post(name: .rayFocus, object: nil)
            }
        }
    }

    func menuAnchor(forRow index: Int?) -> NSPoint {
        guard let panel = NSApp.windows.compactMap({ $0 as? LauncherPanel }).first else { return NSEvent.mouseLocation }

        let barHeight: CGFloat = showUtilityBar ? Metrics.utilityBarSize.height + Metrics.stageSpacing : 0
        // bottom edge of the launchpad, measured from the top of the window
        var y = Metrics.windowPadding + barHeight + launcherSize.height
        if dropdownVisible, let i = index {
            // bottom edge of row i
            y += Metrics.stageSpacing + Metrics.dropdownHeaderHeight + CGFloat(i) * (Metrics.rowHeight + 1) + Metrics.rowHeight
        }
        return NSPoint(x: panel.frame.minX + Metrics.windowPadding + Metrics.dropdownInset + 40, y: panel.frame.maxY - y)
    }

    private func aliasAction(for item: Item, at index: Int?) -> SideAction {
        SideAction(title: "Set Alias…", icon: "character.cursor.ibeam") { [weak self] in
            guard let self else { return }
            openAliasBubble(for: item, row: dropdownVisible ? index : nil)
        }
    }

    func openAliasBubble(for item: Item, row: Int?) {
        aliasList = AliasStore.aliases(for: item.id)
        aliasDraft = ""
        aliasRow = row
        withAnimation(motion(.quick)) {
            aliasTarget = item
            aliasContentIn = true
        }
        // AliasBubbleView focuses its own text field when it appears
    }

    func closeAliasBubble() {
        guard aliasTarget != nil else { return }
        withAnimation(.smooth(duration: 0.16)) {
            aliasTarget = nil
            aliasContentIn = false
        }
        aliasDraft = ""
        refocus()
    }

    func saveAlias() {
        guard let item = aliasTarget else { return }
        AliasStore.add(aliasDraft, to: item.id)
        closeAliasBubble()
    }

    func removeAlias(_ alias: String) {
        guard let item = aliasTarget else { return }
        AliasStore.remove(alias, from: item.id)
        withAnimation(motion(.row)) { aliasList = AliasStore.aliases(for: item.id) }
    }
}

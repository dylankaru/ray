//
//  LauncherFindModel.swift
//  ray
//
//  Created by Dylan Karunanayake on 1/11/2026.
//

import SwiftUI

extension LauncherModel {

    // Commands
    
    var commandItems: [Item] {
        [settingsItem, notesItem, cameraItem, clipboardHistoryItem, emojiItem]
    }

    private var settingsItem: Item {
        Item(id: "cmd:settings", title: "Ray Settings", icon: "gearshape", subtitle: "Command") {
            AppDelegate.openSettings()
        }
    }

    private var notesItem: Item {
        Item(id: "cmd:notes", title: "Ray Notes", icon: "note.text", subtitle: "Command") {
            Notes.open()
        }
    }

    private var cameraItem: Item {
        Item(id: "cmd:camera", title: "Open Camera", icon: "web.camera", subtitle: "Command") { [weak self] in
            guard let self else { return }
            CameraSession.shared.start()
            query = ""
            closeDropdown()
            withAnimation(motion(.dropdown)) {
                self.showingCamera = true
                self.tileLayout = .camera
            }
        }
    }

    private var clipboardHistoryItem: Item {
        Item(id: "cmd:clipboard", title: "Show Clipboard History", icon: "list.bullet.clipboard", subtitle: "Command") { [weak self] in
            self?.query = ""
            self?.showingClipboardHistory = true
        }
    }

    private var emojiItem: Item {
        Item(id: "cmd:emoji", title: "Emoji Dictionary", icon: "face.smiling", subtitle: "Command") { [weak self] in
            self?.query = ""
            self?.showingEmoji = true
        }
    }

    func loadApps() async {
        let found = await Task.detached(priority: .userInitiated) { Search.scanApps() }.value
        var items: [Item] = []
        for app in found {
            let path: String = app.path
            let url = URL(fileURLWithPath: path)
            items.append(Item(id: path, title: app.name, icon: "app",
                              subtitle: (path as NSString).abbreviatingWithTildeInPath,
                              iconPath: path) {
                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            })
        }
        pool = items + commandItems
        refresh()
    }

    func indexFiles() async {
        try? await Task.sleep(for: .seconds(2)) // let the launch and the first open settle before the scan starts
        while !Task.isCancelled {
            let found = await Task.detached(priority: .background) { () -> FileIndex in
                #if DEBUG
                let t0 = ContinuousClock.now
                defer { print("file scan:", ContinuousClock.now - t0) }
                #endif
                return Search.scanFiles()
            }.value
            #if DEBUG
            print("indexed \(found.count) files, \((found.names.count + found.lower.count) / 1024) KB of names")
            #endif
            fileIndex = found
            if mode == .find && !query.isEmpty { searchFiles(trimmedQuery) }
            try? await Task.sleep(for: .seconds(600)) // a rescan is the most expensive thing ray does, so it's rare
        }
    }

    func searchFiles(_ q: String) {
        guard !showingEmoji else { return }
        fileSearchTask?.cancel()
        guard !showingClipboardHistory else { return }

        // One letter matches almost every file, so the results would be noise and the scan is the most expensive one
        guard q.count >= 2, fileIndex.count > 0 else {
            filesPending = false
            if !fileHits.isEmpty {
                fileHits = []
                recomputeFind(preserveSelection: true)
            }
            return
        }

        let index: FileIndex = fileIndex
        let tokens: [[UInt8]] = q.lowercased().split(separator: " ").map { Array($0.utf8) }

        // While searches are quick (a few ms) they run right here, so the best match is on screen in the same frame as the keystroke
        // if one ever gets slow it moves off the main thread, and the next quick one moves it back
        if lastFileSearch < .milliseconds(8) {
            let t0 = ContinuousClock.now
            let top = Search.rankFiles(tokens, in: index, limit: 6)
            lastFileSearch = ContinuousClock.now - t0
            #if DEBUG
            print("file search '\(q)' (inline):", lastFileSearch)
            #endif
            filesPending = false
            fileHits = top.map { fileItem($0) }
            recomputeFind(preserveSelection: true)
            return
        }

        filesPending = true
        let work = Task.detached(priority: .userInitiated) { () -> (entries: [FileEntry], took: Duration) in
            let t0 = ContinuousClock.now
            let top = Search.rankFiles(tokens, in: index, limit: 6)
            let took = ContinuousClock.now - t0
            #if DEBUG
            print("file search '\(q)' (background):", took)
            #endif
            return (top, took)
        }
        fileSearchTask = work

        Task {
            let result = await work.value
            guard !work.isCancelled else { return } // a newer search owns filesPending now
            lastFileSearch = result.took
            filesPending = false
            guard mode == .find, trimmedQuery == q else { return }
            fileHits = result.entries.map { fileItem($0) }
            recomputeFind(preserveSelection: true)
        }
    }

    private func fileItem(_ e: FileEntry) -> Item {
        let parent: String = ((e.path as NSString).deletingLastPathComponent as NSString).abbreviatingWithTildeInPath
        let path: String = e.path
        return Item(id: path, title: e.name, icon: e.isDir ? "folder" : "doc",
                    subtitle: parent, iconPath: path) {
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
        }
    }

    func refresh() {
        if showingClipboardHistory { // clipboard history replaces the Find results while it's open
            clearFileSearch()
            calcResult = nil
            results = clipboardItems()
            selection = min(selection, max(0, results.count - 1))
            return
        }
        if showingEmoji { // so does the emoji dictionary
            clearFileSearch()
            calcResult = nil
            results = emojiItems()
            selection = 0
            return
        }

        let q = trimmedQuery

        switch mode {
        case .find:
            if q.isEmpty {
                fileSearchTask?.cancel()
                filesPending = false
                fileHits = []
            }
            recomputeFind(preserveSelection: false)
            // same bug here
            if !q.isEmpty { searchFiles(q) }

        case .calc:
            clearFileSearch()
            let value: String? = Calc.eval(q)
            calcResult = value
            results = value.map { [copyItem($0)] } ?? []
            selection = 0

        case .note:
            clearFileSearch()
            calcResult = nil
            let body = query.trimmingCharacters(in: .whitespacesAndNewlines)
            results = body.isEmpty ? [] : [noteItem(query)]
            selection = 0
        }
    }

    private func clearFileSearch() {
        fileSearchTask?.cancel()
        filesPending = false
    }

    func recomputeFind(preserveSelection: Bool) {
        guard !showingEmoji else { return }
        guard !showingClipboardHistory else { return } // late file results must not overwrite the clipboard rows
        let q = trimmedQuery
        calcResult = nil
        let keepID: String? = results.indices.contains(selection) ? results[selection].id : nil

        var out: [Item]
        if q.isEmpty {
            out = Search.rank("", in: pool, limit: 8)
        } else {
            let apps: [Item] = Search.rank(q, in: pool, limit: 8)
            let tokens = q.lowercased().split(separator: " ").map { String($0) }
            let files: [Item] = fileHits
                .filter { item in
                    let low = item.title.lowercased()
                    return tokens.allSatisfy { low.contains($0) }
                }
                .prefix(max(0, 6 - apps.count))
                .map { $0 }
            out = apps + files + [webItem(q)]
        }
        results = out

        if preserveSelection, selection != 0, let id = keepID, let idx = out.firstIndex(where: { $0.id == id }) {
            selection = idx
        } else {
            selection = 0
        }
    }

    private func clipboardItems() -> [Item] {
        let q = trimmedQuery.lowercased()
        let matches: [ClipEntry] = q.isEmpty ? clipboard.items : clipboard.items.filter { $0.searchText.lowercased().contains(q) }
        let clipboard = self.clipboard

        return matches.prefix(7).enumerated().map { i, entry in
            let id = "clip:\(i)"
            let copy: () -> Void = { clipboard.copyToClipboard(entry) }

            switch entry {
            case .text(let text):
                let line: String = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
                return Item(id: id, title: line.trimmingCharacters(in: .whitespaces), icon: "doc.on.clipboard", action: copy)

            case .files(let urls):
                let first: URL = urls[0]
                let title: String = urls.count == 1 ? first.lastPathComponent : "\(first.lastPathComponent) + \(urls.count - 1) more"
                let folder: String = (first.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath
                return Item(id: id, title: title, icon: "doc", subtitle: folder, iconPath: first.path, action: copy)

            case .image(let data):
                let size: String? = NSImage(data: data).map { "\(Int($0.size.width)) × \(Int($0.size.height))" }
                return Item(id: id, title: "Image", icon: "photo", subtitle: size, action: copy)
            }
        }
    }

    private func emojiItems() -> [Item] {
        let tokens = trimmedQuery.lowercased().split(separator: " ").map(String.init)
        let all = EmojiStore.all
        var matches = all
        if let first = tokens.first {
            let hits = all.filter { e in tokens.allSatisfy { e.name.contains($0) } }
            matches = hits.filter { $0.name.hasPrefix(first) } + hits.filter { !$0.name.hasPrefix(first) }
        }
        return matches.map { e in
            var item = Item(id: "emoji:\(e.glyph)", title: e.name.capitalized, icon: "face.smiling") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(e.glyph, forType: .string)
            }
            item.emoji = e.glyph
            return item
        }
    }

    private func copyItem(_ value: String) -> Item {
        Item(id: "calc", title: "Copy \(value)", icon: "doc.on.doc") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(value, forType: .string)
        }
    }

    private func webItem(_ q: String) -> Item {
        Item(id: "web:\(q)", title: q, icon: "globe", subtitle: "Search the web") {
            let encoded = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? q
            if let url = URL(string: "https://www.google.com/search?q=\(encoded)") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    private func noteItem(_ text: String) -> Item {
        let loaded = loadedNote // captured now, so the save knows whether it's editing loaded content
        return Item(id: "note", title: text, icon: "square.and.pencil", subtitle: "Save note") {
            if let loaded { Notes.replace(loaded: loaded, with: text) } else { Notes.save(text) }
        }
    }
}

//
//  ClipboardManager.swift
//  ray
//
//  Created by Dylan Karunanayake on 16/10/2026.
//

import SwiftUI

// One thing on the clipboard. Files and images keep their real data so choosing one pastes the real thing back
enum ClipEntry: Equatable {
    case text(String)
    case files([URL])
    case image(Data) // PNG data

    // What the search field matches against
    var searchText: String {
        switch self {
        case .text(let s): return s
        case .files(let urls): return urls.map(\.lastPathComponent).joined(separator: " ")
        case .image: return "image screenshot picture"
        }
    }
}

// One shared manager that starts at launch, so it records everything you copy
// even while the launcher has never been opened. ContentView shows it with its own row(...) function.
@Observable
final class ClipboardManager {
    static let shared = ClipboardManager()

    var items: [ClipEntry] = []

    @ObservationIgnored private var lastChangeCount = NSPasteboard.general.changeCount
    @ObservationIgnored private var timer: Timer?

    private static let maxItems = 20
    private static let maxImageBytes = 8 * 1024 * 1024 // bigger images would eat memory, 20 of them adds up fast

    private init() {
        // Poll the pasteboard, macOS has no change notification for it
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkPasteboard()
        }
        timer?.tolerance = 0.2 // cheaper on battery
    }

    private func checkPasteboard() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChangeCount else { return }
        lastChangeCount = pb.changeCount

        // Password managers mark what they copy, don't store those
        let types = pb.types?.map(\.rawValue) ?? []
        if types.contains("org.nspasteboard.ConcealedType") ||
           types.contains("org.nspasteboard.TransientType") { return }

        // Files first, because Finder also puts the file name on the pasteboard as plain text
        if let urls = pb.readObjects(forClasses: [NSURL.self],
                                     options: [.urlReadingFileURLsOnly: true]) as? [URL],
           !urls.isEmpty {
            record(.files(urls))
            return
        }

        if let string = pb.string(forType: .string),
           !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            record(.text(string))
            return
        }

        // Screenshots and copied images have no text at all
        if let png = Self.pngData(from: pb), png.count <= Self.maxImageBytes {
            record(.image(png))
        }
    }

    private static func pngData(from pb: NSPasteboard) -> Data? {
        if let png = pb.data(forType: .png) { return png }
        guard let tiff = pb.data(forType: .tiff),
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    // Newest first, re-copying something moves it to the top instead of adding a duplicate
    private func record(_ entry: ClipEntry) {
        items.removeAll { $0 == entry }
        items.insert(entry, at: 0)
        if items.count > Self.maxItems { items.removeLast() }
    }

    // Puts the entry back on the pasteboard in its real form, so pasting gives you the file or image again
    func copyToClipboard(_ entry: ClipEntry) {
        let pb = NSPasteboard.general
        pb.clearContents()
        switch entry {
        case .text(let s):
            pb.setString(s, forType: .string)
        case .files(let urls):
            pb.writeObjects(urls as [NSURL])
        case .image(let data):
            pb.setData(data, forType: .png)
        }
        lastChangeCount = pb.changeCount // so our own copy isn't recorded again
        record(entry)
    }

    func clearHistory() {
        items.removeAll()
    }
}

//
//  Notes.swift
//  ray
//
//  Created by Dylan Karunanayake on 13/10/2026.
//

import AppKit

enum NoteDestination: String, CaseIterable {
    case file
    case notes
    
    var title: String {
        switch self {
        case .file: return "Within Ray"
        case .notes: return "Apple Notes"
        }
    }
    
    var icon: String {
        switch self {
        case .file: return "doc.text"
        case .notes: return "note.text"
        }
    }
    
    var other: NoteDestination {
        self == .file ? .notes : .file
    }
}

enum Notes {
    nonisolated static let destinationKey = "ray_note_destination"
    
    nonisolated static var fileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: "ray-notes.md")
    }
    
    nonisolated static var destination: NoteDestination {
        NoteDestination(rawValue: UserDefaults.standard.string(forKey: destinationKey) ?? "") ?? .file
    }
    
    nonisolated static func open() {
        switch destination {
        case .file:
            let url = fileURL
            if !FileManager.default.fileExists(atPath: url.path) {
                try? "".write(to: url, atomically: true, encoding: .utf8)
            }
            NSWorkspace.shared.open(url)
        case .notes:
            if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Notes") {
                NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration())
            }
        }
    }
    
    /// Saves text as a NEW entry in the destination (a dated line in the file, a new note in Apple Notes)
    nonisolated static func save(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
         
#if DEBUG
        print("note save, destination:", destination.title)
#endif
         
        switch destination {
        case .file: append(text)
        case .notes:
            Task.detached(priority: .userInitiated) {
                let ok = await saveToAppleNotes(text)
                if !ok {
                    append(text)
                    await MainActor.run { NSSound.beep() }
                }
            }
        }
    }
    
    /// Writes the editor's text back over the content that was loaded into it
    /// Used instead of save() when the editor was opened with the destination's existing content,
    /// otherwise saving would add all of that content a second time
    nonisolated static func replace(loaded: String, with raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text != loaded.trimmingCharacters(in: .whitespacesAndNewlines) else { return } // nothing changed
        
#if DEBUG
        print("note replace, destination:", destination.title)
#endif
        
        switch destination {
        case .file:
            try? (text + "\n").write(to: fileURL, atomically: true, encoding: .utf8)
        case .notes:
            Task.detached(priority: .userInitiated) {
                let ok = await replaceAppleNote(text)
                if !ok {
                    append(text)
                    await MainActor.run { NSSound.beep() }
                }
            }
        }
    }
    
    /// The existing content of a destination, nil if there isn't any or it can't be read
    nonisolated static func load(from chosen: NoteDestination? = nil) async -> String? {
        switch chosen ?? destination {
        case .file:
            guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
            
            // A huge file would make the editor crawl, and saving writes the whole text back, so a big one is never loaded
            let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
            let size = (attributes?[.size] as? Int) ?? 0
            guard size <= 200_000 else { return nil }
            
            return try? String(contentsOf: fileURL, encoding: .utf8)
            
        case .notes:
            return await loadFromAppleNotes()
        }
    }
    
    nonisolated static func append(_ text: String) {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        let stamp = formatter.string(from: Date())
         
        let entry: String
        if text.contains("\n") {
            entry = "\n### \(stamp)\n\(text)\n\n"
        } else {
            entry = "- \(stamp) \(text)\n"
        }
         
#if DEBUG
        print("note ->", fileURL.path)
#endif
         
        if let h = try? FileHandle(forWritingTo: fileURL) {
            h.seekToEndOfFile()
            h.write(Data(entry.utf8))
            try? h.close()
        } else {
            try? entry.write(to: fileURL, atomically: true, encoding: .utf8)
        }
    }
    
    nonisolated static func saveToAppleNotes(_ text: String) async -> Bool {
        let script = [
            "on run argv",
            "tell application \"Notes\"",
            "make new note with properties {body:item 1 of argv}",
            "end tell",
            "end run",
        ]
        return await runOsascript(script, argument: appleNotesHTML(text))
    }
    
    /// Overwrites the body of the note that loadFromAppleNotes() reads (note 1)
    nonisolated static func replaceAppleNote(_ text: String) async -> Bool {
        let script = [
            "on run argv",
            "tell application \"Notes\"",
            "set body of note 1 to item 1 of argv",
            "end tell",
            "end run",
        ]
        return await runOsascript(script, argument: appleNotesHTML(text))
    }
    
    /// Notes wants HTML, each line is its own block and the first line becomes the title
    nonisolated private static func appleNotesHTML(_ text: String) -> String {
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map { escapeHTML(String($0)) }
        var html = ""
        if let first = lines.first {
            html += "<h1>\(first)</h1>"
            lines.removeFirst()
        }
        for line in lines {
            html += line.isEmpty ? "<div><br></div>" : "<div>\(line)</div>"
        }
        return html
    }
    
    /// Runs an AppleScript through osascript, the argument goes in separately so nothing in a note can break the script
    nonisolated private static func runOsascript(_ script: [String], argument: String) async -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = script.flatMap { ["-e", $0] } + [argument]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
         
        return await withCheckedContinuation { continuation in
            process.terminationHandler = { finished in
                continuation.resume(returning: finished.terminationStatus == 0)
            }
            do {
                try process.run()
            } catch {
                continuation.resume(returning: false)
            }
        }
    }
    
    nonisolated static func loadFromAppleNotes() async -> String? {
        let script = [
            "on run",
            "tell application \"Notes\"",
            "if (count of notes) > 0 then",
            "return body of note 1",
            "else",
            "return \"\"",
            "end if",
            "end tell",
            "end run"
        ]
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = script.flatMap { ["-e", $0] }
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        
        return await withCheckedContinuation { continuation in
            process.terminationHandler = { finished in
                if finished.terminationStatus == 0 {
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let html = String(data: data, encoding: .utf8) ?? ""
                    let text = htmlToPlainText(html)
                    continuation.resume(returning: text.trimmingCharacters(in: .whitespacesAndNewlines))
                } else {
                    continuation.resume(returning: nil)
                }
            }
            do {
                try process.run()
            } catch {
                continuation.resume(returning: nil)
            }
        }
    }
    
    nonisolated private static func htmlToPlainText(_ html: String) -> String {
        var text = html
        text = text.replacingOccurrences(of: "<h1>", with: "")
            .replacingOccurrences(of: "</h1>", with: "\n\n")
            .replacingOccurrences(of: "<h2>", with: "")
            .replacingOccurrences(of: "</h2>", with: "\n\n")
            .replacingOccurrences(of: "<div><br></div>", with: "\n")
            .replacingOccurrences(of: "<br>", with: "\n")
            .replacingOccurrences(of: "<div>", with: "")
            .replacingOccurrences(of: "</div>", with: "\n")
        
        if let regex = try? NSRegularExpression(pattern: "<[^>]+>", options: []) {
            let range = NSRange(text.startIndex..., in: text)
            text = regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")
        }
        
        return text.replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
    }
    
    nonisolated private static func escapeHTML(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
    }
}

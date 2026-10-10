//
//  Item.swift
//  ray
//
//  Created by Dylan Karunanayake on 9/10/2026.
//

import AppKit

/// Item is the expected shape of any option command in ray
/// Option command is an item in the dropdown view
/// All but subtitle and iconPath are required
struct Item: Identifiable {
    let id: String
    let title: String
    let icon: String // SF symbol, used when there's no iconPath given
    let subtitle: String?
    let iconPath: String? // If you have a proper image for an action
    let bytes: [UInt8]
    let action: () -> Void

    init(id: String, title: String, icon: String, subtitle: String? = nil,
         iconPath: String? = nil, action: @escaping () -> Void) {
        self.id = id
        self.title = title
        self.icon = icon
        self.subtitle = subtitle
        self.iconPath = iconPath
        self.bytes = Array(title.lowercased().utf8)
        self.action = action
    }
}

// Fuzzy search learns how you interact with ray
enum Fuzzy {
    static func score(_ q: [UInt8], _ t: [UInt8]) -> Int? {
        var qi = 0
        var score = 0
        var prev = -2

        for (ti, c) in t.enumerated() {
            guard qi < q.count else { break }
            if c == q[qi] {
                var s = 1
                if ti == 0 { s += 8 } // first letter
                else if t[ti - 1] == 32 { s += 6 } // start of a word
                if prev == ti - 1 { s += 4 } // consecutive letters
                score += s
                prev = ti
                qi += 1
            }
        }
        guard qi == q.count else { return nil }
        if t.starts(with: q) { score += 20 } // exact prefix
        return score - t.count / 4 // prefer shorter names
    }

    // Contiguous match, for file names, prefix and word-start rank higher
    nonisolated static func substringScore(_ q: [UInt8], _ t: [UInt8]) -> Int? {
        let n = q.count
        let m = t.count
        guard n > 0, n <= m else { return nil }
        let first = q[0]
        var i = 0
        while i <= m - n {
            if t[i] == first {
                var j = 1
                while j < n && t[i + j] == q[j] { j += 1 }
                if j == n {
                    var s = 100 - min(i, 60)
                    if i == 0 {
                        s += 60
                    } else {
                        let p = t[i - 1]
                        if p == 32 || p == 46 || p == 45 || p == 95 { s += 30 }
                    }
                    return s - m / 4
                }
            }
            i += 1
        }
        return nil
    }
}

enum Search {
    static func rank(_ query: String, in pool: [Item], limit: Int = 7) -> [Item] {
        let q = Array(query.lowercased().utf8.filter { $0 != 32 })
        guard !q.isEmpty else { return Array(pool.prefix(limit)) }

        var scored: [(Item, Int)] = []
        for item in pool {
            if let s = Fuzzy.score(q, item.bytes) { scored.append((item, s)) }
        }
        scored.sort { $0.1 > $1.1 }
        return scored.prefix(limit).map { $0.0 }
    }

    nonisolated static func scanApps() -> [(name: String, path: String)] {
        let fm = FileManager.default
        let dirs = [
            "/Applications",
            "/Applications/Utilities",
            "/System/Applications",
            "/System/Applications/Utilities",
            "/System/Cryptexes/App/System/Applications",
            NSHomeDirectory() + "/Applications",
        ]

        var seen = Set<String>()
        var out: [(name: String, path: String)] = []

        for dir in dirs {
            guard let names = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for n in names where n.hasSuffix(".app") {
                let name = String(n.dropLast(4))
                if seen.insert(name).inserted { out.append((name, dir + "/" + n)) }
            }
        }
        return out.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

nonisolated struct FileEntry: Sendable {
    let path: String
    let name: String
    let bytes: [UInt8]
    let isDir: Bool
    let depth: Int
}

extension Search {
    // Walks the home folder
    nonisolated static func scanFiles() -> [FileEntry] {
        let fm = FileManager.default
        let home = URL(fileURLWithPath: realHome())
        let skip: Set<String> = [
            "Library", "Applications", "node_modules", ".git", ".Trash", "DerivedData",
            "Pods", "venv", ".venv", "__pycache__", "build", ".build",
        ]
        guard let e = fm.enumerator(at: home,
                                    includingPropertiesForKeys: [.isDirectoryKey],
                                    options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }

        var out: [FileEntry] = []
        out.reserveCapacity(100_000)

        while let url = e.nextObject() as? URL {
            let name = url.lastPathComponent
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDir && skip.contains(name) {
                e.skipDescendants()
                continue
            }
            if e.level > 8 { e.skipDescendants() }
            out.append(FileEntry(path: url.path,
                                 name: name,
                                 bytes: Array(name.lowercased().utf8),
                                 isDir: isDir,
                                 depth: e.level))
            if out.count >= 400_000 { break }
        }
        return out
    }

    // Every space-separated token must appear in the name, in any order
    nonisolated static func rankFiles(_ tokens: [[UInt8]], in entries: [FileEntry], limit: Int) -> [FileEntry] {
        guard !tokens.isEmpty else { return [] }
        var scored: [(score: Int, index: Int)] = []

        outer: for (idx, e) in entries.enumerated() {
            var total = 0
            for t in tokens {
                guard let s = Fuzzy.substringScore(t, e.bytes) else { continue outer }
                total += s
            }
            scored.append((total - e.depth * 2 + (e.isDir ? 3 : 0), idx))
        }
        scored.sort { $0.score > $1.score }
        return scored.prefix(limit).map { entries[$0.index] }
    }

    // Real home folder
    nonisolated static func realHome() -> String {
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            return String(cString: dir)
        }
        return NSHomeDirectory()
    }
}

enum Highlight {
    // Each typed word as a contiguous match if every word is found, else the fuzzy letters
    static func matched(_ query: String, in title: String) -> Set<Int> {
        let t: [Character] = Array(title.lowercased())
        let tokens: [[Character]] = query.lowercased().split(separator: " ").map { Array($0) }
        guard !tokens.isEmpty else { return [] }

        var out = Set<Int>()
        var all = true
        for q in tokens {
            if let i = firstIndex(of: q, in: t) {
                out.formUnion(i..<(i + q.count))
            } else {
                all = false
                break
            }
        }
        return all ? out : subsequence(Array(query.lowercased().filter { $0 != " " }), in: t)
    }

    private static func firstIndex(of q: [Character], in t: [Character]) -> Int? {
        guard !q.isEmpty, q.count <= t.count else { return nil }
        for i in 0...(t.count - q.count) where Array(t[i..<(i + q.count)]) == q {
            return i
        }
        return nil
    }

    private static func subsequence(_ q: [Character], in t: [Character]) -> Set<Int> {
        var out = Set<Int>()
        var qi = 0
        for (i, ch) in t.enumerated() {
            guard qi < q.count else { break }
            if ch == q[qi] {
                out.insert(i)
                qi += 1
            }
        }
        return qi == q.count ? out : []
    }
}

enum Calc {
    static func eval(_ query: String) -> String? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return CASEngine.shared.evaluate(trimmed)
    }

    static func getLaTeX(_ query: String) -> String {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        // math.js natively converts AST to LaTeX.
        // If typing is incomplete (e.g., "2+"), use fallback visual formatting.
        if let latex = CASEngine.shared.toLaTeX(trimmed) {
            return latex
        } else {
            return fallbackLaTeX(trimmed)
        }
    }

    private static func fallbackLaTeX(_ raw: String) -> String {
        var s = raw.replacingOccurrences(of: "*", with: " \\cdot ")
        s = s.replacingOccurrences(of: "pi", with: "\\pi ")
        s = s.replacingOccurrences(of: "sqrt", with: "\\sqrt")
        return s
    }
}

enum Notes {
    // Appends a dated line to ~/ray-notes.md
    static func append(_ text: String) {
        let url = FileManager.default.homeDirectoryForCurrentUser.appending(path: "ray-notes.md")
        let day = Date.now.formatted(.iso8601.year().month().day())
        let line = "- \(day) \(text)\n"

        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile()
            h.write(Data(line.utf8))
            try? h.close()
        } else {
            try? line.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}

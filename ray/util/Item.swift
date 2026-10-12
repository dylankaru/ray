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

/// App and file icons are looked up once and reused, instead of asking NSWorkspace on every render
enum IconCache {
    private static let cache = NSCache<NSString, NSImage>()

    static func icon(for path: String) -> NSImage {
        let key = path as NSString
        if let hit = cache.object(forKey: key) { return hit }
        let img = NSWorkspace.shared.icon(forFile: path)
        cache.setObject(img, forKey: key)
        return img
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

/// What a file hit looks like once it's been picked out of the index
nonisolated struct FileEntry: Sendable {
    let path: String
    let name: String
    let isDir: Bool
    let depth: Int
}

/// The file index, stored as a few flat arrays instead of one object per file
/// Every name is followed by a 0 byte, so a search can never match across two names
/// Full paths are rebuilt on demand, and only for the handful of hits that actually get shown
nonisolated struct FileIndex: Sendable {
    var root = ""
    var names: [UInt8] = []      // original case, shown to the user
    var lower: [UInt8] = []      // same layout, ASCII lowercased, what searches actually scan
    var starts: [UInt32] = []    // entry i begins at starts[i], has count + 2 elements (one spare at the end)
    var parents: [Int32] = []    // index of the parent entry, -1 for the top level
    var meta: [UInt8] = []       // bit 7 = folder, low bits = depth
    var count: Int { parents.count }

    func name(_ i: Int) -> String {
        String(decoding: names[Int(starts[i])..<(Int(starts[i + 1]) - 1)], as: UTF8.self)
    }

    func entry(_ i: Int) -> FileEntry {
        var parts: [String] = []
        var cur = i
        while cur >= 0 {
            parts.append(name(cur))
            cur = Int(parents[cur])
        }
        let path = root + "/" + parts.reversed().joined(separator: "/")
        return FileEntry(path: path,
                         name: parts[0],
                         isDir: meta[i] & 0x80 != 0,
                         depth: Int(meta[i] & 0x7F))
    }
}

extension Search {

    // MARK: Building the index

    // Walks the home folder with plain readdir, no URL objects, so it's fast and barely allocates
    nonisolated static func scanFiles() -> FileIndex {
        let home = realHome()
        let maxEntries = 400_000
        let skipDirs: Set<String> = [
            "Library", "Applications", "node_modules", ".git", ".Trash", "DerivedData",
            "Pods", "venv", ".venv", "__pycache__", "build", ".build",
        ]
        // Folders that are really single files to the user, they're listed but never opened up
        let packageExts: Set<String> = [
            "app", "framework", "bundle", "plugin", "xcodeproj", "xcworkspace", "xcassets", "playground",
            "photoslibrary", "musiclibrary", "tvlibrary", "rtfd", "kext", "appex", "prefpane",
            "pages", "numbers", "key", "sparsebundle", "dsym", "lproj",
        ]

        func isPackage(_ name: String) -> Bool {
            guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return false }
            return packageExts.contains(name[name.index(after: dot)...].lowercased())
        }

        struct Frame {
            let path: String
            let parent: Int32
            let depth: Int
        }

        var idx = FileIndex()
        idx.root = home
        idx.names.reserveCapacity(1 << 22)
        idx.lower.reserveCapacity(1 << 22)
        idx.starts.reserveCapacity(1 << 17)
        idx.parents.reserveCapacity(1 << 17)
        idx.meta.reserveCapacity(1 << 17)

        var stack: [Frame] = [Frame(path: home, parent: -1, depth: 1)]
        var full = false

        // The scan sleeps as long as it just worked, every couple of thousand entries
        // That caps it at roughly half of one core however slow the build is, at the cost of a slightly later index
        var visited = 0
        var batchStart = DispatchTime.now().uptimeNanoseconds

        walk: while let frame = stack.popLast() {
            guard let dir = opendir(frame.path) else { continue }
            defer { closedir(dir) }

            while let ent = readdir(dir) {
                let len = Int(ent.pointee.d_namlen)
                let type = ent.pointee.d_type
                guard len > 0 else { continue }

                withUnsafePointer(to: &ent.pointee.d_name) { tuple in
                    tuple.withMemoryRebound(to: UInt8.self, capacity: len) { (p: UnsafePointer<UInt8>) -> Void in
                        if p[0] == 0x2E { return } // hidden files, and "." and ".."
                        let bytes = UnsafeBufferPointer(start: p, count: len)

                        let isDir: Bool = (type == UInt8(DT_DIR))
                        var dirName: String? = nil
                        if isDir {
                            // A String is only built for folders, files never allocate one
                            let s = String(decoding: bytes, as: UTF8.self)
                            if skipDirs.contains(s) { return }
                            dirName = s
                        }

                        let level = frame.depth
                        let i = idx.parents.count
                        idx.parents.append(frame.parent)
                        idx.starts.append(UInt32(idx.names.count))
                        idx.names.append(contentsOf: bytes)
                        idx.names.append(0)
                        for b in bytes { idx.lower.append((b >= 65 && b <= 90) ? b | 0x20 : b) }
                        idx.lower.append(0)
                        idx.meta.append((isDir ? 0x80 : 0) | UInt8(min(level, 127)))

                        if let s = dirName, level <= 8, !isPackage(s) {
                            stack.append(Frame(path: frame.path + "/" + s, parent: Int32(i), depth: level + 1))
                        }
                        if idx.parents.count >= maxEntries { full = true }
                    }
                }
                if full { break walk }

                visited += 1
                if visited & 2047 == 0 {
                    let worked = DispatchTime.now().uptimeNanoseconds - batchStart
                    usleep(UInt32(min(worked / 1000, 50_000))) // microseconds, never more than 50 ms at a time
                    batchStart = DispatchTime.now().uptimeNanoseconds
                }
            }
        }

        // One spare offset at the end, then shrink every array to its exact size
        let end = UInt32(idx.names.count)
        idx.starts.append(end)
        idx.starts.append(end)

        func shrunk<T>(_ a: [T]) -> [T] { a.withUnsafeBufferPointer { Array($0) } }
        idx.names = shrunk(idx.names)
        idx.lower = shrunk(idx.lower)
        idx.starts = shrunk(idx.starts)
        idx.parents = shrunk(idx.parents)
        idx.meta = shrunk(idx.meta)
        return idx
    }

    // MARK: Searching

    // Every space-separated token must appear in the name, in any order
    // The longest token is searched across the whole buffer in one sweep, the other tokens are only checked inside names that already matched
    // Only the best `limit` hits are kept while scanning
    nonisolated static func rankFiles(_ tokens: [[UInt8]], in idx: FileIndex, limit: Int) -> [FileEntry] {
        let count = idx.count
        guard count > 0, limit > 0 else { return [] }

        let toks: [[UInt8]] = tokens
            .map { $0.map { ($0 >= 65 && $0 <= 90) ? $0 | 0x20 : $0 } }
            .filter { !$0.isEmpty && !$0.contains(0) }
        guard !toks.isEmpty else { return [] }
        var anchor = 0
        for t in toks.indices where toks[t].count > toks[anchor].count { anchor = t }

        var best: [(score: Int, index: Int)] = []
        best.reserveCapacity(limit + 1)
        var worst = Int.min

        idx.lower.withUnsafeBufferPointer { lowBuf in
        idx.starts.withUnsafeBufferPointer { stBuf in
        idx.meta.withUnsafeBufferPointer { metaBuf in
        toks[anchor].withUnsafeBufferPointer { ancBuf in
            guard let hay = lowBuf.baseAddress, let st = stBuf.baseAddress,
                  let anc = ancBuf.baseAddress else { return }
            let total = lowBuf.count
            let an = ancBuf.count
            var pos = 0
            var cur = 0
            var hits = 0

            while pos < total {
                let found = findFirst(hay, total, from: pos, needle: anc, an)
                if found < 0 { break }

                hits &+= 1
                if hits & 0x3FF == 0 && Task.isCancelled { return } // a newer keystroke made this search stale

                // Which entry does this hit belong to? Hits arrive in order, so it's usually the current or the next one
                let h = UInt32(found)
                if h >= st[cur + 1] {
                    if h < st[cur + 2] {
                        cur += 1
                    } else {
                        var lo = cur + 1
                        var hi = count
                        while hi - lo > 1 {
                            let mid = (lo + hi) >> 1
                            if st[mid] <= h { lo = mid } else { hi = mid }
                        }
                        cur = lo
                    }
                }

                let s0 = Int(st[cur])
                let m = Int(st[cur + 1]) - s0 - 1
                pos = Int(st[cur + 1]) // the rest of this name is done, jump to the next one
                let name = hay + s0

                var score = fileScore(name, at: found - s0, len: m)
                let meta = metaBuf[cur]
                score += (meta & 0x80 != 0 ? 3 : 0) - Int(meta & 0x7F) * 2

                if toks.count > 1 {
                    var ok = true
                    for t in toks.indices where t != anchor {
                        guard let p = position(of: toks[t], in: name, len: m) else { ok = false; break }
                        score += fileScore(name, at: p, len: m)
                    }
                    if !ok { continue }
                } else if best.count == limit && score <= worst {
                    continue
                }

                if best.count < limit || score > worst {
                    best.append((score, cur))
                    var j = best.count - 1
                    while j > 0 && best[j].score > best[j - 1].score {
                        best.swapAt(j, j - 1)
                        j -= 1
                    }
                    if best.count > limit { best.removeLast() }
                    if best.count == limit { worst = best[limit - 1].score }
                }
            }
        }}}}

        return best.map { idx.entry($0.index) }
    }

    // Prefix and word-start rank higher, later matches rank lower, shorter names win
    @inline(__always)
    private nonisolated static func fileScore(_ name: UnsafePointer<UInt8>, at i: Int, len m: Int) -> Int {
        var s = 100 - min(i, 60)
        if i == 0 {
            s += 60
        } else {
            let p = name[i - 1]
            if p == 32 || p == 46 || p == 45 || p == 95 { s += 30 }
        }
        return s - m / 4
    }

    // Where a token first appears inside one (short) name
    @inline(__always)
    private nonisolated static func position(of t: [UInt8], in name: UnsafePointer<UInt8>, len: Int) -> Int? {
        guard t.count <= len else { return nil }
        return t.withUnsafeBytes { tb -> Int? in
            guard let base = tb.baseAddress, let hit = memmem(name, len, base, t.count) else { return nil }
            return UnsafeRawPointer(name).distance(to: UnsafeRawPointer(hit))
        }
    }

    // First occurrence of the needle at or after `from`, or -1
    // Compares the needle's first and last byte on 16 positions at a time, and only checks the middle when both line up
    @inline(__always)
    private nonisolated static func findFirst(_ hay: UnsafePointer<UInt8>, _ total: Int, from: Int,
                                              needle: UnsafePointer<UInt8>, _ n: Int) -> Int {
        if n == 1 {
            guard let p = memchr(hay + from, Int32(needle[0]), total - from) else { return -1 }
            return UnsafeRawPointer(hay).distance(to: UnsafeRawPointer(p))
        }

        let first = needle[0]
        let last = needle[n - 1]
        let fv = SIMD16<UInt8>(repeating: first)
        let lv = SIMD16<UInt8>(repeating: last)
        let raw = UnsafeRawPointer(hay)
        var i = from

        while i + n + 15 <= total {
            let a = raw.loadUnaligned(fromByteOffset: i, as: SIMD16<UInt8>.self)
            let b = raw.loadUnaligned(fromByteOffset: i + n - 1, as: SIMD16<UInt8>.self)
            let m = (a .== fv) .& (b .== lv)
            if any(m) {
                for lane in 0..<16 where m[lane] {
                    if n == 2 || memcmp(hay + i + lane + 1, needle + 1, n - 2) == 0 { return i + lane }
                }
            }
            i += 16
        }
        while i + n <= total {
            if hay[i] == first && memcmp(hay + i, needle, n) == 0 { return i }
            i += 1
        }
        return -1
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

    // Compares in place instead of building a new array at every position
    private static func firstIndex(of q: [Character], in t: [Character]) -> Int? {
        guard !q.isEmpty, q.count <= t.count else { return nil }
        outer: for i in 0...(t.count - q.count) {
            for j in 0..<q.count where t[i + j] != q[j] { continue outer }
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

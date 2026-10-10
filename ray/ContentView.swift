//
//  ContentView.swift
//  ray
//
//  Created by Dylan Karunanayake on 8/10/2026.
//

import SwiftUI

// I'm gonna practice writing comments

/// Mode is what the launcher is currently doing with what you type
/// Find searches apps, files and the web all at once, Calc and Note do what they say
enum Mode: Int, CaseIterable {
    case find, calc, note

    var prompt: String {
        switch self {
        case .find: return "Search apps, files and the web"
        case .calc: return "Type an expression"
        case .note: return "Write a note"
        }
    }

    /// Type this as the first character in Find mode to jump modes
    static func from(prefix c: Character) -> Mode? {
        switch c {
        case "=": return .calc
        case "'": return .note
        default:  return nil
        }
    }
}

/// PaneAction is the expected shape of an command option in ray
/// All parameters are required
struct PaneAction {
    let title: String
    let icon: String
    let run: () -> Void
}

// TODO: Change, i really dont like this logo thing
struct RayMark: Shape {
    func path(in r: CGRect) -> Path {
        let s: CGFloat = min(r.width, r.height)
        var p = Path()
        p.move(to: CGPoint(x: r.minX + 0.12 * s, y: r.maxY - 0.12 * s))
        p.addLine(to: CGPoint(x: r.minX + 0.88 * s, y: r.minY + 0.12 * s))
        p.move(to: CGPoint(x: r.minX + 0.04 * s, y: r.maxY - 0.50 * s))
        p.addLine(to: CGPoint(x: r.minX + 0.50 * s, y: r.minY + 0.04 * s))
        p.move(to: CGPoint(x: r.minX + 0.50 * s, y: r.maxY - 0.04 * s))
        p.addLine(to: CGPoint(x: r.minX + 0.96 * s, y: r.minY + 0.50 * s))
        return p
    }
}

// GlassCard is shape/body of the launcher, everything the user sees and interacts with will be housed here
// The dark colour is a tint on the glass itself (not a fill behind it) so it morphs with the glass instead of popping in
struct GlassCard: ViewModifier {
    let radius: CGFloat

    func body(content: Content) -> some View {
        let s = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let edge = LinearGradient(colors: [Color.black.opacity(0.6), Color.black.opacity(0.6)], startPoint: .top, endPoint: .bottom)
        // I know it's barely noticable but why not
        return content
            .glassEffect(.regular.tint(Color.black.opacity(0.125)).interactive(), in: s)
            .overlay(s.strokeBorder(edge, lineWidth: 0.6))
            .shadow(color: .black.opacity(0.35), radius: 22, y: 9)
    }
}

// I wonder what this could b🫠
struct ContentView: View {

    // The feel of the dropdown. Response = how fast it lands (lower is snappier),
    // damping = how much it bounces at the end (1 = none, 0.72 = a small overshoot)
    private static let dropdownSpring = Animation.spring(response: 0.42, dampingFraction: 0.72)
    private static let rowSpring = Animation.spring(response: 0.32, dampingFraction: 0.78)
    private static let selectionSpring = Animation.spring(response: 0.28, dampingFraction: 0.78)

    // Defaults
    @AppStorage("ray_typing_delay") private static var typingDelay: Double = 0.8
    @AppStorage("ray_still_delay") private static var stillDelay: Double = 3.0

    @State private var query: String = ""
    @State private var mode: Mode = .find
    @State private var selection: Int = 0
    @State private var pool: [Item] = []            // every installed app, loaded once
    @State private var results: [Item] = []         // what the tile and dropdown show right now
    @State private var calcResult: String? = nil
    @State private var fileEntries: [FileEntry] = [] // our own index of the home folder
    @State private var fileHits: [Item] = []         // files matching the current query
    @State private var showDropdown: Bool = false
    @State private var rowsRevealed: Bool = false   // drives the staggered row entrance
    @State private var dropdownTask: Task<Void, Never>? = nil
    @State private var actionIndex: Int = 0
    @State private var lastMouseLocation: CGPoint = .zero
    @FocusState private var focused: Bool
    @Namespace private var ns          // the sliding row highlight
    @Namespace private var glassNS     // lets the dropdown glass grow out of the launcher glass

    private let tileSize: CGFloat = 240
    private let rowHeight: CGFloat = 46
    private let launcherRadius: CGFloat = 40
    private let launcherPadding: CGFloat = 15
    private let dropdownRadius: CGFloat = 28
    private let dropdownInset: CGFloat = 8
    private let selectionTint = Color.accentColor.opacity(0.28)

    // Concentric with the launcher, always the outer radius minus the padding, so changing either one stays correct
    private var tileShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: launcherRadius - launcherPadding, style: .continuous)
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespaces)
    }

    private var dropdownVisible: Bool {
        showDropdown && results.count > 1 && mode != .calc // If there is only one result what's the point of the dropdown
    }

    // What the tile shows, idle shows nothing enter can't fire blind
    private var paneItem: Item? {
        guard results.indices.contains(selection) else { return nil }
        if mode == .find && query.isEmpty && !dropdownVisible { return nil }
        return results[selection]
    }

    private var currentActions: [PaneAction] {
        guard let item = paneItem else { return [] }
        return actions(for: item)
    }

    private var currentAction: PaneAction? {
        let acts: [PaneAction] = currentActions
        guard !acts.isEmpty else { return nil }
        return acts[min(actionIndex, acts.count - 1)]
    }

    var body: some View {
        keyHandled
            .onChange(of: query) { _, newValue in queryChanged(newValue) }
            .onChange(of: mode) { refresh(); scheduleDropdown() }
            .onChange(of: selection) { actionIndex = 0 }
            .onChange(of: dropdownVisible) { _, visible in revealRows(visible) }
            .onReceive(NotificationCenter.default.publisher(for: .rayReset)) { _ in reset() }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
                refocus()
            }
            .task { await loadApps() }
            .task { await indexFiles() }
            .onAppear { focused = true; refresh(); scheduleDropdown() }
    }

    private var keyHandled: some View {
        framed
            .onKeyPress(.downArrow) { handleDown() }
            .onKeyPress(.upArrow)   { move(-1); return .handled }
            .onKeyPress(.escape)    { handleEscape() }
            .onKeyPress(.tab, phases: .down) { press in handleTab(press) } // Tab swaps between Find, Calc and Note
            .onKeyPress(.delete)    { handleDelete() }
    }

    private var framed: some View {
        stage
            .padding(60)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background { shortcutButtons }
    }

    // This is the [name for top box] and dropdown
    private var stage: some View {
        // This is where the liquid happens. Cards closer than `spacing` melt into each other, so the dropdown
        // starts fused with the launcher and pulls away until it's the 16pt gap apart. Keep spacing == the VStack gap
        GlassEffectContainer(spacing: 16) {
            VStack(spacing: 16) {
                launcher
                if dropdownVisible {
                    dropdown
                }
            }
            .frame(width: 380, alignment: .top)
        }
        .animation(Self.dropdownSpring, value: dropdownVisible)
        .animation(.smooth(duration: 0.16), value: mode)
    }

    // For a user to choose different options in the dropdown
    private var shortcutButtons: some View {
        Group {
            ForEach(0..<7, id: \.self) { i in
                Button("") { run(at: i) }
                    .keyboardShortcut(shortcutKey(i), modifiers: .command)
            }
            Button("") { cycleAction(1) }.keyboardShortcut(.downArrow, modifiers: .option)
            Button("") { cycleAction(-1) }.keyboardShortcut(.upArrow, modifiers: .option)
        }
        .opacity(0)
        .frame(width: 0, height: 0)
    }

    private func shortcutKey(_ i: Int) -> KeyEquivalent {
        let digit: String = String(i + 1)
        let ch: Character = digit.first ?? "1"
        return KeyEquivalent(ch)
    }

    private var launcher: some View {
        VStack(spacing: 0) {
            tile
            inputField
        }
        .padding(launcherPadding)
        .frame(width: tileSize + launcherPadding * 2)
        .modifier(GlassCard(radius: launcherRadius))
        .glassEffectID("launcher", in: glassNS)
    }

    private var tile: some View {
        VStack(spacing: 12) {
            paneIcon
            paneTitle
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .frame(width: tileSize, height: tileSize)
        .overlay(alignment: .bottom) { actionChip.padding(.bottom, 14) }
        .background(tileBackground)
    }

    private var tileBackground: some View {
        ZStack {
            tileShape.fill(selectionTint)
            tileShape.strokeBorder(Color.accentColor.opacity(0.45), lineWidth: 0.6)
        }
    }

    // In Calc mode the big thing is the answer instead of an icon
    @ViewBuilder
    private var paneIcon: some View {
        if mode == .calc {
            Text(calcResult ?? "0")
                .font(.system(size: 46, weight: .ultraLight, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(calcResult == nil ? Color.secondary.opacity(0.5) : Color.primary)
                .contentTransition(.numericText())
                .animation(.snappy(duration: 0.12), value: calcResult)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .frame(height: 84)
        } else if let item = paneItem {
            bigIcon(item)
        } else {
            RayMark()
                .stroke(Color.secondary.opacity(0.6), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
                .frame(width: 42, height: 42)
                .frame(height: 84)
        }
    }

    // Apps and files get their real icon, everything else (web, notes) gets a symbol
    @ViewBuilder
    private func bigIcon(_ item: Item) -> some View {
        if let path = item.iconPath {
            Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                .resizable()
                .interpolation(.high)
                .frame(width: 80, height: 80)
                .frame(height: 84)
        } else {
            Image(systemName: item.icon)
                .font(.system(size: 46, weight: .light))
                .foregroundStyle(.primary)
                .frame(height: 84)
        }
    }

    @ViewBuilder
    private var paneTitle: some View {
        if mode == .calc {
            Text("Result")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
        } else if let item = paneItem {
            Text(attributed(item.title))
                .font(.system(size: 16, weight: .medium))
//                .monospaced() // Optional, to be a setting
                .lineLimit(2)
                .multilineTextAlignment(.center)
        } else {
            Text(query.isEmpty ? "Type to search" : "No matches")
                .font(.system(size: 14))
//                .monospaced() // Optional, to be a setting
                .foregroundStyle(.tertiary)
        }
    }

    // Tooltip to run the action
    private var actionChip: some View {
        let dim: Bool = (currentAction == nil)

        return HStack(spacing: 6) {
            Image(systemName: currentAction?.icon ?? "arrowshape.turn.up.right")
                .font(.system(size: 11, weight: .medium))
            Text(currentAction?.title ?? "Action")
                .font(.system(size: 12, weight: .medium))
        }
        .foregroundStyle(dim ? Color.secondary.opacity(0.5) : Color.primary.opacity(0.9))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Capsule().fill(Color.white.opacity(0.10)))
        .contentShape(Capsule())
        .onTapGesture { cycleAction(1); focused = true }
    }

    // Part of the aesthetic of ray is that it isn't visible so we take up less space
    // The one exception is Calc and Note, there you need to see what you typed so it shows up under the tile
    private var inputField: some View {
        let visible: Bool = (mode != .find)

        return TextField(mode.prompt, text: $query)
            .textFieldStyle(.plain)
            .font(.system(size: 13.5))
            .multilineTextAlignment(.center)
            .focused($focused)
            .onSubmit { run() }
            .frame(height: visible ? 32 : 1)
            .padding(.horizontal, 10)
            .padding(.top, visible ? 10 : 0)
            .opacity(visible ? 1 : 0.01)
            .allowsHitTesting(visible)
    }

    private var dropdown: some View {
        VStack(spacing: 0) {
            dropdownHeader

            VStack(spacing: 1) {
                ForEach(Array(results.enumerated()), id: \.element.id) { i, item in
                    row(item, index: i)
                        .opacity(rowsRevealed ? 1 : 0)
                        .offset(y: rowsRevealed ? 0 : -8)
                        .animation(Self.rowSpring.delay(0.08 + Double(i) * 0.03), value: rowsRevealed) // wait for the liquid to start forming, then each row lands a beat after the one above
                }
            }
            .padding(.horizontal, dropdownInset)
            .padding(.bottom, dropdownInset)
            .animation(Self.selectionSpring, value: selection)
        }
        .frame(width: 380)
        .modifier(GlassCard(radius: dropdownRadius))
        .glassEffectID("dropdown", in: glassNS)
    }

    // Rows start hidden and are revealed right after the dropdown mounts so the stagger plays
    // On close they reset instantly (no animation) so the next open starts clean
    private func revealRows(_ visible: Bool) {
        if visible {
            rowsRevealed = true
        } else {
            var t = Transaction(animation: nil)
            t.disablesAnimations = true
            withTransaction(t) { rowsRevealed = false }
        }
    }

    private var dropdownHeader: some View {
        HStack(spacing: 6) {
            Text(query.isEmpty ? "Suggestions" : "\(results.count) results")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(.secondary)
            if !query.isEmpty {
                Text("“\(query)”")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            Spacer()
            keycap("↑↓")
        }
        .padding(.horizontal, 22)
        .padding(.top, 14)
        .padding(.bottom, 8)
    }

    private func row(_ item: Item, index i: Int) -> some View {
        let selected: Bool = (i == selection)

        return HStack(spacing: 12) {
            rowIcon(item)

            VStack(alignment: .leading, spacing: 1) {
                Text(attributed(item.title))
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(1)
                rowSubtitle(item)
            }

            Spacer(minLength: 8)

            rowTrailing(selected: selected, index: i)
        }
        .padding(.horizontal, 12)
        .frame(height: rowHeight)
        .background { rowBackground(selected) }
        .contentShape(Rectangle())
        .onTapGesture { selection = i; run() }
        .onHover { hovering in hover(hovering, index: i) }
    }

    @ViewBuilder
    private func rowIcon(_ item: Item) -> some View {
        if let path = item.iconPath {
            Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                .resizable()
                .interpolation(.high)
                .frame(width: 28, height: 28)
        } else {
            Image(systemName: item.icon)
                .font(.system(size: 15, weight: .light))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
        }
    }

    // Apps show their path, files show the folder they're in
    @ViewBuilder
    private func rowSubtitle(_ item: Item) -> some View {
        if let sub = item.subtitle {
            Text(sub)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    @ViewBuilder
    private func rowTrailing(selected: Bool, index i: Int) -> some View {
        if selected {
            keycap("↵")
        } else {
            Text("⌘\(i + 1)")
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(.quaternary)
        }
    }

    @ViewBuilder
    private func rowBackground(_ selected: Bool) -> some View {
        if selected {
            RoundedRectangle(cornerRadius: dropdownRadius - dropdownInset, style: .continuous)
                .fill(selectionTint)
                .matchedGeometryEffect(id: "selected", in: ns)
        }
    }

    private func keycap(_ s: String) -> some View {
        Text(s)
            .font(.system(size: 10.5, weight: .medium, design: .rounded))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    // Show the user what they are typing
    private func attributed(_ title: String) -> AttributedString {
        let q: String = trimmedQuery
        let matched: Set<Int> = (mode == .find && !q.isEmpty) ? Highlight.matched(q, in: title) : []

        var out = AttributedString()
        for (i, ch) in title.enumerated() {
            var piece = AttributedString(String(ch))
            if matched.contains(i) { piece.swiftUI.underlineStyle = .single }
            out.append(piece)
        }
        return out
    }

    // What the chip offers depends on what the item is
    // Calc copies, Note saves, web searches, apps and files get Open / Reveal / Copy Path
    private func actions(for item: Item) -> [PaneAction] {
        if mode == .calc {
            return [PaneAction(title: "Copy", icon: "doc.on.doc", run: item.action)]
        }
        if mode == .note {
            return [PaneAction(title: "Save Note", icon: "square.and.pencil", run: item.action)]
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

    private func cycleAction(_ d: Int) {
        let n: Int = currentActions.count
        guard n > 1 else { return }
        actionIndex = (actionIndex + d + n) % n
    }

    // Hides the dropdown and reopens it after an idle delay (pulled from UserDefaults)
    private func scheduleDropdown() {
        dropdownTask?.cancel()
        showDropdown = false
        let delay: Double = query.isEmpty ? Self.stillDelay : Self.typingDelay
        dropdownTask = Task {
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            showDropdown = true
        }
    }

    private func closeDropdown() {
        dropdownTask?.cancel()
        showDropdown = false
    }

    // Typing = (=) or (') as the very first character jumps to Calc or Note instead of searching
    private func queryChanged(_ q: String) {
        if mode == .find, q.count == 1, let first = q.first, let m = Mode.from(prefix: first) {
            mode = m
            query = ""
            return
        }
        refresh()
        scheduleDropdown()
    }

    private func handleDown() -> KeyPress.Result {
        if !dropdownVisible && results.count > 1 && mode != .calc {
            dropdownTask?.cancel()
            showDropdown = true
        } else {
            move(1)
        }
        return .handled
    }

    private func handleEscape() -> KeyPress.Result {
        if dropdownVisible {
            closeDropdown()
        } else {
            hide()
        }
        return .handled
    }

    // Tab cycles modes, Shift-Tab goes back
    private func handleTab(_ press: KeyPress) -> KeyPress.Result {
        step(press.modifiers.contains(.shift) ? -1 : 1)
        return .handled
    }

    // Backspace on an empty field drops you back to Find
    private func handleDelete() -> KeyPress.Result {
        guard query.isEmpty, mode != .find else { return .ignored }
        mode = .find
        return .handled
    }

    private func hover(_ hovering: Bool, index i: Int) {
        guard hovering else { return }
        let current: CGPoint = NSEvent.mouseLocation
        if current != lastMouseLocation {
            lastMouseLocation = current
            selection = i
        }
    }

    private func step(_ d: Int) {
        let all: [Mode] = Mode.allCases
        let next: Int = (mode.rawValue + d + all.count) % all.count
        mode = all[next]
    }

    private func move(_ d: Int) {
        guard !results.isEmpty else { return }
        selection = max(0, min(results.count - 1, selection + d))
    }

    private func loadApps() async {
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
        pool = items
        refresh()
    }

    // Our own file index, rebuilt every 5 minutes in the background instead of using Spotlight (way faster)
    private func indexFiles() async {
        while !Task.isCancelled {
            let found = await Task.detached(priority: .utility) { Search.scanFiles() }.value
            fileEntries = found
            if mode == .find && !query.isEmpty { searchFiles(trimmedQuery) }
            try? await Task.sleep(for: .seconds(300))
        }
    }

    // Runs off the main thread, then merges into the Find results when it's done
    private func searchFiles(_ q: String) {
        let entries: [FileEntry] = fileEntries
        let tokens: [[UInt8]] = q.lowercased().split(separator: " ").map { Array($0.utf8) }
        Task {
            let top = await Task.detached(priority: .userInitiated) {
                Search.rankFiles(tokens, in: entries, limit: 6)
            }.value
            guard mode == .find, trimmedQuery == q else { return }
            fileHits = top.map { fileItem($0) }
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

    private func refresh() {
        let q: String = trimmedQuery

        switch mode {
        case .find:
            if q.isEmpty { fileHits = [] }
            recomputeFind(preserveSelection: false)
            if !q.isEmpty { searchFiles(q) }

        case .calc:
            let value: String? = Calc.eval(q)
            calcResult = value
            results = value.map { [copyItem($0)] } ?? []
            selection = 0

        case .note:
            calcResult = nil
            results = q.isEmpty ? [] : [noteItem(q)]
            selection = 0
        }
    }

    // Find results are apps first, then files, then web search always last
    // preserveSelection keeps you on the same row when files arrive late
    private func recomputeFind(preserveSelection: Bool) {
        let q: String = trimmedQuery
        calcResult = nil
        let keepID: String? = results.indices.contains(selection) ? results[selection].id : nil

        var out: [Item] = []
        if q.isEmpty {
            out = Search.rank("", in: pool, limit: 7)
        } else {
            let apps: [Item] = Search.rank(q, in: pool, limit: 4)
            let tokens: [String] = q.lowercased().split(separator: " ").map { String($0) }
            let files: [Item] = fileHits
                .filter { item in
                    let low: String = item.title.lowercased()
                    return tokens.allSatisfy { low.contains($0) }
                }
                .prefix(max(0, 6 - apps.count))
                .map { $0 }
            out = apps + files + [webItem(q)]
        }
        results = out

        if preserveSelection, let id = keepID, let idx = out.firstIndex(where: { $0.id == id }) {
            selection = idx
        } else {
            selection = 0
        }
    }

    private func copyItem(_ value: String) -> Item {
        Item(id: "calc", title: "Copy \(value)", icon: "doc.on.doc") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(value, forType: .string)
        }
    }

    // Notes get appended to ~/ray-notes.md
    private func noteItem(_ text: String) -> Item {
        Item(id: "note", title: text, icon: "square.and.pencil", subtitle: "Save note") {
            Notes.append(text)
        }
    }

    private func webItem(_ q: String) -> Item {
        Item(id: "web:\(q)", title: q, icon: "globe", subtitle: "Search the web") {
            let encoded: String = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? q
            if let url = URL(string: "https://www.google.com/search?q=\(encoded)") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    private func run(at i: Int) {
        guard results.indices.contains(i) else { return }
        selection = i
        run()
    }

    private func run() {
        guard results.indices.contains(selection) else { return }
        if mode == .find && query.isEmpty && !dropdownVisible { return }
        let chosen: PaneAction? = currentAction
        hide()
        chosen?.run()
    }

    private func hide() {
        NSApp.windows.first { $0 is LauncherPanel }?.orderOut(nil)
    }

    // Always open and close empty
    private func reset() {
        var t = Transaction(animation: nil)
        t.disablesAnimations = true
        withTransaction(t) {
            closeDropdown()
            query = ""
            mode = .find
            selection = 0
            actionIndex = 0
            fileHits = []
            calcResult = nil
        }
        focused = true
        refresh()
        scheduleDropdown()
    }

    // This fixes a bug I had where I had to refocus the app for ray to recognise my keystrokes
    // Idk why it happened in the first place but this fixed it :/
    private func refocus() {
        focused = false
        DispatchQueue.main.async { focused = true }
    }
}

//
//  ContentView.swift
//  ray
//
//  Created by Dylan Karunanayake on 8/10/2026.
//

import SwiftUI

// I'm gonna practice writing comments
/*
 
 Quick terminology so I don't forget..
 Launchpad:      the rounded squircle that acts as the actual launcher
 Map:            the dropdown of related command options
 Option Command: the suggested/main action given in the launchpad
 Command Option: the suggested/list of actions given in the map
 
 */

// Mode is what the launcher is currently doing with what you type
enum Mode: Int, CaseIterable {
    case find, calc, note

    var prompt: String {
        switch self {
        case .find: return "Search apps, files and the web"
        case .calc: return "Type an expression"
        default: return ""
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

/// PaneAction is the expected shape of an option command in ray
/// All parameters are required
struct PaneAction {
    let title: String
    let icon: String
    let run: () -> Void
}

/// SideAction is what the left and right arrows + gestures do on a row
struct SideAction {
    let title: String
    let icon: String
    let run: () -> Void
}

// Different types of animations for the emoji that lives in the launchpad
enum OnboardingEmojiAnimation {
    case wave
}

// Things the Onboarding teaches you
enum OnboardingTask {
    case typing, modeSwitch, arrows, number
}

// One page of the first-run onbarding that lives in the dropdown
// Give it either an emoji or an SF Symbol, keys are shown as keycaps under the text
struct OnboardingStep {
    var emoji: String? = nil
    var animation: OnboardingEmojiAnimation? = nil
    var symbol: String? = nil
    let title: String
    let body: String
    var keys: [String] = []
    var showsMarkerDemo: Bool = false
    var tasks: [OnboardingTask] = []
    var hint: String? = nil
}

enum Onboarding {
    static let steps: [OnboardingStep] = [
        OnboardingStep(emoji: "👋",
                       animation: OnboardingEmojiAnimation.wave,
                       symbol: "faceid",
                       title: "Welcome to Ray",
                       body: "This is just an onboarding so you don't get lost, this won't take very long."),
        OnboardingStep(symbol: "keyboard",
                       title: "Summon it from anywhere",
                       body: "Press these keys in any app. Click away or hit escape and it leaves.",
                       keys: ["⌥", "Space"]),
        OnboardingStep(symbol: "magnifyingglass",
                       title: "Just start typing",
                       body: "Apps, files and the web in one search. The letters you typed get highlighted so you can see why something matched.", // TODO: add AI messaging as well
                       showsMarkerDemo: true,
                       tasks: [.typing],
                       hint: "Try searching for something"),
        OnboardingStep(symbol: "plusminus",
                       title: "Math and notes too",
                       body: "Press Tab to switch modes, or start with = for a calculation and ' for a quick note.",
                       keys: ["Tab", "=", "'"],
                       tasks: [.modeSwitch],
                       hint: "Try it, press Tab"),
        OnboardingStep(symbol: "arrow.up.arrow.down",
                       title: "Pick your result",
                       body: "The list opens when you pause. Move with the arrows, jump with a number, open with return.",
                       keys: ["↑↓", "⌘1", "↵"],
                       tasks: [.arrows, .number],
                       hint: "Try it, press ↓ or ⌘1"),
        OnboardingStep(symbol: "checkmark.circle",
                       title: "You're all set",
                       body: "You can change anything later in Ray Settings. You can also replay the onboarding there."),
    ]
}

// Marks a piece of text as typed
struct MarkedAttribute: TextAttribute {}

struct MarkerRenderer: TextRenderer {
    var color: Color

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        for line in layout {
            for run in line where run[MarkedAttribute.self] != nil {
                let r = run.typographicBounds.rect.insetBy(dx: 0, dy: 1) // dx 0 so it never spills onto the next letter
                context.fill(Path(r), with: .color(color))
            }
            context.draw(line)
        }
    }
}

// GlassCard is shape/body of the launcher, everything the user sees and interacts with will be housed here
struct GlassCard: ViewModifier {
    let radius: CGFloat

    func body(content: Content) -> some View {
        let s = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let edge = LinearGradient(colors: [Color.black.opacity(0.6), Color.black.opacity(0.6)], startPoint: .top, endPoint: .bottom)
        // I know it's barely noticable but why not
        return content
            .rayGlassEffect(Color.black.opacity(0.22), interactive: true, in: s) // Glass is so good TODO: check if you can scale interaction intensity
            .overlay(s.strokeBorder(edge, lineWidth: 0.6))
            .shadow(color: .black.opacity(0.35), radius: 22, y: 9)
    }
}

// 🫠
struct ContentView: View {
    
    // The feel of the map
    private static let dropdownSpring = Animation.spring(response: 0.42, dampingFraction: 0.72)
    private static let rowSpring = Animation.spring(response: 0.32, dampingFraction: 0.78)
    private static let selectionSpring = Animation.spring(response: 0.28, dampingFraction: 0.78)
    
    // Defaults
    @AppStorage("ray_typing_delay") private static var typingDelay: Double = 0.8
    @AppStorage("ray_still_delay") private static var stillDelay: Double = 3.0
    @AppStorage("ray_onboarded") private var onboarded: Bool = false // Onboarding related
    @AppStorage("ray_marker_theme") private var markerTheme: MarkerTheme = .highlighter
    @AppStorage("ray_note_destination") private var noteDestination: NoteDestination = .file // Where Note mode saves to
    @AppStorage("ray_note_draft") private var noteDraft: String = "" // An unsaved note survives closing the launcher
    @AppStorage("ray_note_draft_base") private var noteDraftBase: String = "" // What a draft was edited from, if anything
    @AppStorage("ray_marker_colour") private var markerColour: MarkerColour = .yellow
    @AppStorage("ray_marker_weight") private var markerWeight: MarkerBoldness = .verybold
    
    @State private var query: String = ""
    @State private var mode: Mode = .find
    @State private var selection: Int = 0
    @State private var pool: [Item] = []
    @State private var results: [Item] = []
    @State private var onboardingStep: Int = 0 // Onboarding related
    @State private var taskDone: Bool = false  // Onboarding related
    @State private var calcResult: String? = nil
    @State private var fileIndex = FileIndex() // The flat file index, see Item.swift
    @State private var fileSearchTask: Task<(entries: [FileEntry], took: Duration), Never>? = nil
    @State private var filesPending: Bool = false
    @State private var lastFileSearch: Duration = .zero // How long the last file search took, fast ones run inline
    @State private var fileHits: [Item] = []
    @State private var showDropdown: Bool = false
    @State private var rowsRevealed: Bool = false
    @State private var dropdownTask: Task<Void, Never>? = nil
    @State private var actionIndex: Int = 0
    @State private var lastMouseLocation: CGPoint = .zero
    @State private var showUtilityBar: Bool = true
    @State private var isUpdateAvailable = false
    @State private var runningPaths: Set<String> = [] // Apps that are running right now, refreshed whenever the launcher opens
    @State private var loadedNote: String? = nil // The destination's content that was loaded into the editor, saving replaces it instead of adding it again
    @State private var noteLayout: Bool = false  // Drives the launchpad's size, flipped inside withAnimation so the resize always animates
    @FocusState private var focused: Bool
    @Namespace private var ns
    @Namespace private var glassNS
    
    private let tileSize: CGFloat = 240
    private let noteTileSize = CGSize(width: 348, height: 252) // Note mode, wider than tall so there's room to write
    private let rowHeight: CGFloat = 46
    private let launcherRadius: CGFloat = 50
    private let launcherPadding: CGFloat = 16
    private let tileRadius: CGFloat = 38
    private let dropdownRadius: CGFloat = 28
    private let dropdownInset: CGFloat = 8
    private let dropdownHeaderHeight: CGFloat = 36 // Roughly the height of "Suggestions", only used to place the Open With menu
    private let selectionTint = Color.gray.opacity(0.3)
    
    // True while the launchpad is the note editor
    private var isNote: Bool {
        mode == .note && !doOnboarding
    }

    // Size follows noteLayout, not the mode, because noteLayout is changed inside withAnimation (see the mode onChange)
    // An .animation modifier on the mode fought with the quick fade on mode and lost
    private var tileDimensions: CGSize {
        noteLayout ? noteTileSize : CGSize(width: tileSize, height: tileSize)
    }

    private var launcherSize: CGSize {
        CGSize(width: tileDimensions.width + launcherPadding * 2,
               height: tileDimensions.height + launcherPadding * 2)
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespaces)
    }
    
    private var doOnboarding: Bool {
        !onboarded
    }
    
    private var dropdownVisible: Bool {
        if doOnboarding { return showDropdown } // the tour opens the dropdown even though there's nothing to list
        return showDropdown && results.count > 1 && mode != .calc // If there is only one result what's the point of the dropdown
    }
    
    // What the tile shows, idle shows nothing enter can't fire blind
    // During the tour the tile also stays empty until you type, so a tour page never shows a random app
    private var paneItem: Item? {
        guard results.indices.contains(selection) else { return nil }
        if mode == .find && query.isEmpty && (!dropdownVisible || doOnboarding) { return nil }
        if filesPending && results[selection].id.hasPrefix("web:") { return nil } // files are on their way, don't flash the web search
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
            .onChange(of: mode) {
                refresh(); scheduleDropdown()
                if mode != .find { completeTask(.modeSwitch) }
                if mode == .note && !doOnboarding && query.isEmpty {
                    if !noteDraft.isEmpty {
                        loadedNote = noteDraftBase.isEmpty ? nil : noteDraftBase // set first, the save action captures it
                        query = noteDraft                                        // an unsaved note comes back first
                    } else {
                        loadDestinationContent()                                 // nothing unsaved, so show what's already there
                    }
                }
                withAnimation(Self.dropdownSpring) { noteLayout = isNote } // same spring as the map opening, in its own transaction so nothing else can override it
                refocus() // the editor is a different view from the search field, so focus has to move
            }
            .onChange(of: selection) { actionIndex = 0 }
            .onChange(of: dropdownVisible) { _, visible in revealRows(visible) }
            .onReceive(NotificationCenter.default.publisher(for: .rayReset)) { _ in reset() }
            .onReceive(NotificationCenter.default.publisher(for: .rayFocus)) { _ in refocus() }
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
            .onKeyPress(.leftArrow)  { handleSide(.leading) }  // ← Reveal in Finder
            .onKeyPress(.rightArrow) { handleSide(.trailing) } // → Open With (files) or Quit (apps)
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
    
    // This is the raydar, launchpad and map
    private var stage: some View {
        GlassEffectContainer(spacing: 16) {
            VStack(spacing: 16) {
                if showUtilityBar && isUpdateAvailable {
                    utilityBar {
                        HStack {
                            //                            Image(systemName: "radar")
                            Text("An update for ray is [available](https://github.com/dylankaru/ray/releases/latest).")
                        }
                        .font(.system(size: 13, weight: .medium))
                    }
                }
                launcher // Launchpad
                if dropdownVisible {
                    dropdown // Map
                }
            }
            .frame(width: 380, alignment: .top)
        }
        .animation(Self.dropdownSpring, value: dropdownVisible)
        .animation(.smooth(duration: 0.16), value: mode)
        .task {
            isUpdateAvailable = await checkForUpdates()
        }
    }
    
    private func checkForUpdates() async -> Bool {
        let status = await AppUpdateChecker.shared.checkAppUpdate()
        
        switch status {
        case .upToDate:
            return false
        case .updateAvailable:
            return true
        }
    }
    
    // Utility bar for minimalism sake will only be visible if it's needed, like when an app related notification is due
    // like updates or other functionality like if its a friend's birthday or smth (for extensions ig)
    @ViewBuilder
    private func utilityBar<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            content()
        }
        .frame(width: 380, height: 60)
        .modifier(GlassCard(radius: dropdownRadius))
        .glassEffectID("utilityBar", in: glassNS)
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
        tile
            .frame(width: tileDimensions.width, height: tileDimensions.height) // the same animated size the glass uses
            .background(tileBackground) // the inner rect lives here, not inside the tiles, so it never snaps ahead of the glass
            .padding(launcherPadding)
            .frame(width: launcherSize.width, height: launcherSize.height)
            .modifier(GlassCard(radius: launcherRadius))
            .glassEffectID("launcher", in: glassNS)
    }
    
    @ViewBuilder
    private var tile: some View {
        if mode == .note && !doOnboarding {
            noteTile
        } else {
            findTile
        }
    }

    private var findTile: some View {
        VStack(spacing: 12) {
            if doOnboarding, let emoji = Onboarding.steps[onboardingStep].emoji {
                OnboardingEmojiView(
                    emoji: emoji,
                    animation: Onboarding.steps[onboardingStep].animation
                )
            } else {
                paneIcon
                paneTitle
            }
        }
        .padding(.horizontal, 16)
        .frame(width: tileSize, height: tileSize, alignment: .center)
        .overlay(alignment: .bottom) { tileBottom } // an overlay never changes the tile's size
    }
    
    // Fill and outline share one radius, strokeBorder keeps the outline inside the shape
    private var tileBackground: some View {
        let shape = RoundedRectangle(cornerRadius: tileRadius, style: .continuous)
        
        return ZStack {
            shape.fill(selectionTint)
            shape.strokeBorder(Color.accentColor.opacity(0.45), lineWidth: 0.6)
        }
    }
    
    private var tileBottom: some View {
        let typing: Bool = (mode != .find)
        
        return VStack(spacing: typing ? 8 : 0) {
            inputField
            if !typing && !doOnboarding {
                actionChip
            }
        }
        .padding(.bottom, 14)
    }
    
    private var noteTile: some View {
        VStack(spacing: 0) {
//            noteHeader
            noteEditor
            noteFooter
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity) // fills whatever size the launchpad is animating through
    }

    private var noteHeader: some View {
        HStack(spacing: 6) {
            Button {
                switchNoteDestination()
                focused = true
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: noteDestination.icon)
                    Text(noteDestination.title)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.white.opacity(0.10)))
            }
            .buttonStyle(.plain)
            .help("Where notes are saved, click or press ⌥↑ ⌥↓ to switch")
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }
    
    private var notesYayFactor: [String] = [
        "Write a note",
        "Ready when you are",
        "What's your next million dollar business idea?",
        "How are you blessing your notes today?",
        "Moles of hydrogen is two times moles of water",
        "Fun fact: a broken themometer is right twice a day",
        "I'm the brightest tool in the shed",
        "Type away",
        "He loves using Claude to generate questions for Gemini",
    ]

    private var noteEditor: some View {
        TextEditor(text: $query)
            .font(.system(size: 14))
            .lineSpacing(2)
            .scrollContentBackground(.hidden)
            .focused($focused)
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .overlay(alignment: .topLeading) {
                if query.isEmpty {
                    Text(notesYayFactor.randomElement() ?? "Kevin can't remember things")
                        .font(.system(size: 14))
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 4)
                        .padding(.horizontal, 18)
                        .padding(.top, 18)
                        .allowsHitTesting(false)
                }
            }
            .onKeyPress(.return, phases: .down) { press in handleNoteReturn(press) }
            .onKeyPress(.tab, phases: .down) { press in handleTab(press) }
            .onKeyPress(.escape) { handleEscape() }
            .onKeyPress(.delete) { handleDelete() }
    }

    private var noteFooter: some View {
        HStack() {
            noteStats
            Spacer()
            HStack {
                keycap("↵")
                Text("Save")
            }
            HStack {
                keycap("⇧↵")
                Text("New line")
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 50)
        .padding(.top, 4)
        .padding(.bottom, 12)
    }
    
    private var noteStats: some View {
        Text(noteStatsString)
            .monospacedDigit()
            .foregroundStyle(.tertiary)
    }

    private var noteStatsString: String {
        let words = query.split { $0.isWhitespace }.count
        return words == 0 ? "0 words" : "\(words) word" + (words == 1 ? "" : "s")
    }

    // Shift-return and option-return are a new line, the editor inserts that itself
    // A bare return saves, an empty note just ignores it
    private func handleNoteReturn(_ press: KeyPress) -> KeyPress.Result {
        if press.modifiers.contains(.shift) || press.modifiers.contains(.option) { return .ignored }
        run()
        return .handled
    }

    // Shows what the destination already holds (the file, or Apple Notes' first note) in the editor
    // Saving then replaces that content, see noteItem and Notes.replace
    private func loadDestinationContent() {
        Task {
            guard let existing = await Notes.load(), !existing.isEmpty else { return }
            guard mode == .note, query.isEmpty else { return } // you may have typed or left Note mode while it loaded
            loadedNote = existing // set before the query, the save action captures it
            query = existing
        }
    }

    // ⌥↑ ⌥↓ in Note mode. If the loaded text is untouched it's swapped for the other destination's content
    // If you've edited it, your text stays and will be saved as a new note instead
    private func switchNoteDestination() {
        let untouched = loadedNote != nil && query == loadedNote
        noteDestination = noteDestination.other
        loadedNote = nil
        guard untouched else { return }

        query = ""
        Task {
            guard let existing = await Notes.load(from: noteDestination), !existing.isEmpty else { return }
            guard mode == .note, query.isEmpty else { return }
            loadedNote = existing
            query = existing
        }
    }

    // Leaving Note mode: unsaved text becomes the draft, loaded text you didn't change isn't one, and the editor is emptied
    // Without the last part the note would stay in `query` and show up as the search text in the other modes
    private func stashNote() {
        noteDraft = (query == loadedNote) ? "" : query
        noteDraftBase = noteDraft.isEmpty ? "" : (loadedNote ?? "") // remembers what the draft was edited from
        loadedNote = nil
        query = ""
    }

    private struct WaveValues {
        var rotation: Double = 0
    }
    
    struct OnboardingEmojiView: View {
        let emoji: String
        let animation: OnboardingEmojiAnimation?
        
        @State private var isAnimating = false
        
        var body: some View {
            Group {
                if case .wave = animation {
                    Text(emoji)
                        .font(.system(size: 80))
                        .keyframeAnimator(
                            initialValue: WaveValues(),
                            repeating: true
                        ) { content, value in
                            content.rotationEffect(
                                .degrees(value.rotation),
                                anchor: UnitPoint(x: 1, y: 1)
                            )
                        } keyframes: { _ in
                            KeyframeTrack(\.rotation) {
                                // Gently lean back
                                CubicKeyframe(-14, duration: 0.35)
                                
                                // Sweep forward
                                CubicKeyframe(12, duration: 0.45)
                                
                                // A softer, smaller return swing
                                CubicKeyframe(-7, duration: 0.35)
                                
                                // Ease back to neutral
                                CubicKeyframe(0, duration: 0.4)
                                
                                // Pause before the next wave
                                LinearKeyframe(0, duration: 1.0)
                            }
                        }
                    
                } else {
                    // More animations go here if we ever need them
                }
            }
        }
    }
    
    @ViewBuilder
    private var paneIcon: some View {
        if mode == .calc { // The launchpad will show the answer instead of an app icon or anything like that
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
            Image("ray")
                .font(.system(size: 46))
                .foregroundStyle(.background)
                .frame(height: 84)
        }
    }
    
    // Apps and files get their real icon, everything else (web, notes) gets a symbol
    @ViewBuilder
    private func bigIcon(_ item: Item) -> some View {
        if let path = item.iconPath {
            Image(nsImage: IconCache.icon(for: path))
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
            highlighted(item.title)
                .font(.system(size: 16, weight: .medium))
            //                .monospaced() // Optional, to be a setting maybe
                .lineLimit(2)
                .multilineTextAlignment(.center)
        } else {
            Text(query.isEmpty ? "Type to search" : (filesPending ? " " : "No matches"))
                .font(.system(size: 14))
            //                .monospaced() // Optional, to be a setting maybe
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
    private var inputField: some View {
        let visible: Bool = (mode != .find)
        
        return TextField(mode.prompt, text: $query)
            .textFieldStyle(.plain)
            .font(.system(size: 13.5))
            .multilineTextAlignment(.center)
            .focused($focused)
            .onSubmit { run() }
            .padding(.horizontal, visible ? 12 : 0)
            .frame(width: visible ? tileSize - 48 : 1, height: visible ? 30 : 1)
            .background { if visible { Capsule().fill(Color.white.opacity(0.08)) } }
            .opacity(visible ? 1 : 0.01)
            .allowsHitTesting(visible)
    }
    
    // The map
    private var dropdown: some View {
        VStack(spacing: 0) {
            if doOnboarding {
                onboardingContent
            } else {
                dropdownHeader
                
                VStack(spacing: 1) {
                    ForEach(Array(results.enumerated()), id: \.element.id) { i, item in
                        row(item, index: i)
                            .opacity(rowsRevealed ? 1 : 0)
                            .offset(y: rowsRevealed ? 0 : -8)
                            .animation(Self.rowSpring.delay(0.25 + Double(i) * 0.03), value: rowsRevealed) // For stagger
                            // Swipe left reveals the trailing action (same as →), swipe right the leading one (same as ←)
                            .swipeActions(edge: .trailing, allowsFullSwipe: !isApp(item)) { swipeButton(.trailing, item: item, index: i) }
                            .swipeActions(edge: .leading, allowsFullSwipe: true) { swipeButton(.leading, item: item, index: i) }
                    }
                }
                .padding(.horizontal, dropdownInset)
                .padding(.bottom, dropdownInset)
                .animation(Self.selectionSpring, value: selection)
                .clipped()
            }
        }
        .frame(width: 380)
        .modifier(GlassCard(radius: dropdownRadius))
        .glassEffectID("dropdown", in: glassNS)
    }
    
    private var onboardingContent: some View {
        let step: OnboardingStep = Onboarding.steps[min(onboardingStep, Onboarding.steps.count - 1)]
        let last: Bool = onboardingStep >= Onboarding.steps.count - 1
        
        return VStack(spacing: 0) {
            ZStack {
                onboardingPage(step)
                    .id(onboardingStep)
                    .transition(.opacity.combined(with: .offset(y: 10)))
            }
            .frame(maxWidth: .infinity, minHeight: 250)
            .animation(Self.rowSpring, value: onboardingStep)
            
            onboardingFooter(last: last)
        }
    }
    
    private func onboardingPage(_ step: OnboardingStep) -> some View {
        VStack(spacing: 10) {
            onboardingIcon(step)
            
            Text(step.title)
                .font(.system(size: 18, weight: .semibold))
            
            Text(step.body)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            
            if !step.keys.isEmpty {
                HStack(spacing: 6) {
                    ForEach(step.keys, id: \.self) { key in
                        keycap(key)
                    }
                }
                .padding(.top, 4)
            }
            
            if step.showsMarkerDemo {
                markerDemo
            }
            
            if let hint = step.hint {
                taskHint(hint)
                    .padding(.bottom, 4)
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 8)
    }
    
    @ViewBuilder
    private func onboardingIcon(_ step: OnboardingStep) -> some View {
        if let symbol = step.symbol {
            Image(systemName: symbol)
                .font(.system(size: 45, weight: .light))
                .foregroundStyle(.primary)
        }
    }
    
    private func taskHint(_ hint: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: taskDone ? "checkmark.circle.fill" : "circle.dotted")
                .foregroundStyle(taskDone ? Color.green : Color.secondary)
                .contentTransition(.symbolEffect(.replace))
            
            Text(taskDone ? "Nice!" : hint)
                .foregroundStyle(taskDone ? Color.primary : Color.secondary)
        }
        .font(.system(size: 12, weight: .medium))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        //        .background(
        //            Capsule()
        //                .fill(taskDone ? Color.green.opacity(0.12) : Color.secondary.opacity(0.08))
        //        )
        .padding(.top, 8)
        .id(taskDone)
        .transition(.scale(scale: 0.92, anchor: .leading).combined(with: .opacity))
        .animation(Self.rowSpring, value: taskDone)
    }
    
    // Shows the marker highlight with the real renderer, "saf" lighting up the start of Safari
    private var markerDemo: some View {
        HStack(spacing: 10) {
            Text("saf")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
            Image(systemName: "arrow.right")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            (Text("Saf").customAttribute(MarkedAttribute()) + Text("ari"))
                .textRenderer(MarkerRenderer(color: markerColour.colour))
                .font(.system(size: 16, weight: .medium))
        }
        .padding(.top, 6)
    }
    
    private func onboardingFooter(last: Bool) -> some View {
        HStack {
            Button { finishOnboarding() } label: {
                HStack(spacing: 6) {
                    keycap("esc")
                    Text("Skip")
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tertiary)
            
            Spacer()
            
            progressDots
            
            Spacer()
            
            Button { advanceOnboarding() } label: {
                HStack(spacing: 6) {
                    Text(last ? "Get started" : "Next")
                    keycap("↵")
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .font(.system(size: 12))
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 0.5)
        }
    }
    
    // The active page stretches into a pill, click a dot to jump to that page
    private var progressDots: some View {
        HStack(spacing: 5) {
            ForEach(0..<Onboarding.steps.count, id: \.self) { i in
                Capsule()
                    .fill(Color.white.opacity(i == onboardingStep ? 0.85 : 0.25))
                    .frame(width: i == onboardingStep ? 16 : 5, height: 5)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                    .onTapGesture { goToStep(i) }
            }
        }
        .animation(Self.rowSpring, value: onboardingStep)
    }
    
    private func advanceOnboarding() {
        if onboardingStep >= Onboarding.steps.count - 1 {
            finishOnboarding()
        } else {
            goToStep(onboardingStep + 1)
        }
    }
    
    // Every page starts clean, so whatever you typed on the last page is gone
    private func goToStep(_ i: Int) {
        guard i >= 0, i < Onboarding.steps.count else { return }
        taskDone = false
        clearOnboardingInput()
        onboardingStep = i
    }
    
    // Called from the real handlers (typing, Tab, arrows, ⌘1), so the keys genuinely work during the onboarding
    // If this page was waiting for it, show the tick and move on after a beat
    private func completeTask(_ kind: OnboardingTask) {
        guard doOnboarding, !taskDone else { return }
        
        let step = Onboarding.steps[
            min(onboardingStep, Onboarding.steps.count - 1)
        ]
        
        guard step.tasks.contains(kind) else { return }
        
        if kind == .typing {
            guard trimmedQuery.lowercased().hasPrefix("saf") else {
                return
            }
        }
        
        taskDone = true
        let page = onboardingStep
        
        Task {
            try? await Task.sleep(for: .seconds(0.9))
            guard doOnboarding,
                  taskDone,
                  onboardingStep == page else { return }
            
            advanceOnboarding()
        }
    }
    
    
    private func clearOnboardingInput() {
        if !query.isEmpty { query = "" }
        if mode != .find { mode = .find }
    }
    
    // Marks the onboarding as seen and folds the dropdown away, after that it behaves normally
    private func finishOnboarding() {
        clearOnboardingInput()
        taskDone = false
        onboarded = true
        onboardingStep = 0
        closeDropdown()
        scheduleDropdown()
    }
    
    // Rows start hidden and are revealed right after the dropdown mounts so the stagger plays
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
                highlighted(item.title)
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(1)
                rowSubtitle(item)
            }
            
            Spacer(minLength: 8)
            
            rowTrailing(item, selected: selected, index: i)
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
            Image(nsImage: IconCache.icon(for: path))
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
    private func rowTrailing(_ item: Item, selected: Bool, index i: Int) -> some View {
        if selected {
            HStack(spacing: 4) {
                // The side actions only show up on the selected row, so there's a hint that the arrows do something
                if let a = sideAction(.leading, for: item, at: i) { sideHint("←", a) }
                if let a = sideAction(.trailing, for: item, at: i) { sideHint("→", a) }
                keycap("↵")
            }
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
    
    @ViewBuilder
    private func highlighted(_ title: String) -> some View {
        let text = markedText(title)
        if markerTheme == .highlighter {
            text.textRenderer(MarkerRenderer(color: markerColour.colour))
        } else {
            text
        }
    }
    
    private func markedText(_ title: String) -> Text {
        let q: String = trimmedQuery
        let matched: Set<Int> = (mode == .find && !q.isEmpty) ? Highlight.matched(q, in: title) : []
        guard !matched.isEmpty else { return Text(title) }
        
        var segments: [Text] = []
        var buffer = ""
        var bufferMarked = false
        
        for (i, ch) in title.enumerated() {
            let marked: Bool = matched.contains(i)
            if i > 0 && marked != bufferMarked {
                segments.append(segment(buffer, marked: bufferMarked))
                buffer = ""
            }
            buffer.append(ch)
            bufferMarked = marked
        }
        segments.append(segment(buffer, marked: bufferMarked))
        
        return segments.reduce(Text(""), +)
    }
    
    private func segment(_ text: String, marked: Bool) -> Text {
        guard marked else { return Text(text) }
        
        switch markerTheme {
        case .highlighter:
            return Text(text).customAttribute(MarkedAttribute())
        case .underline:
            return Text(text).underline(true, color: .white)
        case .bold:
            return Text(text).fontWeight(markerWeight.weight)
        }
    }

    // What the chip offers depends on what the item is
    private func actions(for item: Item) -> [PaneAction] {
        if mode == .calc {
            return [PaneAction(title: "Copy", icon: "doc.on.doc", run: item.action)]
        }
        if mode == .note {
            return [PaneAction(title: "Save to \(noteDestination.title)", icon: "square.and.pencil", run: item.action)]
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
        if mode == .note && !doOnboarding { // in Note mode these keys pick where the note goes
            switchNoteDestination()
            return
        }
        let n: Int = currentActions.count
        guard n > 1 else { return }
        actionIndex = (actionIndex + d + n) % n
    }

    // Hides the dropdown and reopens it after an idle delay (pulled from UserDefaults)
    private func scheduleDropdown() {
        if doOnboarding && showDropdown { return } // the onboarding stays put while you try things
        dropdownTask?.cancel()
        showDropdown = false
        let delay: Double = doOnboarding ? 0.5 : (query.isEmpty ? Self.stillDelay : Self.typingDelay)
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
        if !q.isEmpty { completeTask(.typing) }
    }

    private func handleDown() -> KeyPress.Result {
        completeTask(.arrows)
        if !dropdownVisible && results.count > 1 && mode != .calc {
            dropdownTask?.cancel()
            showDropdown = true
        } else {
            move(1)
        }
        return .handled
    }

    // MARK: Side actions

    // Left and right on a row. Leading (←) is "Reveal in Finder", trailing (→) is "Open With…" for files and "Quit" for running apps
    // The same actions back the swipe gestures, swiping left reveals the trailing one
    private enum Side { case leading, trailing }

    private func isApp(_ item: Item) -> Bool {
        item.iconPath?.hasSuffix(".app") == true
    }

    // nil means this row has nothing for that arrow, so the key falls through and the swipe shows nothing
    private func sideAction(_ side: Side, for item: Item, at index: Int?) -> SideAction? {
        guard mode == .find, !doOnboarding, let path = item.iconPath else { return nil } // web searches, calc and notes have none
        let url = URL(fileURLWithPath: path)

        switch side {
        case .leading:
            return SideAction(title: "Reveal in Finder", icon: "folder") {
                hide()
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }

        case .trailing:
            if isApp(item) {
                // Only offered while the app is actually running, and never for Ray itself
                guard runningPaths.contains(path), path != Bundle.main.bundleURL.path else { return nil }
                return SideAction(title: "Quit", icon: "power") {
                    hide()
                    NSWorkspace.shared.runningApplications.first { $0.bundleURL?.path == path }?.terminate()
                }
            }
            return SideAction(title: "Open With…", icon: "ellipsis.circle") {
                // Next turn of the run loop, so the key press that started this is finished before the menu starts tracking
                DispatchQueue.main.async {
                    let picked = OpenWith.show(for: path, at: menuAnchor(forRow: index))
                    if picked { hide() } else { restoreKeyboard() } // closing the menu with esc leaves the launcher up
                }
            }
        }
    }

    // A pop-up menu takes keyboard focus while it's open and the launcher doesn't always get it back
    // So make the panel key again, then ask the text field to focus once it really is
    private func restoreKeyboard() {
        if let panel = NSApp.windows.compactMap({ $0 as? LauncherPanel }).first, panel.isVisible {
            panel.makeKeyAndOrderFront(nil)
        }
        for delay in [0.05, 0.25] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                NotificationCenter.default.post(name: .rayFocus, object: nil)
            }
        }
    }

    // Where the Open With menu opens, in screen coordinates, just under the row (or under the launchpad if the map is closed)
    private func menuAnchor(forRow index: Int?) -> NSPoint {
        guard let panel = NSApp.windows.compactMap({ $0 as? LauncherPanel }).first else { return NSEvent.mouseLocation }

        let barHeight: CGFloat = (showUtilityBar && isUpdateAvailable) ? 60 + 16 : 0
        var y: CGFloat = 60 + barHeight + launcherSize.height // bottom edge of the launchpad, measured from the top of the window
        if dropdownVisible, let i = index {
            y += 16 + dropdownHeaderHeight + CGFloat(i) * (rowHeight + 1) + rowHeight // bottom edge of row i
        }
        return NSPoint(x: panel.frame.minX + 60 + dropdownInset + 40, y: panel.frame.maxY - y)
    }

    private func handleSide(_ side: Side) -> KeyPress.Result {
        // Left and right only belong to us in Find mode, in Calc and Note they still move the text cursor
        guard !doOnboarding, mode == .find, results.indices.contains(selection) else { return .ignored }
        if query.isEmpty && !dropdownVisible { return .ignored }
        guard let action = sideAction(side, for: results[selection], at: selection) else { return .ignored }
        action.run()
        return .handled
    }

    // The little hint on the selected row, an arrow and the icon of what it does
    private func sideHint(_ arrow: String, _ action: SideAction) -> some View {
        HStack(spacing: 3) {
            Text(arrow)
            Image(systemName: action.icon)
        }
        .font(.system(size: 10.5, weight: .medium, design: .rounded))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    @ViewBuilder
    private func swipeButton(_ side: Side, item: Item, index i: Int) -> some View {
        if let a = sideAction(side, for: item, at: i) {
            Button { a.run() } label: {
                Label(a.title, systemImage: a.icon)
            }
            .tint(side == .leading ? .orange : .blue)
        }
    }

    private func handleEscape() -> KeyPress.Result {
        if doOnboarding { // esc skips the tour instead of closing Ray
            finishOnboarding()
            return .handled
        }
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
        if mode == .note && !doOnboarding { stashNote() }
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
        let next: Mode = all[(mode.rawValue + d + all.count) % all.count]
        if mode == .note && !doOnboarding { stashNote() }  // note text must not turn into a search
        if next == .note && !doOnboarding { query = "" }   // and search text must not turn into a note, the draft or destination content loads instead
        mode = next
    }

    private func move(_ d: Int) {
        if doOnboarding { // arrows still work, during the tour they count towards the "pick your result" page
            completeTask(.arrows)
            return
        }
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
        pool = items + [settingsItem, notesItem]
        refresh()
    }

    // Not an app, but it lives in the same search so typing "settings" finds it
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

    // Our own file index, rebuilt every 10 minutes in the background instead of using Spotlight (way faster)
    private func indexFiles() async {
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

    // Runs off the main thread, then merges into the Find results when it's done
    // Typing again cancels the search that's still running, so old scans never pile up
    private func searchFiles(_ q: String) {
        fileSearchTask?.cancel()

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
        // If one ever gets slow it moves off the main thread, and the next quick one moves it back
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

    private func refresh() {
        let q: String = trimmedQuery

        switch mode {
        case .find:
            if q.isEmpty {
                fileSearchTask?.cancel()
                filesPending = false
                fileHits = []
            }
            recomputeFind(preserveSelection: false)
            if !q.isEmpty { searchFiles(q) }

        case .calc:
            fileSearchTask?.cancel()
            filesPending = false
            let value: String? = Calc.eval(q)
            calcResult = value
            results = value.map { [copyItem($0)] } ?? []
            selection = 0

        case .note:
            fileSearchTask?.cancel()
            filesPending = false
            calcResult = nil
            let body: String = query.trimmingCharacters(in: .whitespacesAndNewlines)
            results = body.isEmpty ? [] : [noteItem(query)]
            selection = 0
        }
    }

    // Find results are apps first, then files, then web search always last
    // preserveSelection keeps you on the same row when files arrive late, but only if you had moved off the top one
    private func recomputeFind(preserveSelection: Bool) {
        let q: String = trimmedQuery
        calcResult = nil
        let keepID: String? = results.indices.contains(selection) ? results[selection].id : nil

        var out: [Item] = []
        if q.isEmpty {
            out = Search.rank("", in: pool, limit: 8)
        } else {
            let apps: [Item] = Search.rank(q, in: pool, limit: 8)
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

        // Late file results only keep your place if you moved off the top row yourself
        // Otherwise the best match wins, instead of staying stuck on the web search that was the only row when you started typing
        if preserveSelection, selection != 0, let id = keepID, let idx = out.firstIndex(where: { $0.id == id }) {
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

    // Saved to whichever destination is picked at the moment you press return, see Notes.swift
    // If the editor was opened with the destination's existing content the save replaces it, otherwise it adds a new note
    private func noteItem(_ text: String) -> Item {
        let loaded = loadedNote // captured now, so the save knows whether it's editing loaded content
        return Item(id: "note", title: text, icon: "square.and.pencil", subtitle: "Save note") {
            if let loaded { Notes.replace(loaded: loaded, with: text) } else { Notes.save(text) }
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
        if doOnboarding {
            completeTask(.number)
            return
        }
        guard results.indices.contains(i) else { return }
        selection = i
        run()
    }

    private func run() {
        if doOnboarding {
            advanceOnboarding()
            return
        }
        guard results.indices.contains(selection) else { return }
        if mode == .find && query.isEmpty && !dropdownVisible { return }
        let chosen: PaneAction? = currentAction
        if mode == .note { // saved, so there is nothing left to restore
            noteDraft = ""
            noteDraftBase = ""
            query = ""
        }
        hide()
        chosen?.run()
    }

    private func hide() {
        AppDelegate.dismiss()
    }

    // Always open and close empty
    private func reset() {
        if mode == .note && !doOnboarding { stashNote() } // closing with unsaved text keeps it as a draft
        loadedNote = nil
        var t = Transaction(animation: nil)
        t.disablesAnimations = true
        withTransaction(t) {
            closeDropdown()
            query = ""
            mode = .find
            selection = 0
            actionIndex = 0
            fileSearchTask?.cancel()
            filesPending = false
            fileHits = []
            calcResult = nil
        }
        runningPaths = Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleURL?.path })
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

//
//  LauncherModel.swift
//  ray
//
//  Created by Dylan Karunanayake on 1/11/2026.
//

import SwiftUI
internal import Combine

@MainActor
final class LauncherModel: ObservableObject {

    @AppStorage("ray_motion_style") var motionStyle: MotionStyle = .standard
    @AppStorage("ray_typing_delay") var typingDelay: Double = 0.8
    @AppStorage("ray_still_delay") var stillDelay: Double = 3.0
    @AppStorage("ray_onboarded") var onboarded: Bool = false
    @AppStorage("ray_note_destination") var noteDestination: NoteDestination = .file
    @AppStorage("ray_note_draft") var noteDraft: String = ""
    @AppStorage("ray_note_draft_base") var noteDraftBase: String = "" // what a draft was edited from, if anything
    @AppStorage("ray_custom_tint") var customTint: RayThemes = .black
    @AppStorage("ray_tint_strength") var tintStrength: Double = 0.4

    @Published var query: String = ""
    @Published var mode: Mode = .find
    @Published var selection: Int = 0
    @Published var actionIndex: Int = 0
    @Published var tileLayout: TileLayout = .compact

    @Published var pool: [Item] = [] // every app + command, searched by Find
    @Published var results: [Item] = [] // what the map shows right now
    @Published var calcResult: String? = nil

    @Published var fileIndex = FileIndex() // the flat file index, see Item.swift
    @Published var fileHits: [Item] = []
    @Published var filesPending = false
    var fileSearchTask: Task<(entries: [FileEntry], took: Duration), Never>? = nil
    var lastFileSearch: Duration = .zero // how long the last file search took, fast ones run inline

    @Published var showDropdown = false
    @Published var rowsRevealed = false
    @Published var scrollToSelection = true
    var dropdownTask: Task<Void, Never>? = nil
    var lastMouseLocation: CGPoint = .zero

    @Published var showingCamera = false
    @Published var showingClipboardHistory = false
    @Published var showingEmoji = false

    @Published var loadedNote: String? = nil

    @Published var onboardingStep = 0
    @Published var taskDone = false

    @Published var aliasTarget: Item? = nil
    @Published var aliasRow: Int? = nil
    @Published var aliasDraft = ""
    @Published var aliasList: [String] = []
    @Published var aliasContentIn = false

    @Published var runningPaths: Set<String> = [] // apps running right now, refreshed whenever the launcher opens
    let clipboard = ClipboardManager.shared

    var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    func motion(_ role: MotionStyle.Role) -> Animation? {
        motionStyle.animation(role, reduceMotion: reduceMotion)
    }

    func rowDelay(_ i: Int) -> Double {
        guard !reduceMotion else { return 0 }
        return 0.25 + Double(i) * motionStyle.stagger(reduceMotion: reduceMotion)
    }


    var trimmedQuery: String { query.trimmingCharacters(in: .whitespaces) }
    var doOnboarding: Bool { !onboarded }
    var isNote: Bool { mode == .note && !doOnboarding }
    var showUtilityBar: Bool { UtilityBarManager.shared.isVisible }
    var resultsAreEmoji: Bool { results.first?.id.hasPrefix("emoji:") == true }

    var highlightQuery: String { mode == .find ? trimmedQuery : "" }

    var selectionTint: Color {
        if customTint.colour == .white && tintStrength >= 0.3 { return Color.black.opacity(0.2) }
        if customTint.colour == .black { return Color.gray.opacity(0.3) }
        if customTint.colour != .white && tintStrength >= 0.2 { return Color.black.opacity(0.2) }
        return Color.gray.opacity(0.3)
    }

    var targetLayout: TileLayout {
        if showingCamera { return .camera }
        return isNote ? .note : .compact
    }

    var tileDimensions: CGSize {
        switch tileLayout {
        case .compact: return CGSize(width: Metrics.tileSize, height: Metrics.tileSize)
        case .note:    return Metrics.noteTileSize
        case .camera:  return Metrics.cameraTileSize
        }
    }

    var launcherSize: CGSize {
        CGSize(width: tileDimensions.width + Metrics.launcherPadding * 2,
               height: tileDimensions.height + Metrics.launcherPadding * 2)
    }

    var dropdownVisible: Bool {
        if showingClipboardHistory || showingEmoji { return true }
        if showingCamera { return false }
        if doOnboarding { return showDropdown }
        return showDropdown && results.count > 1 && mode != .calc // one result? no point in a dropdown
    }

    var paneItem: Item? {
        guard results.indices.contains(selection) else { return nil }
        if mode == .find && query.isEmpty && (!dropdownVisible || doOnboarding) { return nil }
        if filesPending && results[selection].id.hasPrefix("web:") { return nil } // files are on their way, don't flash the web search
        return results[selection]
    }

    var currentActions: [PaneAction] {
        guard let item = paneItem else { return [] }
        return actions(for: item)
    }

    var currentAction: PaneAction? {
        let acts = currentActions
        guard !acts.isEmpty else { return nil }
        return acts[min(actionIndex, acts.count - 1)]
    }

    var cameraSelected: Bool {
        mode == .find && !showingCamera
            && results.indices.contains(selection)
            && results[selection].id == "cmd:camera"
    }

    func appeared() {
        refresh()
        scheduleDropdown()
        tintStrength = min(max(tintStrength, 0.1), customTint.maxStrength) // clamp helper
    }

    func queryChanged(_ q: String) {
        // = or ' as the very first character jumps to calc or notes instead of searching
        if mode == .find, q.count == 1, let first = q.first, let m = Mode.from(prefix: first) {
            mode = m
            query = ""
            return
        }
        refresh()
        scheduleDropdown()
        if !q.isEmpty { completeTask(.typing) }
    }

    func modeChanged() {
        refresh()
        scheduleDropdown()
        if mode != .find { completeTask(.modeSwitch) }
        if isNote && query.isEmpty { restoreNoteIntoEditor() }
        withAnimation(motion(.dropdown)) { tileLayout = targetLayout }
        refocus()
    }

    // Clipboard history / emoji swap the results between find and themselves
    func subScreenChanged() {
        refresh()
        scheduleDropdown()
    }

    func clipboardItemsChanged() {
        if showingClipboardHistory { refresh() }
    }

    func cameraSelectedChanged(_ selected: Bool) {
        if selected {
            CameraSession.shared.start()
        } else if !showingCamera {
            CameraSession.shared.stop(after: 1.5)
        }
    }

    func showingCameraChanged(_ showing: Bool) {
        if !showing { CameraSession.shared.stop() }
        withAnimation(motion(.dropdown)) { tileLayout = targetLayout }
    }

    func selectionChanged() {
        actionIndex = 0
        closeAliasBubble()
    }

    func dropdownVisibleChanged(_ visible: Bool) {
        revealRows(visible)
        if !visible { closeAliasBubble() }
    }

    // Hides the dropdown and reopens it after an idle delay
    func scheduleDropdown() {
        if doOnboarding && showDropdown { return } // the onboarding stays put while you try things
        dropdownTask?.cancel()
        showDropdown = false
        let delay: Double = doOnboarding ? 0.5 : (query.isEmpty ? stillDelay : typingDelay)
        dropdownTask = Task {
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            showDropdown = true
        }
    }

    func closeDropdown() {
        dropdownTask?.cancel()
        showDropdown = false
    }

    func revealRows(_ visible: Bool) {
        if visible {
            rowsRevealed = true
        } else {
            var t = Transaction(animation: nil)
            t.disablesAnimations = true
            withTransaction(t) { rowsRevealed = false }
        }
    }

    func handleDown() -> KeyPress.Result {
        guard aliasTarget == nil else { return .handled } // the bubble is open, arrows belong to it
        completeTask(.arrows)
        if !dropdownVisible && results.count > 1 && mode != .calc {
            dropdownTask?.cancel()
            showDropdown = true
        } else {
            move(showingEmoji ? Metrics.emojiColumns : 1)
        }
        return .handled
    }

    func handleEscape() -> KeyPress.Result {
        if aliasTarget != nil { closeAliasBubble(); return .handled }
        if doOnboarding { finishOnboarding(); return .handled }
        if showingClipboardHistory { showingClipboardHistory = false; return .handled }
        if showingEmoji { showingEmoji = false; refresh(); return .handled }
        if showingCamera { showingCamera = false; selection = 0; refresh(); return .handled }
        if dropdownVisible { closeDropdown() } else { hide() }
        return .handled
    }

    /// Tab cycles modes, Shift-Tab goes back
    func handleTab(_ press: KeyPress) -> KeyPress.Result {
        guard aliasTarget == nil else { return .handled }
        step(press.modifiers.contains(.shift) ? -1 : 1)
        // theres a bug idk how to fix here. -> about publichs changes from with views but i cant see what it actaully does
        return .handled
    }

    func handleDelete() -> KeyPress.Result {
        guard aliasTarget == nil else { return .ignored } // backspace edits the bubble's text
        guard query.isEmpty, mode != .find else { return .ignored }
        if isNote { stashNote() }
        mode = .find
        return .handled
    }

    func handleSide(_ side: Side) -> KeyPress.Result {
        // In the emoji grid left and right just move through the grid
        if showingEmoji, aliasTarget == nil {
            move(side == .leading ? -1 : 1)
            return .handled
        }
        guard aliasTarget == nil else { return .ignored }
        guard !doOnboarding, !showingClipboardHistory, mode == .find,
              dropdownVisible, results.indices.contains(selection) else { return .ignored }
        guard let action = sideAction(side, for: results[selection], at: selection) else { return .ignored }
        action.run()
        return .handled
    }

    func move(_ d: Int) {
        guard aliasTarget == nil else { return }
        if doOnboarding { // arrows still work during the tour coz they count towards the "pick your result" page
            completeTask(.arrows)
            return
        }
        guard !results.isEmpty else { return }
        scrollToSelection = true
        selection = max(0, min(results.count - 1, selection + d))
    }

    func hover(_ hovering: Bool, index i: Int) {
        guard hovering else { return }
        let current = NSEvent.mouseLocation
        if current != lastMouseLocation {
            lastMouseLocation = current
            selection = i
        }
    }

    func step(_ d: Int) {
        showingClipboardHistory = false
        showingEmoji = false
        showingCamera = false
        let all = Mode.allCases
        let next = all[(mode.rawValue + d + all.count) % all.count]
        if isNote { stashNote() }
        // same bug here
        if next == .note && !doOnboarding { query = "" }
        mode = next
    }

    // 1-7
    func run(at i: Int) {
        guard aliasTarget == nil else { return } // shouldn't launch things behind the bubble
        if doOnboarding {
            completeTask(.number)
            return
        }
        guard results.indices.contains(i) else { return }
        selection = i
        run()
    }

    func run() {
        if doOnboarding {
            advanceOnboarding()
            return
        }
        guard results.indices.contains(selection) else { return }
        if mode == .find && query.isEmpty && !dropdownVisible { return }

        let chosen = currentAction
        if mode == .note { // saved, so there is nothing left to restore
            noteDraft = ""
            noteDraftBase = ""
            query = ""
        }
        if chosen?.keepsOpen != true { hide() } // actions like Clipboard History stay inside the launcher
        chosen?.run()
    }

    func hide() {
        AppDelegate.dismiss()
    }

    // Always open and close empty
    func reset() {
        if isNote { stashNote() } // closing with unsaved text keeps it as a draft
        loadedNote = nil

        var t = Transaction(animation: nil)
        t.disablesAnimations = true
        withTransaction(t) {
            tileLayout = .compact
            closeDropdown()
            query = ""
            mode = .find
            selection = 0
            actionIndex = 0
            fileSearchTask?.cancel()
            filesPending = false
            fileHits = []
            calcResult = nil
            showingClipboardHistory = false
            showingEmoji = false
            showingCamera = false
            CameraSession.shared.stop()
            aliasTarget = nil
            aliasDraft = ""
        }
        runningPaths = Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleURL?.path })
        refocus()
        refresh()
        scheduleDropdown()
    }

    func refocus() {
        NotificationCenter.default.post(name: .rayFocus, object: nil)
    }
}

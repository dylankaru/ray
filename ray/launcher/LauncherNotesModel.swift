//
//  LauncherNotesModel.swift
//  ray
//
//  Created by Dylan Karunanayake on 1/11/2026.
//

import SwiftUI

// Note mode: the editor, drafts, and where notes get saved.
// TODO: make notes not close when press enter and also maybe make multiple notes system? maybe idk

extension LauncherModel {

    var noteStatsString: String {
        let words = query.split { $0.isWhitespace }.count
        return words == 0 ? "0 words" : "\(words) word" + (words == 1 ? "" : "s")
    }

    func handleNoteReturn(_ press: KeyPress) -> KeyPress.Result {
        if press.modifiers.contains(.shift) || press.modifiers.contains(.option) { return .ignored }
        run()
        return .handled
    }

    func restoreNoteIntoEditor() {
        if !noteDraft.isEmpty {
            loadedNote = noteDraftBase.isEmpty ? nil : noteDraftBase
            query = noteDraft
        } else {
            loadDestinationContent()
        }
    }

    func loadDestinationContent() {
        Task {
            guard let existing = await Notes.load(), !existing.isEmpty else { return }
            guard mode == .note, query.isEmpty else { return } // you may have typed or left Note mode while it loaded
            loadedNote = existing // set before the query, the save action captures it
            query = existing
        }
    }

    // If you've edited it, your text stays and will be saved as a new note instead
    func switchNoteDestination() {
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

    func stashNote() {
        noteDraft = (query == loadedNote) ? "" : query
        noteDraftBase = noteDraft.isEmpty ? "" : (loadedNote ?? "") // remembers what the draft was edited from
        loadedNote = nil
        query = ""
    }
}

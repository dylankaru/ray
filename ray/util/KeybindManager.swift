//
//  KeybindManager.swift
//  ray
//
//  Created by Dylan Karunanayake on 22/10/2026.
//

import SwiftUI
import Carbon
internal import Combine

struct Keybind: Codable, Hashable {
    var keyCode: UInt32
    var modifiers: UInt32   // Carbon flags: cmdKey, optionKey, controlKey, shiftKey
    var display: String     // e.g. "⌥Space", stored so we never need a keycode→name table

    static let defaultRay = Keybind(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey), display: "⌥ + Space")
}

enum KeybindAction: Codable, Hashable {
    case toggleRay
    case openApp(path: String)
}

struct KeybindEntry: Codable, Identifiable, Hashable {
    var id = UUID()
    var bind: Keybind
    var action: KeybindAction
}

enum KeybindError: Error {
    case conflict(KeybindEntry)   // already used by another action in Ray
    case unavailable              // macOS or another app owns it
}

final class KeybindStore: ObservableObject {
    static let shared = KeybindStore()

    @Published private(set) var entries: [KeybindEntry] = []
    private var hotKeyIDs: [UUID: UInt32] = [:]
    private let defaultsKey = "ray_keybinds"
    private var perform: ((KeybindAction) -> Void)?

    private init() { load() }

    func start(perform: @escaping (KeybindAction) -> Void) {
        self.perform = perform
        for e in entries { register(e) }
    }
    
    func restart() {
        for e in entries { unregister(e) }
        for e in entries { register(e) }
    }

    func bind(for action: KeybindAction) -> Keybind? {
        entries.first { $0.action == action }?.bind
    }

    func set(_ bind: Keybind, for action: KeybindAction) -> Result<Void, KeybindError> {
        if let clash = entries.first(where: {
            $0.bind.keyCode == bind.keyCode && $0.bind.modifiers == bind.modifiers && $0.action != action
        }) { return .failure(.conflict(clash)) }

        let old = entries.first { $0.action == action }
        if let old { unregister(old) }

        let new = KeybindEntry(bind: bind, action: action)
        guard register(new) else {
            if let old { register(old) }
            return .failure(.unavailable)
        }
        entries.removeAll { $0.action == action }
        entries.append(new)
        save()
        return .success(())
    }

    func remove(_ action: KeybindAction) {
        guard let e = entries.first(where: { $0.action == action }) else { return }
        unregister(e)
        entries.removeAll { $0.id == e.id }
        save()
    }

    @discardableResult
    private func register(_ e: KeybindEntry) -> Bool {
        let id = HotKey.register(keyCode: e.bind.keyCode, modifiers: e.bind.modifiers) { [weak self] in
            self?.perform?(e.action)
        }
        guard let id else { return false }
        hotKeyIDs[e.id] = id
        return true
    }

    private func unregister(_ e: KeybindEntry) {
        if let id = hotKeyIDs[e.id] { HotKey.unregister(id) }
        hotKeyIDs[e.id] = nil
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let saved = try? JSONDecoder().decode([KeybindEntry].self, from: data) {
            entries = saved
        } else {
            entries = [KeybindEntry(bind: .defaultRay, action: .toggleRay)]
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }
}

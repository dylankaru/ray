//
//  KeybindRecorder.swift
//  ray
//
//  Created by Dylan Karunanayake on 22/10/2026.
//

import SwiftUI
import Carbon
internal import Combine

// not sure if a enum is really necessary for this but cbbs
enum waitingStatus {
    case firstInterval, secondInterval, thirdInterval
}

struct KeybindRecorder: View {
    let action: KeybindAction
    @ObservedObject private var store = KeybindStore.shared
    
    @State private var recording: Bool = false
    @State private var monitor: Any?
    @State private var message: String?
    @State private var pressed: [String] = []
    @State private var escapeWork: DispatchWorkItem?
    @State private var waitingStatus: waitingStatus = .firstInterval
    
    private let doubleTapWindow: TimeInterval = 0.35
    
    var body: some View {
        HStack {
            Button {
                recording ? cancel() : start()
            } label: {
                HStack(alignment: .center) {
                    Text(store.bind(for: action)?.display ?? "Ready to Record")
                }
                .frame(width: 120)
                .overlay(alignment: .trailing) {
                    if store.bind(for: action) != nil, recording {
                        Button {
                            store.remove(action)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 11))
                                .padding(.trailing, 2)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .popover(isPresented: Binding(get: { recording }, set: { if !$0 { cancel() }} ), arrowEdge: .bottom) {
                bubble
            }
            
            if let message { Text(message).font(.caption).foregroundStyle(.red) }
        }
    }
    
    private var bubble: some View {
        VStack(spacing: 8) {
            if pressed.isEmpty {
                annoyedTextThing
                    .task(id: pressed.isEmpty) {
                        guard pressed.isEmpty else { return }
                        
                        waitingStatus = .firstInterval
                        
                        try? await Task.sleep(for: .seconds(5))
                        waitingStatus = .secondInterval
                        
                        try? await Task.sleep(for: .seconds(5))
                        waitingStatus = .thirdInterval
                    }
            } else {
                HStack(spacing: 5) {
                    ForEach(pressed, id: \.self) { key in
                        Text(key)
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
                }
            }
            
            HStack(spacing: 4) {
                Text("Hit")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
                keycap("esc")
                Text("twice to cancel")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(minWidth: 170, minHeight: 100)
        .animation(.smooth(duration: 0.12), value: pressed)
    }
    
    private var annoyedTextThing: some View {
        switch waitingStatus {
        case .firstInterval:
            Text("Listening...")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        case .secondInterval:
            Text("Any day now.")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        case .thirdInterval:
            Text("You there? I can wait.")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }
    
    private func modifiers(from f: NSEvent.ModifierFlags) -> (mods: UInt32, glyphs: [String]) {
        var mods: UInt32 = 0
        var glyphs: [String] = []
        if f.contains(.control) { mods |= UInt32(controlKey); glyphs.append("⌃") }
        if f.contains(.option)  { mods |= UInt32(optionKey);  glyphs.append("⌥") }
        if f.contains(.shift)   { mods |= UInt32(shiftKey);   glyphs.append("⇧") }
        if f.contains(.command) { mods |= UInt32(cmdKey);     glyphs.append("⌘") }
        return (mods, glyphs)
    }
    
    private func keyName(for e: NSEvent) -> String {
            switch Int(e.keyCode) {
            case kVK_Space:          return "Space"
            case kVK_Tab:            return "Tab"
            case kVK_Return:         return "Return"
            case kVK_ANSI_KeypadEnter: return "Enter"
            case kVK_Delete:         return "Delete"
            case kVK_ForwardDelete:  return "Fwd Delete"
            case kVK_Escape:         return "Esc"
            case kVK_LeftArrow:      return "←"
            case kVK_RightArrow:     return "→"
            case kVK_UpArrow:        return "↑"
            case kVK_DownArrow:      return "↓"
            case kVK_Home:           return "Home"
            case kVK_End:            return "End"
            case kVK_PageUp:         return "Page Up"
            case kVK_PageDown:       return "Page Down"
            case kVK_F1:  return "F1"
            case kVK_F2:  return "F2"
            case kVK_F3:  return "F3"
            case kVK_F4:  return "F4"
            case kVK_F5:  return "F5"
            case kVK_F6:  return "F6"
            case kVK_F7:  return "F7"
            case kVK_F8:  return "F8"
            case kVK_F9:  return "F9"
            case kVK_F10: return "F10"
            case kVK_F11: return "F11"
            case kVK_F12: return "F12"
            default:
                let chars = (e.charactersIgnoringModifiers ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                return chars.isEmpty ? "Key \(e.keyCode)" : chars.uppercased()
            }
        }
        
        private func start() {
            message = nil
            pressed = []
            recording = true
            
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { e in
                let (mods, glyphs) = modifiers(from: e.modifierFlags)
                
                if e.type == .flagsChanged {
                    if escapeWork == nil { pressed = glyphs }
                    return e
                }
                
                let isEscape = e.keyCode == UInt16(kVK_Escape)
                
                // Bare Esc: second tap within the window cancels, otherwise it's committed as the bind
                if isEscape && mods == 0 {
                    if let work = escapeWork {
                        work.cancel()
                        escapeWork = nil
                        cancel()
                        return nil
                    }
                    pressed = ["Esc"]
                    let keyCode = UInt32(e.keyCode)
                    let work = DispatchWorkItem {
                        escapeWork = nil
                        commit(keyCode: keyCode, mods: 0, display: "Esc")
                    }
                    escapeWork = work
                    DispatchQueue.main.asyncAfter(deadline: .now() + doubleTapWindow, execute: work)
                    return nil
                }
                
                // Everything else needs a modifier
                guard mods != 0 else { NSSound.beep(); return nil }
                
                let key = keyName(for: e)
                pressed = glyphs + [key]
                commit(keyCode: UInt32(e.keyCode), mods: mods, display: glyphs.joined() + key)
                return nil
            }
        }
        
        private func commit(keyCode: UInt32, mods: UInt32, display: String) {
            let bind = Keybind(keyCode: keyCode, modifiers: mods, display: display)
            switch store.set(bind, for: action) {
            case .success: message = nil
            case .failure(.conflict): message = "Already used in ray"
            case .failure(.unavailable): message = "Unavailable"
            }
            
            removeMonitor()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.375) { recording = false }
        }
        
        private func removeMonitor() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        private func cancel() {
            escapeWork?.cancel()
            escapeWork = nil
            removeMonitor()
            recording = false
            pressed = []
        }
        
        private func keycap(_ s: String) -> some View {
            Text(s)
                .font(.system(size: 10.5, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
    }

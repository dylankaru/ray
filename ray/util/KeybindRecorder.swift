//
//  KeybindRecorder.swift
//  ray
//
//  Created by Dylan Karunanayake on 22/10/2026.
//

import SwiftUI
import Carbon
internal import Combine

struct KeybindRecorder: View {
    let action: KeybindAction
    @ObservedObject private var store = KeybindStore.shared
    
    @State private var recording: Bool = false
    @State private var monitor: Any?
    @State private var message: String?
    @State private var pressed: [String] = []
    
    var body: some View {
        HStack {
            Button {
                recording ? cancel() : start()
            } label: {
                HStack(alignment: .center) {
                    Text(store.bind(for: action)?.display ?? "Ready to record")
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
//                        .padding(.trailing)
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
                Text("Enter your shortcut")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 5) {
                    ForEach(pressed, id: \.self) { key in
                        Text(key)
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
                }
            }
            
//            Its too long and looks yucky
//            Text("A modifier key must be entered before other keys")
//                .font(.system(size: 11, design: .monospaced))
            
            HStack(spacing: 4) {
                keycap("esc")
                Text("to cancel")
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
    
    private func modifiers(from f: NSEvent.ModifierFlags) -> (mods: UInt32, glyphs: [String]) {
        var mods: UInt32 = 0
        var glyphs: [String] = []
        if f.contains(.control) { mods |= UInt32(controlKey); glyphs.append("⌃") }
        if f.contains(.option)  { mods |= UInt32(optionKey);  glyphs.append("⌥") }
        if f.contains(.shift)   { mods |= UInt32(shiftKey);   glyphs.append("⇧") }
        if f.contains(.command) { mods |= UInt32(cmdKey);     glyphs.append("⌘") }
        return (mods, glyphs)
    }
    
    private func start() {
        message = nil
        pressed = []
        recording = true
        
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { e in
            let (mods, glyphs) = modifiers(from: e.modifierFlags)
            
            if e.type == .flagsChanged {
                pressed = glyphs
                return e
            }
            
            if e.keyCode == UInt16(kVK_Escape) { cancel(); return nil }
            guard mods != 0 else { NSSound.beep(); return nil }
            
            let key = e.keyCode == UInt16(kVK_Space) ? "Space"
            : (e.charactersIgnoringModifiers ?? "?").uppercased()
            pressed = glyphs + [key]
            
            let bind = Keybind(keyCode: UInt32(e.keyCode), modifiers: mods,
                               display: glyphs.joined() + key)
            switch store.set(bind, for: action) {
            case .success: message = nil
            case .failure(.conflict): message = "Already used in ray"
            case .failure(.unavailable): message = "Unavailable"
            }
            
            removeMonitor()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.375) { recording = false }
            return nil
        }
    }
    
    private func removeMonitor() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private func cancel() {
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

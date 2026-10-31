//
//  HotkeySettingsView.swift
//  ray
//
//  Created by Dylan Karunanayake on 15/10/2026.
//

import SwiftUI
import UniformTypeIdentifiers

struct HotkeySettingsView: View {
    @ObservedObject private var store = KeybindStore.shared
    @State private var pendingPaths: [String] = []

    private static let utilities: [(name: String, path: String)] = [
        ("Activity Monitor", "/System/Applications/Utilities/Activity Monitor.app"),
        ("System Settings", "/System/Applications/System Settings.app"),
        ("Terminal", "/System/Applications/Utilities/Terminal.app"),
        ("Console", "/System/Applications/Utilities/Console.app"),
        ("Disk Utility", "/System/Applications/Utilities/Disk Utility.app"),
        ("Keychain Access", "/System/Applications/Utilities/Keychain Access.app"),
        ("Screenshot", "/System/Applications/Utilities/Screenshot.app"),
        ("Network Utility", "/System/Applications/Utilities/Network Utility.app"),
        ("Font Book", "/System/Applications/Font Book.app"),
        ("Calculator", "/System/Applications/Calculator.app"),
    ]

    private var appPaths: [String] {
        var seen = Set<String>()
        let bound: [String] = store.entries.compactMap {
            if case .openApp(let path) = $0.action { return path }
            return nil
        }
        return (bound + pendingPaths).filter { seen.insert($0).inserted }
    }
    
    @ViewBuilder
    private func BindableRow(_ name: String, icon: String, actionBind: KeybindAction) -> some View {
        HStack {
            SettingLabel(name, icon)
            Spacer()
            KeybindRecorder(action: actionBind)
        }
    }

    var body: some View {
        Form {
            Section("Global") {
                BindableRow("Open ray", icon: "ray", actionBind: .toggleRay)
                BindableRow("Open Ivy", icon: "ivy", actionBind: .toggleIvyWithinRayInstantly)
            }
            
            // the non-bindable has been DEPRECIATED like a little boi

            Section("App Shortcuts") {
                if appPaths.isEmpty {
                    Text("Assign a shortcut to open any app or utility instantly.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                ForEach(appPaths, id: \.self) { path in
                    HStack {
                        appLabel(path)
                        Spacer()
                        KeybindRecorder(action: .openApp(path: path))
                        Button {
                            removeApp(path)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .help("Remove shortcut")
                    }
                }

                Menu {
                    // Only list utilities that exist on our Mac yay
                    ForEach(
                        Self.utilities
                            .filter { FileManager.default.fileExists(atPath: $0.path) }
                            .filter { !appPaths.contains($0.path) }
                        , id: \.path)
                    { util in
                        Button {
                            addApp(util.path)
                        } label: {
                            Label {
                                Text(util.name)
                            } icon: {
                                Image(nsImage: NSWorkspace.shared.icon(forFile: util.path))
                            }
                        }
                    }
                    Divider()
                    Button("Another App…") { pickApp() }
                } label: {
                    Label("Add App Shortcut", systemImage: "plus")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }
        .formStyle(.grouped)
    }

    private func addApp(_ path: String) {
        if !appPaths.contains(path) { pendingPaths.append(path) }
    }

    private func removeApp(_ path: String) {
        store.remove(.openApp(path: path))
        pendingPaths.removeAll { $0 == path }
    }

    private func pickApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Add"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        addApp(url.path)
    }

    private func appLabel(_ path: String) -> some View {
        let exists = FileManager.default.fileExists(atPath: path)
        let name = FileManager.default.displayName(atPath: path)
            .replacingOccurrences(of: ".app", with: "")

        return HStack(spacing: 8) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                .resizable()
                .frame(width: 26, height: 26)
                .opacity(exists ? 1 : 0.4)
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                Text(exists ? (path as NSString).abbreviatingWithTildeInPath : "Missing")
                    .font(.system(size: 10))
                    .foregroundStyle(exists ? Color.secondary : Color.red)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    @ViewBuilder
    private func SettingLabel(_ text: String, _ imageName: String, subtext: String? = nil) -> some View {
        let size: CGFloat = 20

        let iconName: String = {
            if NSImage(named: imageName) != nil {
                return imageName
            } else if NSImage(systemSymbolName: imageName, accessibilityDescription: nil) != nil {
                return imageName
            } else {
                return "person.fill.questionmark"
            }
        }()

        let isCustomAsset = NSImage(named: imageName) != nil

        HStack {
            VStack {
                if isCustomAsset {
                    Image(iconName)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: size, height: size)
                } else {
                    Image(systemName: iconName)
                        .fontWeight(.black)
                        .font(.system(size: size - 2))
                }
            }
            .frame(width: size, height: size)
            .padding(6)
            .background(.gray, in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(text)

                if let subtexted = subtext, !subtexted.isEmpty {
                    Text(subtexted)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

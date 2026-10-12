//
//  SettingsView.swift
//  ray
//
//  Created by Dylan Karunanayake on 9/10/2026.
//

//
//  SettingsView.swift
//  ray
//

import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case general, hotkeys

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .hotkeys: return "Hotkeys"
        }
    }

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .hotkeys: return "keyboard"
        }
    }
}

struct SettingsView: View {
    @State private var tab: SettingsTab? = .general

    private var current: SettingsTab { tab ?? .general }

    var body: some View {
        NavigationSplitView {
            List(selection: $tab) {
                ForEach(SettingsTab.allCases) { t in
                    Label(t.title, systemImage: t.icon)
                        .tag(t)
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            detail
                .navigationTitle(current.title)
        }
        .toolbar(removing: .sidebarToggle)
        .frame(width: 650, height: 420)
    }

    @ViewBuilder
    private var detail: some View {
        switch current {
        case .general: GeneralSettings()
        case .hotkeys: HotkeySettings()
        }
    }
}

// MARK: - General

// These keys are the same ones ContentView reads, so moving a slider changes the dropdown timing straight away
struct GeneralSettings: View {
    @AppStorage("ray_typing_delay") private var typingDelay: Double = 0.8
    @AppStorage("ray_still_delay") private var stillDelay: Double = 3.0
    @AppStorage("ray_onboarded") private var onboarded: Bool = false

    var body: some View {
        Form {
            Section("Results dropdown") {
                delayRow("While typing", value: $typingDelay, range: 0.2...2.0)
                delayRow("Nothing typed", value: $stillDelay, range: 0.5...8.0)
            }

            Section {
                Button("Replay the welcome tour") {
                    onboarded = false
                }
                Button("Reset to defaults") {
                    typingDelay = 0.8
                    stillDelay = 3.0
                }
            }
        }
        .formStyle(.grouped)
    }

    private func delayRow(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        LabeledContent(title) {
            HStack(spacing: 10) {
                Slider(value: value, in: range, step: 0.1)
                    .frame(width: 170)
                Text(String(format: "%.1fs", value.wrappedValue))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 40, alignment: .trailing)
            }
        }
    }
}

// MARK: - Hotkeys

struct HotkeySettings: View {
    var body: some View {
        Form {
            Section("Global") {
                LabeledContent("Open Ray", value: "⌥ Space")
            }
            Section {
                Text("Rebinding isn't built yet. The hotkey is set in HotKey.swift.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

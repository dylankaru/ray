//
//  SettingsView.swift
//  ray
//
//  Created by Dylan Karunanayake on 9/10/2026.
//

import SwiftUI

// Necessary pages TODO: maybe add extensions or smth?
enum SettingsTab: String, CaseIterable, Identifiable {
    case general, search, hotkeys

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .search: return "Search"
        case .hotkeys: return "Hotkeys"
        }
    }

    // Preferred if not the fill icon, coz not all of them have a fill yk so then it looks a bit thick
    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .search: return "sparkle.magnifyingglass"
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
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            detail
                .navigationTitle(current.title)
        }
        .frame(width: 650, height: 420)
    }

    @ViewBuilder
    private var detail: some View {
        switch current {
        case .general: GeneralSettingsView()
        case .search: SearchSettingsView()
        case .hotkeys: HotkeySettingsView()
        }
    }
}

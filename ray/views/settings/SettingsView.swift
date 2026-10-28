//
//  SettingsView.swift
//  ray
//
//  Created by Dylan Karunanayake on 9/10/2026.
//

import SwiftUI

// Necessary pages TODO: maybe add extensions or smth?
enum SettingsTab: String, CaseIterable, Identifiable {
    case general, design, search, hotkeys, ivy, birthday

    var id: String { rawValue }

    var title: String { rawValue.capitalized }

    // Preferred if not the fill icon, coz not all of them have a fill yk so then it looks a bit thick
    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .design: return "paintbrush"
        case .search: return "sparkle.magnifyingglass"
        case .hotkeys: return "keyboard"
        case .ivy: return "ivy"
        case .birthday: return "birthday.cake"
        }
    }
    
    var usesCustomImage: Bool {
        switch self{
        case .ivy: return true
        default: return false
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
                    if t.usesCustomImage {
                        Label(t.title, image: t.icon)
                            .tag(t)
                    } else {
                        Label(t.title, systemImage: t.icon)
                            .tag(t)
                    }
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
        case .design: DesignSettingsView()
        case .search: SearchSettingsView()
        case .hotkeys: HotkeySettingsView()
        case .ivy: IvySettingsView()
        case .birthday :BirthdaySettingsView()
        }
    }
}

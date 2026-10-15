//
//  HotkeySettingsView.swift
//  ray
//
//  Created by Dylan Karunanayake on 15/10/2026.
//

import SwiftUI

struct HotkeySettingsView: View {
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

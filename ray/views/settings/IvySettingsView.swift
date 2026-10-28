//
//  IvySettingsView.swift
//  ray
//
//  Created by Dylan Karunanayake on 24/10/2026.
//

import SwiftUI

struct IvySettingsView: View {
    var body: some View {
        Form {
            Section() {
                
            } header: {
                Text("API Keys")
            } footer: {
                Text("API keys for model providers are stored on your Mac's keychain and are not stored in plaintext.")
            }
        }
        .formStyle(.grouped)
    }
}

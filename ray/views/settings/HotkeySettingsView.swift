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
                HStack {
                    SettingLabel("Open ray", "ray")
                    Spacer()
                    KeybindRecorder(action: .toggleRay)
                }
                
                HStack {
                    SettingLabel("", "")
                    Spacer()
                    KeybindRecorder(action: .openApp(path: ""))
                }
            }

//            Section {
//                Text("Rebinding isn't built yet. The hotkey is set in HotKey.swift.")
//                    .font(.footnote)
//                    .foregroundStyle(.secondary)
//            }
            // YOU HAVE BEEN DEPRECAITED little boi
        }
        .formStyle(.grouped)
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

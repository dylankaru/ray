//
//  DesignSettingsView.swift
//  ray
//
//  Created by Dylan Karunanayake on 24/10/2026.
//

import SwiftUI

struct DesignSettingsView: View {
    // Defaults
    @AppStorage("ray_custom_tint") private var customTint: RayThemes = .black
    @AppStorage("ray_tint_strength") private var tintStrength: Double = 0.4
    @AppStorage("ray_motion_style") private var motionStyle: MotionStyle = .standard

    var body: some View {
        Form {
            Section("Layout") {
                Picker("ray Tint", selection: $customTint) {
                    ForEach(RayThemes.allCases, id: \.self) { colour in
                        Text(colour.title.capitalized).tag(colour)
                    }
                }
                .rayTabs(forceMenu: true)
                
                slider("Tint Strength", value: $tintStrength, range: 0.1...customTint.maxStrength)
            }
            
            Section("Motion") {
                Picker("Animation Preset", selection: $motionStyle) {
                    ForEach(MotionStyle.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .rayTabs(forceMenu: true)

                if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                    Text("Reduce Motion is on in System Settings, so ray will use simple fades.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: customTint) { _, newTheme in
            tintStrength = min(max(tintStrength, 0.1), newTheme.maxStrength)
        }
    }
    
    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, unit: String = "") -> some View {
        LabeledContent(title) {
            HStack(spacing: 10) {
                Slider(value: value, in: range)
                    .frame(width: 170)
                Text(String(format: "%.1f\(unit)", value.wrappedValue))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 40, alignment: .trailing)
            }
        }
    }
}

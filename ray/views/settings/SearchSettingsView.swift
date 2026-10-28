//
//  SearchSettingsView.swift
//  ray
//
//  Created by Dylan Karunanayake on 15/10/2026.
//

import SwiftUI

struct SearchSettingsView: View {
    // Defaults
    @AppStorage("ray_typing_delay") private var typingDelay: Double = 0.8
    @AppStorage("ray_still_delay") private var stillDelay: Double = 3.0
    @AppStorage("ray_marker_theme") private var markerTheme: MarkerTheme = .highlighter
    @AppStorage("ray_marker_colour") private var markerColour: MarkerColour = .yellow
    @AppStorage("ray_marker_weight") private var markerWeight: MarkerBoldness = .prettybold
    @AppStorage("ray_marker_strength") private var markerStrength: Double = 0.8
    
    var body: some View {
        Form {
            Section() {
                Picker("Marker Style", selection: $markerTheme) {
                    ForEach(MarkerTheme.allCases, id: \.self) { theme in
                        Text(theme.title).tag(theme)
                    }
                }
                .rayTabs() // To get tabs -> 27, menu -> 26, and segmented/palette -> <26
                
                if markerTheme == .highlighter {
                    Picker("Marker Colour", selection: $markerColour) {
                        ForEach(MarkerColour.allCases, id: \.self) { colour in
                            Text(colour.title.capitalized).tag(colour)
                        }
                    }
                    .rayTabs() // wow
                    
                    slider("Strength of Highlight", value: $markerStrength, range: 0.4...0.9, unit: "")
                } else if markerTheme == .bold {
                    Picker("Marker Weight", selection: $markerWeight) {
                        ForEach(MarkerBoldness.allCases, id: \.self) { weight in
                            Text(weight.title.capitalized).tag(weight)
                        }
                    }
                    .rayTabs() // again, wow
                }
            } header: {
                Text("Search")
            } footer: {
                if markerTheme == .bold {
                    Text("The different numbers represent different thicknesses, they aren't linearly increasing; 1 is super thin, 2 is bold, 3 is heavy, and 4 is black (very very bold).")
                }
            }
            
            Section("Map") {
                slider("While typing", value: $typingDelay, range: 0.2...2.0, unit: "s")
                slider("Nothing typed", value: $stillDelay, range: 0.5...6.0, unit: "s")
                
                Button("Reset to defaults") {
                    typingDelay = 0.8
                    stillDelay = 3.0
                }
            }
        }
        .formStyle(.grouped)
    }
    
    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, unit: String = "") -> some View {
        LabeledContent(title) {
            HStack(spacing: 10) {
                Slider(value: value, in: range, step: 0.1)
                    .frame(width: 170)
                Text(String(format: "%.1f\(unit)", value.wrappedValue))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 40, alignment: .trailing)
            }
        }
    }
}

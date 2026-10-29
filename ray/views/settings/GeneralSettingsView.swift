//
//  GeneralSettings.swift
//  ray
//
//  Created by Dylan Karunanayake on 15/10/2026.
//

import SwiftUI
import ServiceManagement

struct GeneralSettingsView: View {
    // Defaults
    @AppStorage("ray_startup_launch") private var launchOnStartup: Bool = SMAppService.mainApp.status == .enabled
    @AppStorage("ray_onboarded") private var onboarded: Bool = false
    @AppStorage("ray_default_search_fallback") private var preferredSearchMethod: PreferredSearchState = .browser

    var body: some View {
        Form {
            Section("ray Specifics") {
                Toggle("Start ray on startup", isOn: $launchOnStartup)
                    .onChange(of: launchOnStartup) { _, new in
                        setLoadOnLaunch(new)
                    }
                
                VStack {
                    Picker("Preferred Search Method", selection: $preferredSearchMethod) {
                        ForEach(PreferredSearchState.allCases, id: \.self) { method in
                            Text(method.title).tag(method)
                        }
                    }
                    .rayTabs()
                    
                    Text("When ray doesn't know what you're looking for, ray will search it by sending it to \(preferredSearchMethod == .browser ? "your Mac's default browser" : "Ivy").")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 12))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            
            Section {
                Button("Replay the welcome tour") {
                    onboarded = false
                }
            }
        }
        .formStyle(.grouped)
    }
    
    private func setLoadOnLaunch(_ enabled: Bool) {
        let service = SMAppService.mainApp
        
        do {
            if enabled {
                try service.register()
                print("Successfully registered for system startup.")
            } else {
                try service.unregister()
                print("Successfully unregistered.")
            }
        } catch {
            print("Failed to update launch at login status: \(error.localizedDescription)")
        }
    }
}

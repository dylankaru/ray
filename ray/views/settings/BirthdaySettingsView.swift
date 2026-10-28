//
//  BirthdaySettingsView.swift
//  ray
//
//  Created by Dylan Karunanayake on 25/10/2026.
//

import SwiftUI

struct BirthdaySettingsView: View {
    @AppStorage("ray_birthdays_raydar_enabled") private var birthdaysEnabled: Bool = false
    
    private var manager: UtilityBarManager { .shared }

    @State private var name = ""
    @State private var date = Date()
    @State private var includeYear = false

    private var sorted: [BirthdayEntry] {
        manager.entries.sorted { $0.daysUntil < $1.daysUntil }
    }

    var body: some View {
        Form {
            Section("Brithdays") {
                Toggle("Enable Birthdays", isOn: $birthdaysEnabled)
                    .onChange(of: birthdaysEnabled) { _, new in
                        birthdaysEnabled = new
                    }
            }
            
            Section("Add a birthday") {
                TextField("Name", text: $name).textFieldStyle(.roundedBorder)
                DatePicker("Date", selection: $date, displayedComponents: .date)
                Toggle("Remember birth year (shows their age)", isOn: $includeYear)
                Button("Add") {
                    manager.addBirthday(name: name, date: date, includeYear: includeYear)
                    name = ""
                    includeYear = false
                }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .disabled(!birthdaysEnabled)
            .opacity(birthdaysEnabled ? 1 : 0.4)

            Section("Upcoming") {
                if sorted.isEmpty {
                    Text("No birthdays yet").foregroundStyle(.secondary)
                }
                ForEach(sorted) { entry in
                    LabeledContent {
                        HStack {
                            Text(whenText(entry)).foregroundStyle(.secondary)
                            Button {
                                manager.removeBirthday(entry)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                    } label: {
                        Text(entry.name)
                    }
                }
            }
            .disabled(!birthdaysEnabled)
            .opacity(birthdaysEnabled ? 1 : 0.4)
        }
        .formStyle(.grouped)
    }

    private func whenText(_ e: BirthdayEntry) -> String {
        switch e.daysUntil {
        case 0: return "Today 🎉"
        case 1: return "Tomorrow"
        default: return "In \(e.daysUntil) days"
        }
    }
}

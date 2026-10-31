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
    @State private var month = Calendar.current.component(.month, from: Date())
    @State private var day = Calendar.current.component(.day, from: Date())
    @State private var year: Int? = nil // coz it's optional
    
    private var sorted: [BirthdayEntry] {
        manager.entries.sorted { $0.daysUntil < $1.daysUntil }
    }
    
    var body: some View {
        Form {
            Section("Birthdays") {
                Toggle("Enable Birthdays", isOn: $birthdaysEnabled)
            }
            
            Section("Add a New Birthday") {
                TextField("Name", text: $name)
                    .textFieldStyle(.roundedBorder)
                
                LabeledContent("Date") {
                    RayDatePicker(month: $month, day: $day, year: $year)
                }
                
                Button("Add") { addBirthday() }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .disabled(!birthdaysEnabled)
            .opacity(birthdaysEnabled ? 1 : 0.4)
            
            Section("Upcoming Birthdays") {
                if sorted.isEmpty {
                    Text("No birthdays yet 🙁").foregroundStyle(.secondary)
                    
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
            }
            .disabled(!birthdaysEnabled)
            .opacity(birthdaysEnabled ? 1 : 0.4)
        }
        .formStyle(.grouped)
    }
    
    private func addBirthday() {
        let comps = DateComponents(year: year ?? 2000, month: month, day: day)
        guard let date = Calendar.current.date(from: comps) else { return }
        
        manager.addBirthday(name: name.trimmingCharacters(in: .whitespaces), date: date, includeYear: true)
        name = ""
        year = nil
    }
    
    private func whenText(_ e: BirthdayEntry) -> String {
        switch e.daysUntil {
        case 0: return "Today 🎉"
        case 1: return "Tomorrow"
        default: return "In \(e.daysUntil) days"
        }
    }
}

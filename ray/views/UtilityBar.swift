//
//  UtilityBar.swift
//  ray
//
//  Created by Dylan Karunanayake on 25/10/2026.
//

// Im planning on changing how the utility bar works, instead of having a variable to check if it should be visible ill just make a manager that checks to see if there should be something to show and if so js so that so no need for the extra boolean check anymore

import SwiftUI
import Observation

enum UtilityBarStates: String, CaseIterable {
    case update
    case birthday

    var title: String { rawValue.capitalized }
}

struct BirthdayEntry: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var month: Int
    var day: Int
    var year: Int?

    // Days until the next celebration of the day of the birth
    var daysUntil: Int {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        var comps = DateComponents(month: month, day: day)
        comps.year = cal.component(.year, from: today)
        guard var next = cal.date(from: comps) else { return 999 }
        if next < today {
            comps.year = (comps.year ?? 0) + 1
            next = cal.date(from: comps) ?? next
        }
        return cal.dateComponents([.day], from: today, to: next).day ?? 999
    }

    // The age they're turning, if a birth year was saved
    var turningAge: Int? {
        guard let year else { return nil }
        let thisYear = Calendar.current.component(.year, from: .now)
        return thisYear - year
    }
}

@Observable @MainActor
final class UtilityBarManager {
    static let shared = UtilityBarManager()
    
    private let utilityBarKey = "ray_show_utility_bar"
    
    struct Update {
        let version: String
        let url: URL?
        let isForced: Bool
    }
    
    private struct CachedUpdate: Codable {
        let version: String
        let url: URL?
        let isForced: Bool
    }
    
    private(set) var update: Update?
    private(set) var entries: [BirthdayEntry] = []
    
    var todaysBirthdays: [BirthdayEntry] { entries.filter { $0.daysUntil == 0 } }
    
    // Not sure if forced updates should be a thing tbh, but if they do exist they defo should supercede birthdays
    // in render priority, still need to think about that tho
    var state: UtilityBarStates? {
        //        if update?.isForced == true { return .update } :/
        if !todaysBirthdays.isEmpty { return .birthday }
        if update != nil { return .update }
        return nil
    }
    
    var isVisible: Bool { state != nil }

    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private let cacheKey = "ray_cached_update"
    @ObservationIgnored private let birthdayKey = "ray_birthdays"

    private init() {
        if let data = UserDefaults.standard.data(forKey: cacheKey),
           let cached = try? JSONDecoder().decode(CachedUpdate.self, from: data),
           Self.isNewer(cached.version, than: AppVersionManager.currentVersion) {
            update = Update(version: cached.version, url: cached.url, isForced: cached.isForced)
        }
        if let data = UserDefaults.standard.data(forKey: birthdayKey),
           let saved = try? JSONDecoder().decode([BirthdayEntry].self, from: data) {
            entries = saved
        }
    }

    func start() {
        guard task == nil else { return }
        task = Task {
            while !Task.isCancelled {
                await checkForUpdate()
                try? await Task.sleep(for: .seconds(6 * 60 * 60))
            }
        }
    }

    func checkForUpdate() async {
        #if DEBUG // THIS IS JUST FOR TESTING, its lwk annyoing coz its always there but i might comment it out soon so :)
        update = Update(version: "9.9.9", url: UpdateConfig.githubRepoLink, isForced: true)
        // i commented it out
        #else
        if case let .updateAvailable(version, url, isForced) = await AppUpdateChecker.shared.checkAppUpdate() {
            update = Update(version: version, url: url, isForced: isForced)
        } else {
            update = nil
        }
        saveCache()
        #endif
    }

    func addBirthday(name: String, date: Date, includeYear: Bool) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        guard let month = c.month, let day = c.day else { return }
        entries.append(BirthdayEntry(name: trimmed, month: month, day: day, year: includeYear ? c.year : nil))
        saveBirthdays()
    }

    func removeBirthday(_ entry: BirthdayEntry) {
        entries.removeAll { $0.id == entry.id }
        saveBirthdays()
    }

    private func saveBirthdays() {
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: birthdayKey)
        }
    }

    private func saveCache() {
        if let update,
           let data = try? JSONEncoder().encode(CachedUpdate(version: update.version, url: update.url, isForced: update.isForced)) {
            UserDefaults.standard.set(data, forKey: cacheKey)
        } else {
            UserDefaults.standard.removeObject(forKey: cacheKey)
        }
    }

    private static func isNewer(_ candidate: String, than current: String) -> Bool {
        candidate.compare(current, options: .numeric) == .orderedDescending
    }
}

struct UtilityBarContent: View {
    let state: UtilityBarStates

    var body: some View {
        switch state {
        case .update:   UpdateBarContent()
        case .birthday: BirthdayBarContent()
        }
    }
}

// TODO: make it so that birthday notifications can be dismissed so that they aren't always there..
// coz that would be a bit annoying
// also considering if birthdays should automatically store birthyear but then what if they dont know..
// then they'd just be a bad friend, that cannot be on me
private struct BirthdayBarContent: View {
    var body: some View {
        let today = UtilityBarManager.shared.todaysBirthdays
        if let first = today.first {
            HStack(spacing: 10) {
                Text("🎂").font(.system(size: 28))
                VStack(alignment: .leading, spacing: 2) {
                    Text(today.count == 1 ? "It's \(first.name.capitalized)'s birthday!" : "\(today.count) birthdays today!")
                        .font(.system(size: 13, weight: .medium))
                    if today.count == 1, let age = first.turningAge {
                        Text("They're turning \(age) today, be sure to show them love.")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    } else if today.count > 1 {
                        Text(today.map(\.name).joined(separator: ", "))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
    }
}

private struct UpdateBarContent: View {
    var body: some View {
        if let update = UtilityBarManager.shared.update {
            HStack {
                Image("git.diff")
                    .renderingMode(.template)
                    .font(.system(size: 28, weight: .heavy))
                    .opacity(0.9)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 0) {
                        Text("A new version of ray is ")
                        Link(destination: URL(string: "https://github.com/dylankaru/ray/releases/latest")!) {
                            FlowingGradientText(text: "available")
                        }
                        .pointerStyle(.link)
                        Text(".")
                    }
                    .font(.system(size: 13, weight: .medium))

                    HStack(spacing: 2) {
                        Text("Update v\(AppVersionManager.currentVersion)").italic()
                        Image(systemName: "arrow.right").font(.system(size: 10, weight: .bold))
                        Text("v\(update.version)").italic()
                    }
                    .foregroundStyle(.secondary)
                    .font(.system(size: 10, weight: .regular))
                }
            }
        }
    }
}

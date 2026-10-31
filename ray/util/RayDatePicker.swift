//
//  RayDatePicker.swift
//  ray
//
//  Created by Dylan Karunanayake on 30/10/2026.
//

import SwiftUI

struct RayDatePicker: View {
    @Binding var month: Int
    @Binding var day: Int
    @Binding var year: Int?
    
    @State private var showingPopover = false
    
    private static let arbitraryYear = 2000
    
    private var date: Date {
        Calendar.current.date(from: DateComponents(year: year ?? Self.arbitraryYear, month: month, day: day)) ?? Date()
    }
    
    private var title: String {
        let f = DateFormatter()
        f.locale = .current
        f.setLocalizedDateFormatFromTemplate(year == nil ? "dMMM" : "dMMMyyyy")
        return f.string(from: date)
    }
    
    var body: some View {
        HStack(spacing: 6) {
            Button {
                showingPopover = true
            } label : {
                Text(title)
                    .monospacedDigit()
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 5).fill(.quaternary))
            }
            .buttonStyle(.plain)
            
            Stepper("", onIncrement: { shiftDay(1) }, onDecrement: { shiftDay(-1) })
                .labelsHidden()
        }
        .popover(isPresented: $showingPopover, arrowEdge: .bottom) {
            BirthdayCalendarPopover(month: $month, day: $day, year: $year)
        }
    }
    
    private func shiftDay(_ delta: Int) {
        let cal = Calendar.current
        guard let new = cal.date(byAdding: .day, value: delta, to: date) else { return }
        month = cal.component(.month, from: new)
        day = cal.component(.day, from: new)
        if year != nil { year = cal.component(.year, from: new) }
    }
}

private struct BirthdayCalendarPopover: View {
    @Binding var month: Int
    @Binding var day: Int
    @Binding var year: Int?

    @State private var displayMonth: Int
    @State private var displayYear: Int

    private let cal = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

    init(month: Binding<Int>, day: Binding<Int>, year: Binding<Int?>) {
        _month = month
        _day = day
        _year = year
        _displayMonth = State(initialValue: month.wrappedValue)
        _displayYear = State(initialValue: year.wrappedValue ?? 2000)
    }

    private var firstOfMonth: Date {
        cal.date(from: DateComponents(year: displayYear, month: displayMonth, day: 1)) ?? Date()
    }

    private var headerTitle: String {
        let f = DateFormatter()
        f.locale = .current
        f.setLocalizedDateFormatFromTemplate(year == nil ? "LLLL" : "LLLL yyyy")
        return f.string(from: firstOfMonth)
    }

    private var weekdaySymbols: [String] {
        let symbols = cal.shortWeekdaySymbols
        let start = cal.firstWeekday - 1
        return (Array(symbols[start...]) + Array(symbols[..<start])).map { String($0.prefix(2)) }
    }

    private var cells: [Date] {
        let weekday = cal.component(.weekday, from: firstOfMonth)
        let offset = (weekday - cal.firstWeekday + 7) % 7
        guard let start = cal.date(byAdding: .day, value: -offset, to: firstOfMonth) else { return [] }
        return (0..<42).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
    }

    private func isSelected(_ d: Date) -> Bool {
        let c = cal.dateComponents([.year, .month, .day], from: d)
        guard c.month == month, c.day == day else { return false }
        return year == nil || c.year == year
    }

    private func isInDisplayedMonth(_ d: Date) -> Bool {
        cal.component(.month, from: d) == displayMonth
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text(headerTitle)
                    .font(.title3.bold())
                Spacer()
                Button { changeMonth(-1) } label: { Image(systemName: "chevron.left") }
                Button { goToToday() } label: { Image(systemName: "circle.fill").font(.system(size: 7)) }
                Button { changeMonth(1) } label: { Image(systemName: "chevron.right") }
            }
            .buttonStyle(.plain)

            VStack(spacing: 4) {
                LazyVGrid(columns: columns, spacing: 0) {
                    ForEach(weekdaySymbols, id: \.self) { s in
                        Text(s)
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(height: 24)
                    }
                }
                Divider()
                LazyVGrid(columns: columns, spacing: 2) {
                    ForEach(cells, id: \.self) { d in
                        dayCell(d)
                    }
                }
            }

            Divider()

            HStack {
                Toggle("Include year", isOn: includeYearBinding)
                    .toggleStyle(.checkbox)
                Spacer()
                if year != nil {
                    Stepper(value: yearBinding, in: 1900...cal.component(.year, from: Date())) {
                        Text(String(displayYear)).monospacedDigit()
                    }
                }
            }
        }
        .padding(14)
        .frame(width: 270)
    }

    private func dayCell(_ d: Date) -> some View {
        let n = cal.component(.day, from: d)
        let inMonth = isInDisplayedMonth(d)
        let selected = isSelected(d)

        return Button {
            select(d)
        } label: {
            Text("\(n)")
                .font(.system(size: 14))
                .foregroundStyle(selected ? Color.white : (inMonth ? Color.primary : Color.secondary.opacity(0.5)))
                .frame(maxWidth: .infinity)
                .frame(height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(selected ? Color.accentColor : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func select(_ d: Date) {
        let c = cal.dateComponents([.year, .month, .day], from: d)
        month = c.month ?? month
        day = c.day ?? day
        displayMonth = month
        if year != nil {
            year = c.year
            displayYear = c.year ?? displayYear
        }
    }

    private func changeMonth(_ delta: Int) {
        var m = displayMonth + delta
        if m < 1 {
            m = 12
            if year != nil { displayYear -= 1 }
        } else if m > 12 {
            m = 1
            if year != nil { displayYear += 1 }
        }
        displayMonth = m
    }

    private func goToToday() {
        let today = Date()
        displayMonth = cal.component(.month, from: today)
        if year != nil { displayYear = cal.component(.year, from: today) }
    }

    private func clampDay() {
        let ref = cal.date(from: DateComponents(year: year ?? 2000, month: month, day: 1)) ?? Date()
        let count = cal.range(of: .day, in: .month, for: ref)?.count ?? 31
        if day > count { day = count }
    }

    private var includeYearBinding: Binding<Bool> {
        Binding(
            get: { year != nil },
            set: { on in
                displayYear = 2000
                year = on ? displayYear : nil
                clampDay()
            }
        )
    }

    private var yearBinding: Binding<Int> {
        Binding(
            get: { displayYear },
            set: { new in
                displayYear = new
                year = new
                clampDay()
            }
        )
    }
}


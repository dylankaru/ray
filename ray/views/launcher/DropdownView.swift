//
//  DropdownView.swift
//  ray
//
//  Created by Dylan Karunanayake on 1/11/2026.
//

import SwiftUI

// The map is a header plus either a section to house and organise greater controls for ray
struct DropdownView: View {
    @EnvironmentObject private var model: LauncherModel
    let glassNS: Namespace.ID

    var body: some View {
        VStack(spacing: 0) {
            if model.doOnboarding {
                OnboardingView()
            } else {
                DropdownHeader()
                if model.resultsAreEmoji { EmojiGrid() } else { ResultList() }
            }
        }
        .frame(width: Metrics.dropdownWidth)
        .glassCard(radius: Metrics.dropdownRadius)
        .rayGlassEffectID("dropdown", in: glassNS)
    }
}

private struct DropdownHeader: View {
    @EnvironmentObject private var model: LauncherModel

    private var title: String {
        if model.showingClipboardHistory { return "Clipboard History" }
        if model.showingEmoji { return model.query.isEmpty ? "Emoji" : "\(model.results.count) results" }
        return model.query.isEmpty ? "Suggestions" : "\(model.results.count) results"
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(.secondary)
            if !model.query.isEmpty {
                Text("“\(model.query)”")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            Spacer()
            Keycap(model.showingEmoji ? "↑↓←→" : "↑↓")
        }
        .padding(.horizontal, 22)
        .padding(.top, 14)
        .padding(.bottom, 8)
    }
}

private struct ResultList: View {
    @EnvironmentObject private var model: LauncherModel
    @Namespace private var ns // for the selection highlight sliding between rows

    var body: some View {
        VStack(spacing: 1) {
            if model.results.isEmpty {
                Text(model.showingClipboardHistory ? "Nothing copied yet" : "No results")
                    .font(.system(size: 13))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .frame(height: Metrics.rowHeight)
            }
            ForEach(Array(model.results.enumerated()), id: \.element.id) { i, item in
                ResultRow(item: item, index: i, ns: ns)
                    .opacity(model.rowsRevealed ? 1 : 0)
                    .offset(y: (model.rowsRevealed || model.reduceMotion) ? 0 : -8)
                    .animation(model.motion(.row)?.delay(model.rowDelay(i)), value: model.rowsRevealed)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) { swipeButton(.trailing, item: item, index: i) }
                    .swipeActions(edge: .leading, allowsFullSwipe: true) { swipeButton(.leading, item: item, index: i) }
            }
        }
        .padding(.horizontal, Metrics.dropdownInset)
        .padding(.bottom, Metrics.dropdownInset)
        .animation(model.motion(.selection), value: model.selection)
        .clipped()
    }

    @ViewBuilder
    private func swipeButton(_ side: Side, item: Item, index i: Int) -> some View {
        if let a = model.sideAction(side, for: item, at: i) {
            Button { a.run() } label: {
                Label(a.title, systemImage: a.icon)
            }
            .tint(side == .leading ? .orange : .blue)
        }
    }
}

private struct ResultRow: View {
    @EnvironmentObject private var model: LauncherModel
    let item: Item
    let index: Int
    let ns: Namespace.ID

    private var selected: Bool { index == model.selection }

    var body: some View {
        HStack(spacing: 12) {
            icon

            VStack(alignment: .leading, spacing: 1) {
                HighlightedText(title: item.title, query: model.highlightQuery)
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(1)
                subtitle
            }

            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, 12)
        .frame(height: Metrics.rowHeight)
        .background { background }
        .contentShape(Rectangle())
        .onTapGesture { model.selection = index; model.run() }
        .onHover { hovering in model.hover(hovering, index: index) }
    }

    @ViewBuilder
    private var icon: some View {
        if let path = item.iconPath {
            Image(nsImage: IconCache.icon(for: path))
                .resizable()
                .interpolation(.high)
                .frame(width: 28, height: 28)
        } else {
            Image(systemName: item.icon)
                .font(.system(size: 15, weight: .light))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
        }
    }

    // Apps show their path, files show the folder they're in
    @ViewBuilder
    private var subtitle: some View {
        if let sub = item.subtitle {
            Text(sub)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    @ViewBuilder
    private var trailing: some View {
        if selected {
            HStack(spacing: 4) {
                if let a = model.sideAction(.leading, for: item, at: index) { SideHint(arrow: "←", action: a) }
                if let a = model.sideAction(.trailing, for: item, at: index) { SideHint(arrow: "→", action: a) }
                Keycap("↵")
            }
        } else {
            Text("⌘\(index + 1)")
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(.quaternary)
        }
    }

    @ViewBuilder
    private var background: some View {
        if selected {
            RoundedRectangle(cornerRadius: Metrics.dropdownRadius - Metrics.dropdownInset, style: .continuous)
                .fill(model.selectionTint)
                .matchedGeometryEffect(id: "selected", in: ns)
        }
    }
}

private struct EmojiGrid: View {
    @EnvironmentObject private var model: LauncherModel

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: Metrics.emojiColumns), spacing: 2) {
                    ForEach(Array(model.results.enumerated()), id: \.element.id) { i, item in
                        Text(item.emoji ?? "")
                            .font(.system(size: 24))
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                            .background {
                                if i == model.selection {
                                    RoundedRectangle(cornerRadius: Metrics.dropdownRadius - Metrics.dropdownInset, style: .continuous)
                                        .fill(model.selectionTint)
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { model.selection = i; model.run() }
                            .onHover { hovering in
                                if hovering { model.scrollToSelection = false }
                                model.hover(hovering, index: i)
                            }
                            .id(item.id)
                    }
                }
                .id(model.trimmedQuery)
                .padding(.horizontal, Metrics.dropdownInset)
                .padding(.vertical, Metrics.dropdownInset)
            }
            .frame(height: 6 * 42)
            .onChange(of: model.selection) { _, new in
                guard model.scrollToSelection, model.results.indices.contains(new) else { return }
                proxy.scrollTo(model.results[new].id)
            }
        }
        .padding(.bottom, Metrics.dropdownInset)
    }
}

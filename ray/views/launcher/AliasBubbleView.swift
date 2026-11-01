//
//  AliasBubble.swift
//  ray
//
//  Created by Dylan Karunanayake on 1/11/2026.
//

import SwiftUI

/// Positions the bubble so its arrow touches the trailing edge of the row, or of the launchpad when the map is closed
struct AliasBubbleOverlay: View {
    @EnvironmentObject private var model: LauncherModel
    let glassNS: Namespace.ID

    var body: some View {
        if model.aliasTarget != nil {
            let barHeight: CGFloat = model.showUtilityBar ? Metrics.utilityBarSize.height + Metrics.stageSpacing : 0
            let edgeWidth: CGFloat = (model.aliasRow != nil) ? Metrics.dropdownWidth : model.launcherSize.width
            let x = (Metrics.stageWidth + edgeWidth) / 2 + 4

            let y: CGFloat = {
                if let i = model.aliasRow {
                    return barHeight + model.launcherSize.height + Metrics.stageSpacing + Metrics.dropdownHeaderHeight
                        + CGFloat(i) * (Metrics.rowHeight + 1) + Metrics.rowHeight / 2
                }
                return barHeight + model.launcherSize.height / 2
            }()

            AliasBubble(glassNS: glassNS)
                .fixedSize(horizontal: false, vertical: true) // natural height
                .frame(height: 0, alignment: .center)         // a zero-height line, the bubble overflows it equally up and down
                .padding(.leading, x)
                .padding(.top, y)
        }
    }
}

private struct AliasBubble: View {
    @EnvironmentObject private var model: LauncherModel
    @FocusState private var aliasFocused: Bool
    let glassNS: Namespace.ID

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Alias for \(model.aliasTarget?.title ?? "")")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            TextField("e.g. ppt", text: $model.aliasDraft)
                .textFieldStyle(.plain)
                .font(.system(size: 13.5))
                .focused($aliasFocused)
                .onSubmit { model.saveAlias() }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.white.opacity(0.10)))

            if !model.aliasList.isEmpty {
                HStack(spacing: 4) {
                    ForEach(model.aliasList, id: \.self) { alias in
                        Button { model.removeAlias(alias) } label: {
                            HStack(spacing: 3) {
                                Text(alias)
                                Image(systemName: "xmark").font(.system(size: 7, weight: .bold))
                            }
                            .font(.system(size: 10.5, weight: .medium, design: .rounded))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.white.opacity(0.09), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .help("Remove alias")
                        .transition(.scale(scale: 0.7).combined(with: .opacity))
                    }
                }
            }

            HStack(spacing: 10) {
                HStack(spacing: 4) { Keycap("↵"); Text("Save") }
                HStack(spacing: 4) { Keycap("esc"); Text("Cancel") }
            }
            .font(.system(size: 10.5))
            .foregroundStyle(.tertiary)
        }
        .opacity(model.aliasContentIn ? 1 : 0) // only the contents fade, the glass morphs on its own
        .padding(.leading, 14 + 12)            // + the tail width
        .padding(.trailing, 14)
        .padding(.vertical, 12)
        .frame(width: 192, alignment: .leading)
        .rayGlassEffect(Color.black.opacity(0.22), in: BubbleShape())
        .rayGlassEffectID("aliasBubble", in: glassNS)
        .rayGlassEffectTransition(1) // matchedGeometry
        .overlay(BubbleShape().stroke(Color.white.opacity(0.14), lineWidth: 0.8))
        .shadow(color: .black.opacity(0.3), radius: 12, y: 5)
        .onAppear { DispatchQueue.main.async { aliasFocused = true } }
    }
}

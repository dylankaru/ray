//
//  LauncherView.swift
//  ray
//
//  Created by Dylan Karunanayake on 1/11/2026.
//

import SwiftUI

// The launchpad: the squircle with the icon/title, the input and the chip. Becomes the note editor or the camera.
struct LauncherView: View {
    @EnvironmentObject private var model: LauncherModel
    var focused: FocusState<Bool>.Binding
    let glassNS: Namespace.ID

    var body: some View {
        let dims = model.tileDimensions
        let size = model.launcherSize

        tile
            .frame(width: dims.width, height: dims.height)
            .overlay { cameraOverlay(dims) }
            .background(TileBackground())
            .padding(Metrics.launcherPadding)
            .frame(width: size.width, height: size.height)
            .glassCard(radius: Metrics.launcherRadius)
            .rayGlassEffectID("launcher", in: glassNS)
    }

    // The clipboard isn't a branch here on purpose, swapping the tile out would remove the hidden text field
    // and the arrows and esc would stop reaching their handlers, so FindTile shows the clipboard state instead
    @ViewBuilder
    private var tile: some View {
        if model.isNote {
            NoteTile(focused: focused)
        } else {
            FindTile(focused: focused)
        }
    }

    @ViewBuilder
    private func cameraOverlay(_ dims: CGSize) -> some View {
        if model.showingCamera {
            CameraTile()
                .frame(width: Metrics.cameraTileSize.width, height: Metrics.cameraTileSize.height) // always laid out at full size
                .frame(width: dims.width, height: dims.height) // the animated window onto it
                .clipShape(RoundedRectangle(cornerRadius: Metrics.tileRadius, style: .continuous))
                .transition(.opacity)
        }
    }
}

private struct TileBackground: View {
    @EnvironmentObject private var model: LauncherModel

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Metrics.tileRadius, style: .continuous)
        ZStack {
            shape.fill(model.selectionTint)
            shape.strokeBorder(Color.accentColor.opacity(0.45), lineWidth: 0.6)
        }
    }
}

private struct FindTile: View {
    @EnvironmentObject private var model: LauncherModel
    var focused: FocusState<Bool>.Binding

    var body: some View {
        VStack(spacing: 12) {
            if model.doOnboarding, let emoji = model.currentOnboardingStep.emoji {
                OnboardingEmojiView(emoji: emoji, animation: model.currentOnboardingStep.animation)
            } else if model.showingClipboardHistory {
                Image(systemName: "list.bullet.clipboard")
                    .font(.system(size: 46, weight: .light))
                    .foregroundStyle(.primary)
                    .frame(height: 84)
                Text("Clipboard History")
                    .font(.system(size: 16, weight: .medium))
            } else {
                paneIcon
                paneTitle
            }
        }
        .padding(.horizontal, 16)
        .frame(width: Metrics.tileSize, height: Metrics.tileSize, alignment: .center)
        .overlay(alignment: .bottom) { bottom }
    }

    @ViewBuilder
    private var paneIcon: some View {
        if model.mode == .calc { // the launchpad shows the answer instead
            Text(model.calcResult ?? "0")
                .font(.system(size: 46, weight: .ultraLight, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(model.calcResult == nil ? Color.secondary.opacity(0.5) : Color.primary)
                .contentTransition(.numericText())
                .animation(model.motion(.quick), value: model.calcResult)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .frame(height: 84)
        } else if let item = model.paneItem {
            bigIcon(item)
        } else {
            Image("ray")
                .font(.system(size: 46))
                .foregroundStyle(.background)
                .frame(height: 84)
        }
    }

    @ViewBuilder
    private func bigIcon(_ item: Item) -> some View {
        if let e = item.emoji {
            Text(e)
                .font(.system(size: 64))
                .frame(height: 84)
        } else if let path = item.iconPath {
            Image(nsImage: IconCache.icon(for: path))
                .resizable()
                .interpolation(.high)
                .frame(width: 80, height: 80)
                .frame(height: 84)
        } else {
            Image(systemName: item.icon)
                .font(.system(size: 46, weight: .light))
                .foregroundStyle(.primary)
                .frame(height: 84)
        }
    }

    @ViewBuilder
    private var paneTitle: some View {
        if model.mode == .calc {
            Text("Result")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
        } else if let item = model.paneItem {
            HighlightedText(title: item.title, query: model.highlightQuery)
                .font(.system(size: 16, weight: .medium))
                .lineLimit(2)
                .multilineTextAlignment(.center)
        } else {
            Text(model.query.isEmpty ? "Type to search" : (model.filesPending ? " " : "No matches"))
                .font(.system(size: 14))
                .foregroundStyle(.tertiary)
        }
    }

    private var bottom: some View {
        let typing = (model.mode != .find)
        return VStack(spacing: typing ? 8 : 0) {
            inputField
            if !typing && !model.doOnboarding {
                actionChip
            }
        }
        .padding(.bottom, 14)
    }

    // Part of the aesthetic of ray is that it isn't visible so we take up less space
    private var inputField: some View {
        let visible = (model.mode != .find)
        return TextField(model.mode.prompt, text: $model.query)
            .textFieldStyle(.plain)
            .font(.system(size: 13.5))
            .multilineTextAlignment(.center)
            .focused(focused)
            .onSubmit { model.run() }
            .padding(.horizontal, visible ? 12 : 0)
            .frame(width: visible ? Metrics.tileSize - 48 : 1, height: visible ? 30 : 1)
            .background { if visible { Capsule().fill(Color.white.opacity(0.08)) } }
            .opacity(visible ? 1 : 0.01)
            .allowsHitTesting(visible)
    }

    @ViewBuilder
    private var actionChip: some View {
        if let action = model.currentAction {
            HStack(spacing: 6) {
                Image(systemName: action.icon)
                    .font(.system(size: 11, weight: .medium))
                Text(action.title)
                    .font(.system(size: 12, weight: .medium))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color.white.opacity(0.10)))
            .contentShape(Capsule())
            .onTapGesture { model.cycleAction(1); focused.wrappedValue = true }
        }
    }
}

private struct NoteTile: View {
    @EnvironmentObject private var model: LauncherModel
    var focused: FocusState<Bool>.Binding

    @State private var placeholder = NoteTile.placeholders.randomElement() ?? "Write a note"

    private static let placeholders: [String] = [
        "Write a note",
        "Ready when you are",
        "What's your next million dollar business idea?",
        "How are you blessing your notes today?",
        "Moles of hydrogen is two times moles of water",
        "Fun fact: a broken themometer is right twice a day",
        "I'm the brightest tool in the shed",
        "Type away",
        "He loves using Claude to generate questions for Gemini",
        "Pro Tip: Get Claude Pro",
    ]

    var body: some View {
        VStack(spacing: 0) {
            editor
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var editor: some View {
        TextEditor(text: $model.query)
            .font(.system(size: 14))
            .lineSpacing(2)
            .scrollContentBackground(.hidden)
            .focused(focused)
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .overlay(alignment: .topLeading) {
                if model.query.isEmpty {
                    Text(placeholder)
                        .font(.system(size: 14))
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 4)
                        .padding(.horizontal, 18)
                        .padding(.top, 18)
                        .allowsHitTesting(false)
                }
            }
            .onKeyPress(.return, phases: .down) { press in model.handleNoteReturn(press) }
            .onKeyPress(.tab, phases: .down) { press in model.handleTab(press) }
            .onKeyPress(.escape) { model.handleEscape() }
            .onKeyPress(.delete) { model.handleDelete() }
    }

    private var footer: some View {
        HStack {
            Text(model.noteStatsString)
                .monospacedDigit()
            Spacer()
            HStack { Keycap("↵"); Text("Save") }
            HStack { Keycap("⇧↵"); Text("New line") }
        }
        .font(.system(size: 11))
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 50)
        .padding(.top, 4)
        .padding(.bottom, 12)
    }
}

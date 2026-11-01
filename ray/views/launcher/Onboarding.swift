//
//  Onboarding.swift
//  ray
//
//  Created by Dylan Karunanayake on 1/11/2026.
//

import SwiftUI

enum OnboardingEmojiAnimation { case wave }

// Things the onboarding teaches you
enum OnboardingTask { case typing, modeSwitch, arrows, number }

// Model for a page, emojis can be animated if passed
struct OnboardingStep {
    var emoji: String? = nil
    var animation: OnboardingEmojiAnimation? = nil
    var symbol: String? = nil
    let title: String
    let body: String
    var note: String? = nil
    var keys: [String] = []
    var showsMarkerDemo: Bool = false
    var tasks: [OnboardingTask] = []
    var hint: String? = nil
}

enum Onboarding {
    static let steps: [OnboardingStep] = [
        OnboardingStep(emoji: "👋",
                       animation: .wave,
                       symbol: "faceid",
                       title: "Welcome to Ray",
                       body: "This is just an onboarding so you don't get lost, this won't take very long."),
        OnboardingStep(symbol: "keyboard",
                       title: "Summon it from anywhere",
                       body: "Ray is a launcher. You can use the below keybind to open it",
                       note: "p.s. you can change it in settings",
                       keys: ["⌥", "Space"]),
        OnboardingStep(symbol: "magnifyingglass",
                       title: "Just start typing",
                       body: "Apps, files and the web in one search. The letters you typed get highlighted so you can see why something matched.", // TODO: add AI messaging as well
                       showsMarkerDemo: true,
                       tasks: [.typing],
                       hint: "Try searching for something"),
        OnboardingStep(symbol: "plusminus",
                       title: "Math and notes too",
                       body: "Press Tab to switch modes, or start with = for a calculation and ' for a quick note.",
                       keys: ["Tab", "=", "'"],
                       tasks: [.modeSwitch],
                       hint: "Try it, press Tab"),
        OnboardingStep(symbol: "arrow.up.arrow.down",
                       title: "Pick your result",
                       body: "The list opens when you pause. Move with the arrows, jump with a number, open with return.",
                       keys: ["↑↓", "⌘1", "↵"],
                       tasks: [.arrows, .number],
                       hint: "Try it, press ↓ or ⌘1"),
        OnboardingStep(symbol: "checkmark.circle",
                       title: "You're all set",
                       body: "You can customise things in Ray Settings. You can also replay the onboarding there."),
    ]
}

extension LauncherModel {

    var currentOnboardingStep: OnboardingStep {
        Onboarding.steps[min(onboardingStep, Onboarding.steps.count - 1)]
    }

    var isLastOnboardingStep: Bool {
        onboardingStep >= Onboarding.steps.count - 1
    }

    func advanceOnboarding() {
        if isLastOnboardingStep {
            finishOnboarding()
        } else {
            goToStep(onboardingStep + 1)
        }
    }

    // Every page starts clean, so whatever you typed on the last page is gone
    func goToStep(_ i: Int) {
        guard i >= 0, i < Onboarding.steps.count else { return }
        taskDone = false
        clearOnboardingInput()
        onboardingStep = i
    }

    // If this page was waiting for it, show the tick and move on after a beat
    func completeTask(_ kind: OnboardingTask) {
        guard doOnboarding, !taskDone else { return }
        guard currentOnboardingStep.tasks.contains(kind) else { return }

        if kind == .typing {
            guard trimmedQuery.lowercased().hasPrefix("saf") else { return }
        }

        taskDone = true
        let page = onboardingStep

        Task {
            try? await Task.sleep(for: .seconds(0.9))
            guard doOnboarding, taskDone, onboardingStep == page else { return }
            advanceOnboarding()
        }
    }

    func clearOnboardingInput() {
        if !query.isEmpty { query = "" }
        if mode != .find { mode = .find }
    }

    func finishOnboarding() {
        clearOnboardingInput()
        taskDone = false
        onboarded = true
        onboardingStep = 0
        closeDropdown()
        scheduleDropdown()
    }
}

// The page content + footer shown in the map during the tour
struct OnboardingView: View {
    @EnvironmentObject private var model: LauncherModel

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                OnboardingPage(step: model.currentOnboardingStep)
                    .id(model.onboardingStep)
                    .transition(.opacity.combined(with: .offset(y: 10)))
            }
            .frame(maxWidth: .infinity, minHeight: 250)
            .animation(model.motion(.row), value: model.onboardingStep)

            OnboardingFooter()
        }
    }
}

private struct OnboardingPage: View {
    @EnvironmentObject private var model: LauncherModel
    let step: OnboardingStep

    var body: some View {
        VStack(spacing: 10) {
            if let symbol = step.symbol {
                Image(systemName: symbol)
                    .font(.system(size: 45, weight: .light))
                    .foregroundStyle(.primary)
            }

            Text(step.title)
                .font(.system(size: 18, weight: .semibold))

            Text(step.body)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if !step.keys.isEmpty {
                HStack(spacing: 6) {
                    ForEach(step.keys, id: \.self) { Keycap($0) }
                }
                .padding(.top, 4)
            }

            if let note = step.note, !note.isEmpty {
                Text(note)
                    .font(.system(size: 8))
                    .monospaced()
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
            }

            if step.showsMarkerDemo { MarkerDemo() }

            if let hint = step.hint {
                taskHint(hint).padding(.bottom, 4)
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 8)
    }

    private func taskHint(_ hint: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: model.taskDone ? "checkmark.circle.fill" : "circle.dotted")
                .foregroundStyle(model.taskDone ? Color.green : Color.secondary)
                .contentTransition(.symbolEffect(.replace))

            Text(model.taskDone ? "Nice!" : hint)
                .foregroundStyle(model.taskDone ? Color.primary : Color.secondary)
        }
        .font(.system(size: 12, weight: .medium))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .padding(.top, 8)
        .id(model.taskDone)
        .transition(.scale(scale: 0.92, anchor: .leading).combined(with: .opacity))
        .animation(model.motion(.row), value: model.taskDone)
    }
}

private struct MarkerDemo: View {
    @AppStorage("ray_marker_colour") private var markerColour: MarkerColour = .yellow

    var body: some View {
        HStack(spacing: 10) {
            Text("saf")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
            Image(systemName: "arrow.right")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            (Text("Saf").customAttribute(MarkedAttribute()) + Text("ari"))
                .textRenderer(MarkerRenderer(color: markerColour.colour))
                .font(.system(size: 16, weight: .medium))
        }
        .padding(.top, 6)
    }
}

private struct OnboardingFooter: View {
    @EnvironmentObject private var model: LauncherModel

    var body: some View {
        HStack {
            Button { model.finishOnboarding() } label: {
                HStack(spacing: 6) { Keycap("esc"); Text("Skip") }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tertiary)

            Spacer()
            progressDots
            Spacer()

            Button { model.advanceOnboarding() } label: {
                HStack(spacing: 6) {
                    Text(model.isLastOnboardingStep ? "Get started" : "Next")
                    Keycap("↵")
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .font(.system(size: 12))
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 0.5)
        }
    }

    /// The active page stretches into a pill, click a dot to jump to that page
    private var progressDots: some View {
        HStack(spacing: 5) {
            ForEach(0..<Onboarding.steps.count, id: \.self) { i in
                Capsule()
                    .fill(Color.white.opacity(i == model.onboardingStep ? 0.85 : 0.25))
                    .frame(width: i == model.onboardingStep ? 16 : 5, height: 5)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                    .onTapGesture { model.goToStep(i) }
            }
        }
        .animation(model.motion(.row), value: model.onboardingStep)
    }
}

private struct WaveValues {
    var rotation: Double = 0
}

struct OnboardingEmojiView: View {
    let emoji: String
    let animation: OnboardingEmojiAnimation?

    var body: some View {
        Group {
            if case .wave = animation {
                Text(emoji)
                    .font(.system(size: 80))
                    .keyframeAnimator(initialValue: WaveValues(), repeating: true) { content, value in
                        content.rotationEffect(.degrees(value.rotation), anchor: UnitPoint(x: 1, y: 1))
                    } keyframes: { _ in
                        KeyframeTrack(\.rotation) {
                            CubicKeyframe(-14, duration: 0.35)
                            CubicKeyframe(12, duration: 0.45)
                            CubicKeyframe(-7, duration: 0.35)
                            CubicKeyframe(0, duration: 0.4)
                            LinearKeyframe(0, duration: 1.0)
                        }
                    }
            } else {
                // more animations ig
            }
        }
    }
}

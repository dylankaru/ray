//
//  Components.swift
//  ray
//
//  Created by Dylan Karunanayake on 18/10/2026.
//

import SwiftUI

// GlassCard is the shape/body of the launcher, everything the user sees and interacts with is housed in one
struct GlassCard: ViewModifier {
    @AppStorage("ray_custom_tint") private var customTint: RayThemes = .black
    @AppStorage("ray_tint_strength") private var tintStrength: Double = 0.4

    let radius: CGFloat

    func body(content: Content) -> some View {
        let s = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let edge = LinearGradient(colors: [Color.black.opacity(0.6), Color.black.opacity(0.6)], startPoint: .top, endPoint: .bottom)
        return content
            .rayGlassEffect(customTint.colour.opacity(tintStrength), interactive: true, in: s) // TODO: check if you can scale interaction intensity
            .overlay(s.strokeBorder(edge, lineWidth: 0.6))
            .shadow(color: .black.opacity(0.35), radius: 22, y: 9)
    }
}

extension View {
    func glassCard(radius: CGFloat) -> some View { modifier(GlassCard(radius: radius)) }
}

// The little rounded key labels (↵, esc, ⌘1...)
struct Keycap: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 10.5, weight: .medium, design: .rounded))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

// The hint on the selected row: an arrow and the icon of what it does
struct SideHint: View {
    let arrow: String
    let action: SideAction

    var body: some View {
        HStack(spacing: 3) {
            Text(arrow)
            Image(systemName: action.icon)
        }
        .font(.system(size: 10.5, weight: .medium, design: .rounded))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

// Marks a piece of text as typed
struct MarkedAttribute: TextAttribute {}

struct MarkerRenderer: TextRenderer {
    var color: Color

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        for line in layout {
            for run in line where run[MarkedAttribute.self] != nil {
                let r = run.typographicBounds.rect.insetBy(dx: 0, dy: 1) // dx 0 so it never spills onto the next letter
                context.fill(Path(r), with: .color(color))
            }
            context.draw(line)
        }
    }
}

struct HighlightedText: View {
    let title: String
    let query: String

    @AppStorage("ray_marker_theme") private var markerTheme: MarkerTheme = .highlighter
    @AppStorage("ray_marker_colour") private var markerColour: MarkerColour = .yellow
    @AppStorage("ray_marker_weight") private var markerWeight: MarkerBoldness = .verybold
    @AppStorage("ray_custom_tint") private var customTint: RayThemes = .black
    @AppStorage("ray_tint_strength") private var tintStrength: Double = 0.4

    var body: some View {
        if markerTheme == .highlighter {
            markedText.textRenderer(MarkerRenderer(color: markerColour.colour))
        } else {
            markedText
        }
    }

    private var markedText: Text {
        let matched: Set<Int> = query.isEmpty ? [] : Highlight.matched(query, in: title)
        guard !matched.isEmpty else { return Text(title) }

        var segments: [Text] = []
        var buffer = ""
        var bufferMarked = false

        for (i, ch) in title.enumerated() {
            let marked = matched.contains(i)
            if i > 0 && marked != bufferMarked {
                segments.append(segment(buffer, marked: bufferMarked))
                buffer = ""
            }
            buffer.append(ch)
            bufferMarked = marked
        }
        segments.append(segment(buffer, marked: bufferMarked))
        return segments.reduce(Text(""), +)
    }

    private func segment(_ text: String, marked: Bool) -> Text {
        guard marked else { return Text(text) }
        switch markerTheme {
        case .highlighter: return Text(text).customAttribute(MarkedAttribute())
        case .underline:   return Text(text).underline(true, color: customTint.appropriateTextColor(strength: tintStrength))
        case .bold:        return Text(text).fontWeight(markerWeight.weight)
        }
    }
}

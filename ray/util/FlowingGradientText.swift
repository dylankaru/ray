//
//  FlowingGradientText.swift
//  ray
//
//  Created by Dylan Karunanayake on 18/10/2026.
//

import SwiftUI

struct FlowingGradientText: View {
    let text: String
    var duration: Double = 2.9

    private let colors: [Color] = [
        Color(red: 1.00, green: 0.80, blue: 0.30), // amber
        Color(red: 1.00, green: 0.55, blue: 0.25), // orange
        Color(red: 1.00, green: 0.38, blue: 0.45), // coral
        Color(red: 1.00, green: 0.80, blue: 0.30), // back to amber
    ]

    var body: some View {
        Text(text)
            .hidden() // only here to reserve the text's size
            .overlay {
                GeometryReader { geo in
                    TimelineView(.animation(minimumInterval: 1.0 / 30)) { ctx in
                        let t = ctx.date.timeIntervalSinceReferenceDate
                        let phase = (t / duration).truncatingRemainder(dividingBy: 1)

                        HStack(spacing: 0) {
                            LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)
                                .frame(width: geo.size.width)
                            LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)
                                .frame(width: geo.size.width)
                        }
                        .offset(x: -phase * geo.size.width)
                    }
                }
                .mask { Text(text) }
            }
    }
}


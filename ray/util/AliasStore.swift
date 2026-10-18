//
//  AliasStore.swift
//  ray
//
//  Created by Dylan Karunanayake on 16/10/2026.
//

import SwiftUI
import Foundation

enum AliasStore {
    private static let key = "ray.aliases"

    private static var cache: [String: [String]] = {
        UserDefaults.standard.dictionary(forKey: key) as? [String: [String]] ?? [:]
    }()

    private static var byteCache: [String: [[UInt8]]] = {
        cache.mapValues { $0.map { Array($0.utf8) } }
    }()

    static func aliases(for id: String) -> [String] {
        cache[id] ?? []
    }

    static func bytes(for id: String) -> [[UInt8]] {
        byteCache[id] ?? []
    }

    static func add(_ alias: String, to id: String) {
        let clean = alias.lowercased().filter { !$0.isWhitespace }
        guard !clean.isEmpty else { return }
        var list = cache[id] ?? []
        guard !list.contains(clean) else { return }
        list.append(clean)
        cache[id] = list
        byteCache[id] = list.map { Array($0.utf8) }
        save()
    }

    static func remove(_ alias: String, from id: String) {
        let clean = alias.lowercased()
        guard var list = cache[id] else { return }
        list.removeAll { $0 == clean }
        cache[id] = list.isEmpty ? nil : list
        byteCache[id] = list.isEmpty ? nil : list.map { Array($0.utf8) }
        save()
    }

    private static func save() {
        UserDefaults.standard.set(cache, forKey: key)
    }
}

//TODO: move it away form here
struct BubbleShape: Shape {
    var radius: CGFloat = 18
    var tailWidth: CGFloat = 12
    var tailHeight: CGFloat = 22

    func path(in rect: CGRect) -> Path {
        let b = CGRect(x: rect.minX + tailWidth, y: rect.minY,
                       width: rect.width - tailWidth, height: rect.height)
        let r = min(radius, b.height / 2, b.width / 2)
        let midY = rect.midY
        let half = tailHeight / 2

        var p = Path()
        p.move(to: CGPoint(x: b.minX + r, y: b.minY))
        p.addLine(to: CGPoint(x: b.maxX - r, y: b.minY))
        p.addArc(tangent1End: CGPoint(x: b.maxX, y: b.minY), tangent2End: CGPoint(x: b.maxX, y: b.minY + r), radius: r)
        p.addLine(to: CGPoint(x: b.maxX, y: b.maxY - r))
        p.addArc(tangent1End: CGPoint(x: b.maxX, y: b.maxY), tangent2End: CGPoint(x: b.maxX - r, y: b.maxY), radius: r)
        p.addLine(to: CGPoint(x: b.minX + r, y: b.maxY))
        p.addArc(tangent1End: CGPoint(x: b.minX, y: b.maxY), tangent2End: CGPoint(x: b.minX, y: b.maxY - r), radius: r)

        // Up the left edge, out to the tip and back, with a slightly rounded point
        p.addLine(to: CGPoint(x: b.minX, y: midY + half))
        p.addLine(to: CGPoint(x: rect.minX + 1.5, y: midY + 1.8))
        p.addQuadCurve(to: CGPoint(x: rect.minX + 1.5, y: midY - 1.8),
                       control: CGPoint(x: rect.minX - 0.5, y: midY))
        p.addLine(to: CGPoint(x: b.minX, y: midY - half))

        p.addLine(to: CGPoint(x: b.minX, y: b.minY + r))
        p.addArc(tangent1End: CGPoint(x: b.minX, y: b.minY), tangent2End: CGPoint(x: b.minX + r, y: b.minY), radius: r)
        p.closeSubpath()
        return p
    }
}

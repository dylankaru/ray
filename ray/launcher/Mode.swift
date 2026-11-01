//
//  Mode.swift
//  ray
//
//  Created by Dylan Karunanayake on 1/11/2026.
//

import Foundation

enum Mode: Int, CaseIterable {
    case find, calc, note

    var prompt: String {
        switch self {
        case .find: return "Search apps, files and the web"
        case .calc: return "Type an expression"
        case .note: return ""
        }
    }

    // Type this as the first character in Find mode to jump modes
    // TODO: might remove or make better soon
    static func from(prefix c: Character) -> Mode? {
        switch c {
        case "=": return .calc
        case "'": return .note
        default:  return nil
        }
    }
}

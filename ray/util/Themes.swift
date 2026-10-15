//
//  Themes.swift
//  ray
//
//  Created by Dylan Karunanayake on 9/10/2026.
//

import SwiftUI

enum MarkerTheme: String, CaseIterable, Codable {
    case highlighter
    case underline
    case bold
    
    var title: String {
        switch self {
        case .highlighter: return "Highlighter"
        case .underline: return "Underline"
        case .bold: return "Bold"
        }
    }
}

// Since marker styles are mutually exclusive, as in multiple chosen at the same time is not possible, I tried to combine them
// into one enum, but it would make handling them a bit weirder..

enum MarkerColour: String, CaseIterable, Codable {
    case cyan
    case green
    case grey
    case yellow
    
    var strength: Double {
        get {
            (UserDefaults.standard.object(forKey: "ray_marker_strength") as? Double) ?? 0.8
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "ray_marker_strength")
        }
    }
    
    var colour: Color {
        let currentStrength = strength
        switch self {
        case .cyan: return Color.cyan.opacity(currentStrength)
        case .green: return Color.green.opacity(currentStrength)
        case .grey: return Color.gray.opacity(currentStrength)
        case .yellow: return Color.yellow.opacity(currentStrength)
        }
    }
    
    var title: String {
        switch self {
        case .cyan: return "cyan"
        case .green: return "green"
        case .grey: return "grey"
        case .yellow: return "yellow"
        }
    }
}

enum MarkerBoldness: String, CaseIterable, Codable {
    case superlight
    case slightlybold
    case prettybold
    case verybold
    
    var weight: Font.Weight {
        switch self {
        case .superlight: return .ultraLight
        case .slightlybold: return .bold
        case .prettybold: return .heavy
        case .verybold: return .black
        }
    }
    
    var title: String {
        switch self {
        case .superlight: return "1"
        case .slightlybold: return "2"
        case .prettybold: return "3"
        case .verybold: return "4"
        }
    }
}

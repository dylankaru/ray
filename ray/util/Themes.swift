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
    
    var title: String { rawValue.capitalized }
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
    
    var title: String { rawValue.capitalized }
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

/*
 IN MY HONEST OPINION, the coloured styles come of as flourescent and at higher opacities in intensely strong.
 It feels like a massive eyesore sore i limited them 0.4
 Black and white are the only ones that i feel look good exceeding that, and I dont rlly want to give the user that judgement because if
 the product has the capacity to look bad then it i think it comes off worse on me than their preferences :sob: sory for being so rude
 and blunt
 */
enum RayThemes: String, CaseIterable, Codable {
    case black
    case white
    case green
    case blue
    case orange
    case indigo
    case mint
    case pink
    
    var title: String { rawValue.capitalized }
    
    var colour: Color {
        switch self {
        case .black: return .black
        case .white: return .white
        case .green: return .green
        case .blue: return .blue
        case .orange: return .orange
        case .indigo: return .indigo
        case .mint: return .mint
        case .pink: return .pink
        }
    }
    
    var maxStrength: Double {
        switch self {
        case .white: 0.8
        case .black: 0.8
        default: 0.4
        }
    }
    
    func appropriateTextColor(strength: Double) -> Color {
        switch self {
        case .white: return strength >= 0.6 ? .black : .white
        default: return .white
        }
    }
}

enum MotionStyle: String, CaseIterable  {
    case snappy, standard, bouncy, off
    
    var title: String { self == .standard ? "Default" : rawValue.capitalized  }
    
    enum Role { case dropdown, row, selection, quick }
    
    func animation(_ role: Role, reduceMotion: Bool) -> Animation? {
        if self == .off || reduceMotion { return nil }
        
        switch (self, role) {
        case (.snappy, .dropdown):   return .spring(response: 0.28, dampingFraction: 0.9)
        case (.snappy, .row):        return .spring(response: 0.22, dampingFraction: 0.9)
        case (.snappy, .selection):  return .spring(response: 0.20, dampingFraction: 0.9)
        case (.snappy, .quick):      return .smooth(duration: 0.10)
            
        case (.bouncy, .dropdown):   return .spring(response: 0.50, dampingFraction: 0.55)
        case (.bouncy, .row):        return .spring(response: 0.40, dampingFraction: 0.62)
        case (.bouncy, .selection):  return .spring(response: 0.35, dampingFraction: 0.60)
        case (.bouncy, .quick):      return .smooth(duration: 0.20)
            
        case (_, .dropdown):         return .spring(response: 0.42, dampingFraction: 0.72)
        case (_, .row):              return .spring(response: 0.32, dampingFraction: 0.78)
        case (_, .selection):        return .spring(response: 0.28, dampingFraction: 0.78)
        case (_, .quick):            return .smooth(duration: 0.16)
        }
    }
    
    func stagger(reduceMotion: Bool) -> Double {
        if self == .off || reduceMotion { return 0 }
        switch self {
        case .snappy: return 0.015
        case .bouncy: return 0.04
        default:      return 0.03
        }
    }
}

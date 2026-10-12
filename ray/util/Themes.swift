//
//  Themes.swift
//  ray
//
//  Created by Dylan Karunanayake on 9/10/2026.
//

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

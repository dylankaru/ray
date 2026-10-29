//
//  IvyManager.swift
//  ray
//
//  Created by Dylan Karunanayake on 29/10/2026.
//

import Foundation

enum PreferredSearchState: String, CaseIterable{
    case browser
    case ivy
    
    var title: String { rawValue.capitalized }
}

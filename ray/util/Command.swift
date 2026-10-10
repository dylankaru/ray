//
//  Command.swift
//  ray
//
//  Created by Dylan Karunanayake on 8/10/2026.
//

struct Command: Identifiable {
    let title: String
    let subtitle: String
    let icon: String
    let action: () -> Void
    var id: String { title }
}

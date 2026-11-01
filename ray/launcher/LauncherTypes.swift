//
//  LauncherTypes.swift
//  ray
//
//  Created by Dylan Karunanayake on 1/11/2026.
//

import SwiftUI

/// The shape of an option command in ray
struct PaneAction {
    let title: String
    let icon: String
    var keepsOpen: Bool = false
    let run: () -> Void
}

/// What the left/ right arrows and swipe gestures do on a row
struct SideAction {
    let title: String
    let icon: String
    let run: () -> Void
}

enum TileLayout { case compact, note, camera }

enum Side { case leading, trailing }

enum Metrics {
    static let windowPadding: CGFloat = 60
    static let stageSpacing: CGFloat = 16

    static let tileSize: CGFloat = 240
    static let noteTileSize = CGSize(width: 348, height: 252)
    static let cameraTileSize = CGSize(width: 560, height: 315)

    static let launcherPadding: CGFloat = 16
    static let launcherRadius: CGFloat = 50
    static let tileRadius: CGFloat = 38

    static let dropdownWidth: CGFloat = 380
    static let dropdownRadius: CGFloat = 28
    static let dropdownInset: CGFloat = 8
    static let dropdownHeaderHeight: CGFloat = 36
    static let rowHeight: CGFloat = 46
    static let emojiColumns = 8

    static let utilityBarSize = CGSize(width: 380, height: 60)

    static var stageWidth: CGFloat { cameraTileSize.width + launcherPadding * 2 }
}

//
//  ContentView.swift
//  ray
//
//  Created by Dylan Karunanayake on 8/10/2026.
//

import SwiftUI

// I'm gonna practice writing comments
/*
 
 Quick terminology so I don't forget..
 Launchpad: the rounded squircle that acts as the actual launcher
 Map:       the dropdown of related command options
 Raydar:    the capsule on top of the launchpad
 Bag:       the term that refers to the entire launcher, so the launchpad, map, and raydar all at the same time
 Trigger:   the suggested/main action given in the launchpad
 Option:    a suggested in the list of given possible actions in the map
 
 btw it should technically be v0.x not v1.x but im silly so i forgot 😁
 
 v1.1:
 >  I've changed the consumer names because they seem pretty poorly named
 
 v1.2:
 > I think ill start updating this big chunk of commands because it helps me remember what to write in the devlogs
 > Ive added a bunch of stuff in no particular order: tint, strength of tint, motion intensity controls, basic keybind remapping
 > camera item
 > Also added a birthday ting
 
 v1.3:
 > added support for systems old as macos 15.6 i think, though i dont have an old mac to test the ui on but i have a friend who has an old mac, it might be on sequoia so ill check if he can check it for me
 > Also added emoji dictionary to search for emojis, it works and is functional but the ui is still a bit bad ykwis so ill have to fix that later soon too
 > Added keybind rebinding support and made some changes to the birthday thing again making a new custom input for better intuitive usage,, still not finished tho
 > also forgot camera wasn't flipped :/
 > I made a bunch of new modules to make the code make more sense and much more readable
 */

// The root view. It owns the model, handles keys, and lays out the stage. Nothing else.
struct ContentView: View {
    @StateObject private var model = LauncherModel()
    @FocusState private var focused: Bool
    @Namespace private var glassNS

    private var bar: UtilityBarManager { .shared }

    var body: some View {
        keyHandled
            .foregroundStyle(model.customTint.appropriateTextColor(strength: model.tintStrength))
            .environmentObject(model)
            // State changes → model reactions (the model decides what each one means)
            .onChange(of: model.query) { _, new in model.queryChanged(new) }
            .onChange(of: model.mode) { model.modeChanged() }
            .onChange(of: model.cameraSelected) { _, selected in model.cameraSelectedChanged(selected) }
            .onChange(of: model.showingCamera) { _, showing in model.showingCameraChanged(showing) }
            .onChange(of: model.selection) { model.selectionChanged() }
            .onChange(of: model.showingClipboardHistory) { model.subScreenChanged() }
            .onChange(of: model.showingEmoji) { model.subScreenChanged() }
            .onChange(of: model.clipboard.items) { model.clipboardItemsChanged() }
            .onChange(of: model.dropdownVisible) { _, visible in model.dropdownVisibleChanged(visible) }
            // Things that happen to the window
            .onReceive(NotificationCenter.default.publisher(for: .rayReset)) { _ in model.reset() }
            .onReceive(NotificationCenter.default.publisher(for: .rayFocus)) { _ in refocus() }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in refocus() }
            // Background work
            .task { await model.loadApps() }
            .task { await model.indexFiles() }
            .onAppear { focused = true; model.appeared() }
    }

    private var keyHandled: some View {
        framed
            .onKeyPress(.downArrow) { model.handleDown() }
            .onKeyPress(.upArrow) { model.move(model.showingEmoji ? -Metrics.emojiColumns : -1); return .handled }
            .onKeyPress(.leftArrow) { model.handleSide(.leading) }   // ← Reveal in Finder
            .onKeyPress(.rightArrow) { model.handleSide(.trailing) } // → Open With (files), Set Alias (apps and commands)
            .onKeyPress(.escape) { model.handleEscape() }
            .onKeyPress(.tab, phases: .down) { press in model.handleTab(press) } // Tab swaps between Find, Calc and Note
            .onKeyPress(.delete) { model.handleDelete() }
    }

    // Invisible buttons that exist only to own keyboard shortcuts
    private var shortcutButtons: some View {
        Group {
            ForEach(0..<7, id: \.self) { i in
                Button("") { model.run(at: i) }
                    .keyboardShortcut(shortcutKey(i), modifiers: .command)
            }
            Button("") { model.cycleAction(1) }.keyboardShortcut(.downArrow, modifiers: .option)
            Button("") { model.cycleAction(-1) }.keyboardShortcut(.upArrow, modifiers: .option)
            Button("") { model.quitSelectedApp() }.keyboardShortcut(.rightArrow, modifiers: .option) // ⌥→ quits the selected running app
        }
        .opacity(0)
        .frame(width: 0, height: 0)
    }

    private func shortcutKey(_ i: Int) -> KeyEquivalent {
        KeyEquivalent(String(i + 1).first ?? "1")
    }

    // Toggles focus off and on, fixes the text field not receiving keystrokes
    private func refocus() {
        focused = false
        DispatchQueue.main.async { focused = true }
    }

    private var framed: some View {
        stage
            .padding(Metrics.windowPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background { shortcutButtons }
    }

    // The raydar, launchpad and map
    private var stage: some View {
        RayGlassContainer(spacing: Metrics.stageSpacing) {
            VStack(spacing: Metrics.stageSpacing) {
                if let state = bar.state {
                    // Raydar is only visible when it's needed like updates, a friend's birthday, other soon to come features too ig
                    VStack(spacing: 0) { UtilityBarContent(state: state) }
                        .frame(width: Metrics.utilityBarSize.width, height: Metrics.utilityBarSize.height)
                        .glassCard(radius: Metrics.dropdownRadius)
                        .rayGlassEffectID("utilityBar", in: glassNS)
                }
                LauncherView(focused: $focused, glassNS: glassNS) // launchpad
                if model.dropdownVisible {
                    DropdownView(glassNS: glassNS) // map
                }
            }
            .frame(width: Metrics.stageWidth, alignment: .top)
            .overlay(alignment: .topLeading) { AliasBubbleOverlay(glassNS: glassNS) }
        }
        .animation(model.motion(.dropdown), value: model.dropdownVisible)
        .animation(model.motion(.quick), value: model.mode)
    }
}

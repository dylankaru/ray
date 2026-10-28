//
//  rayApp.swift
//  ray
//
//  Created by Dylan Karunanayake on 8/10/2026.
//

import SwiftUI

// I'm gonna practice writing more comments in my code

@main
struct rayApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
 
    var body: some Scene {
        Settings { EmptyView() }
    }
}

// TODO: make the dropdown more customisable or add a mini dashboard
// TODO: --> as in make it so that they can get quick stats to glance like maybe a friends birthday is tday or smth
// TODO: praj said to add animations to spawning and despawning the bag
// TODO: add emoji thing and maybe even emoji kitchen to that too, that would be aura
// TODO: maybe more tints too?

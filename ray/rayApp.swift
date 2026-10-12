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
 
// TODO: make the notes waaay better
// TODO: improve the expansion appear/disappear animation
// TODO: add camera module
// TODO: make ray update checks auto (liek when new app installed it cant see it yet) DOING
// TODO: make the dropdown more customisable or add a mini dashboard
// TODO: --> as in make it so that they can get quick stats to glance like maybe a friends birthday is tday or smth
// TODO: improve performance (90mb of ram is a lot, and 7% cpu)

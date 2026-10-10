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
// TODO: make ray update checks auto (liek when new app installed it cant see it yet)

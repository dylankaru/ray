//
//  RayLiquid.swift
//  ray
//
//  Created by Dylan Karunanayake on 15/10/2026.
//

import SwiftUI

// Tabs and liquid glass in general is only available on versions MacOS 26+ (tabs specifically is 27+)
// and a minimum deployment of 26/27 would be insanely new, so making this lets me support older systems
// whilst still using liquid glass on newer systems (liquid glass looks so smexy)
extension View {
    @ViewBuilder
    public func rayGlassEffect<S: Shape>(in shape: S = Capsule()) -> some View {
        if #available(macOS 26, *) {
            self.glassEffect(.regular.interactive(), in: shape)
        } else {
            self
        }
    }
    
    @ViewBuilder
    public func rayGlassEffect<S: Shape>(_ tint: Color? = nil, interactive: Bool = false, in shape: S = Capsule()) -> some View {
        if #available(macOS 26, *) {
            let glass: Glass = tint.map { .regular.tint($0) } ?? .regular
            let modifiedGlass = interactive ? glass.interactive() : glass
            self.glassEffect(modifiedGlass, in: shape)
        } else {
            self
        }
    }
    
    @ViewBuilder
    public func rayGlassContainer<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        if #available(macOS 26, *) {
            GlassEffectContainer {
                content()
            }
        } else {
            content()
        }
    }
    
    @ViewBuilder
    public func rayGlassEffectID<ID: Hashable, S: Shape>(_ id: ID, in shape: S) -> some View {
        if #available(macOS 26, *) {
//            self.glassEffectID(id, in: shape)
        } else {
            self
        }
    }
    
    @ViewBuilder
    public func rayGlassButton() -> some View {
        if #available(macOS 26, *) {
            self.buttonStyle(.glass)
        } else {
            self.buttonStyle(.plain)
        }
    }
    
    @ViewBuilder
    public func rayTabs(forceMenu: Bool = false) -> some View {
        if !forceMenu {
            if #available(macOS 27, *) {
                self.pickerStyle(.tabs)
            } else if #available(macOS 26, *) {
                self.pickerStyle(.menu)
            } else {
                self.pickerStyle(.segmented)
            }
        } else {
            self.pickerStyle(.menu)
        }
    }
}

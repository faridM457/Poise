//
//  ContentView.swift
//  Poise
//
//  Created by Rafid Mohammed on 9/11/26.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        PoiseRootView()
            // The app only supports light mode (see AGENTS.md) -- dark mode
            // was never actually designed or tested, so any control that
            // doesn't hardcode its own colors (a bare Text, a TextField's
            // typed text, a native Toggle) silently follows the system's
            // dynamic appearance instead. That's what caused white text on
            // this app's fixed-light backgrounds when the system is in Dark
            // Mode -- forcing light appearance here fixes that whole class
            // of bug in one place instead of auditing every control.
            .preferredColorScheme(.light)
    }
}

//
//  ContentView.swift
//  Poise
//
//  Created by Rafid Mohammed on 9/11/26.
//

import SwiftUI

struct ContentView: View {
    @State private var subscriptionState = SubscriptionState()

    var body: some View {
        PoiseRootView()
            .environment(subscriptionState)
            .task {
                await subscriptionState.refreshAtStartup()
            }
    }
}

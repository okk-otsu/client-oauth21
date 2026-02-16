//
//  RootView.swift
//  cli-oauth21
//
//  Created by MacBook on 16.02.2026.
//

import SwiftUI

struct RootView: View {
    @State private var hasTokens = TokenStorage.shared.loadTokens() != nil

    var body: some View {
        if hasTokens {
            ContentView()
                .onAppear {
                    // автоматически помечаем как аутентифицированного
                }
        } else {
            ContentView()
        }
    }
}

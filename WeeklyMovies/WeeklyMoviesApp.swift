//
//  WeeklyMoviesApp.swift
//  WeeklyMovies
//
//  Created by Nicolas Richards on 2/27/26.
//

import SwiftUI

@main
struct WeeklyMoviesApp: App {
    init() {
        TipJar.shared.startListening()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

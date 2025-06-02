//
//  JellyJellyApp.swift
//  JellyJelly
//
//  Created by Li Li on 6/2/25.
//

import SwiftUI

@main
struct JellyJellyApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}

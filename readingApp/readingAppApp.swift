
//
//  readingAppApp.swift
//  readingApp
//
//  Created by Joey Rubin on 7/16/25.
//

import SwiftUI

@main
struct readingAppApp: App {
    // Create the persistence controller
    let persistenceController = PersistenceController.shared
    
    // Create the AppManager and pass the Core Data context to it
    @StateObject private var appManager: AppManager
    
    init() {
        let context = persistenceController.container.viewContext
        _appManager = StateObject(wrappedValue: AppManager(context: context))
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
            // Inject the managed object context into the environment
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .environmentObject(appManager)
        }
    }
}

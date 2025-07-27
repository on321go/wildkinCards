
//
//  readingAppApp.swift
//  readingApp
//
//  Created by Joey Rubin on 7/16/25.
//

import SwiftUI

@main
struct readingAppApp: App {
    // The single source for Core Data and CloudKit persistence.
    let persistenceController = PersistenceController.shared
    
    // The AppManager now manages the state for the entire app, including challenges and battles.
    @StateObject private var appManager: AppManager
    
    // The ConnectionManager for multiplayer battles is prepared at the app's root.
    @StateObject private var connectionManager = MultipeerConnectionManager.sharedInstance

    init() {
        let context = persistenceController.container.viewContext
        _appManager = StateObject(wrappedValue: AppManager(context: context))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                // Inject the Core Data context for views that need it.
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                // Inject the AppManager for global state management.
                .environmentObject(appManager)
                // Inject the ConnectionManager for all battle-related views.
                .environmentObject(connectionManager)
        }
    }
}

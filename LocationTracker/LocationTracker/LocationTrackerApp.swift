import SwiftUI

@main
struct LocationTrackerApp: App {
    @StateObject private var tracker = LocationTracker.shared
    @StateObject private var matchStore = MatchStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(tracker)
                .environmentObject(matchStore)
                .tint(.violet)
        }
    }
}

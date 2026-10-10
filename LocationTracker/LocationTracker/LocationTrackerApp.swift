import SwiftUI

@main
struct LocationTrackerApp: App {
    @StateObject private var tracker = LocationTracker.shared

    var body: some Scene {
        WindowGroup {
            ContentView().environmentObject(tracker)
        }
    }
}

import SwiftUI

@main
struct LocationTrackerApp: App {
    @StateObject private var tracker = LocationTracker.shared
    @StateObject private var matchStore = MatchStore()
    @StateObject private var recommendations = RecommendationStore()

    init() {
        NotificationManager.shared.configure()
        configureBrutAppearance()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(tracker)
                .environmentObject(matchStore)
                .environmentObject(recommendations)
        }
    }
}

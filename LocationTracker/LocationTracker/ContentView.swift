import SwiftUI
import CoreLocation

struct ContentView: View {
    @EnvironmentObject var tracker: LocationTracker
    @EnvironmentObject var matchStore: MatchStore

    var body: some View {
        NavigationStack {
            List {
                Section("Demo") {
                    Button("Simulate match") { matchStore.simulateMatch() }
                }
                Section {
                    LabeledContent("Authorization", value: authText)
                    LabeledContent("Tracking", value: tracker.isTracking ? "On" : "Off")
                    LabeledContent("Fixes recorded", value: "\(tracker.totalCount)")
                    if tracker.auth != .authorizedAlways {
                        Button("Enable Always Location") { tracker.requestPermission() }
                    } else {
                        Button(tracker.isTracking ? "Stop" : "Start") {
                            tracker.isTracking ? tracker.stop() : tracker.start()
                        }
                    }
                }
                Section("Recent") {
                    ForEach(tracker.fixes) { fix in
                        VStack(alignment: .leading) {
                            Text(String(format: "%.6f, %.6f", fix.lat, fix.lon))
                                .font(.system(.body, design: .monospaced))
                            Text("\(fix.timestamp.formatted(date: .omitted, time: .standard)) · ±\(Int(fix.accuracy))m")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Location Tracker")
        }
        .fullScreenCover(item: $matchStore.match) { match in
            MatchFlowView(match: match)
        }
    }

    private var authText: String {
        switch tracker.auth {
        case .authorizedAlways: "Always"
        case .authorizedWhenInUse: "When in use"
        case .denied: "Denied"
        case .restricted: "Restricted"
        default: "Not determined"
        }
    }
}

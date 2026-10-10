import SwiftUI
import CoreLocation

struct ContentView: View {
    @EnvironmentObject var matchStore: MatchStore
    @EnvironmentObject var recommendations: RecommendationStore

    var body: some View {
        TabView {
            NearbyMapView()
                .tabItem { Label("Map", systemImage: "map") }
            RecommendationsView()
                .tabItem { Label("Playlist", systemImage: "music.note.list") }
                .badge(recommendations.newCount)
            TrackerView()
                .tabItem { Label("Tracker", systemImage: "location") }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            NotificationManager.shared.onOpenMatch = { id in
                matchStore.whenReady { matchStore.openMatch(userId: id) }
            }
            // No backend yet: optionally put the songs the user sends into the user's own playlist.
            matchStore.onSongSent = { [recommendations] song, line, user in
                guard recommendations.loopbackSentSongs else { return }
                recommendations.receive(song: song, senderId: Recommendation.selfId, senderName: "You",
                                        note: line, sharedGenres: user.sharedGenres)
            }
        }
        .fullScreenCover(item: $matchStore.match) { match in
            MatchFlowView(match: match)
        }
    }
}

struct TrackerView: View {
    @EnvironmentObject var tracker: LocationTracker
    @EnvironmentObject var matchStore: MatchStore

    var body: some View {
        NavigationStack {
            List {
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

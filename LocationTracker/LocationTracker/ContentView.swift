import SwiftUI
import CoreLocation

private enum AppTab: String, CaseIterable {
    case map, playlist, tracker

    var title: String {
        switch self {
        case .map: "map"
        case .playlist: "playlist"
        case .tracker: "tracker"
        }
    }

    var icon: String {
        switch self {
        case .map: "map"
        case .playlist: "music.note.list"
        case .tracker: "location"
        }
    }

    var fill: Color {
        switch self {
        case .map: .cubeGreen
        case .playlist: .cubeOrange
        case .tracker: .lightBlue
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var matchStore: MatchStore
    @EnvironmentObject var recommendations: RecommendationStore
    @EnvironmentObject var blockStore: BlockStore
    @State private var tab: AppTab = .map

    var body: some View {
        // Native TabView keeps each tab alive. Its bar is hidden; BrutTabBar replaces it.
        TabView(selection: $tab) {
            NearbyMapView()
                .toolbar(.hidden, for: .tabBar)
                .tag(AppTab.map)
            RecommendationsView()
                .toolbar(.hidden, for: .tabBar)
                .tag(AppTab.playlist)
            TrackerView()
                .toolbar(.hidden, for: .tabBar)
                .tag(AppTab.tracker)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            BrutTabBar(selection: $tab, playlistBadge: recommendations.newCount)
        }
        .brutScreen()
        .onAppear {
            NotificationManager.shared.onOpenMatch = { [blockStore] id in
                guard !blockStore.isBlocked(id) else { return }   // a tap on an old alert from a blocked person
                matchStore.whenReady { matchStore.openMatch(userId: id) }
            }
            recommendations.isBlocked = { [blockStore] in blockStore.isBlocked($0) }
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

/// Floating bar: white, 2 pt border, 4 pt hard shadow. The selected tab is a filled pill.
private struct BrutTabBar: View {
    @Binding var selection: AppTab
    let playlistBadge: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(AppTab.allCases, id: \.self) { item in
                Button {
                    tapHaptic()
                    selection = item
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: item.icon).font(.system(size: 16, weight: .semibold))
                        if selection == item {
                            Text(item.title).font(.subheadline.weight(.bold))
                        }
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 40)
                    .frame(maxWidth: selection == item ? .infinity : nil)
                    .background(Capsule().fill(selection == item ? item.fill : Color.clear))
                    .overlay(Capsule().stroke(selection == item ? Color.ink : Color.clear, lineWidth: Brut.border))
                    .overlay(alignment: .topTrailing) {
                        if item == .playlist && playlistBadge > 0 {
                            Text("\(playlistBadge)")
                                .font(.caption2.weight(.bold))
                                .frame(minWidth: 18, minHeight: 18)
                                .background(Circle().fill(Color.cubeRed))
                                .overlay(Circle().stroke(Color.ink, lineWidth: 1.5))
                                .foregroundStyle(.white)
                                .offset(x: 2, y: -6)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.title)
            }
        }
        .padding(8)
        .brutCard(radius: Brut.radiusLarge)
        .padding(.horizontal, 20)
        .padding(.top, 6)
        .padding(.bottom, 10)
        .animation(.easeOut(duration: 0.15), value: selection)
    }
}

struct TrackerView: View {
    @EnvironmentObject var tracker: LocationTracker
    @EnvironmentObject var matchStore: MatchStore
    @EnvironmentObject var blockStore: BlockStore

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    statusCard

                    if tracker.auth != .authorizedAlways {
                        Button("enable always location") { tracker.requestPermission() }
                            .buttonStyle(.brutPrimary)
                    } else {
                        Button(tracker.isTracking ? "stop tracking" : "start tracking") {
                            tracker.isTracking ? tracker.stop() : tracker.start()
                        }
                        .buttonStyle(BrutButtonStyle(fill: tracker.isTracking ? .surface : .cubeRed,
                                                     textColor: tracker.isTracking ? .ink : .white))
                    }

                    NavigationLink {
                        BlockedPeopleView()
                    } label: {
                        HStack(spacing: 12) {
                            IconBox(systemName: "hand.raised.fill", fill: .cubeOrange, size: 40)
                            Text("blocked people").font(.headline)
                            Spacer()
                            GenreChip(text: "\(blockStore.blocked.count)", fill: .surface)
                            Image(systemName: "chevron.right").font(.footnote.weight(.bold))
                        }
                        .padding(12)
                        .brutCard(shadow: 0)
                    }
                    .buttonStyle(.plain)

                    Text("recent").font(.title3.weight(.bold))
                    if tracker.fixes.isEmpty {
                        Text("no location fixes yet.")
                            .foregroundStyle(Color.inkSecondary)
                    }
                    ForEach(tracker.fixes) { fix in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(String(format: "%.6f, %.6f", fix.lat, fix.lon))
                                .font(.system(.body, design: .monospaced))
                            Text("\(fix.timestamp.formatted(date: .omitted, time: .standard)) · ±\(Int(fix.accuracy))m")
                                .font(.caption).foregroundStyle(Color.inkSecondary)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .brutCard(shadow: 0)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .pageBackground()
            .navigationTitle("tracker")
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                IconBox(systemName: "location.fill", fill: tracker.isTracking ? .cubeGreen : .lightBlue, size: 44)
                Text(tracker.isTracking ? "tracking is on" : "tracking is off")
                    .font(.title3.weight(.bold))
            }
            row("authorization", authText)
            row("fixes recorded", "\(tracker.totalCount)")
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .brutCard()
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(Color.inkSecondary)
            Spacer()
            GenreChip(text: value, fill: .surface)
        }
    }

    private var authText: String {
        switch tracker.auth {
        case .authorizedAlways: "always"
        case .authorizedWhenInUse: "when in use"
        case .denied: "denied"
        case .restricted: "restricted"
        default: "not determined"
        }
    }
}

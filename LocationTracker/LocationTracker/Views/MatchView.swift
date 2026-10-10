import SwiftUI

/// Root of the match flow. Present with `fullScreenCover`.
struct MatchFlowView: View {
    @EnvironmentObject var store: MatchStore
    let match: Match

    var body: some View {
        NavigationStack(path: $store.path) {
            MatchView(match: match)
                .navigationDestination(for: MatchRoute.self) { route in
                    switch route {
                    case .songSearch: SongSearchView(user: match.user)
                    case .meetup: MeetupView(user: match.user)
                    case .sent(let subtitle): SentView(name: match.user.name, subtitle: subtitle)
                    }
                }
        }
        .tint(.violet)
        .preferredColorScheme(.dark)
    }
}

struct MatchView: View {
    @EnvironmentObject var store: MatchStore
    let match: Match
    var outOfRange = false

    private var user: NearbyUser { match.user }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                PulsingRings().frame(height: 120).padding(.top, 8)

                VStack(spacing: 6) {
                    Text("Someone near you")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.mint)
                    Text("\(user.name) is \(distanceText)")
                        .font(.largeTitle.bold())
                        .multilineTextAlignment(.center)
                    if let genreLine {
                        Text(genreLine).foregroundStyle(Color.secondaryText)
                    }
                }

                if outOfRange {
                    Label("\(user.name) moved out of range", systemImage: "location.slash")
                        .font(.subheadline)
                        .padding(12)
                        .frame(maxWidth: .infinity)
                        .background(Color.card, in: RoundedRectangle(cornerRadius: 12))
                }

                nowPlayingCard

                if !user.sharedGenres.isEmpty {
                    HStack {
                        ForEach(user.sharedGenres.prefix(3), id: \.self) { GenreChip(text: $0) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button {
                    tapHaptic()
                    store.path.append(.songSearch)
                } label: {
                    Label("Recommend a song", systemImage: "music.note.list")
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(outOfRange)

                Button {
                    tapHaptic()
                    store.path.append(.meetup)
                } label: {
                    Label("Meet up", systemImage: "figure.wave")
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(outOfRange)

                Button("Not now") { store.close() }
                    .foregroundStyle(Color.secondaryText)
                    .padding(.top, 4)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
            .foregroundStyle(.white)
        }
        .background(Color.appBackground.ignoresSafeArea())
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { store.close() } label: { Image(systemName: "xmark") }
                    .accessibilityLabel("Close")
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    private var nowPlayingCard: some View {
        HStack(spacing: 14) {
            CoverArt(url: user.nowPlaying?.artworkURL)
            VStack(alignment: .leading, spacing: 4) {
                if let song = user.nowPlaying {
                    Text("NOW PLAYING")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.secondaryText)
                    Text(song.title).font(.headline).lineLimit(2)
                    Text(song.artist).font(.footnote).foregroundStyle(Color.secondaryText)
                } else {
                    Text("Not playing music right now").foregroundStyle(Color.secondaryText)
                }
            }
            Spacer(minLength: 0)
            if user.nowPlaying != nil { EqualizerView() }
        }
        .padding(16)
        .background(Color.card, in: RoundedRectangle(cornerRadius: 20))
    }

    /// Rounds to the nearest 10 m. Under 20 m: "right next to you".
    private var distanceText: String {
        if user.distanceMeters < 20 { return "right next to you" }
        let rounded = Int((user.distanceMeters / 10).rounded()) * 10
        return "\(rounded) m away"
    }

    private var genreLine: String? {
        let g = user.sharedGenres
        switch g.count {
        case 0: return nil
        case 1: return "You both like \(g[0])"
        default: return "You both like \(g[0]) and \(g[1])"
        }
    }
}

private struct PulsingRings: View {
    @State private var animate = false

    var body: some View {
        ZStack {
            ForEach(0..<2, id: \.self) { i in
                Circle()
                    .stroke(Color.mint.opacity(0.6), lineWidth: 2)
                    .frame(width: 40, height: 40)
                    .scaleEffect(animate ? 3 : 1)
                    .opacity(animate ? 0 : 0.8)
                    .animation(
                        .easeOut(duration: 2).repeatForever(autoreverses: false).delay(Double(i)),
                        value: animate
                    )
            }
            Circle().fill(Color.mint).frame(width: 20, height: 20)
        }
        .onAppear { animate = true }
    }
}

#Preview("Match") {
    NavigationStack { MatchView(match: MockData.match) }
        .environmentObject(MatchStore())
        .preferredColorScheme(.dark)
}

#Preview("No song") {
    var m = MockData.match
    m = Match(id: m.id, user: NearbyUser(id: "u", name: "Maya", distanceMeters: 15, nowPlaying: nil, sharedGenres: ["indie rock"]))
    return NavigationStack { MatchView(match: m) }
        .environmentObject(MatchStore())
        .preferredColorScheme(.dark)
}

#Preview("Out of range") {
    NavigationStack { MatchView(match: MockData.match, outOfRange: true) }
        .environmentObject(MatchStore())
        .preferredColorScheme(.dark)
}

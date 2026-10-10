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
        .brutScreen()
    }
}

struct MatchView: View {
    @EnvironmentObject var store: MatchStore
    let match: Match
    var outOfRange = false

    private var user: NearbyUser { match.user }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                header

                if outOfRange {
                    Label("\(user.name) moved out of range", systemImage: "location.slash")
                        .font(.subheadline.weight(.semibold))
                        .padding(12)
                        .frame(maxWidth: .infinity)
                        .brutCard(fill: .cubeOrange, shadow: 0)
                }

                nowPlayingCard

                if !user.sharedGenres.isEmpty {
                    HStack {
                        ForEach(user.sharedGenres.prefix(3), id: \.self) { GenreChip(text: $0) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                VStack(spacing: 6) {
                    Button {
                        tapHaptic()
                        store.path.append(.songSearch)
                    } label: {
                        Label("send a song", systemImage: "music.note.list")
                    }
                    .buttonStyle(.brutPrimary)
                    .disabled(outOfRange)

                    Button {
                        tapHaptic()
                        store.path.append(.meetup)
                    } label: {
                        Label("meet up", systemImage: "figure.wave")
                    }
                    .buttonStyle(.brutSecondary)
                    .disabled(outOfRange)
                }

                Button("not now") { store.close() }
                    .buttonStyle(BrutLinkStyle())
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .pageBackground()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { store.close() } label: { Image(systemName: "xmark").fontWeight(.bold) }
                    .accessibilityLabel("Close")
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        ZStack {
            // Scattered decoration. Positions are offsets from the centre.
            DecorStar(color: .cubeYellow, size: 34, rotation: 12).offset(x: -130, y: -40)
            DecorStar(color: .cubeOrange, size: 22, rotation: -8).offset(x: 120, y: -70)
            DecorBlob(color: .lightBlue, size: 54).offset(x: 135, y: 30)
            DecorStar(color: .cubeGreen, size: 18).offset(x: -110, y: 60)

            VStack(spacing: 8) {
                PulsingRings().frame(height: 110)

                Text("someone's near you!")
                    .font(.scribble(22))
                    .foregroundStyle(Color.cubeRed)
                    .rotationEffect(.degrees(-3))
                Text("\(user.name) is \(distanceText)")
                    .font(.system(.largeTitle, weight: .heavy))
                    .multilineTextAlignment(.center)
                    .lineSpacing(-2)
                if let genreLine {
                    Text(genreLine).foregroundStyle(Color.inkSecondary)
                }
            }
        }
        .padding(.top, 8)
    }

    private var nowPlayingCard: some View {
        HStack(spacing: 14) {
            CoverArt(url: user.nowPlaying?.artworkURL)
            VStack(alignment: .leading, spacing: 4) {
                if let song = user.nowPlaying {
                    GenreChip(text: "now playing", fill: .cubeGreen)
                    Text(song.title).font(.headline).lineLimit(2)
                    Text(song.artist).font(.footnote).foregroundStyle(Color.inkSecondary)
                } else {
                    Text("not playing music right now").foregroundStyle(Color.inkSecondary)
                }
            }
            Spacer(minLength: 0)
            if user.nowPlaying != nil { EqualizerView() }
        }
        .padding(16)
        .brutCard(radius: Brut.radiusLarge)
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
        case 1: return "you both like \(g[0])"
        default: return "you both like \(g[0]) and \(g[1])"
        }
    }
}

private struct PulsingRings: View {
    @State private var animate = false

    var body: some View {
        ZStack {
            ForEach(0..<2, id: \.self) { i in
                Circle()
                    .stroke(Color.ink, lineWidth: 2)
                    .frame(width: 40, height: 40)
                    .scaleEffect(animate ? 3 : 1)
                    .opacity(animate ? 0 : 0.8)
                    .animation(
                        .easeOut(duration: 2).repeatForever(autoreverses: false).delay(Double(i)),
                        value: animate
                    )
            }
            Circle().fill(Color.cubeGreen).frame(width: 24, height: 24)
                .overlay(Circle().stroke(Color.ink, lineWidth: Brut.border))
                .background(Circle().fill(Color.ink).offset(x: 3, y: 3))
        }
        .onAppear { animate = true }
    }
}

#Preview("Match") {
    NavigationStack { MatchView(match: MockData.match) }
        .environmentObject(MatchStore())
        .brutScreen()
}

#Preview("No song") {
    var m = MockData.match
    m = Match(id: m.id, user: NearbyUser(id: "u", name: "Maya", distanceMeters: 15, nowPlaying: nil, sharedGenres: ["indie rock"]))
    return NavigationStack { MatchView(match: m) }
        .environmentObject(MatchStore())
        .brutScreen()
}

#Preview("Out of range") {
    NavigationStack { MatchView(match: MockData.match, outOfRange: true) }
        .environmentObject(MatchStore())
        .brutScreen()
}

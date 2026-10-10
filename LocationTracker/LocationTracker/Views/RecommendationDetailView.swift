import SwiftUI

struct RecommendationDetailView: View {
    @EnvironmentObject var store: RecommendationStore
    @EnvironmentObject var matchStore: MatchStore
    @Environment(\.openURL) private var openURL

    let id: Recommendation.ID

    @State private var queued = false

    private var item: Recommendation? { store.items.first { $0.id == id } }

    /// The sender as a person we can reply to. `nil` for songs the user sent to themselves.
    private func sender(of item: Recommendation) -> NearbyUser? {
        MockData.nearbyUsers(around: MockData.defaultCenter).first { $0.id == item.senderId }
    }

    var body: some View {
        Group {
            if let item {
                content(item)
            } else {
                Text("This song is not in your playlist.").foregroundStyle(Color.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appBackground.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { store.markRead(id) }
    }

    private func content(_ item: Recommendation) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                CoverArt(url: item.song.artworkURL, size: 200)
                    .padding(.top, 8)
                VStack(spacing: 4) {
                    Text(item.song.title).font(.title.bold()).multilineTextAlignment(.center)
                    Text(item.song.artist).font(.title3).foregroundStyle(Color.secondaryText)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("SENT BY")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.secondaryText)
                    Text("\(item.senderName) · \(item.timeText)").font(.headline)
                    if !item.note.isEmpty {
                        Text("\"\(item.note)\"").italic()
                    }
                    if !item.sharedGenres.isEmpty {
                        HStack {
                            ForEach(item.sharedGenres.prefix(3), id: \.self) { GenreChip(text: $0) }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(Color.card, in: RoundedRectangle(cornerRadius: 20))

                Button {
                    tapHaptic()
                    openURL(spotifySearchURL(item.song))
                } label: {
                    Label("Open in Spotify", systemImage: "arrow.up.right.square")
                }
                .buttonStyle(PrimaryButtonStyle())

                // UI only for now.
                // TODO: add the track to the Spotify queue (POST /v1/me/player/queue).
                // Needs Spotify sign-in and a track URI.
                Button {
                    tapHaptic()
                    queued = true
                } label: {
                    Label(queued ? "Added to queue" : "Add to queue",
                          systemImage: queued ? "checkmark" : "text.badge.plus")
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(queued)

                if let user = sender(of: item) {
                    Button {
                        tapHaptic()
                        matchStore.open(user, route: .songSearch)
                    } label: {
                        Label("Send a song back", systemImage: "arrowshape.turn.up.left")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
            .foregroundStyle(.white)
        }
    }

    /// Mock songs have no Spotify link yet. Search for the song instead.
    private func spotifySearchURL(_ song: Song) -> URL {
        let query = "\(song.title) \(song.artist)"
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""
        return URL(string: "https://open.spotify.com/search/\(query)")
            ?? URL(string: "https://open.spotify.com")!
    }
}

#Preview {
    let store = RecommendationStore()
    store.clear()
    store.addSamples()
    return NavigationStack { RecommendationDetailView(id: store.items[0].id) }
        .environmentObject(store)
        .environmentObject(MatchStore())
        .preferredColorScheme(.dark)
}

import SwiftUI

struct RecommendationDetailView: View {
    @EnvironmentObject var store: RecommendationStore
    @EnvironmentObject var matchStore: MatchStore
    @EnvironmentObject var blockStore: BlockStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    let id: Recommendation.ID

    @State private var queued = false
    @State private var confirmBlock = false

    private var item: Recommendation? { store.items.first { $0.id == id } }

    /// The sender as a person we can reply to. `nil` for songs the user sent to themselves.
    private func sender(of item: Recommendation) -> NearbyUser? {
        MockData.currentUsers().first { $0.id == item.senderId }
    }

    var body: some View {
        Group {
            if let item {
                content(item)
            } else {
                Text("this song is not in your playlist.").foregroundStyle(Color.inkSecondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .pageBackground()
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { store.markRead(id) }
        .toolbar {
            // Songs the user sent to themselves have no one to block.
            if let item, item.senderId != Recommendation.selfId {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("block \(item.senderName)", systemImage: "hand.raised", role: .destructive) {
                            confirmBlock = true
                        }
                    } label: {
                        Image(systemName: "ellipsis").fontWeight(.bold)
                    }
                    .accessibilityLabel("More")
                }
            }
        }
        .confirmationDialog(
            "block \(item?.senderName ?? "this person")?",
            isPresented: $confirmBlock, titleVisibility: .visible
        ) {
            Button("block", role: .destructive) { block() }
            Button("cancel", role: .cancel) {}
        } message: {
            Text("they leave your map, you get no alerts from them, and their songs are removed.")
        }
    }

    private func block() {
        guard let item else { return }
        let senderId = item.senderId
        blockStore.block(id: senderId, name: item.senderName)
        dismiss()
        store.removeAll(from: senderId)
    }

    private func content(_ item: Recommendation) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                ZStack {
                    DecorStar(color: .cubeYellow, size: 34, rotation: 12).offset(x: -125, y: -80)
                    DecorStar(color: .cubeOrange, size: 22, rotation: -10).offset(x: 130, y: -95)
                    DecorBlob(color: .lightBlue, size: 50).offset(x: 130, y: 85)
                    CoverArt(url: item.song.artworkURL, size: 200)
                        .background(RoundedRectangle(cornerRadius: 25).fill(Color.ink).offset(x: Brut.shadowLarge, y: Brut.shadowLarge))
                }
                .padding(.top, 8)
                VStack(spacing: 4) {
                    Text(item.song.title).font(.system(.title, weight: .heavy)).multilineTextAlignment(.center)
                    Text(item.song.artist).font(.title3).foregroundStyle(Color.inkSecondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    GenreChip(text: "sent by", fill: .cubeOrange)
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
                .brutCard(radius: Brut.radiusLarge)

                Button {
                    tapHaptic()
                    openURL(spotifySearchURL(item.song))
                } label: {
                    Label("open in spotify", systemImage: "arrow.up.right.square")
                }
                .buttonStyle(.brutPrimary)

                // UI only for now.
                // TODO: add the track to the Spotify queue (POST /v1/me/player/queue).
                // Needs Spotify sign-in and a track URI.
                Button {
                    tapHaptic()
                    queued = true
                } label: {
                    Label(queued ? "added to queue" : "add to queue",
                          systemImage: queued ? "checkmark" : "text.badge.plus")
                }
                .buttonStyle(BrutButtonStyle(fill: queued ? .cubeGreen : .cubeBlue, textColor: .ink))
                .disabled(queued)

                if let user = sender(of: item) {
                    Button {
                        tapHaptic()
                        matchStore.open(user, route: .songSearch)
                    } label: {
                        Label("send a song back", systemImage: "arrowshape.turn.up.left")
                    }
                    .buttonStyle(.brutGhost)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
    }

    /// Mock songs have no Spotify link yet. Search for the song instead.
    private func spotifySearchURL(_ song: Song) -> URL {
        // Escape everything except letters, digits and - . _ ~ so a "/" in "AC/DC" cannot split the path.
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        let query = "\(song.title) \(song.artist)".addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
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
        .environmentObject(BlockStore())
        .brutScreen()
}

import SwiftUI

struct SongSearchView: View {
    @EnvironmentObject var store: MatchStore
    let user: NearbyUser

    @State private var query = ""
    @State private var results: [Song] = []
    @State private var isLoading = false
    @State private var failed = false
    @State private var selected: Song?
    @FocusState private var focused: Bool

    private var trimmed: String { query.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(Color.inkSecondary)
                TextField("search songs", text: $query)
                    .focused($focused)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
            }
            .brutInput(focused: focused)
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            content
        }
        .pageBackground()
        .navigationTitle("send to \(user.name)")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { focused = true }
        .task(id: trimmed) { await search() }
        .sheet(item: $selected) { song in
            ConfirmSongSheet(song: song, user: user) { line in
                selected = nil
                store.send(.song(song, line: line))
            }
            .presentationDetents([.height(480)])
            .brutScreen()
        }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ProgressView().frame(maxHeight: .infinity)
        } else if failed {
            VStack(spacing: 12) {
                Text("cannot search now.").font(.headline)
                Button("try again") { Task { await search() } }
                    .buttonStyle(.brutGhost)
                    .frame(width: 180)
            }
            .frame(maxHeight: .infinity)
        } else if !trimmed.isEmpty && results.isEmpty {
            VStack(spacing: 6) {
                DecorStar(color: .cubeOrange, size: 36, rotation: 8)
                Text("no songs found for \"\(trimmed)\"").font(.headline)
                Text("try a different title or artist.").foregroundStyle(Color.inkSecondary)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 20)
            .frame(maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    Text(trimmed.isEmpty ? "suggested for \(user.name)" : "results")
                        .font(.title3.weight(.bold))
                    ForEach(results) { song in
                        Button { tapHaptic(); selected = song } label: { row(song) }
                            .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }

    private func row(_ song: Song) -> some View {
        HStack(spacing: 12) {
            CoverArt(url: song.artworkURL, size: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(song.title).font(.body.weight(.semibold))
                Text(song.artist).font(.footnote).foregroundStyle(Color.inkSecondary)
            }
            Spacer()
            Image(systemName: "paperplane.fill")
                .font(.footnote)
                .foregroundStyle(Color.ink)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color.cubeRed))
                .overlay(Circle().stroke(Color.ink, lineWidth: Brut.border))
        }
        .padding(12)
        .brutCard(shadow: 0)
    }

    /// Mock search. Replace with a call to the backend (for example GET /api/search?q=).
    /// Throw an error here to show the "cannot search now." screen.
    private func fetchSongs(_ query: String) async throws -> [Song] {
        MockData.search(query)
    }

    private func search() async {
        failed = false
        if trimmed.isEmpty {
            isLoading = false
            results = Array(MockData.songs.prefix(4))
            return
        }
        isLoading = true
        do {
            try await Task.sleep(for: .milliseconds(350))   // debounce; cancelled when the query changes
            let found = try await fetchSongs(trimmed)
            guard !Task.isCancelled else { return }
            results = found
            isLoading = false
        } catch is CancellationError {
            return   // A newer search has started. It sets the loading state.
        } catch {
            failed = true
            isLoading = false
        }
    }
}

private struct ConfirmSongSheet: View {
    let song: Song
    let user: NearbyUser
    let onSend: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var line = ""
    @FocusState private var focused: Bool
    private let limit = 80

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                CoverArt(url: song.artworkURL, size: 64)
                VStack(alignment: .leading, spacing: 2) {
                    Text(song.title).font(.headline)
                    Text(song.artist).foregroundStyle(Color.inkSecondary)
                }
            }
            Text("send this song to \(user.name)?").font(.title2.weight(.heavy))

            VStack(alignment: .leading, spacing: 8) {
                Text("add a short line (optional)").font(.footnote.weight(.semibold)).foregroundStyle(Color.inkSecondary)
                TextField("this one reminds me of you", text: $line)
                    .focused($focused)
                    .brutInput(focused: focused)
                    .onChange(of: line) { _, new in if new.count > limit { line = String(new.prefix(limit)) } }
                if line.count >= 60 {
                    Text("\(line.count)/\(limit)").font(.caption).foregroundStyle(Color.inkSecondary)
                }
            }

            Button { tapHaptic(); onSend(line) } label: { Text("send to \(user.name)") }
                .buttonStyle(.brutPrimary)
            Button("cancel") { dismiss() }
                .buttonStyle(BrutLinkStyle())
                .frame(maxWidth: .infinity)
        }
        .padding(20)
        .pageBackground()
    }
}

#Preview {
    NavigationStack { SongSearchView(user: MockData.match.user) }
        .environmentObject(MatchStore())
        .brutScreen()
}

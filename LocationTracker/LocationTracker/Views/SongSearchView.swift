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
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(Color.secondaryText)
                TextField("Search songs", text: $query)
                    .focused($focused)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
            }
            .padding(14)
            .background(Color.card, in: RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            content
        }
        .foregroundStyle(.white)
        .background(Color.appBackground.ignoresSafeArea())
        .navigationTitle("Recommend to \(user.name)")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { focused = true }
        .task(id: trimmed) { await search() }
        .sheet(item: $selected) { song in
            ConfirmSongSheet(song: song, user: user) { line in
                selected = nil
                store.send(.song(song, line: line))
            }
            .presentationDetents([.medium])
            .preferredColorScheme(.dark)
        }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ProgressView().frame(maxHeight: .infinity)
        } else if failed {
            VStack(spacing: 12) {
                Text("Cannot search now.")
                Button("Try again") { Task { await search() } }
                    .buttonStyle(SecondaryButtonStyle())
                    .frame(width: 180)
            }
            .frame(maxHeight: .infinity)
        } else if !trimmed.isEmpty && results.isEmpty {
            VStack(spacing: 6) {
                Text("No songs found for \"\(trimmed)\"").font(.headline)
                Text("Try a different title or artist.").foregroundStyle(Color.secondaryText)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 20)
            .frame(maxHeight: .infinity)
        } else {
            List {
                Section {
                    ForEach(results) { song in
                        Button { tapHaptic(); selected = song } label: { row(song) }
                            .listRowBackground(Color.appBackground)
                    }
                } header: {
                    Text(trimmed.isEmpty ? "Suggested for \(user.name)" : "Results")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.secondaryText)
                        .textCase(nil)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    private func row(_ song: Song) -> some View {
        HStack(spacing: 12) {
            CoverArt(url: song.artworkURL, size: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(song.title).font(.body)
                Text(song.artist).font(.footnote).foregroundStyle(Color.secondaryText)
            }
            Spacer()
            Image(systemName: "paperplane").foregroundStyle(Color.violet)
        }
        .foregroundStyle(.white)
    }

    /// Mock search. Replace with a call to the backend (for example GET /api/search?q=).
    private func search() async {
        failed = false
        if trimmed.isEmpty {
            results = Array(MockData.songs.prefix(4))
            return
        }
        isLoading = true
        try? await Task.sleep(for: .milliseconds(350))   // debounce; cancelled when the query changes
        if Task.isCancelled { return }
        results = MockData.search(trimmed)
        isLoading = false
    }
}

private struct ConfirmSongSheet: View {
    let song: Song
    let user: NearbyUser
    let onSend: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var line = ""
    private let limit = 80

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                CoverArt(url: song.artworkURL, size: 64)
                VStack(alignment: .leading, spacing: 2) {
                    Text(song.title).font(.headline)
                    Text(song.artist).foregroundStyle(Color.secondaryText)
                }
            }
            Text("Send this song to \(user.name)?").font(.title3.bold())

            VStack(alignment: .leading, spacing: 6) {
                Text("Add a short line (optional)").font(.footnote).foregroundStyle(Color.secondaryText)
                TextField("This one reminds me of you", text: $line)
                    .padding(14)
                    .background(Color.card, in: RoundedRectangle(cornerRadius: 14))
                    .onChange(of: line) { _, new in if new.count > limit { line = String(new.prefix(limit)) } }
                if line.count >= 60 {
                    Text("\(line.count)/\(limit)").font(.caption).foregroundStyle(Color.secondaryText)
                }
            }

            Button { tapHaptic(); onSend(line) } label: { Text("Send to \(user.name)") }
                .buttonStyle(PrimaryButtonStyle())
            Button("Cancel") { dismiss() }
                .frame(maxWidth: .infinity)
                .foregroundStyle(Color.secondaryText)
        }
        .padding(20)
        .foregroundStyle(.white)
        .background(Color.appBackground.ignoresSafeArea())
    }
}

#Preview {
    NavigationStack { SongSearchView(user: MockData.match.user) }
        .environmentObject(MatchStore())
        .preferredColorScheme(.dark)
}

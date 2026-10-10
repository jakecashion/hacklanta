import SwiftUI

/// The "Playlist" tab: songs other people sent to you.
struct RecommendationsView: View {
    @EnvironmentObject var store: RecommendationStore

    var body: some View {
        NavigationStack {
            Group {
                if store.items.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .background(Color.appBackground.ignoresSafeArea())
            .navigationTitle("Songs for you")
            .toolbar {
                if store.newCount > 0 {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Mark all read") { store.markAllRead() }
                    }
                }
            }
            .navigationDestination(for: Recommendation.ID.self) { id in
                RecommendationDetailView(id: id)
            }
        }
    }

    private var list: some View {
        List {
            Section {
                ForEach(store.items) { item in
                    NavigationLink(value: item.id) { RecommendationRow(item: item) }
                        .listRowBackground(
                            RoundedRectangle(cornerRadius: 16).fill(Color.card).padding(.vertical, 4))
                        .listRowSeparator(.hidden)
                        .swipeActions {
                            Button(role: .destructive) { store.delete(item.id) } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
            } header: {
                Text(summary)
                    .font(.subheadline)
                    .foregroundStyle(Color.secondaryText)
                    .textCase(nil)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "music.note.list")
                .font(.system(size: 44))
                .foregroundStyle(Color.secondaryText)
            Text("No songs yet").font(.title3.bold())
            Text("When someone near you sends a song, it shows here.")
                .foregroundStyle(Color.secondaryText)
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var summary: String {
        let n = store.items.count
        let base = n == 1 ? "1 song" : "\(n) songs"
        return store.newCount > 0 ? "\(base) · \(store.newCount) new" : base
    }
}

private struct RecommendationRow: View {
    let item: Recommendation

    var body: some View {
        HStack(spacing: 12) {
            CoverArt(url: item.song.artworkURL, size: 56)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.song.title)
                    .font(item.isNew ? .headline : .body)
                    .lineLimit(1)
                Text(item.song.artist)
                    .font(.footnote).foregroundStyle(Color.secondaryText)
                Text("from \(item.senderName) · \(item.timeText)")
                    .font(.caption).foregroundStyle(Color.secondaryText)
                if !item.note.isEmpty {
                    Text("\"\(item.note)\"")
                        .font(.caption.italic())
                        .foregroundStyle(Color.secondaryText)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if item.isNew {
                Circle().fill(Color.mint).frame(width: 10, height: 10)
                    .accessibilityLabel("New")
            }
        }
        .foregroundStyle(.white)
        .padding(.vertical, 6)
    }
}

#Preview("With songs") {
    let store = RecommendationStore()
    store.clear()
    store.addSamples()
    return RecommendationsView()
        .environmentObject(store)
        .environmentObject(MatchStore())
        .preferredColorScheme(.dark)
}

#Preview("Empty") {
    let store = RecommendationStore()
    store.clear()
    return RecommendationsView()
        .environmentObject(store)
        .environmentObject(MatchStore())
        .preferredColorScheme(.dark)
}

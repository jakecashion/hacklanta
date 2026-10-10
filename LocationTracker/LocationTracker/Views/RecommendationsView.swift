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
            .pageBackground()
            .navigationTitle("songs for you")
            .toolbar {
                if store.newCount > 0 {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("mark all read") { store.markAllRead() }
                            .font(.subheadline.weight(.bold))
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
                    RecommendationRow(item: item)
                        .background(NavigationLink(value: item.id) { EmptyView() }.opacity(0))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 6, leading: 20, bottom: 10, trailing: 24))
                        .swipeActions {
                            Button(role: .destructive) { store.delete(item.id) } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
            } header: {
                Text(summary)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.inkSecondary)
                    .textCase(nil)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            ZStack {
                DecorStar(color: .cubeYellow, size: 30, rotation: 10).offset(x: -60, y: -30)
                DecorStar(color: .cubeOrange, size: 20, rotation: -10).offset(x: 62, y: -38)
                IconBox(systemName: "music.note.list", fill: .lightBlue, size: 72)
            }
            Text("no songs yet").font(.title2.weight(.heavy))
            Text("when someone near you sends a song, it shows here.")
                .foregroundStyle(Color.inkSecondary)
                .multilineTextAlignment(.center)
        }
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
                    .font(item.isNew ? .headline : .body.weight(.semibold))
                    .lineLimit(1)
                Text(item.song.artist)
                    .font(.footnote).foregroundStyle(Color.inkSecondary)
                Text("from \(item.senderName) · \(item.timeText)")
                    .font(.caption).foregroundStyle(Color.inkSecondary)
                if !item.note.isEmpty {
                    Text("\"\(item.note)\"")
                        .font(.caption.italic())
                        .foregroundStyle(Color.inkSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if item.isNew {
                Text("new")
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(Color.cubeGreen))
                    .overlay(Capsule().stroke(Color.ink, lineWidth: 1.5))
            }
        }
        .padding(12)
        // New songs lift off the page with a shadow. Read songs stay flat.
        .brutCard(shadow: item.isNew ? Brut.shadowMedium : 0)
    }
}

#Preview("With songs") {
    let store = RecommendationStore()
    store.clear()
    store.addSamples()
    return RecommendationsView()
        .environmentObject(store)
        .environmentObject(MatchStore())
        .brutScreen()
}

#Preview("Empty") {
    let store = RecommendationStore()
    store.clear()
    return RecommendationsView()
        .environmentObject(store)
        .environmentObject(MatchStore())
        .brutScreen()
}

import Foundation

/// The playlist of songs other people sent to the user.
/// Saved in Documents/recommendations.json. Mock delivery for now:
/// replace `receive` calls with a backend fetch and a push later.
final class RecommendationStore: ObservableObject {
    @Published private(set) var items: [Recommendation] = []

    /// Demo setting: also add the songs the user sends to the user's own playlist.
    @Published var loopbackSentSongs: Bool {
        didSet { UserDefaults.standard.set(loopbackSentSongs, forKey: Self.loopbackKey) }
    }

    /// Set by the app. Songs from a blocked sender are dropped. Not set in previews, so nobody is blocked there.
    var isBlocked: (String) -> Bool = { _ in false }

    var newCount: Int { items.filter(\.isNew).count }

    private static let loopbackKey = "loopbackSentSongs"
    private let ioQueue = DispatchQueue(label: "recommendations.io", qos: .utility)
    private let fileURL = FileManager.default
        .urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("recommendations.json")

    init() {
        loopbackSentSongs = UserDefaults.standard.object(forKey: Self.loopbackKey) as? Bool ?? true
        load()
    }

    func receive(song: Song, senderId: String, senderName: String,
                 note: String = "", sharedGenres: [String] = [], at date: Date = Date()) {
        guard senderId == Recommendation.selfId || !isBlocked(senderId) else { return }
        let item = Recommendation(song: song, senderId: senderId, senderName: senderName,
                                  note: note.trimmingCharacters(in: .whitespacesAndNewlines),
                                  sharedGenres: sharedGenres, receivedAt: date)
        items.insert(item, at: 0)
        save()
    }

    func markRead(_ id: Recommendation.ID) {
        guard let i = items.firstIndex(where: { $0.id == id }), items[i].isNew else { return }
        items[i].isNew = false
        save()
    }

    func markAllRead() {
        for i in items.indices { items[i].isNew = false }
        save()
    }

    func delete(_ id: Recommendation.ID) {
        items.removeAll { $0.id == id }
        save()
    }

    func removeAll(from senderId: String) {
        items.removeAll { $0.senderId == senderId }
        save()
    }

    func clear() {
        items = []
        save()
    }

    /// Three mock songs from mock people, for demos.
    func addSamples() {
        let people = MockData.currentUsers()
        let samples: [(Int, Song, String, TimeInterval)] = [
            (0, MockData.songs[0], "You will love this one", -300),
            (1, MockData.songs[2], "Reminded me of last night", -7_200),
            (2, MockData.songs[4], "", -90_000),
        ]
        for (index, song, note, offset) in samples.reversed() {
            let p = people[index]
            receive(song: song, senderId: p.id, senderName: p.name, note: note,
                    sharedGenres: p.sharedGenres, at: Date().addingTimeInterval(offset))
        }
    }

    // MARK: Storage

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }   // no file yet
        do {
            items = try JSONDecoder().decode([Recommendation].self, from: data)
        } catch {
            // Do not lose the user's songs: keep the unreadable file, then start with an empty list.
            print("Could not read recommendations:", error)
            let backup = fileURL.deletingLastPathComponent().appendingPathComponent("recommendations.unreadable.json")
            try? FileManager.default.removeItem(at: backup)
            try? FileManager.default.moveItem(at: fileURL, to: backup)
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        let url = fileURL
        ioQueue.async {
            do { try data.write(to: url, options: .atomic) }
            catch { print("Could not save recommendations:", error) }
        }
    }
}

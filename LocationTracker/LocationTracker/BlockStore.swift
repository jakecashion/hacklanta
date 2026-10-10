import Foundation

/// The people the user blocked. Saved in Documents/blocked.json.
/// Mock for now: when there is a backend, send the blocked ids to the server so it can filter too.
final class BlockStore: ObservableObject {
    @Published private(set) var blocked: [BlockedUser] = []

    private let ioQueue = DispatchQueue(label: "blocked.io", qos: .utility)
    private let fileURL = FileManager.default
        .urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("blocked.json")

    init() { load() }

    func isBlocked(_ id: String) -> Bool {
        blocked.contains { $0.id == id }
    }

    func block(id: String, name: String) {
        guard id != Recommendation.selfId, !isBlocked(id) else { return }
        blocked.insert(BlockedUser(id: id, name: name), at: 0)
        save()
    }

    func unblock(_ id: String) {
        blocked.removeAll { $0.id == id }
        save()
    }

    // MARK: Storage

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }   // no file yet
        do {
            blocked = try JSONDecoder().decode([BlockedUser].self, from: data)
        } catch {
            // Do not lose the user's list: keep the unreadable file, then start with an empty list.
            print("Could not read blocked list:", error)
            let backup = fileURL.deletingLastPathComponent().appendingPathComponent("blocked.unreadable.json")
            try? FileManager.default.removeItem(at: backup)
            try? FileManager.default.moveItem(at: fileURL, to: backup)
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(blocked) else { return }
        let url = fileURL
        ioQueue.async {
            do { try data.write(to: url, options: .atomic) }
            catch { print("Could not save blocked list:", error) }
        }
    }
}

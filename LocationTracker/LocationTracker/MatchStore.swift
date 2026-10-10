import SwiftUI

/// Holds the current match and the navigation path for the match flow.
/// Mock data for now. Replace `send(_:)` with a real API call later.
final class MatchStore: ObservableObject {
    @Published var match: Match?
    @Published var path: [MatchRoute] = []

    func simulateMatch() {
        path = []
        match = MockData.match
    }

    /// Open the match screen for a mock person, for example from a notification tap.
    func openMatch(userId: String) {
        let users = MockData.nearbyUsers(around: MockData.defaultCenter)
        guard let user = users.first(where: { $0.id == userId }) else { return }
        path = []
        match = Match(id: user.id, user: user)
    }

    /// Open the match flow for `user`, starting on `route`.
    func open(_ user: NearbyUser, route: MatchRoute) {
        path = [route]
        match = Match(id: user.id, user: user)
    }

    func send(_ message: OutgoingMessage) {
        guard let match else { return }
        let name = match.user.name
        print("SEND to \(name):", message)
        switch message {
        case .song(let song, _):
            path = [.sent("\(name) will see \(song.title) in their playlist.")]
        case .meetup:
            path = [.sent("\(name) will get your message.")]
        }
    }

    func close() {
        match = nil
        path = []
    }
}

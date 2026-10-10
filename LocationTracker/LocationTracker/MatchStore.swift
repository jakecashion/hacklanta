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

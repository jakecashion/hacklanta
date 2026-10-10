import SwiftUI

/// Holds the current match and the navigation path for the match flow.
/// Mock data for now. Replace `send(_:)` with a real API call later.
final class MatchStore: ObservableObject {
    @Published var match: Match?
    @Published var path: [MatchRoute] = []

    /// Called when the user sends a song: (song, short line, receiver).
    var onSongSent: ((Song, String, NearbyUser) -> Void)?

    func simulateMatch() {
        path = []
        match = MockData.match
    }

    // A full screen cover cannot show while a sheet is up. `NearbyMapView` tells the store
    // when a sheet is up, and the store waits for it to close before it runs the action.
    var isSheetUp = false
    @Published var closeSheetsToken = 0
    private var deferredAction: (() -> Void)?

    /// Run `action` now, or after the open sheet has closed.
    func whenReady(_ action: @escaping () -> Void) {
        if isSheetUp {
            deferredAction = action
            closeSheetsToken += 1
        } else {
            action()
        }
    }

    /// Call from the sheet's `onDismiss`.
    func sheetDidDismiss() {
        let action = deferredAction
        deferredAction = nil
        action?()
    }

    /// Open the match screen for a mock person, for example from a notification tap.
    func openMatch(userId: String) {
        let users = MockData.currentUsers()
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
        case .song(let song, let line):
            onSongSent?(song, line, match.user)
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

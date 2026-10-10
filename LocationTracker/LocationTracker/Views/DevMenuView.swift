import SwiftUI
import UserNotifications

/// Developer tools. Open it with the wrench button on the map.
struct DevMenuView: View {
    @EnvironmentObject var matchStore: MatchStore
    @EnvironmentObject var recommendations: RecommendationStore
    @EnvironmentObject var blockStore: BlockStore
    @Environment(\.dismiss) private var dismiss

    @State private var status: UNAuthorizationStatus = .notDetermined
    @State private var personId = MockData.match.user.id
    @State private var message: String?

    private let people = MockData.currentUsers()

    private var person: NearbyUser { people.first { $0.id == personId } ?? people[0] }

    var body: some View {
        NavigationStack {
            List {
                Section("Test person") {
                    Picker("Person", selection: $personId) {
                        ForEach(people) { Text($0.name).tag($0.id) }
                    }
                    Button(blockStore.isBlocked(person.id) ? "Unblock \(person.name)" : "Block \(person.name)") {
                        if blockStore.isBlocked(person.id) {
                            blockStore.unblock(person.id)
                        } else {
                            blockStore.block(id: person.id, name: person.name)
                            recommendations.removeAll(from: person.id)
                        }
                    }
                }

                Section {
                    LabeledContent("Permission", value: statusText)
                    if status != .authorized {
                        Button("Allow notifications") {
                            Task { await NotificationManager.shared.requestPermission(); await refresh() }
                        }
                    }
                    Button("Send test notification (5 s)") { send(after: 5) }
                    Button("Send test notification (10 s)") { send(after: 10) }
                } header: {
                    Text("Notifications")
                } footer: {
                    Text("To test a tap from the lock screen, tap the button, then lock the phone. Tap the notification to open the match screen.")
                }

                Section {
                    Toggle("Also add songs I send to my own playlist", isOn: $recommendations.loopbackSentSongs)
                    Button("Receive a song from \(person.name)") { receiveSong() }
                    Button("Add 3 sample songs") { recommendations.addSamples() }
                    Button("Clear playlist", role: .destructive) { recommendations.clear() }
                } header: {
                    Text("Playlist")
                } footer: {
                    Text("There is no server yet. Use these buttons to fill the Playlist tab.")
                }

                Section("Match flow") {
                    Button("Open match screen now") {
                        guard !blockStore.isBlocked(personId) else { message = "\(person.name) is blocked."; return }
                        let id = personId
                        matchStore.whenReady { matchStore.openMatch(userId: id) }
                    }
                }

                if let message {
                    Section { Text(message).font(.footnote).foregroundStyle(.secondary) }
                }
            }
            .scrollContentBackground(.hidden)
            .pageBackground()
            .navigationTitle("Dev menu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
            .task { await refresh() }
        }
    }

    private var statusText: String {
        switch status {
        case .authorized, .provisional, .ephemeral: "Allowed"
        case .denied: "Denied (change in Settings)"
        default: "Not asked yet"
        }
    }

    private func refresh() async {
        status = await NotificationManager.shared.authorizationStatus()
    }

    private func receiveSong() {
        guard !blockStore.isBlocked(person.id) else { message = "\(person.name) is blocked. The song was dropped."; return }
        let notes = ["You will love this one", "Reminded me of you", "On repeat all week", ""]
        recommendations.receive(
            song: MockData.songs.randomElement()!,
            senderId: person.id, senderName: person.name,
            note: notes.randomElement()!, sharedGenres: person.sharedGenres)
        message = "Added a song from \(person.name)."
    }

    private func send(after seconds: TimeInterval) {
        guard !blockStore.isBlocked(person.id) else { message = "\(person.name) is blocked. No alert sent."; return }
        Task {
            do {
                try await NotificationManager.shared.scheduleTestMatch(for: person, after: seconds)
                message = "Scheduled for \(person.name) in \(Int(seconds)) s."
            } catch {
                message = "Could not schedule: \(error.localizedDescription)"
            }
            await refresh()
        }
    }
}

#Preview {
    DevMenuView()
        .environmentObject(MatchStore())
        .environmentObject(RecommendationStore())
        .environmentObject(BlockStore())
        .brutScreen()
}

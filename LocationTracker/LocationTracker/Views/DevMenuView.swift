import SwiftUI
import UserNotifications

/// Developer tools. Open it with the wrench button on the map.
struct DevMenuView: View {
    @EnvironmentObject var matchStore: MatchStore
    @Environment(\.dismiss) private var dismiss

    @State private var status: UNAuthorizationStatus = .notDetermined
    @State private var personId = MockData.match.user.id
    @State private var message: String?

    private let people = MockData.nearbyUsers(around: MockData.defaultCenter)

    private var person: NearbyUser { people.first { $0.id == personId } ?? people[0] }

    var body: some View {
        NavigationStack {
            List {
                Section("Test person") {
                    Picker("Person", selection: $personId) {
                        ForEach(people) { Text($0.name).tag($0.id) }
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

                Section("Match flow") {
                    Button("Open match screen now") {
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            matchStore.openMatch(userId: personId)
                        }
                    }
                }

                if let message {
                    Section { Text(message).font(.footnote).foregroundStyle(.secondary) }
                }
            }
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

    private func send(after seconds: TimeInterval) {
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
    DevMenuView().environmentObject(MatchStore())
}

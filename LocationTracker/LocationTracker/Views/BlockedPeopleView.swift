import SwiftUI

/// People the user blocked. Open it from the Tracker tab.
struct BlockedPeopleView: View {
    @EnvironmentObject var blockStore: BlockStore

    var body: some View {
        Group {
            if blockStore.blocked.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        Text("they do not show on your map, send you alerts or send you songs.")
                            .foregroundStyle(Color.inkSecondary)
                        ForEach(blockStore.blocked) { person in
                            row(person)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
            }
        }
        .pageBackground()
        .navigationTitle("blocked people")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ person: BlockedUser) -> some View {
        HStack(spacing: 12) {
            IconBox(systemName: "hand.raised.fill", fill: .cubeOrange, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(person.name).font(.headline)
                Text("blocked \(person.timeText)").font(.caption).foregroundStyle(Color.inkSecondary)
            }
            Spacer(minLength: 0)
            Button("unblock") {
                tapHaptic()
                blockStore.unblock(person.id)
            }
            .buttonStyle(BrutButtonStyle(fill: .surface, textColor: .ink, fullWidth: false))
        }
        .padding(12)
        .brutCard(shadow: 0)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            ZStack {
                DecorStar(color: .cubeYellow, size: 30, rotation: 10).offset(x: -60, y: -30)
                DecorStar(color: .cubeGreen, size: 20, rotation: -10).offset(x: 62, y: -38)
                IconBox(systemName: "hand.raised", fill: .lightBlue, size: 72)
            }
            Text("no one blocked").font(.title2.weight(.heavy))
            Text("you can block someone from a song they sent you.")
                .foregroundStyle(Color.inkSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    NavigationStack { BlockedPeopleView() }
        .environmentObject(BlockStore())
        .brutScreen()
}

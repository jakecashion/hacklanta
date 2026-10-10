import SwiftUI

struct MeetupView: View {
    @EnvironmentObject var store: MatchStore
    let user: NearbyUser

    @State private var text = ""
    @State private var selectedPreset: String?
    private let limit = 140

    private let presets: [(icon: String, text: String)] = [
        ("music.note", "Your music is fire! wanna talk?"),
        ("headphones", "Wanna create a spotify blend?"),
    ]

    private var canSend: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Say hi to \(user.name)").font(.title.bold())
                    Text("Pick a message or write your own.").foregroundStyle(Color.secondaryText)
                }

                ForEach(presets, id: \.text) { preset in
                    Button {
                        tapHaptic()
                        selectedPreset = preset.text
                        text = preset.text
                    } label: {
                        HStack {
                            Image(systemName: preset.icon).frame(width: 28)
                            Text(preset.text)
                            Spacer()
                            if selectedPreset == preset.text {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.violet)
                            }
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity)
                        .background(Color.card, in: RoundedRectangle(cornerRadius: 16))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.violet, lineWidth: selectedPreset == preset.text ? 2 : 0)
                        )
                    }
                    .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Or write your own").font(.footnote).foregroundStyle(Color.secondaryText)
                    TextField("Type a message", text: $text, axis: .vertical)
                        .lineLimit(3...5)
                        .padding(14)
                        .background(Color.card, in: RoundedRectangle(cornerRadius: 14))
                        .onChange(of: text) { _, new in
                            if new.count > limit { text = String(new.prefix(limit)) }
                            if new != selectedPreset { selectedPreset = nil }
                        }
                    Text("\(text.count)/\(limit)")
                        .font(.caption).foregroundStyle(Color.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }

                Button {
                    tapHaptic()
                    store.send(.meetup(text: text.trimmingCharacters(in: .whitespacesAndNewlines)))
                } label: { Text("Send") }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!canSend)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
            .foregroundStyle(.white)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color.appBackground.ignoresSafeArea())
        .navigationTitle("Meet up")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack { MeetupView(user: MockData.match.user) }
        .environmentObject(MatchStore())
        .preferredColorScheme(.dark)
}

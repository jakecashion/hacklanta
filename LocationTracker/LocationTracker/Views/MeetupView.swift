import SwiftUI

struct MeetupView: View {
    @EnvironmentObject var store: MatchStore
    let user: NearbyUser

    @State private var text = ""
    @State private var selectedPreset: String?
    @FocusState private var focused: Bool
    private let limit = 140

    private let presets: [(icon: String, text: String)] = [
        ("music.note", "Your music is fire! wanna talk?"),
        ("headphones", "Wanna create a spotify blend?"),
    ]

    private var canSend: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ZStack(alignment: .topTrailing) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("say hi to \(user.name)").font(.system(.largeTitle, weight: .heavy))
                        Text("pick a message or write your own.").foregroundStyle(Color.inkSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    DecorStar(color: .cubeYellow, size: 26, rotation: 12).offset(x: -4, y: -14)
                }

                ForEach(presets, id: \.text) { preset in
                    let isSelected = selectedPreset == preset.text
                    Button {
                        tapHaptic()
                        selectedPreset = preset.text
                        text = preset.text
                    } label: {
                        HStack(spacing: 12) {
                            IconBox(systemName: preset.icon, fill: isSelected ? .cubeGreen : .lightBlue, size: 40)
                            Text(preset.text).font(.body.weight(.semibold)).multilineTextAlignment(.leading)
                            Spacer()
                            if isSelected { Image(systemName: "checkmark").fontWeight(.bold) }
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity)
                        // Selected card lifts (shadow). Others stay flat.
                        .brutCard(shadow: isSelected ? Brut.shadowMedium : 0)
                    }
                    .buttonStyle(.plain)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("or write your own").font(.footnote.weight(.semibold)).foregroundStyle(Color.inkSecondary)
                    TextField("type a message", text: $text, axis: .vertical)
                        .lineLimit(3...5)
                        .focused($focused)
                        .brutInput(focused: focused)
                        .onChange(of: text) { _, new in
                            if new.count > limit { text = String(new.prefix(limit)) }
                            if new != selectedPreset { selectedPreset = nil }
                        }
                    Text("\(text.count)/\(limit)")
                        .font(.caption).foregroundStyle(Color.inkSecondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }

                Button {
                    tapHaptic()
                    store.send(.meetup(text: text.trimmingCharacters(in: .whitespacesAndNewlines)))
                } label: { Text("send") }
                .buttonStyle(.brutPrimary)
                .disabled(!canSend)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .pageBackground()
        .navigationTitle("meet up")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack { MeetupView(user: MockData.match.user) }
        .environmentObject(MatchStore())
        .brutScreen()
}

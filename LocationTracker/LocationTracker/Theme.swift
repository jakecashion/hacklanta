import SwiftUI

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    static let appBackground = Color(hex: 0x0E0E12)
    static let card = Color(hex: 0x1A1A22)
    static let violet = Color(hex: 0x7C5CFF)
    static let mint = Color(hex: 0x2EE6A6)
    static let secondaryText = Color.white.opacity(0.6)
}

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(Color.violet.opacity(isEnabled ? 1 : 0.35), in: RoundedRectangle(cornerRadius: 16))
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white.opacity(isEnabled ? 1 : 0.4))
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(Color.card, in: RoundedRectangle(cornerRadius: 16))
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

struct GenreChip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.violet.opacity(0.2), in: Capsule())
    }
}

struct CoverArt: View {
    let url: URL?
    var size: CGFloat = 72

    var body: some View {
        AsyncImage(url: url) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            ZStack {
                Color.gray.opacity(0.3)
                Image(systemName: "music.note").foregroundStyle(.white.opacity(0.7))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size / 6))
    }
}

struct EqualizerView: View {
    private let barCount = 4

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.15)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(0..<barCount, id: \.self) { i in
                    let h = 6 + 14 * abs(sin(t * 3 + Double(i) * 1.3))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.mint)
                        .frame(width: 4, height: h)
                }
            }
            .frame(height: 20, alignment: .bottom)
        }
    }
}

func tapHaptic() {
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
}

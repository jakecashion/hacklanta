import SwiftUI

/// Map pin: album art in a pastel ring with an ink border, a hard shadow and a pointer tail.
/// The tail tip is the bottom of this view. Anchor it to the map coordinate with `anchor: .bottom`.
struct SongPin: View {
    let user: NearbyUser
    var isSelected = false

    private var ringColor: Color { user.distanceMeters <= 100 ? .cubeGreen : .lightBlue }

    var body: some View {
        VStack(spacing: -2) {
            CoverArt(url: user.nowPlaying?.artworkURL, size: 48)
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.ink, lineWidth: Brut.border))
                .padding(4)
                .background(Circle().fill(ringColor))
                .overlay(Circle().stroke(Color.ink, lineWidth: Brut.border))
                .background(Circle().fill(Color.ink).offset(x: Brut.shadowSmall, y: Brut.shadowSmall))
                .overlay(alignment: .topTrailing) {
                    if user.nowPlaying != nil {
                        EqualizerView()
                            .scaleEffect(0.5)
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(Color.cubeYellow))
                            .overlay(Circle().stroke(Color.ink, lineWidth: 1.5))
                            .offset(x: 6, y: -6)
                    }
                }
            PinTail()
                .fill(ringColor)
                .overlay(PinTail().stroke(Color.ink, lineWidth: Brut.border))
                .frame(width: 14, height: 10)
        }
        .scaleEffect(isSelected ? 1.25 : 1, anchor: .bottom)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isSelected)
    }
}

private struct PinTail: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

#Preview("Pins") {
    let base = MockData.nearbyUsers(around: MockData.defaultCenter)
    return HStack(spacing: 24) {
        SongPin(user: base[0])                    // near, playing
        SongPin(user: base[2])                    // far, playing
        SongPin(user: base[3])                    // no song
        SongPin(user: base[0], isSelected: true)  // selected
    }
    .padding(40)
    .pageBackground()
}

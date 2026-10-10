import SwiftUI

/// Bottom card shown when the user taps a pin.
struct NearbyUserCard: View {
    let user: NearbyUser
    let onRecommend: () -> Void
    let onMeetUp: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                CoverArt(url: user.nowPlaying?.artworkURL, size: 64)
                VStack(alignment: .leading, spacing: 4) {
                    if let song = user.nowPlaying {
                        GenreChip(text: "now playing", fill: .cubeGreen)
                        Text(song.title).font(.headline).lineLimit(2)
                        Text(song.artist).font(.footnote).foregroundStyle(Color.inkSecondary)
                    } else {
                        Text("not playing music right now").foregroundStyle(Color.inkSecondary)
                    }
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                Text("\(user.name) · \(distanceText)")
                    .font(.subheadline.weight(.bold))
                ForEach(user.sharedGenres.prefix(2), id: \.self) { GenreChip(text: $0) }
            }
            .lineLimit(1)

            HStack(spacing: 8) {
                Button { tapHaptic(); onRecommend() } label: {
                    Label("send a song", systemImage: "music.note.list")
                        .minimumScaleFactor(0.8)
                }
                .buttonStyle(.brutPrimary)
                Button { tapHaptic(); onMeetUp() } label: {
                    Label("meet up", systemImage: "figure.wave")
                        .minimumScaleFactor(0.8)
                }
                .buttonStyle(.brutSecondary)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .pageBackground()
    }

    private var distanceText: String {
        if user.distanceMeters < 20 { return "right next to you" }
        return "\(Int((user.distanceMeters / 10).rounded()) * 10) m away"
    }
}

#Preview("Playing") {
    NearbyUserCard(user: MockData.nearbyUsers(around: MockData.defaultCenter)[0], onRecommend: {}, onMeetUp: {})
        .brutScreen()
}

#Preview("No song") {
    NearbyUserCard(user: MockData.nearbyUsers(around: MockData.defaultCenter)[3], onRecommend: {}, onMeetUp: {})
        .brutScreen()
}

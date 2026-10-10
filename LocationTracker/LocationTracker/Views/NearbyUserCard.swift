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
                        Text("NOW PLAYING")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color.secondaryText)
                        Text(song.title).font(.headline).lineLimit(2)
                        Text(song.artist).font(.footnote).foregroundStyle(Color.secondaryText)
                    } else {
                        Text("Not playing music right now").foregroundStyle(Color.secondaryText)
                    }
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                Text("\(user.name) · \(distanceText) away")
                    .font(.subheadline.weight(.semibold))
                ForEach(user.sharedGenres.prefix(3), id: \.self) { GenreChip(text: $0) }
            }
            .lineLimit(1)

            HStack(spacing: 12) {
                Button { tapHaptic(); onRecommend() } label: {
                    Label("Recommend a song", systemImage: "music.note.list")
                        .minimumScaleFactor(0.8)
                }
                .buttonStyle(PrimaryButtonStyle())
                Button { tapHaptic(); onMeetUp() } label: {
                    Label("Meet up", systemImage: "figure.wave")
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
        .padding(20)
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appBackground.ignoresSafeArea())
    }

    private var distanceText: String {
        if user.distanceMeters < 20 { return "right next to you" }
        return "\(Int((user.distanceMeters / 10).rounded()) * 10) m"
    }
}

#Preview("Playing") {
    NearbyUserCard(user: MockData.nearbyUsers(around: MockData.defaultCenter)[0], onRecommend: {}, onMeetUp: {})
}

#Preview("No song") {
    NearbyUserCard(user: MockData.nearbyUsers(around: MockData.defaultCenter)[3], onRecommend: {}, onMeetUp: {})
}

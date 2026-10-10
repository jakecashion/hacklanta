import Foundation

struct Song: Identifiable, Hashable {
    let id: String
    let title: String
    let artist: String
    var artworkURL: URL? = nil
}

struct NearbyUser: Identifiable, Hashable {
    let id: String
    let name: String
    let distanceMeters: Double
    var nowPlaying: Song?
    var sharedGenres: [String]
}

struct Match: Identifiable, Hashable {
    let id: String
    let user: NearbyUser
}

enum OutgoingMessage {
    case song(Song, line: String)
    case meetup(text: String)
}

enum MatchRoute: Hashable {
    case songSearch
    case meetup
    case sent(String)   // subtitle text for SentView
}

enum MockData {
    static let match = Match(
        id: "match-1",
        user: NearbyUser(
            id: "u-maya",
            name: "Maya",
            distanceMeters: 52,
            nowPlaying: Song(id: "s0", title: "Motion Sickness", artist: "Phoebe Bridgers"),
            sharedGenres: ["indie rock", "shoegaze", "bedroom pop"]
        )
    )

    static let songs: [Song] = [
        Song(id: "s1", title: "Garden Song", artist: "Phoebe Bridgers"),
        Song(id: "s2", title: "Slow Burn", artist: "Kacey Musgraves"),
        Song(id: "s3", title: "Alison", artist: "Slowdive"),
        Song(id: "s4", title: "Cherry-coloured Funk", artist: "Cocteau Twins"),
        Song(id: "s5", title: "Dress", artist: "Wednesday"),
        Song(id: "s6", title: "Motion Sickness", artist: "Phoebe Bridgers"),
    ]

    static func search(_ query: String) -> [Song] {
        let q = query.lowercased()
        return songs.filter { $0.title.lowercased().contains(q) || $0.artist.lowercased().contains(q) }
    }
}

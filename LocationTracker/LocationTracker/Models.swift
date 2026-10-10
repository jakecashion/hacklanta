import CoreLocation
import Foundation

struct Song: Identifiable, Hashable, Codable {
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
    var latitude: Double = 0
    var longitude: Double = 0

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

struct Match: Identifiable, Hashable {
    let id: String
    let user: NearbyUser
}

/// A song someone sent to the user. Shown in the Playlist tab.
struct Recommendation: Identifiable, Codable, Hashable {
    var id = UUID()
    let song: Song
    let senderId: String
    let senderName: String
    var note: String = ""
    var sharedGenres: [String] = []
    var receivedAt = Date()
    var isNew = true

    static let selfId = "me"

    /// For example "just now" or "5 minutes ago".
    var timeText: String {
        if Date().timeIntervalSince(receivedAt) < 60 { return "just now" }
        return receivedAt.formatted(.relative(presentation: .numeric))
    }
}

/// A person the user blocked. Saved in Documents/blocked.json.
struct BlockedUser: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    var blockedAt = Date()

    /// For example "just now" or "2 days ago".
    var timeText: String {
        if Date().timeIntervalSince(blockedAt) < 60 { return "just now" }
        return blockedAt.formatted(.relative(presentation: .numeric))
    }
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
    /// Default map center (Atlanta) when the tracker has no fix yet.
    static let defaultCenter = CLLocationCoordinate2D(latitude: 33.7490, longitude: -84.3880)

    /// Where the mock people are placed. The map moves it to the real position after the first fix.
    /// Use `currentUsers()` everywhere (not `defaultCenter`) so a person has the same coordinates on every screen.
    static var center = defaultCenter

    static func currentUsers() -> [NearbyUser] { nearbyUsers(around: center) }

    static let match = Match(id: "match-1", user: nearbyUsers(around: defaultCenter)[0])

    /// Four mock people at fixed offsets (north, east in meters) from `center`.
    static func nearbyUsers(around center: CLLocationCoordinate2D) -> [NearbyUser] {
        let people: [(id: String, name: String, north: Double, east: Double, song: Song?, genres: [String])] = [
            ("u-maya", "Maya", 40, 30,
             Song(id: "s0", title: "Motion Sickness", artist: "Phoebe Bridgers"),
             ["indie rock", "shoegaze", "bedroom pop"]),
            ("u-dev", "Dev", -120, 90,
             Song(id: "s3", title: "Alison", artist: "Slowdive"),
             ["shoegaze", "dream pop"]),
            ("u-sam", "Sam", 180, -150,
             Song(id: "s5", title: "Dress", artist: "Wednesday"),
             ["indie rock"]),
            ("u-lee", "Lee", -260, -300,
             nil,
             ["bedroom pop"]),
        ]
        let metersPerDegree = 111_320.0
        return people.map { p in
            NearbyUser(
                id: p.id,
                name: p.name,
                distanceMeters: (p.north * p.north + p.east * p.east).squareRoot(),
                nowPlaying: p.song,
                sharedGenres: p.genres,
                latitude: center.latitude + p.north / metersPerDegree,
                longitude: center.longitude + p.east / (metersPerDegree * cos(center.latitude * .pi / 180))
            )
        }
    }

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

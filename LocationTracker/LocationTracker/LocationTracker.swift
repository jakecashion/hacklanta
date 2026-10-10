import CoreLocation
import Foundation

struct Fix: Codable, Identifiable {
    var id = UUID()
    let lat: Double
    let lon: Double
    let accuracy: Double
    let speed: Double
    let timestamp: Date
}

/// Highest-frequency background tracking iOS allows:
/// best accuracy + no distance filter + never auto-pause + "Always" auth.
final class LocationTracker: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = LocationTracker()

    @Published var auth: CLAuthorizationStatus = .notDetermined
    @Published var fixes: [Fix] = []   // newest first, capped for UI
    @Published var totalCount = 0
    @Published var isTracking = false

    private let manager = CLLocationManager()
    private let fileURL = FileManager.default
        .urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("fixes.jsonl")
    private let encoder = JSONEncoder()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.distanceFilter = kCLDistanceFilterNone
        manager.activityType = .otherNavigation
        manager.pausesLocationUpdatesAutomatically = false
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
        auth = manager.authorizationStatus
        // Relaunched by the system after termination? Resume immediately.
        if auth == .authorizedAlways { start() }
    }

    func requestPermission() {
        // iOS requires WhenInUse first; upgrade to Always afterwards.
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        } else {
            manager.requestAlwaysAuthorization()
        }
    }

    func start() {
        manager.startUpdatingLocation()
        // Wakes/relaunches the app after it's been killed.
        manager.startMonitoringSignificantLocationChanges()
        isTracking = true
    }

    func stop() {
        manager.stopUpdatingLocation()
        manager.stopMonitoringSignificantLocationChanges()
        isTracking = false
    }

    // MARK: CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        auth = manager.authorizationStatus
        switch auth {
        case .authorizedWhenInUse:
            manager.requestAlwaysAuthorization()
            start()
        case .authorizedAlways:
            start()
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let new = locations.map {
            Fix(lat: $0.coordinate.latitude, lon: $0.coordinate.longitude,
                accuracy: $0.horizontalAccuracy, speed: $0.speed, timestamp: $0.timestamp)
        }
        persist(new)
        DispatchQueue.main.async {
            self.totalCount += new.count
            self.fixes = Array((new.reversed() + self.fixes).prefix(200))
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location error:", error)
    }

    // MARK: Storage (append-only JSON lines in Documents/fixes.jsonl)

    private func persist(_ fixes: [Fix]) {
        var data = Data()
        for fix in fixes {
            if let line = try? encoder.encode(fix) { data += line + Data("\n".utf8) }
        }
        if let handle = try? FileHandle(forWritingTo: fileURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: fileURL)
        }
    }
}

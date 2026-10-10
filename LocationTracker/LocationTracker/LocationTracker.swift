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

/// Background location tracking for the nearby-users feature.
/// 10 m accuracy + 10 m distance filter keeps the battery use reasonable.
/// Needs "Always" authorization. Fixes are appended to Documents/fixes.jsonl.
final class LocationTracker: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = LocationTracker()

    @Published var auth: CLAuthorizationStatus = .notDetermined
    @Published var fixes: [Fix] = []   // newest first, capped for UI
    @Published var totalCount = 0
    @Published var isTracking = false

    private static let wantsTrackingKey = "locationTrackingWanted"
    private static let maxFileBytes: UInt64 = 5_000_000
    private static let maxFixAge: TimeInterval = 60

    private let manager = CLLocationManager()
    private let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    private var fileURL: URL { documents.appendingPathComponent("fixes.jsonl") }
    private var oldFileURL: URL { documents.appendingPathComponent("fixes.old.jsonl") }
    private let ioQueue = DispatchQueue(label: "locationtracker.io", qos: .utility)   // file work only
    private let encoder = JSONEncoder()
    private var needsFreshFix = true   // drop a stale cached fix right after start

    /// False after the user taps Stop. Stays false across launches until the user taps Start.
    private var userWantsTracking: Bool {
        get { UserDefaults.standard.object(forKey: Self.wantsTrackingKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Self.wantsTrackingKey) }
    }

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        manager.distanceFilter = 10
        manager.activityType = .otherNavigation
        manager.pausesLocationUpdatesAutomatically = false
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
        auth = manager.authorizationStatus
        loadSavedCount()
        // Relaunched by the system after termination? Resume, unless the user tapped Stop.
        if auth == .authorizedAlways { startIfWanted() }
    }

    func requestPermission() {
        // iOS requires WhenInUse first; upgrade to Always afterwards.
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        } else {
            manager.requestAlwaysAuthorization()
        }
    }

    /// The user taps Start.
    func start() {
        userWantsTracking = true
        beginUpdates()
    }

    /// The user taps Stop. Tracking stays off after a relaunch.
    func stop() {
        userWantsTracking = false
        endUpdates()
    }

    private func startIfWanted() {
        if userWantsTracking { beginUpdates() }
    }

    private func beginUpdates() {
        guard !isTracking else { return }
        needsFreshFix = true
        manager.startUpdatingLocation()
        // Wakes/relaunches the app after it's been killed.
        manager.startMonitoringSignificantLocationChanges()
        isTracking = true
    }

    private func endUpdates() {
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
            startIfWanted()
        case .authorizedAlways:
            startIfWanted()
        case .denied, .restricted:
            // Permission was removed. Stop, but keep the user's choice for when it comes back.
            endUpdates()
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let usable = locations.filter { location in
            guard location.horizontalAccuracy >= 0 else { return false }   // invalid fix
            if needsFreshFix, abs(location.timestamp.timeIntervalSinceNow) > Self.maxFixAge { return false }   // old cached fix
            return true
        }
        guard !usable.isEmpty else { return }
        needsFreshFix = false

        let new = usable.map {
            Fix(lat: $0.coordinate.latitude, lon: $0.coordinate.longitude,
                accuracy: $0.horizontalAccuracy, speed: $0.speed, timestamp: $0.timestamp)
        }
        persist(new)
        totalCount += new.count
        fixes = Array((new.reversed() + fixes).prefix(200))
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location error:", error)
    }

    // MARK: Storage (append-only JSON lines in Documents/fixes.jsonl)
    // All file work runs on `ioQueue`, not the main thread.

    private func persist(_ fixes: [Fix]) {
        var data = Data()
        for fix in fixes {
            if let line = try? encoder.encode(fix) { data += line + Data("\n".utf8) }
        }
        let url = fileURL, oldURL = oldFileURL
        ioQueue.async {
            let fm = FileManager.default
            // Keep the file small: when it is too big, keep one older copy.
            if let size = (try? fm.attributesOfItem(atPath: url.path))?[.size] as? UInt64,
               size > Self.maxFileBytes {
                try? fm.removeItem(at: oldURL)
                try? fm.moveItem(at: url, to: oldURL)
            }
            do {
                if let handle = try? FileHandle(forWritingTo: url) {
                    defer { try? handle.close() }
                    try handle.seekToEnd()
                    try handle.write(contentsOf: data)
                } else {
                    try data.write(to: url)
                    // Location history does not belong in iCloud backups.
                    var values = URLResourceValues()
                    values.isExcludedFromBackup = true
                    var mutableURL = url
                    try? mutableURL.setResourceValues(values)
                }
            } catch {
                print("Could not save fixes:", error)
            }
        }
    }

    /// Show the number of fixes already saved, so "Fixes recorded" does not reset at each launch.
    private func loadSavedCount() {
        let url = fileURL
        ioQueue.async {
            guard let data = try? Data(contentsOf: url) else { return }
            let count = data.reduce(0) { $1 == UInt8(ascii: "\n") ? $0 + 1 : $0 }
            DispatchQueue.main.async { self.totalCount += count }
        }
    }
}

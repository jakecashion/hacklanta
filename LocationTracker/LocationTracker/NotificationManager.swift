import UserNotifications

enum NotificationError: LocalizedError {
    case notAllowed

    var errorDescription: String? {
        "Notifications are off for this app. Turn them on in Settings."
    }
}

/// Local notifications for the match flow. The test notification uses mock data.
/// Replace with real push (APNs) later. The tap handling can stay the same.
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()
    private static let userIdKey = "userId"

    /// Called with the user id when the user taps a match notification.
    var onOpenMatch: ((String) -> Void)? {
        didSet { drainPending() }
    }
    private var pendingUserId: String?   // tap that arrived before `onOpenMatch` was set (cold launch)

    private var center: UNUserNotificationCenter { .current() }

    /// Call once at app start, so taps on cold launch reach the delegate.
    func configure() {
        center.delegate = self
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    @discardableResult
    func requestPermission() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    func scheduleTestMatch(for user: NearbyUser, after seconds: TimeInterval) async throws {
        if await authorizationStatus() == .notDetermined { await requestPermission() }
        switch await authorizationStatus() {
        case .authorized, .provisional, .ephemeral: break
        default: throw NotificationError.notAllowed
        }

        let content = UNMutableNotificationContent()
        content.title = "Someone near you"
        var body = "\(user.name) is about \(Int((user.distanceMeters / 10).rounded()) * 10) m away."
        if let genre = user.sharedGenres.first { body += " You both like \(genre)." }
        content.body = body
        content.sound = .default
        content.userInfo = [Self.userIdKey: user.id]

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, seconds), repeats: false)
        try await center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger))
    }

    // MARK: UNUserNotificationCenterDelegate

    // These methods are @MainActor on purpose. The async versions finish by calling
    // the system completion handler. If that happens off the main thread, iOS crashes with
    // "Call must be made on main thread".

    /// Show the banner even when the app is open.
    @MainActor
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    @MainActor
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        guard let id = response.notification.request.content.userInfo[Self.userIdKey] as? String else { return }
        pendingUserId = id
        drainPending()
    }

    private func drainPending() {
        guard let id = pendingUserId, let handler = onOpenMatch else { return }
        pendingUserId = nil
        handler(id)
    }
}

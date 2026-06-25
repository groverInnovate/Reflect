import Foundation
import LifeReplayCore
import OSLog
import UserNotifications

private let driftCategoryIdentifier = "FOCUS_DRIFT"
private let dailyReviewCategoryIdentifier = "DAILY_REVIEW"
private let snoozeActionIdentifier = "SNOOZE_15"
private let dismissActionIdentifier = "DISMISS"

@MainActor
final class DriftNotificationController: NSObject, UNUserNotificationCenterDelegate {
    enum AuthorizationSummary: String {
        case unavailable = "Unavailable outside app bundle"
        case notDetermined = "Not requested"
        case denied = "Denied"
        case authorized = "Allowed"
        case provisional = "Provisionally allowed"
        case ephemeral = "Ephemeral"
        case unknown = "Unknown"
    }

    private let logger = Logger(subsystem: "LifeReplayMac", category: "Notifications")
    private var isBundledApp: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    override init() {
        super.init()
        guard Bundle.main.bundleURL.pathExtension == "app" else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.setNotificationCategories([Self.driftCategory(), Self.dailyReviewCategory()])
    }

    func authorizationSummary(completion: @escaping @MainActor (AuthorizationSummary) -> Void) {
        guard isBundledApp else {
            completion(.unavailable)
            return
        }

        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let summary: AuthorizationSummary
            switch settings.authorizationStatus {
            case .notDetermined:
                summary = .notDetermined
            case .denied:
                summary = .denied
            case .authorized:
                summary = .authorized
            case .provisional:
                summary = .provisional
            case .ephemeral:
                summary = .ephemeral
            @unknown default:
                summary = .unknown
            }
            Task { @MainActor in completion(summary) }
        }
    }

    func requestAuthorizationIfNeeded(force: Bool = false) {
        guard isBundledApp else {
            logger.info("Notifications disabled while running outside an app bundle")
            return
        }

        UNUserNotificationCenter.current().getNotificationSettings { [logger] settings in
            guard force || settings.authorizationStatus == .notDetermined else {
                logger.info("Notification authorization status is \(settings.authorizationStatus.rawValue)")
                return
            }

            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
                if let error {
                    logger.error("Notification authorization failed: \(error.localizedDescription, privacy: .public)")
                } else {
                    logger.info("Notification authorization granted: \(granted)")
                }
            }
        }
    }

    func notify(driftEvent: DriftEvent) {
        guard isBundledApp else {
            logger.info("Drift notification skipped while running outside an app bundle")
            return
        }
        requestAuthorizationIfNeeded()

        sendNotification(
            identifier: "drift-\(driftEvent.timestamp.timeIntervalSince1970)",
            title: "Focus drift detected",
            body: body(for: driftEvent),
            categoryIdentifier: driftCategoryIdentifier
        )
    }

    func notifyFocusProtection(triggerName: String, previousContext: String, productiveMinutes: Int) {
        guard isBundledApp else {
            logger.info("Focus protection notification skipped while running outside an app bundle")
            return
        }
        requestAuthorizationIfNeeded()

        sendNotification(
            identifier: "focus-protection-\(Date().timeIntervalSince1970)",
            title: "Protect this focus block",
            body: "You were in \(previousContext) for \(productiveMinutes)m, then opened \(triggerName). Pause before the drift sticks.",
            categoryIdentifier: driftCategoryIdentifier
        )
    }

    func sendTestNotification() {
        guard isBundledApp else {
            logger.info("Test notification skipped while running outside an app bundle")
            return
        }
        requestAuthorizationIfNeeded()
        sendNotification(
            identifier: "test-\(Date().timeIntervalSince1970)",
            title: "Life Replay notifications work",
            body: "Drift alerts will appear here when a focus break is detected.",
            categoryIdentifier: driftCategoryIdentifier
        )
    }

    func scheduleDailyReviewReminder(hour: Int = 21, minute: Int = 30) {
        guard isBundledApp else {
            logger.info("Daily review reminder skipped while running outside an app bundle")
            return
        }
        requestAuthorizationIfNeeded()

        let content = UNMutableNotificationContent()
        content.title = "Your Life Replay is ready"
        content.body = "Open the dashboard and review what actually happened today."
        content.sound = .default
        content.categoryIdentifier = dailyReviewCategoryIdentifier

        var dateComponents = DateComponents()
        dateComponents.hour = hour
        dateComponents.minute = minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let request = UNNotificationRequest(
            identifier: "daily-review-reminder",
            content: content,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(request) { [logger] error in
            if let error {
                logger.error("Failed to schedule daily review reminder: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func sendNotification(identifier: String, title: String, body: String, categoryIdentifier: String? = nil) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        if let categoryIdentifier {
            content.categoryIdentifier = categoryIdentifier
        }

        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)

        UNUserNotificationCenter.current().add(request) { [logger] error in
            if let error {
                logger.error("Failed to schedule notification: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if response.actionIdentifier == snoozeActionIdentifier {
            let content = UNMutableNotificationContent()
            content.title = "Focus drift reminder"
            content.body = "Check whether you are back in the intended work block."
            content.sound = .default
            content.categoryIdentifier = driftCategoryIdentifier

            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 15 * 60, repeats: false)
            let request = UNNotificationRequest(
                identifier: "drift-snooze-\(Date().timeIntervalSince1970)",
                content: content,
                trigger: trigger
            )
            center.add(request)
        }
        completionHandler()
    }

    private func body(for driftEvent: DriftEvent) -> String {
        let triggers = driftEvent.triggerAppNames.isEmpty
            ? "a distracting app"
            : driftEvent.triggerAppNames.joined(separator: ", ")
        return "\(driftEvent.switchCountInWindow) switches near \(triggers)."
    }

    private static func driftCategory() -> UNNotificationCategory {
        let snooze = UNNotificationAction(
            identifier: snoozeActionIdentifier,
            title: "Snooze 15m",
            options: []
        )
        let dismiss = UNNotificationAction(
            identifier: dismissActionIdentifier,
            title: "Dismiss",
            options: []
        )
        return UNNotificationCategory(
            identifier: driftCategoryIdentifier,
            actions: [snooze, dismiss],
            intentIdentifiers: [],
            options: []
        )
    }

    private static func dailyReviewCategory() -> UNNotificationCategory {
        UNNotificationCategory(
            identifier: dailyReviewCategoryIdentifier,
            actions: [],
            intentIdentifiers: [],
            options: []
        )
    }
}

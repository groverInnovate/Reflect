import Foundation
import LifeReplayCore
import OSLog
import UserNotifications

@MainActor
final class DriftNotificationController {
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

        let content = UNMutableNotificationContent()
        content.title = "Focus drift detected"
        content.body = body(for: driftEvent)
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "drift-\(driftEvent.timestamp.timeIntervalSince1970)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { [logger] error in
            if let error {
                logger.error("Failed to schedule drift notification: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func body(for driftEvent: DriftEvent) -> String {
        let triggers = driftEvent.triggerAppNames.isEmpty
            ? "a distracting app"
            : driftEvent.triggerAppNames.joined(separator: ", ")
        return "\(driftEvent.switchCountInWindow) switches near \(triggers)."
    }
}

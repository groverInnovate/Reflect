import Foundation
import LifeReplayCore
import OSLog
import UserNotifications

@MainActor
final class DriftNotificationController {
    private let logger = Logger(subsystem: "LifeReplayMac", category: "Notifications")
    private var requestedAuthorization = false
    private var isBundledApp: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    func requestAuthorizationIfNeeded() {
        guard isBundledApp else {
            logger.info("Notifications disabled while running outside an app bundle")
            return
        }
        guard !requestedAuthorization else { return }
        requestedAuthorization = true

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { [logger] granted, error in
            if let error {
                logger.error("Notification authorization failed: \(error.localizedDescription, privacy: .public)")
            } else {
                logger.info("Notification authorization granted: \(granted)")
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

import Foundation
import OSLog
import ServiceManagement

@MainActor
final class LaunchAtLoginController {
    private let logger = Logger(subsystem: "LifeReplayMac", category: "LaunchAtLogin")

    var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    var statusDescription: String {
        switch SMAppService.mainApp.status {
        case .enabled:
            "Enabled"
        case .requiresApproval:
            "Needs Approval"
        case .notRegistered:
            "Off"
        case .notFound:
            "Unavailable"
        @unknown default:
            "Unknown"
        }
    }

    func toggle() {
        do {
            if isEnabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            logger.error("Failed to toggle launch at login: \(error.localizedDescription, privacy: .public)")
        }
    }
}

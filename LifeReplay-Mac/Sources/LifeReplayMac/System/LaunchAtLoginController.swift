import Foundation
import OSLog
import ServiceManagement

@MainActor
final class LaunchAtLoginController {
    private let logger = Logger(subsystem: "LifeReplayMac", category: "LaunchAtLogin")

    private(set) var lastError: String?

    var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    var statusDescription: String {
        if let lastError { return lastError }
        return switch SMAppService.mainApp.status {
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
            lastError = nil
        } catch {
            lastError = "Could not change launch at login: \(error.localizedDescription)"
            logger.error("Failed to toggle launch at login: \(error.localizedDescription, privacy: .public)")
        }
    }
}

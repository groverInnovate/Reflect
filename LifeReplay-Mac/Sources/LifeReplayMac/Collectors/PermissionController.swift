import AppKit
import ApplicationServices
import Foundation
import OSLog

@MainActor
final class PermissionController {
    private let logger = Logger(subsystem: "LifeReplayMac", category: "Permissions")

    var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    var diagnosticSummary: String {
        let bundle = Bundle.main
        return """
        Accessibility trusted: \(isAccessibilityTrusted)
        Bundle identifier: \(bundle.bundleIdentifier ?? "nil")
        Bundle path: \(bundle.bundleURL.path)
        Executable path: \(bundle.executableURL?.path ?? "nil")
        """
    }

    func requestAccessibilityPermission() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        logger.info("Accessibility trust check returned \(trusted)")
    }

    func openAccessibilitySettings() {
        openSettings(url: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    func openAutomationSettings() {
        openSettings(url: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")
    }

    private func openSettings(url: String) {
        guard let settingsURL = URL(string: url) else { return }
        NSWorkspace.shared.open(settingsURL)
    }
}

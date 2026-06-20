import AppKit
import ApplicationServices
import Foundation
import OSLog

@MainActor
final class WindowTitleReader {
    private let logger = Logger(subsystem: "LifeReplayMac", category: "WindowTitleReader")

    func frontWindowTitle(processIdentifier: pid_t?) -> String? {
        guard AXIsProcessTrusted(), let processIdentifier else { return nil }

        let appElement = AXUIElementCreateApplication(processIdentifier)
        var focusedWindow: CFTypeRef?
        let windowResult = AXUIElementCopyAttributeValue(
            appElement,
            "AXFocusedWindow" as CFString,
            &focusedWindow
        )

        guard windowResult == .success, let focusedWindow else {
            logger.debug("Focused window read failed with result \(windowResult.rawValue)")
            return nil
        }

        var titleValue: CFTypeRef?
        let titleResult = AXUIElementCopyAttributeValue(
            focusedWindow as! AXUIElement,
            "AXTitle" as CFString,
            &titleValue
        )

        guard titleResult == .success, let title = titleValue as? String, !title.isEmpty else {
            logger.debug("Focused window title read failed with result \(titleResult.rawValue)")
            return nil
        }

        return title
    }
}

import AppKit
import Foundation
import OSLog

@MainActor
final class BrowserDomainReader {
    private let logger = Logger(subsystem: "LifeReplayMac", category: "BrowserDomainReader")

    private(set) var lastFailure: String?
    private var retryAfter: [String: Date] = [:]

    func domainForFrontmostBrowser(bundleIdentifier: String?) -> String? {
        guard let bundleIdentifier else { return nil }

        let script: String?
        switch bundleIdentifier {
        case "com.apple.Safari":
            script = """
            tell application "Safari"
                if (count of windows) is 0 then return ""
                return URL of current tab of front window
            end tell
            """
        case "com.google.Chrome":
            script = chromeFamilyScript(applicationName: "Google Chrome")
        case "com.brave.Browser":
            script = chromeFamilyScript(applicationName: "Brave Browser")
        case "com.microsoft.edgemac":
            script = chromeFamilyScript(applicationName: "Microsoft Edge")
        case "com.vivaldi.Vivaldi":
            script = chromeFamilyScript(applicationName: "Vivaldi")
        default:
            script = nil
        }

        guard let script else { return nil }
        if let retry = retryAfter[bundleIdentifier], retry > Date() { return nil }
        guard let urlString = runAppleScript(script) else {
            retryAfter[bundleIdentifier] = Date().addingTimeInterval(30)
            return nil
        }
        lastFailure = nil
        guard !urlString.isEmpty else { return nil }
        return normalizedDomain(from: urlString)
    }

    private func chromeFamilyScript(applicationName: String) -> String {
        """
        tell application "\(applicationName)"
            if (count of windows) is 0 then return ""
            return URL of active tab of front window
        end tell
        """
    }

    private func runAppleScript(_ source: String) -> String? {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: "with timeout of 1 seconds\n" + source + "\nend timeout") else { return nil }
        let output = script.executeAndReturnError(&error)
        if let error {
            lastFailure = "Website capture unavailable. Allow this browser in System Settings → Privacy & Security → Automation. App time is still tracked."
            logger.debug("AppleScript browser read failed: \(String(describing: error), privacy: .public)")
            return nil
        }
        return output.stringValue
    }

    private func normalizedDomain(from urlString: String) -> String? {
        guard let url = URL(string: urlString), let host = url.host(percentEncoded: false) else {
            return nil
        }
        let lowercased = host.lowercased()
        if lowercased.hasPrefix("www.") {
            return String(lowercased.dropFirst(4))
        }
        return lowercased
    }
}

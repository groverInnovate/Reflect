import AppKit
import Foundation
import LifeReplayCore

@MainActor
final class DashboardWindowController: NSWindowController {
    private let store: LifeReplayStore
    private let permissions: PermissionController
    private let textView = NSTextView()
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        return formatter
    }()

    init(store: LifeReplayStore, permissions: PermissionController) {
        self.store = store
        self.permissions = permissions

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Life Replay Dashboard"
        window.center()

        super.init(window: window)
        configureContent()
        reload()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("DashboardWindowController is created in code.")
    }

    func reload() {
        textView.string = renderDashboard()
    }

    private func configureContent() {
        guard let contentView = window?.contentView else { return }

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder

        textView.isEditable = false
        textView.isSelectable = true
        textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.textContainerInset = NSSize(width: 18, height: 18)
        textView.backgroundColor = .textBackgroundColor
        scrollView.documentView = textView

        contentView.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: contentView.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
    }

    private func renderDashboard() -> String {
        let events = store.eventsForToday()
        let analysis = FocusEngine().analyze(events: events, now: Date())
        let blocks = ReplayEngine().timelineBlocks(from: analysis.sessions)
        let summary = ReplayEngine().fallbackSummary(
            blocks: blocks,
            driftEvents: analysis.driftEvents,
            focusScore: analysis.focusScore
        )

        var lines: [String] = [
            "Today - \(Date.now.formatted(date: .long, time: .omitted))",
            "",
            "Focus Score: \(analysis.focusScore)/100",
            "Events captured: \(events.count)",
            "Sessions: \(analysis.sessions.count)",
            "Drift events: \(analysis.driftEvents.count)",
            "",
            "Permissions",
            "-----------",
            "Accessibility: \(permissions.isAccessibilityTrusted ? "Allowed" : "Needs approval for window titles")",
            "Automation: macOS will ask when Safari/Chrome tab domains are first read",
            "",
            summary,
            "",
            "Timeline",
            "--------",
        ]

        if blocks.isEmpty {
            lines.append("No timeline blocks yet. Keep collection running and switch apps a bit.")
        } else {
            lines.append(contentsOf: blocks.map(renderBlock))
        }

        lines.append(contentsOf: ["", "Drift Events", "------------"])
        if analysis.driftEvents.isEmpty {
            lines.append("No drift events detected today.")
        } else {
            lines.append(contentsOf: analysis.driftEvents.map(renderDrift))
        }

        lines.append(contentsOf: ["", "Raw Events", "----------"])
        if events.isEmpty {
            lines.append("No raw events captured today.")
        } else {
            lines.append(contentsOf: events.suffix(250).map(renderEvent))
        }

        return lines.joined(separator: "\n")
    }

    private func renderBlock(_ block: TimelineBlock) -> String {
        let start = dateFormatter.string(from: block.start)
        let end = dateFormatter.string(from: block.end)
        let minutes = Int(block.end.timeIntervalSince(block.start) / 60)
        return "\(start)-\(end)  \(block.label)  \(minutes)m  [\(block.category.rawValue)]"
    }

    private func renderDrift(_ drift: DriftEvent) -> String {
        let time = dateFormatter.string(from: drift.timestamp)
        let triggers = drift.triggerAppNames.isEmpty ? "unknown trigger" : drift.triggerAppNames.joined(separator: ", ")
        let severity = Int(drift.severity * 100)
        return "\(time)  \(drift.switchCountInWindow) switches  \(severity)% severity  [\(triggers)]"
    }

    private func renderEvent(_ event: ActivityEvent) -> String {
        let time = dateFormatter.string(from: event.timestamp)
        let name = event.browserDomain ?? event.appName ?? event.appBundleID ?? "-"
        let title = event.windowTitle.map { "  -  \($0)" } ?? ""
        return "\(time)  \(event.kind.rawValue)  \(name)\(title)"
    }
}

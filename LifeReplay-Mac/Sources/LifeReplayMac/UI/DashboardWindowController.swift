import AppKit
import Foundation
import LifeReplayCore

@MainActor
final class DashboardWindowController: NSWindowController {
    private let store: LifeReplayStore
    private let permissions: PermissionController
    private let notifications: DriftNotificationController
    private var notificationSummary: DriftNotificationController.AuthorizationSummary = .unknown
    private let summaryTextView = NSTextView()
    private let timelineTextView = NSTextView()
    private let driftTextView = NSTextView()
    private let rawTextView = NSTextView()
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        return formatter
    }()

    init(store: LifeReplayStore, permissions: PermissionController, notifications: DriftNotificationController) {
        self.store = store
        self.permissions = permissions
        self.notifications = notifications

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
        notifications.authorizationSummary { [weak self] summary in
            self?.notificationSummary = summary
            self?.renderCurrentData()
        }
        renderCurrentData()
    }

    private func renderCurrentData() {
        let data = dashboardData()
        summaryTextView.string = renderSummary(data)
        timelineTextView.string = renderTimeline(data.blocks)
        driftTextView.string = renderDrifts(data.analysis.driftEvents)
        rawTextView.string = renderRawEvents(data.events)
    }

    private func configureContent() {
        guard let contentView = window?.contentView else { return }

        let tabView = NSTabView()
        tabView.translatesAutoresizingMaskIntoConstraints = false
        tabView.addTabViewItem(tab(title: "Summary", textView: summaryTextView))
        tabView.addTabViewItem(tab(title: "Timeline", textView: timelineTextView))
        tabView.addTabViewItem(tab(title: "Drift Events", textView: driftTextView))
        tabView.addTabViewItem(tab(title: "Raw Events", textView: rawTextView))

        contentView.addSubview(tabView)
        NSLayoutConstraint.activate([
            tabView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            tabView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            tabView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            tabView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),
        ])
    }

    private func tab(title: String, textView: NSTextView) -> NSTabViewItem {
        let item = NSTabViewItem()
        item.label = title

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder

        textView.isEditable = false
        textView.isSelectable = true
        textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.textContainerInset = NSSize(width: 18, height: 18)
        textView.backgroundColor = .textBackgroundColor
        scrollView.documentView = textView

        item.view = scrollView
        return item
    }

    private func dashboardData() -> DashboardData {
        let events = store.eventsForToday()
        let analysis = store.makeFocusEngine().analyze(events: events, now: Date())
        let blocks = ReplayEngine().timelineBlocks(from: analysis.sessions, events: events, now: Date())
        let savedReplay = store.existingDailyReplay()
        let summary = ReplayEngine().fallbackSummary(
            blocks: blocks,
            driftEvents: analysis.driftEvents,
            focusScore: analysis.focusScore
        )
        return DashboardData(events: events, analysis: analysis, blocks: blocks, savedReplay: savedReplay, fallbackSummary: summary)
    }

    private func renderSummary(_ data: DashboardData) -> String {
        let lines: [String] = [
            "Today - \(Date.now.formatted(date: .long, time: .omitted))",
            "",
            "Focus Score: \(data.analysis.focusScore)/100",
            "Events captured: \(data.events.count)",
            "Sessions: \(data.analysis.sessions.count)",
            "Drift events: \(data.analysis.driftEvents.count)",
            "Saved replay: \(data.savedReplay.map { "Generated \($0.generatedAt.formatted(date: .omitted, time: .shortened))" } ?? "Not generated yet")",
            "",
            "Permissions",
            "-----------",
            "Accessibility: \(permissions.isAccessibilityTrusted ? "Allowed" : "Needs approval for window titles")",
            "Notifications: \(notificationSummary.rawValue)",
            "Automation: macOS will ask when Safari/Chrome tab domains are first read",
            "",
            data.savedReplay?.narrativeSummary ?? data.fallbackSummary,
        ]
        return lines.joined(separator: "\n")
    }

    private func renderTimeline(_ blocks: [TimelineBlock]) -> String {
        if blocks.isEmpty {
            return "No timeline blocks yet. Keep collection running and switch apps a bit."
        }
        return blocks.map(renderBlock).joined(separator: "\n")
    }

    private func renderDrifts(_ drifts: [DriftEvent]) -> String {
        if drifts.isEmpty {
            return "No drift events detected today."
        }
        return drifts.map(renderDrift).joined(separator: "\n")
    }

    private func renderRawEvents(_ events: [ActivityEvent]) -> String {
        if events.isEmpty {
            return "No raw events captured today."
        }
        return events.suffix(250).map(renderEvent).joined(separator: "\n")
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

private struct DashboardData {
    var events: [ActivityEvent]
    var analysis: FocusAnalysis
    var blocks: [TimelineBlock]
    var savedReplay: DailyReplay?
    var fallbackSummary: String
}

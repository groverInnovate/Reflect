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
    private let insightsTextView = NSTextView()
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
        summaryTextView.string = renderDailyReview(data)
        timelineTextView.string = renderTimeline(data.blocks)
        driftTextView.string = renderFocusBreaks(data.analysis.driftEvents, insights: data.insights)
    }

    private func configureContent() {
        guard let contentView = window?.contentView else { return }

        let tabView = NSTabView()
        tabView.translatesAutoresizingMaskIntoConstraints = false
        tabView.addTabViewItem(tab(title: "Daily Review", textView: summaryTextView))
        tabView.addTabViewItem(tab(title: "Activity Timeline", textView: timelineTextView))
        tabView.addTabViewItem(tab(title: "Focus Breaks", textView: driftTextView))

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
        let insights = ReplayEngine().insightReport(
            blocks: blocks,
            driftEvents: analysis.driftEvents,
            focusScore: analysis.focusScore
        )
        return DashboardData(events: events, analysis: analysis, blocks: blocks, savedReplay: savedReplay, insights: insights)
    }

    private func renderDailyReview(_ data: DashboardData) -> String {
        let insights = data.insights
        var lines: [String] = [
            "Daily Review - \(Date.now.formatted(date: .long, time: .omitted))",
            "",
            "Focus Score: \(insights.focusScore)/100 - \(focusQuality(insights.focusScore))",
            "Tracked time: \(formatMinutes(insights.totalTrackedMinutes))",
            "Productive: \(formatMinutes(insights.productiveMinutes))    Study/research: \(formatMinutes(insights.studyLikeMinutes))    Coding/tooling: \(formatMinutes(insights.codingLikeMinutes))",
            "Wasted/distraction: \(formatMinutes(insights.distractingMinutes))    Idle/away: \(formatMinutes(insights.idleMinutes))",
            "Deep work: \(formatMinutes(insights.deepWorkMinutes))    Fragmented productive: \(formatMinutes(insights.fragmentedProductiveMinutes))",
            "Focus breaks: \(insights.driftCount)",
            "",
            "Where Time Went",
            "---------------",
        ]

        if insights.topActivities.isEmpty {
            lines.append("No meaningful activity blocks yet. Keep collection running during a real session.")
        } else {
            lines += insights.topActivities.map(renderActivityLine)
        }

        lines += [
            "",
            "Focus Story",
            "-----------",
            "Best block: \(insights.longestProductiveBlockLabel ?? "none detected")\(insights.longestProductiveBlockMinutes.map { " for \(formatMinutes($0))" } ?? "")",
            "Main productive threads: \(insights.topProductiveLabels.isEmpty ? "none detected" : insights.topProductiveLabels.joined(separator: ", "))",
            "Main distractions: \(insights.topDistractions.isEmpty ? "none detected" : insights.topDistractions.joined(separator: ", "))",
            "",
            "Journal",
            "-------",
            data.savedReplay?.narrativeSummary ?? insights.journalSummary,
            "",
            "What To Do Next",
            "---------------",
            insights.nextAction,
            "",
            "Protection Status",
            "-----------------",
            "Accessibility: \(permissions.isAccessibilityTrusted ? "Allowed" : "Needs approval for window titles")",
            "Notifications: \(notificationSummary.rawValue)",
            "Drift alerts: \(notificationAdvice())",
        ]
        return lines.joined(separator: "\n")
    }

    private func renderInsights(_ insights: DailyInsightReport) -> String {
        var lines: [String] = [
            "Time Breakdown",
            "--------------",
            "Productive:   \(formatMinutes(insights.productiveMinutes))",
            "Study-like:   \(formatMinutes(insights.studyLikeMinutes))",
            "Coding-like:  \(formatMinutes(insights.codingLikeMinutes))",
            "Deep work:    \(formatMinutes(insights.deepWorkMinutes))",
            "Fragmented productive: \(formatMinutes(insights.fragmentedProductiveMinutes))",
            "Distracting/Wasted: \(formatMinutes(insights.distractingMinutes))",
            "Neutral:      \(formatMinutes(insights.neutralMinutes))",
            "Idle/Away:    \(formatMinutes(insights.idleMinutes))",
            "Tracked:      \(formatMinutes(insights.totalTrackedMinutes))",
            "",
            "Focus",
            "-----",
            "Score: \(insights.focusScore)/100",
            "Drift events: \(insights.driftCount)",
            "Best block: \(insights.longestProductiveBlockLabel ?? "none")\(insights.longestProductiveBlockMinutes.map { " (\(formatMinutes($0)))" } ?? "")",
            "Top productive threads: \(insights.topProductiveLabels.isEmpty ? "none detected" : insights.topProductiveLabels.joined(separator: ", "))",
            "Top distractions: \(insights.topDistractions.isEmpty ? "none detected" : insights.topDistractions.joined(separator: ", "))",
            "",
            "Journal",
            "-------",
            insights.journalSummary,
            "",
            "Observations",
            "------------",
        ]
        lines += insights.observations.map { "- \($0)" }
        lines += [
            "",
            "Next Action",
            "-----------",
            insights.nextAction,
        ]
        return lines.joined(separator: "\n")
    }

    private func renderTimeline(_ blocks: [TimelineBlock]) -> String {
        if blocks.isEmpty {
            return "No timeline blocks yet. Keep collection running and switch apps a bit."
        }
        var lines = [
            "Activity Timeline",
            "-----------------",
            "This is the compact replay of what the Mac observed today.",
            "",
        ]
        lines += blocks.map(renderBlock)
        return lines.joined(separator: "\n")
    }

    private func renderFocusBreaks(_ drifts: [DriftEvent], insights: DailyInsightReport) -> String {
        var lines = [
            "Focus Breaks",
            "------------",
            "Notifications: \(notificationSummary.rawValue)",
            notificationAdvice(),
            "",
        ]

        if drifts.isEmpty {
            lines += [
                "No focus breaks detected today.",
                "",
                "If this was a real work/study session, that means the app did not see a sustained productive block followed by distracting switching.",
                "If you were distracted but nothing appeared here, use Edit Categories to mark the distracting app or domain correctly.",
            ]
            return lines.joined(separator: "\n")
        }

        lines += [
            "Detected \(drifts.count) focus break\(drifts.count == 1 ? "" : "s") today.",
            "Worst visible trigger: \(insights.worstDriftTrigger?.isEmpty == false ? insights.worstDriftTrigger! : "unknown")",
            "",
        ]
        lines += drifts.map(renderDrift)
        return lines.joined(separator: "\n")
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
        let detail = block.detail.map { " - \($0)" } ?? ""
        return "\(start)-\(end)  \(formatMinutes(minutes))  \(categoryLabel(block.category))  \(block.label)\(detail)"
    }

    private func renderDrift(_ drift: DriftEvent) -> String {
        let time = dateFormatter.string(from: drift.timestamp)
        let triggers = drift.triggerAppNames.isEmpty ? "unknown trigger" : drift.triggerAppNames.joined(separator: ", ")
        let severity = Int(drift.severity * 100)
        return "\(time)  \(drift.switchCountInWindow) switches  \(severity)% severity  Trigger: \(triggers)"
    }

    private func renderEvent(_ event: ActivityEvent) -> String {
        let time = dateFormatter.string(from: event.timestamp)
        let name = event.browserDomain ?? event.appName ?? event.appBundleID ?? "-"
        let title = event.windowTitle.map { "  -  \($0)" } ?? ""
        return "\(time)  \(event.kind.rawValue)  \(name)\(title)"
    }

    private func formatMinutes(_ minutes: Int) -> String {
        if minutes < 60 {
            return "\(minutes)m"
        }
        let hours = minutes / 60
        let remainder = minutes % 60
        return remainder == 0 ? "\(hours)h" : "\(hours)h \(remainder)m"
    }

    private func renderActivityLine(_ item: ActivityBreakdownItem) -> String {
        "\(formatMinutes(item.minutes))  \(categoryLabel(item.category))  \(item.label)"
    }

    private func categoryLabel(_ category: FocusCategory) -> String {
        switch category {
        case .productive:
            "Productive"
        case .neutral:
            "Neutral"
        case .distracting:
            "Distracting"
        }
    }

    private func focusQuality(_ score: Int) -> String {
        switch score {
        case 80...100:
            "strong day"
        case 60..<80:
            "useful, with room to tighten focus"
        case 40..<60:
            "mixed day; distractions or fragmentation were visible"
        default:
            "needs protection before distracting apps/sites open"
        }
    }

    private func notificationAdvice() -> String {
        switch notificationSummary {
        case .authorized, .provisional, .ephemeral:
            "Life Replay can warn you when a productive session starts drifting toward distracting apps or domains."
        case .denied:
            "Notifications are denied, so Life Replay can detect drift but cannot interrupt it. Enable notifications from the menu to get prevention alerts."
        case .unavailable:
            "Notifications are only available from the signed .app bundle, not when running the raw executable."
        case .notDetermined:
            "Notifications have not been approved yet. Use the menu notification action so drift alerts can interrupt distractions."
        case .unknown:
            "Notification status is still being checked."
        }
    }
}

private struct DashboardData {
    var events: [ActivityEvent]
    var analysis: FocusAnalysis
    var blocks: [TimelineBlock]
    var savedReplay: DailyReplay?
    var insights: DailyInsightReport
}

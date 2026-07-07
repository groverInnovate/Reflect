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
    private let refreshButton = NSButton(title: "Refresh Today's Review", target: nil, action: nil)
    private let repairButton = NSButton(title: "Repair Sleep Gaps", target: nil, action: nil)
    private let reviewStatusLabel = NSTextField(labelWithString: "")
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
        window.backgroundColor = DashboardStyle.windowBackground
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
        applyStyledReport(renderDailyReview(data), to: summaryTextView)
        applyStyledReport(renderTimeline(data.blocks), to: timelineTextView)
        applyStyledReport(renderFocusBreaks(data.analysis.driftEvents, insights: data.insights), to: driftTextView)
    }

    private func configureContent() {
        guard let contentView = window?.contentView else { return }

        let stackView = NSStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.orientation = .vertical
        stackView.spacing = 12

        let headerView = NSStackView()
        headerView.orientation = .horizontal
        headerView.alignment = .centerY
        headerView.spacing = 12

        refreshButton.target = self
        refreshButton.action = #selector(refreshTodayReview)
        refreshButton.bezelStyle = .rounded
        refreshButton.controlSize = .large

        repairButton.target = self
        repairButton.action = #selector(repairSleepGaps)
        repairButton.bezelStyle = .rounded
        repairButton.controlSize = .large

        reviewStatusLabel.font = .systemFont(ofSize: 12, weight: .medium)
        reviewStatusLabel.textColor = DashboardStyle.secondaryText
        reviewStatusLabel.lineBreakMode = .byTruncatingTail

        headerView.addArrangedSubview(refreshButton)
        headerView.addArrangedSubview(repairButton)
        headerView.addArrangedSubview(reviewStatusLabel)
        headerView.setHuggingPriority(.defaultLow, for: .horizontal)
        reviewStatusLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let tabView = NSTabView()
        tabView.translatesAutoresizingMaskIntoConstraints = false
        tabView.addTabViewItem(tab(title: "Daily Review", textView: summaryTextView))
        tabView.addTabViewItem(tab(title: "Activity Timeline", textView: timelineTextView))
        tabView.addTabViewItem(tab(title: "Focus Breaks", textView: driftTextView))

        stackView.addArrangedSubview(headerView)
        stackView.addArrangedSubview(tabView)
        contentView.addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            stackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            stackView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 14),
            stackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),
            tabView.heightAnchor.constraint(greaterThanOrEqualToConstant: 480),
        ])
    }

    @objc private func refreshTodayReview() {
        refreshButton.isEnabled = false
        repairButton.isEnabled = false
        reviewStatusLabel.stringValue = "Generating today's review..."
        Task { @MainActor in
            let replay = await store.generateDailyReplayWithNarrative()
            reviewStatusLabel.stringValue = replay.map {
                "Updated \($0.generatedAt.formatted(date: .omitted, time: .shortened))"
            } ?? "Could not generate review"
            refreshButton.isEnabled = true
            repairButton.isEnabled = true
            reload()
        }
    }

    @objc private func repairSleepGaps() {
        refreshButton.isEnabled = false
        repairButton.isEnabled = false
        reviewStatusLabel.stringValue = "Repairing suspicious gaps..."

        let result = store.repairTodaySleepGaps()
        if result.repairedIntervals == 0 {
            reviewStatusLabel.stringValue = "No repairable gaps found"
        } else {
            reviewStatusLabel.stringValue = "Repaired \(result.repairedIntervals) gap\(result.repairedIntervals == 1 ? "" : "s")"
        }
        refreshButton.isEnabled = true
        repairButton.isEnabled = true
        reload()
    }

    private func tab(title: String, textView: NSTextView) -> NSTabViewItem {
        let item = NSTabViewItem()
        item.label = title

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = DashboardStyle.reportBackground

        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.font = DashboardStyle.bodyFont
        textView.textContainerInset = NSSize(width: 28, height: 26)
        textView.backgroundColor = DashboardStyle.reportBackground
        textView.textColor = DashboardStyle.primaryText
        scrollView.documentView = textView

        item.view = scrollView
        return item
    }

    private func dashboardData() -> DashboardData {
        let events = store.eventsForToday()
        let analysis = store.makeFocusEngine().analyze(events: events, now: Date())
        let blocks = ReplayEngine().timelineBlocks(
            from: analysis.sessions,
            events: events,
            resolver: CategoryResolver(seeds: store.categorySeeds()),
            now: Date()
        )
        let savedReplay = store.existingDailyReplay()
        let insights = ReplayEngine().insightReport(
            blocks: blocks,
            driftEvents: analysis.driftEvents,
            focusScore: analysis.focusScore
        )
        let health = trackingHealth(events: events, insights: insights)
        return DashboardData(
            events: events,
            analysis: analysis,
            blocks: blocks,
            savedReplay: savedReplay,
            insights: insights,
            trackingHealth: health
        )
    }

    private func renderDailyReview(_ data: DashboardData) -> String {
        let insights = data.insights
        var lines: [String] = [
            "Life Replay",
            "Daily Review - \(Date.now.formatted(date: .long, time: .omitted))",
            "",
            "Today's Numbers",
            "---------------",
            "Focus Score: \(insights.focusScore)/100 - \(focusQuality(insights.focusScore))",
            "Active observed: \(formatMinutes(max(0, insights.totalTrackedMinutes - insights.idleMinutes)))    Idle/away: \(formatMinutes(insights.idleMinutes))",
            "Productive: \(formatMinutes(insights.productiveMinutes))    Study/research: \(formatMinutes(insights.studyLikeMinutes))    Coding/tooling: \(formatMinutes(insights.codingLikeMinutes))",
            "Wasted/distraction: \(formatMinutes(insights.distractingMinutes))    Neutral/unclassified: \(formatMinutes(insights.neutralMinutes))",
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

        if !insights.dataQualityWarnings.isEmpty {
            lines += [
                "",
                "Accuracy Notes",
                "--------------",
            ]
            lines += insights.dataQualityWarnings.map { "Check: \($0)" }
            lines.append("Use Repair Sleep Gaps if this warning came from Mac sleep or lid-close time.")
        }

        if !insights.calibrationSuggestions.isEmpty {
            lines += [
                "",
                "Calibration Suggestions",
                "-----------------------",
            ]
            lines += insights.calibrationSuggestions.map { "Tune: \($0)" }
        }

        lines += [
            "",
            "Tracking Health",
            "---------------",
            "Health: \(data.trackingHealth.confidence) - \(data.trackingHealth.summary)",
            "Events today: \(data.trackingHealth.totalEvents)    Browser tab captures: \(data.trackingHealth.browserDomainEvents)    Window titles: \(data.trackingHealth.windowTitleEvents)",
            "Last signal: \(data.trackingHealth.lastSignalText)",
        ]
        lines += data.trackingHealth.actions.map { "Action: \($0)" }

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
            "Today - \(Date.now.formatted(date: .long, time: .omitted))",
            "-----------------",
            "This is the compact replay of what the Mac observed today. Rapid sub-minute switches are grouped for readability.",
            "",
        ]
        lines += compactTimelineForDisplay(blocks).map(renderBlock)
        return lines.joined(separator: "\n")
    }

    private func renderFocusBreaks(_ drifts: [DriftEvent], insights: DailyInsightReport) -> String {
        var lines = [
            "Focus Breaks",
            "Today - \(Date.now.formatted(date: .long, time: .omitted))",
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

    private func compactTimelineForDisplay(_ blocks: [TimelineBlock]) -> [TimelineBlock] {
        var compacted: [TimelineBlock] = []
        var microRun: [TimelineBlock] = []

        func flushMicroRun() {
            guard !microRun.isEmpty else { return }
            if microRun.count == 1 {
                compacted.append(microRun[0])
            } else {
                let labels = Array(Set(microRun.map(\.label))).sorted()
                compacted.append(TimelineBlock(
                    start: microRun[0].start,
                    end: microRun[microRun.count - 1].end,
                    label: "Mixed \(categoryLabel(microRun[0].category).lowercased()) activity",
                    category: microRun[0].category,
                    detail: labels.joined(separator: ", ")
                ))
            }
            microRun.removeAll()
        }

        for block in blocks {
            let duration = block.end.timeIntervalSince(block.start)
            if duration < 60, block.label != "Idle period" {
                if let last = microRun.last, last.category != block.category {
                    flushMicroRun()
                }
                microRun.append(block)
            } else {
                flushMicroRun()
                compacted.append(block)
            }
        }
        flushMicroRun()
        return compacted
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

    private func trackingHealth(events: [ActivityEvent], insights: DailyInsightReport) -> TrackingHealthReport {
        let activeObservedMinutes = max(0, insights.totalTrackedMinutes - insights.idleMinutes)
        let activeEvents = events.filter { $0.kind == .appActivated || $0.kind == .browserDomain }
        let browserDomainEvents = events.filter { $0.kind == .browserDomain }.count
        let windowTitleEvents = events.filter { $0.windowTitle?.isEmpty == false }.count
        let browserAppEvents = events.filter(isBrowserAppEvent).count
        let idleStarts = events.filter { $0.kind == .idleStart }.count
        let idleEnds = events.filter { $0.kind == .idleEnd }.count
        let neutralShare = activeObservedMinutes == 0
            ? 0
            : Double(insights.neutralMinutes) / Double(max(1, activeObservedMinutes))
        let lastEvent = events.last?.timestamp

        var actions: [String] = []
        var confidence = "Good"
        var summary = "Tracking is healthy enough to judge the day."

        if events.isEmpty {
            confidence = "No data"
            summary = "Life Replay has not captured activity today."
            actions.append("Leave the menu bar app running during a real work or study session.")
        }

        if !permissions.isAccessibilityTrusted {
            confidence = maxRisk(confidence, "Needs setup")
            summary = "Window titles are missing, so notes, PDFs, and browser context may be under-labeled."
            actions.append("Approve Accessibility for LifeReplayMac, then quit and reopen the app.")
        }

        if browserAppEvents > 0, browserDomainEvents == 0 {
            confidence = maxRisk(confidence, "Needs setup")
            summary = "A browser was visible, but active tab domains were not captured."
            actions.append("Use Capture Current Browser Tab from the menu and approve the Automation prompt.")
        }

        if activeObservedMinutes >= 60, activeEvents.count < 8 {
            confidence = maxRisk(confidence, "Low")
            summary = "The day has a long active block with very few switching signals."
            actions.append("Keep the app running continuously; if the Mac slept, run Repair Sleep Gaps.")
        }

        if neutralShare >= 0.35 {
            confidence = maxRisk(confidence, "Medium")
            summary = "A large share of visible time is neutral or unclassified."
            actions.append("Open Edit Categories and classify the top neutral apps/domains from Where Time Went.")
        }

        if idleStarts != idleEnds {
            confidence = maxRisk(confidence, "Medium")
            summary = "An idle interval is still open or partially repaired."
            actions.append("Refresh after you return, or use Repair Sleep Gaps if this came from lid-close time.")
        }

        switch notificationSummary {
        case .denied:
            confidence = maxRisk(confidence, "Medium")
            actions.append("Enable notifications so drift protection can interrupt distractions in real time.")
        case .unavailable:
            actions.append("Use the signed .app bundle for notification and permission testing.")
        default:
            break
        }

        if !insights.dataQualityWarnings.isEmpty {
            confidence = maxRisk(confidence, "Medium")
        }

        if actions.isEmpty {
            actions.append("No immediate calibration needed. Review the timeline against your memory tonight.")
        }

        return TrackingHealthReport(
            confidence: confidence,
            summary: summary,
            totalEvents: events.count,
            browserDomainEvents: browserDomainEvents,
            windowTitleEvents: windowTitleEvents,
            lastSignalText: lastEvent.map(relativeSignalText) ?? "none today",
            actions: Array(actions.prefix(4))
        )
    }

    private func isBrowserAppEvent(_ event: ActivityEvent) -> Bool {
        let candidates = [
            event.appName,
            event.appBundleID,
            event.windowTitle,
        ].compactMap { $0?.lowercased() }
        let browserTerms = ["safari", "chrome", "brave", "edge", "vivaldi", "firefox", "arc"]
        return candidates.contains { value in
            browserTerms.contains { value.contains($0) }
        }
    }

    private func relativeSignalText(_ date: Date) -> String {
        let seconds = max(0, Int(Date().timeIntervalSince(date)))
        if seconds < 60 {
            return "just now"
        }
        if seconds < 60 * 60 {
            return "\(seconds / 60)m ago"
        }
        return "\(seconds / 3600)h \((seconds % 3600) / 60)m ago"
    }

    private func maxRisk(_ current: String, _ candidate: String) -> String {
        let order = ["Good": 0, "Medium": 1, "Low": 2, "Needs setup": 3, "No data": 4]
        return (order[candidate, default: 0] > order[current, default: 0]) ? candidate : current
    }

    private func applyStyledReport(_ report: String, to textView: NSTextView) {
        let styled = NSMutableAttributedString()
        let lines = report.components(separatedBy: "\n")

        for (index, line) in lines.enumerated() {
            let attributes = attributes(for: line, at: index, previousLine: index > 0 ? lines[index - 1] : nil)
            styled.append(NSAttributedString(string: line, attributes: attributes))
            if index < lines.count - 1 {
                styled.append(NSAttributedString(string: "\n", attributes: DashboardStyle.bodyAttributes))
            }
        }

        textView.textStorage?.setAttributedString(styled)
    }

    private func attributes(for line: String, at index: Int, previousLine: String?) -> [NSAttributedString.Key: Any] {
        var attributes = DashboardStyle.bodyAttributes

        if index == 0 {
            attributes[.font] = DashboardStyle.titleFont
            attributes[.foregroundColor] = DashboardStyle.titleText
            attributes[.paragraphStyle] = DashboardStyle.titleParagraphStyle
            return attributes
        }

        if index == 1, previousLine == "Life Replay" {
            attributes[.font] = DashboardStyle.subtitleFont
            attributes[.foregroundColor] = DashboardStyle.secondaryText
            attributes[.paragraphStyle] = DashboardStyle.subtitleParagraphStyle
            return attributes
        }

        if line.allSatisfy({ $0 == "-" }), !line.isEmpty {
            attributes[.foregroundColor] = DashboardStyle.separator
            return attributes
        }

        if isSectionHeader(line: line) {
            attributes[.font] = DashboardStyle.sectionFont
            attributes[.foregroundColor] = DashboardStyle.titleText
            attributes[.paragraphStyle] = DashboardStyle.sectionParagraphStyle
            return attributes
        }

        if line.contains("Productive") || line.contains("strong day") {
            attributes[.foregroundColor] = DashboardStyle.productiveText
        } else if line.contains("Distracting") || line.contains("Wasted") || line.contains("Denied") || line.contains("focus break") || line.hasPrefix("Check:") || line.contains("Needs setup") || line.contains("Low") {
            attributes[.foregroundColor] = DashboardStyle.distractingText
        } else if line.hasPrefix("Tune:") || line.hasPrefix("Action:") || line.contains("Health:") {
            attributes[.foregroundColor] = DashboardStyle.accentText
        } else if line.contains("Idle") || line.contains("Neutral") {
            attributes[.foregroundColor] = DashboardStyle.neutralText
        } else if line.contains("Focus Score") || line.contains("Tracked time") || line.contains("Notifications") {
            attributes[.font] = DashboardStyle.emphasisFont
            attributes[.foregroundColor] = DashboardStyle.accentText
        }

        return attributes
    }

    private func isSectionHeader(line: String) -> Bool {
        [
            "Where Time Went",
            "Accuracy Notes",
            "Today's Numbers",
            "Calibration Suggestions",
            "Tracking Health",
            "Focus Story",
            "Journal",
            "What To Do Next",
            "Protection Status",
            "Activity Timeline",
            "Focus Breaks",
        ].contains(line)
    }
}

private struct DashboardData {
    var events: [ActivityEvent]
    var analysis: FocusAnalysis
    var blocks: [TimelineBlock]
    var savedReplay: DailyReplay?
    var insights: DailyInsightReport
    var trackingHealth: TrackingHealthReport
}

private struct TrackingHealthReport {
    var confidence: String
    var summary: String
    var totalEvents: Int
    var browserDomainEvents: Int
    var windowTitleEvents: Int
    var lastSignalText: String
    var actions: [String]
}

@MainActor
private enum DashboardStyle {
    static let windowBackground = NSColor(calibratedRed: 0.94, green: 0.95, blue: 0.96, alpha: 1)
    static let reportBackground = NSColor(calibratedRed: 0.985, green: 0.985, blue: 0.975, alpha: 1)
    static let titleText = NSColor(calibratedRed: 0.08, green: 0.10, blue: 0.12, alpha: 1)
    static let primaryText = NSColor(calibratedRed: 0.13, green: 0.15, blue: 0.17, alpha: 1)
    static let secondaryText = NSColor(calibratedRed: 0.38, green: 0.42, blue: 0.46, alpha: 1)
    static let accentText = NSColor(calibratedRed: 0.08, green: 0.28, blue: 0.52, alpha: 1)
    static let productiveText = NSColor(calibratedRed: 0.05, green: 0.38, blue: 0.26, alpha: 1)
    static let distractingText = NSColor(calibratedRed: 0.62, green: 0.13, blue: 0.13, alpha: 1)
    static let neutralText = NSColor(calibratedRed: 0.43, green: 0.34, blue: 0.12, alpha: 1)
    static let separator = NSColor(calibratedRed: 0.75, green: 0.78, blue: 0.80, alpha: 1)

    static let titleFont = NSFont.systemFont(ofSize: 30, weight: .bold)
    static let subtitleFont = NSFont.systemFont(ofSize: 15, weight: .medium)
    static let sectionFont = NSFont.systemFont(ofSize: 17, weight: .semibold)
    static let bodyFont = NSFont.systemFont(ofSize: 14, weight: .regular)
    static let emphasisFont = NSFont.systemFont(ofSize: 14, weight: .semibold)

    static var bodyAttributes: [NSAttributedString.Key: Any] {
        [
            .font: bodyFont,
            .foregroundColor: primaryText,
            .paragraphStyle: bodyParagraphStyle,
        ]
    }

    static var bodyParagraphStyle: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 3
        style.paragraphSpacing = 4
        return style
    }

    static var titleParagraphStyle: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.paragraphSpacing = 4
        return style
    }

    static var subtitleParagraphStyle: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.paragraphSpacing = 18
        return style
    }

    static var sectionParagraphStyle: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.paragraphSpacingBefore = 12
        style.paragraphSpacing = 2
        return style
    }
}

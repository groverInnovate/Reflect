import AppKit
import Foundation
import LifeReplayCore

@MainActor
final class DashboardWindowController: NSWindowController {
    private enum DashboardTab: Int, CaseIterable {
        case today
        case summary
        case insights
        case timeline
        case driftEvents
        case rawEvents

        var title: String {
            switch self {
            case .today:
                "Today"
            case .summary:
                "Summary"
            case .insights:
                "Insights"
            case .timeline:
                "Timeline"
            case .driftEvents:
                "Drift Events"
            case .rawEvents:
                "Raw Events"
            }
        }
    }

    private let store: LifeReplayStore
    private let permissions: PermissionController
    private let notifications: DriftNotificationController
    private var notificationSummary: DriftNotificationController.AuthorizationSummary = .unknown
    private var isGeneratingReplay = false
    private var selectedTab: DashboardTab = .today
    private let tabButtonStack = NSStackView()
    private let contentContainer = NSView()
    private let journalScrollView = NSScrollView()
    private let journalStackView = NSStackView()
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
        renderJournal(data)
        summaryTextView.string = renderSummary(data)
        insightsTextView.string = renderInsights(data.insights)
        timelineTextView.string = renderTimeline(data.blocks)
        driftTextView.string = renderDrifts(data.analysis.driftEvents)
        rawTextView.string = renderRawEvents(data.events)
    }

    private func configureContent() {
        guard let contentView = window?.contentView else { return }

        let rootStack = NSStackView()
        rootStack.orientation = .vertical
        rootStack.alignment = .leading
        rootStack.spacing = 10
        rootStack.translatesAutoresizingMaskIntoConstraints = false

        configureTabButtons()
        configureContentViews()

        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        rootStack.addArrangedSubview(tabButtonStack)
        rootStack.addArrangedSubview(contentContainer)

        contentView.addSubview(rootStack)
        NSLayoutConstraint.activate([
            rootStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            rootStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            rootStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            rootStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),
            tabButtonStack.widthAnchor.constraint(equalTo: rootStack.widthAnchor),
            contentContainer.widthAnchor.constraint(equalTo: rootStack.widthAnchor),
            contentContainer.heightAnchor.constraint(equalTo: rootStack.heightAnchor, constant: -42),
        ])

        showSelectedTab()
    }

    private func configureTabButtons() {
        tabButtonStack.orientation = .horizontal
        tabButtonStack.alignment = .centerY
        tabButtonStack.distribution = .fill
        tabButtonStack.spacing = 8
        tabButtonStack.translatesAutoresizingMaskIntoConstraints = false

        for tab in DashboardTab.allCases {
            let button = NSButton(title: tab.title, target: self, action: #selector(selectDashboardTab))
            button.bezelStyle = .rounded
            button.setButtonType(.toggle)
            button.tag = tab.rawValue
            button.state = tab == selectedTab ? .on : .off
            tabButtonStack.addArrangedSubview(button)
        }
        tabButtonStack.addArrangedSubview(NSView())
    }

    private func configureContentViews() {
        configureJournalScrollView()
        configureTextView(summaryTextView)
        configureTextView(insightsTextView)
        configureTextView(timelineTextView)
        configureTextView(driftTextView)
        configureTextView(rawTextView)
    }

    private func configureJournalScrollView() {
        journalScrollView.hasVerticalScroller = true
        journalScrollView.borderType = .noBorder
        journalScrollView.drawsBackground = true
        journalScrollView.backgroundColor = .windowBackgroundColor

        journalStackView.orientation = .vertical
        journalStackView.alignment = .leading
        journalStackView.spacing = 16
        journalStackView.edgeInsets = NSEdgeInsets(top: 22, left: 22, bottom: 22, right: 22)

        let wrapper = NSView()
        wrapper.translatesAutoresizingMaskIntoConstraints = false
        journalStackView.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(journalStackView)
        journalScrollView.documentView = wrapper

        NSLayoutConstraint.activate([
            wrapper.widthAnchor.constraint(equalTo: journalScrollView.contentView.widthAnchor),
            journalStackView.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor),
            journalStackView.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor),
            journalStackView.topAnchor.constraint(equalTo: wrapper.topAnchor),
            journalStackView.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor),
        ])
    }

    private func configureTextView(_ textView: NSTextView) {
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.textContainerInset = NSSize(width: 18, height: 18)
        textView.backgroundColor = .textBackgroundColor
    }

    @objc private func selectDashboardTab(_ sender: NSButton) {
        guard let tab = DashboardTab(rawValue: sender.tag) else { return }
        selectedTab = tab
        showSelectedTab()
    }

    private func showSelectedTab() {
        for case let button as NSButton in tabButtonStack.arrangedSubviews {
            button.state = button.tag == selectedTab.rawValue ? .on : .off
        }

        for view in contentContainer.subviews {
            view.removeFromSuperview()
        }

        let selectedView = contentView(for: selectedTab)
        selectedView.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.addSubview(selectedView)
        NSLayoutConstraint.activate([
            selectedView.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            selectedView.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            selectedView.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            selectedView.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),
        ])
    }

    private func contentView(for tab: DashboardTab) -> NSView {
        switch tab {
        case .today:
            journalScrollView
        case .summary:
            scrollView(for: summaryTextView)
        case .insights:
            scrollView(for: insightsTextView)
        case .timeline:
            scrollView(for: timelineTextView)
        case .driftEvents:
            scrollView(for: driftTextView)
        case .rawEvents:
            scrollView(for: rawTextView)
        }
    }

    private func scrollView(for textView: NSTextView) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder
        scrollView.documentView = textView
        return scrollView
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

    private func renderJournal(_ data: DashboardData) {
        clearJournal()

        journalStackView.addArrangedSubview(headerView(data))
        journalStackView.addArrangedSubview(metricGrid(data.insights))
        journalStackView.addArrangedSubview(sectionView(title: "Journal", body: data.savedReplay?.narrativeSummary ?? data.insights.journalSummary))
        journalStackView.addArrangedSubview(observationsView(data.insights.observations))
        journalStackView.addArrangedSubview(sectionView(title: "Tomorrow Target", body: data.insights.tomorrowTarget))
        journalStackView.addArrangedSubview(focusBreaksView(data.analysis.driftEvents))
        journalStackView.addArrangedSubview(timelinePreviewView(data.blocks))
        journalStackView.addArrangedSubview(permissionFooterView(data))
    }

    private func clearJournal() {
        for view in journalStackView.arrangedSubviews {
            journalStackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
    }

    private func headerView(_ data: DashboardData) -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false

        let titleRow = NSStackView()
        titleRow.orientation = .horizontal
        titleRow.alignment = .centerY
        titleRow.distribution = .fill
        titleRow.spacing = 12
        titleRow.translatesAutoresizingMaskIntoConstraints = false

        let title = label(
            "Today - \(Date.now.formatted(date: .long, time: .omitted))",
            font: .systemFont(ofSize: 30, weight: .bold),
            color: .labelColor
        )
        let generateButton = NSButton(title: isGeneratingReplay ? "Generating..." : "Generate Today's Journal", target: self, action: #selector(generateTodayJournal))
        generateButton.bezelStyle = .rounded
        generateButton.isEnabled = !isGeneratingReplay
        generateButton.setContentCompressionResistancePriority(.required, for: .horizontal)

        let subtitle = label(
            "\(focusScoreTone(data.insights.focusScore))  \(data.events.count) raw events captured, \(data.analysis.sessions.count) focus sessions, \(data.analysis.driftEvents.count) drift events.",
            font: .systemFont(ofSize: 14, weight: .regular),
            color: .secondaryLabelColor
        )

        titleRow.addArrangedSubview(title)
        titleRow.addArrangedSubview(generateButton)
        titleRow.widthAnchor.constraint(equalTo: journalStackView.widthAnchor).isActive = true
        stack.addArrangedSubview(titleRow)
        stack.addArrangedSubview(subtitle)
        return stack
    }

    private func metricGrid(_ insights: DailyInsightReport) -> NSView {
        let rows = NSStackView()
        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = 10
        rows.translatesAutoresizingMaskIntoConstraints = false

        let firstRow = metricRow([
            metricCard(title: "Focus Score", value: "\(insights.focusScore)/100", detail: scoreLabel(insights.focusScore), accent: accentColor(for: insights.focusScore)),
            metricCard(title: "Productive", value: formatMinutes(insights.productiveMinutes), detail: "work and creation", accent: NSColor.systemGreen),
            metricCard(title: "Study-like", value: formatMinutes(insights.studyLikeMinutes), detail: "reading, notes, research", accent: NSColor.systemBlue),
        ])
        let secondRow = metricRow([
            metricCard(title: "Wasted", value: formatMinutes(insights.distractingMinutes), detail: "visible distractions", accent: NSColor.systemRed),
            metricCard(title: "Idle/Away", value: formatMinutes(insights.idleMinutes), detail: "no input detected", accent: NSColor.systemOrange),
            metricCard(title: "Tracked", value: formatMinutes(insights.totalTrackedMinutes), detail: "known activity", accent: NSColor.systemPurple),
        ])

        rows.addArrangedSubview(firstRow)
        rows.addArrangedSubview(secondRow)
        firstRow.widthAnchor.constraint(equalTo: rows.widthAnchor).isActive = true
        secondRow.widthAnchor.constraint(equalTo: rows.widthAnchor).isActive = true
        rows.widthAnchor.constraint(equalTo: journalStackView.widthAnchor).isActive = true
        return rows
    }

    private func metricRow(_ cards: [NSView]) -> NSStackView {
        let row = NSStackView(views: cards)
        row.orientation = .horizontal
        row.alignment = .top
        row.distribution = .fillEqually
        row.spacing = 10
        row.translatesAutoresizingMaskIntoConstraints = false
        return row
    }

    private func metricCard(title: String, value: String, detail: String, accent: NSColor) -> NSView {
        let card = cardView(fill: accent.withAlphaComponent(0.08), border: accent.withAlphaComponent(0.45))

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 5
        stack.translatesAutoresizingMaskIntoConstraints = false

        stack.addArrangedSubview(label(title.uppercased(), font: .systemFont(ofSize: 11, weight: .semibold), color: .secondaryLabelColor))
        stack.addArrangedSubview(label(value, font: .monospacedDigitSystemFont(ofSize: 26, weight: .bold), color: .labelColor))
        stack.addArrangedSubview(label(detail, font: .systemFont(ofSize: 12, weight: .regular), color: .secondaryLabelColor))

        card.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12),
            card.heightAnchor.constraint(greaterThanOrEqualToConstant: 104),
        ])

        return card
    }

    private func sectionView(title: String, body: String) -> NSView {
        let box = plainSectionBox()
        let stack = sectionStack()
        stack.addArrangedSubview(label(title, font: .systemFont(ofSize: 18, weight: .semibold), color: .labelColor))
        stack.addArrangedSubview(label(body, font: .systemFont(ofSize: 14, weight: .regular), color: .labelColor))
        add(stack, to: box)
        return box
    }

    private func observationsView(_ observations: [String]) -> NSView {
        let box = plainSectionBox()
        let stack = sectionStack()
        stack.addArrangedSubview(label("What This Means", font: .systemFont(ofSize: 18, weight: .semibold), color: .labelColor))

        if observations.isEmpty {
            stack.addArrangedSubview(label("No strong insight yet. Keep the collector running through a real work block.", font: .systemFont(ofSize: 14), color: .secondaryLabelColor))
        } else {
            for observation in observations {
                stack.addArrangedSubview(label("- \(observation)", font: .systemFont(ofSize: 14), color: .labelColor))
            }
        }

        add(stack, to: box)
        return box
    }

    private func focusBreaksView(_ drifts: [DriftEvent]) -> NSView {
        let box = plainSectionBox()
        let stack = sectionStack()
        stack.addArrangedSubview(label("Focus Break Points", font: .systemFont(ofSize: 18, weight: .semibold), color: .labelColor))

        if drifts.isEmpty {
            stack.addArrangedSubview(label("No drift events detected today.", font: .systemFont(ofSize: 14), color: .secondaryLabelColor))
        } else {
            for drift in drifts.prefix(5) {
                let time = dateFormatter.string(from: drift.timestamp)
                let triggers = drift.triggerAppNames.isEmpty ? "unknown trigger" : drift.triggerAppNames.joined(separator: ", ")
                let severity = Int(drift.severity * 100)
                stack.addArrangedSubview(label("\(time): \(triggers), \(drift.switchCountInWindow) switches, \(severity)% severity", font: .systemFont(ofSize: 14), color: .labelColor))
            }
        }

        add(stack, to: box)
        return box
    }

    private func timelinePreviewView(_ blocks: [TimelineBlock]) -> NSView {
        let box = plainSectionBox()
        let stack = sectionStack()
        stack.addArrangedSubview(label("Timeline Preview", font: .systemFont(ofSize: 18, weight: .semibold), color: .labelColor))

        var visibleBlocks: [TimelineBlock] = []
        for block in blocks {
            guard visibleBlocks.count < 8 else { break }
            if Int(block.end.timeIntervalSince(block.start) / 60) >= 3 {
                visibleBlocks.append(block)
            }
        }
        if visibleBlocks.isEmpty {
            stack.addArrangedSubview(label("No timeline blocks yet. Leave collection running and switch through a few real apps.", font: .systemFont(ofSize: 14), color: .secondaryLabelColor))
        } else {
            for block in visibleBlocks {
                stack.addArrangedSubview(label(renderJournalBlock(block), font: .monospacedSystemFont(ofSize: 13, weight: .regular), color: .labelColor))
            }
        }

        add(stack, to: box)
        return box
    }

    private func permissionFooterView(_ data: DashboardData) -> NSView {
        let savedReplayText: String
        if let replay = data.savedReplay {
            savedReplayText = "Saved replay generated \(replay.generatedAt.formatted(date: .omitted, time: .shortened))."
        } else {
            savedReplayText = "Today has not been saved as a replay yet."
        }
        let permissionsText = "Accessibility: \(permissions.isAccessibilityTrusted ? "Allowed" : "Needs approval") | Notifications: \(notificationSummary.rawValue)"
        return sectionView(title: "Status", body: "\(savedReplayText)\n\(permissionsText)")
    }

    private func renderSummary(_ data: DashboardData) -> String {
        let savedReplayText: String
        if let replay = data.savedReplay {
            savedReplayText = "Generated \(replay.generatedAt.formatted(date: .omitted, time: .shortened))"
        } else {
            savedReplayText = "Not generated yet"
        }
        let lines: [String] = [
            "Today - \(Date.now.formatted(date: .long, time: .omitted))",
            "",
            "Focus Score: \(data.analysis.focusScore)/100",
            "Events captured: \(data.events.count)",
            "Sessions: \(data.analysis.sessions.count)",
            "Drift events: \(data.analysis.driftEvents.count)",
            "Saved replay: \(savedReplayText)",
            "",
            "Permissions",
            "-----------",
            "Accessibility: \(permissions.isAccessibilityTrusted ? "Allowed" : "Needs approval for window titles")",
            "Notifications: \(notificationSummary.rawValue)",
            "Automation: macOS will ask when Safari/Chrome tab domains are first read",
            "",
            data.savedReplay?.narrativeSummary ?? data.insights.journalSummary,
        ]
        return lines.joined(separator: "\n")
    }

    private func renderInsights(_ insights: DailyInsightReport) -> String {
        var lines: [String] = [
            "Time Breakdown",
            "--------------",
            "Productive:   \(formatMinutes(insights.productiveMinutes))",
            "Study-like:   \(formatMinutes(insights.studyLikeMinutes))",
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
            "Tomorrow Target",
            "---------------",
            insights.tomorrowTarget,
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
        let startIndex = max(0, events.count - 250)
        var lines: [String] = []
        for index in startIndex..<events.count {
            lines.append(renderEvent(events[index]))
        }
        return lines.joined(separator: "\n")
    }

    private func renderBlock(_ block: TimelineBlock) -> String {
        let start = dateFormatter.string(from: block.start)
        let end = dateFormatter.string(from: block.end)
        let minutes = Int(block.end.timeIntervalSince(block.start) / 60)
        return "\(start)-\(end)  \(block.label)  \(minutes)m  [\(block.category.rawValue)]"
    }

    private func renderJournalBlock(_ block: TimelineBlock) -> String {
        let start = dateFormatter.string(from: block.start)
        let end = dateFormatter.string(from: block.end)
        let minutes = Int(block.end.timeIntervalSince(block.start) / 60)
        let category = block.category.rawValue.capitalized
        return "\(start)-\(end)  \(formatMinutes(minutes))  \(category)  \(block.label)"
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

    @objc private func generateTodayJournal() {
        guard !isGeneratingReplay else { return }
        isGeneratingReplay = true
        renderCurrentData()

        Task { @MainActor in
            _ = await store.generateDailyReplayWithNarrative()
            isGeneratingReplay = false
            renderCurrentData()
        }
    }

    private func plainSectionBox() -> NSView {
        cardView(fill: NSColor.controlBackgroundColor.withAlphaComponent(0.55), border: NSColor.separatorColor.withAlphaComponent(0.75))
    }

    private func sectionStack() -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }

    private func add(_ stack: NSStackView, to box: NSView) {
        box.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: box.topAnchor, constant: 14),
            stack.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -14),
            box.widthAnchor.constraint(equalTo: journalStackView.widthAnchor),
        ])
    }

    private func cardView(fill: NSColor, border: NSColor) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.cornerRadius = 8
        view.layer?.borderWidth = 1
        view.layer?.borderColor = border.cgColor
        view.layer?.backgroundColor = fill.cgColor
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }

    private func label(_ text: String, font: NSFont, color: NSColor = .labelColor) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = font
        field.textColor = color
        field.lineBreakMode = .byWordWrapping
        field.maximumNumberOfLines = 0
        field.translatesAutoresizingMaskIntoConstraints = false
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    private func focusScoreTone(_ score: Int) -> String {
        switch score {
        case 80...:
            return "Strong focus day."
        case 60..<80:
            return "Mixed but useful focus day."
        case 40..<60:
            return "Fragmented focus day."
        default:
            return "Low-focus day."
        }
    }

    private func scoreLabel(_ score: Int) -> String {
        switch score {
        case 80...:
            return "strong"
        case 60..<80:
            return "steady"
        case 40..<60:
            return "fragmented"
        default:
            return "needs reset"
        }
    }

    private func accentColor(for score: Int) -> NSColor {
        switch score {
        case 80...:
            return .systemGreen
        case 60..<80:
            return .systemBlue
        case 40..<60:
            return .systemOrange
        default:
            return .systemRed
        }
    }

    private func formatMinutes(_ minutes: Int) -> String {
        if minutes < 60 {
            return "\(minutes)m"
        }
        let hours = minutes / 60
        let remainder = minutes % 60
        return remainder == 0 ? "\(hours)h" : "\(hours)h \(remainder)m"
    }
}

private struct DashboardData {
    var events: [ActivityEvent]
    var analysis: FocusAnalysis
    var blocks: [TimelineBlock]
    var savedReplay: DailyReplay?
    var insights: DailyInsightReport
}

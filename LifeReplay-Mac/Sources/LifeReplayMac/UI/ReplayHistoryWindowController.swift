import AppKit
import Foundation
import LifeReplayCore

@MainActor
final class ReplayHistoryWindowController: NSWindowController {
    private let store: LifeReplayStore
    private let textView = NSTextView()
    private let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    init(store: LifeReplayStore) {
        self.store = store

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Life Replay History"
        window.center()

        super.init(window: window)
        configureContent()
        reload()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("ReplayHistoryWindowController is created in code.")
    }

    func reload() {
        let replays = store.dailyReplays()
        guard !replays.isEmpty else {
            textView.string = "No saved daily replays yet."
            return
        }

        textView.string = replays.map(renderReplay).joined(separator: "\n\n")
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

    private func renderReplay(_ replay: DailyReplay) -> String {
        let blocks = (try? ReplayEngine().decodeBlocks(from: replay.timelineBlocksJSON)) ?? []
        var lines: [String] = [
            replay.date.formatted(date: .long, time: .omitted),
            String(repeating: "-", count: 32),
            "Focus Score: \(replay.focusScore)/100",
            "Generated: \(replay.generatedAt.formatted(date: .abbreviated, time: .shortened))",
            "On-device AI: \(replay.usedOnDeviceAI ? "yes" : "no")",
            "",
            replay.narrativeSummary ?? "No summary.",
            "",
            "Timeline:",
        ]

        if blocks.isEmpty {
            lines.append("  No timeline blocks.")
        } else {
            lines += blocks.prefix(12).map(renderBlock)
        }

        return lines.joined(separator: "\n")
    }

    private func renderBlock(_ block: TimelineBlock) -> String {
        let start = timeFormatter.string(from: block.start)
        let end = timeFormatter.string(from: block.end)
        let minutes = Int(block.end.timeIntervalSince(block.start) / 60)
        return "  \(start)-\(end)  \(block.label)  \(minutes)m  [\(block.category.rawValue)]"
    }
}

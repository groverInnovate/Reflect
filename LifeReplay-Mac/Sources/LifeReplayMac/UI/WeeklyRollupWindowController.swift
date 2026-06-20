import AppKit
import Foundation

@MainActor
final class WeeklyRollupWindowController: NSWindowController {
    private let store: LifeReplayStore
    private let textView = NSTextView()

    init(store: LifeReplayStore) {
        self.store = store

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Life Replay Weekly Rollup"
        window.center()

        super.init(window: window)
        configureContent()
        reload()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("WeeklyRollupWindowController is created in code.")
    }

    func reload() {
        let rollup = store.weeklyRollup()
        guard rollup.days > 0 else {
            textView.string = "No saved daily replays in the last 7 days."
            return
        }

        let bestDay = rollup.bestDay.map {
            "\($0.date.formatted(date: .abbreviated, time: .omitted)) (\($0.focusScore)/100)"
        } ?? "none"

        var lines: [String] = [
            "Last 7 Days",
            "-----------",
            "Saved days: \(rollup.days)",
            "Average focus score: \(rollup.averageFocusScore)/100",
            "Best day: \(bestDay)",
            "",
            "Days",
            "----",
        ]

        lines += rollup.latestDays.map {
            let date = $0.date.formatted(date: .abbreviated, time: .omitted)
            let ai = $0.usedOnDeviceAI ? "AI" : "fallback"
            return "\(date)  \($0.focusScore)/100  \(ai)"
        }

        textView.string = lines.joined(separator: "\n")
    }

    private func configureContent() {
        guard let contentView = window?.contentView else { return }

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder

        textView.isEditable = false
        textView.isSelectable = true
        textView.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
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
}

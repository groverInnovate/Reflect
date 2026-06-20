import AppKit
import Foundation

@MainActor
final class DataStatusWindowController: NSWindowController {
    private let store: LifeReplayStore
    private let textView = NSTextView()

    init(store: LifeReplayStore) {
        self.store = store

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 360),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Life Replay Data Status"
        window.center()

        super.init(window: window)
        configureContent()
        reload()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("DataStatusWindowController is created in code.")
    }

    func reload() {
        let status = store.dataStatus()
        let latestReplay = status.latestReplayGeneratedAt?.formatted(date: .abbreviated, time: .shortened) ?? "none"
        textView.string = """
        Today
        -----
        Activity events: \(status.todayEvents)
        Focus sessions:  \(status.todaySessions)
        Drift events:    \(status.todayDrifts)

        All Time
        --------
        Activity events: \(status.allEvents)
        Focus sessions:  \(status.allSessions)
        Drift events:    \(status.allDrifts)
        Daily replays:   \(status.allReplays)

        Latest replay: \(latestReplay)
        """
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

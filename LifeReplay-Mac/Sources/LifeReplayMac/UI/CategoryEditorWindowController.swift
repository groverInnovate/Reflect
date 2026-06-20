import AppKit
import Foundation
import LifeReplayCore

@MainActor
final class CategoryEditorWindowController: NSWindowController {
    private let store: LifeReplayStore
    private let textView = NSTextView()
    private let statusLabel = NSTextField(labelWithString: "")

    init(store: LifeReplayStore) {
        self.store = store

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Life Replay Categories"
        window.center()

        super.init(window: window)
        configureContent()
        reload()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("CategoryEditorWindowController is created in code.")
    }

    func reload() {
        let lines = store.categories().map {
            "\($0.matchPattern) | \($0.displayName) | \($0.category.rawValue)"
        }
        textView.string = lines.joined(separator: "\n")
        statusLabel.stringValue = "Format: match pattern | display name | productive, neutral, or distracting"
    }

    private func configureContent() {
        guard let contentView = window?.contentView else { return }

        let saveButton = NSButton(title: "Save", target: self, action: #selector(save))
        saveButton.bezelStyle = .rounded
        saveButton.translatesAutoresizingMaskIntoConstraints = false

        let resetButton = NSButton(title: "Reset Defaults", target: self, action: #selector(resetDefaults))
        resetButton.bezelStyle = .rounded
        resetButton.translatesAutoresizingMaskIntoConstraints = false

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.lineBreakMode = .byTruncatingTail

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder

        textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        scrollView.documentView = textView

        contentView.addSubview(scrollView)
        contentView.addSubview(saveButton)
        contentView.addSubview(resetButton)
        contentView.addSubview(statusLabel)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            scrollView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            scrollView.bottomAnchor.constraint(equalTo: saveButton.topAnchor, constant: -12),

            saveButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            saveButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),

            resetButton.leadingAnchor.constraint(equalTo: saveButton.trailingAnchor, constant: 8),
            resetButton.centerYAnchor.constraint(equalTo: saveButton.centerYAnchor),

            statusLabel.leadingAnchor.constraint(equalTo: resetButton.trailingAnchor, constant: 12),
            statusLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            statusLabel.centerYAnchor.constraint(equalTo: saveButton.centerYAnchor),
        ])
    }

    @objc private func save() {
        do {
            let seeds = try parseSeeds(from: textView.string)
            store.replaceCategories(with: seeds)
            statusLabel.stringValue = "Saved \(seeds.count) categories."
        } catch {
            statusLabel.stringValue = error.localizedDescription
        }
    }

    @objc private func resetDefaults() {
        store.replaceCategories(with: DefaultAppCategories.all)
        reload()
        statusLabel.stringValue = "Reset to defaults."
    }

    private func parseSeeds(from text: String) throws -> [AppCategorySeed] {
        let lines = text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }

        var seeds: [AppCategorySeed] = []
        for (index, line) in lines.enumerated() {
            let pieces = line.split(separator: "|").map {
                String($0).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard pieces.count == 3 else {
                throw CategoryEditorError.invalidLine(index + 1)
            }
            guard let category = FocusCategory(rawValue: pieces[2]) else {
                throw CategoryEditorError.invalidCategory(index + 1, pieces[2])
            }
            seeds.append(AppCategorySeed(pieces[0], pieces[1], category))
        }

        guard !seeds.isEmpty else {
            throw CategoryEditorError.empty
        }
        return seeds
    }
}

private enum CategoryEditorError: LocalizedError {
    case empty
    case invalidLine(Int)
    case invalidCategory(Int, String)

    var errorDescription: String? {
        switch self {
        case .empty:
            "No category rules to save."
        case .invalidLine(let line):
            "Line \(line) must use: pattern | display name | category"
        case .invalidCategory(let line, let value):
            "Line \(line) has invalid category '\(value)'. Use productive, neutral, or distracting."
        }
    }
}

import AppKit
import Foundation

@MainActor
final class FocusSettingsWindowController: NSWindowController {
    private let store: LifeReplayStore
    private let idleField = NSTextField()
    private let sessionField = NSTextField()
    private let driftWindowField = NSTextField()
    private let baselineField = NSTextField()
    private let productiveField = NSTextField()
    private let statusLabel = NSTextField(labelWithString: "")

    init(store: LifeReplayStore) {
        self.store = store
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 300),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Focus Drift Settings"
        window.center()

        super.init(window: window)
        configureContent()
        reload()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("FocusSettingsWindowController is created in code.")
    }

    func reload() {
        let settings = store.focusSettings()
        idleField.doubleValue = settings.idleThresholdSeconds
        sessionField.doubleValue = settings.sessionMinimumDurationSeconds
        driftWindowField.doubleValue = settings.driftWindowMinutes
        baselineField.doubleValue = settings.baselineSwitchesPerHour
        productiveField.doubleValue = settings.productiveSessionMinimumMinutes
        statusLabel.stringValue = ""
    }

    private func configureContent() {
        guard let contentView = window?.contentView else { return }

        let grid = NSGridView(views: [
            row("Idle threshold, seconds", idleField),
            row("Session minimum, seconds", sessionField),
            row("Drift window, minutes", driftWindowField),
            row("Baseline switches / hour", baselineField),
            row("Productive block minimum, minutes", productiveField),
        ])
        grid.translatesAutoresizingMaskIntoConstraints = false
        grid.rowSpacing = 10
        grid.columnSpacing = 12
        grid.column(at: 0).xPlacement = .trailing

        let saveButton = NSButton(title: "Save", target: self, action: #selector(save))
        saveButton.translatesAutoresizingMaskIntoConstraints = false
        saveButton.bezelStyle = .rounded

        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(grid)
        contentView.addSubview(saveButton)
        contentView.addSubview(statusLabel)

        NSLayoutConstraint.activate([
            grid.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            grid.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            grid.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 24),

            saveButton.leadingAnchor.constraint(equalTo: grid.leadingAnchor),
            saveButton.topAnchor.constraint(equalTo: grid.bottomAnchor, constant: 18),

            statusLabel.leadingAnchor.constraint(equalTo: saveButton.trailingAnchor, constant: 12),
            statusLabel.trailingAnchor.constraint(equalTo: grid.trailingAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: saveButton.centerYAnchor),
        ])
    }

    private func row(_ label: String, _ field: NSTextField) -> [NSView] {
        field.alignment = .right
        field.formatter = numberFormatter()
        return [NSTextField(labelWithString: label), field]
    }

    private func numberFormatter() -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimum = 1
        formatter.maximumFractionDigits = 1
        return formatter
    }

    @objc private func save() {
        store.updateFocusSettings(
            idleThresholdSeconds: idleField.doubleValue,
            sessionMinimumDurationSeconds: sessionField.doubleValue,
            driftWindowMinutes: driftWindowField.doubleValue,
            baselineSwitchesPerHour: baselineField.doubleValue,
            productiveSessionMinimumMinutes: productiveField.doubleValue
        )
        statusLabel.stringValue = "Saved and recomputed today."
    }
}

import AppKit
import Foundation
import LifeReplayCore
import Observation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
@Observable
final class WorkdayViewModel {
    var date = Date()
    var report = WorkdayReport(blocks: [])
    var drifts: [CoreDriftEvent] = []
    var isTracking = false
    var error: String?
    var browserIssue: String?
    var accessibilityAllowed = false
    let store: LifeReplayStore
    let permissions: PermissionController
    let trackingState: () -> Bool
    let readBrowserIssue: () -> String?
    let toggleTracking: () -> Void
    let loginStatus: () -> String
    let toggleLogin: () -> Void
    let settingsChanged: () -> Void

    init(store: LifeReplayStore, permissions: PermissionController,
         trackingState: @escaping () -> Bool, browserIssue: @escaping () -> String?,
         toggleTracking: @escaping () -> Void, loginStatus: @escaping () -> String,
         toggleLogin: @escaping () -> Void, settingsChanged: @escaping () -> Void) {
        self.store = store; self.permissions = permissions
        self.trackingState = trackingState; self.readBrowserIssue = browserIssue
        self.toggleTracking = toggleTracking; self.loginStatus = loginStatus
        self.toggleLogin = toggleLogin; self.settingsChanged = settingsChanged
    }

    func reload() {
        let data = store.report(for: date)
        report = data.report; drifts = data.drifts
        isTracking = trackingState()
        browserIssue = readBrowserIssue()
        accessibilityAllowed = permissions.isAccessibilityTrusted
        error = store.lastError
    }

    func moveDay(_ offset: Int) {
        date = Calendar.current.date(byAdding: .day, value: offset, to: date) ?? date
        reload()
    }

    func export() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "Life Replay \(date.formatted(.iso8601.year().month().day())).csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try store.exportCSV(for: date, to: url) }
        catch { self.error = "Export failed: \(error.localizedDescription)" }
    }
}

@MainActor
final class DashboardWindowController: NSWindowController {
    private let model: WorkdayViewModel

    init(store: LifeReplayStore, permissions: PermissionController,
         trackingState: @escaping () -> Bool, browserIssue: @escaping () -> String?,
         toggleTracking: @escaping () -> Void, loginStatus: @escaping () -> String,
         toggleLogin: @escaping () -> Void, settingsChanged: @escaping () -> Void) {
        model = WorkdayViewModel(store: store, permissions: permissions, trackingState: trackingState,
            browserIssue: browserIssue, toggleTracking: toggleTracking, loginStatus: loginStatus,
            toggleLogin: toggleLogin, settingsChanged: settingsChanged)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1020, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.title = "Life Replay"
        window.titlebarAppearsTransparent = true
        window.minSize = NSSize(width: 780, height: 620)
        window.isReleasedWhenClosed = false
        window.center()
        window.contentView = NSHostingView(rootView: WorkdayDashboard(model: model))
        super.init(window: window)
        reload()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Created in code") }
    func reload() { model.reload() }
}

private enum ReportStyle {
    static func color(_ category: FocusCategory) -> Color {
        switch category {
        case .productive: .blue
        case .neutral: Color(nsColor: .secondaryLabelColor)
        case .distracting: .orange
        }
    }
    static func duration(_ seconds: TimeInterval) -> String {
        let minutes = Int(max(0, seconds) / 60)
        if seconds <= 0 { return "0m" }
        if minutes == 0 { return "<1m" }
        return minutes < 60 ? "\(minutes)m" : "\(minutes / 60)h \(minutes % 60)m"
    }
    static func categoryName(_ category: FocusCategory) -> String {
        switch category {
        case .productive: "Work"
        case .neutral: "Other"
        case .distracting: "Distractions"
        }
    }
}

private struct WorkdayDashboard: View {
    @Bindable var model: WorkdayViewModel
    @State private var showCategories = false
    @State private var showSettings = false
    @State private var selectedActivity: String?
    @State private var showAway = true
    @State private var search = ""
    private var isToday: Bool { Calendar.current.isDateInToday(model.date) }
    private var visibleBlocks: [TimelineBlock] {
        model.report.blocks.filter {
            (showAway || $0.kind == .observed)
                && (selectedActivity == nil || ($0.kind == .observed && $0.label == selectedActivity))
                && (search.isEmpty || $0.label.localizedCaseInsensitiveContains(search)
                    || ($0.detail?.localizedCaseInsensitiveContains(search) ?? false))
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                if let error = model.error { notice(error, symbol: "exclamationmark.triangle", color: .red) }
                if let issue = model.browserIssue {
                    HStack {
                        notice(issue, symbol: "globe", color: .orange)
                        Button("Open Settings") { model.permissions.openAutomationSettings() }
                    }
                }
                if !model.isTracking && isToday {
                    notice("Tracking is paused. Resume to record your next work session.", symbol: "pause.circle", color: .secondary)
                }
                if model.report.blocks.isEmpty {
                    emptyState
                } else {
                    metrics
                    hourlyChart
                    activityList
                    timeline
                }
                footer
            }
            .padding(32)
            .frame(maxWidth: 1120, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .toolbar {
            ToolbarItemGroup {
                Button { model.toggleTracking(); model.reload() } label: {
                    Label(model.isTracking ? "Pause" : "Resume", systemImage: model.isTracking ? "pause" : "play")
                }.help(model.isTracking ? "Pause tracking" : "Resume tracking")
                Button { model.reload() } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                Menu {
                    Button("Edit Categories…") { showCategories = true }
                    Button("Tracking Settings…") { showSettings = true }
                    Divider()
                    Button("Export This Day as CSV…") { model.export() }.disabled(model.report.blocks.isEmpty)
                } label: { Label("Options", systemImage: "ellipsis.circle") }
            }
        }
        .sheet(isPresented: $showCategories, onDismiss: { model.reload() }) {
            CategoryRulesView(store: model.store)
        }
        .sheet(isPresented: $showSettings, onDismiss: { model.settingsChanged(); model.reload() }) {
            TrackingSettingsView(model: model)
        }
        .onChange(of: model.date) { _, _ in selectedActivity = nil; model.reload() }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
                Text("YOUR WORKDAY").font(.system(size: 11, weight: .semibold)).tracking(2).foregroundStyle(.secondary)
                Text(isToday ? "Today" : model.date.formatted(.dateTime.weekday(.wide)))
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                Text(model.date.formatted(.dateTime.month(.wide).day().year())).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 12) {
                HStack(spacing: 6) {
                    Circle().fill(model.isTracking ? Color.green : Color.secondary).frame(width: 6, height: 6)
                    Text(model.isTracking ? "Tracking" : "Paused").font(.caption).foregroundStyle(.secondary)
                }.accessibilityElement(children: .combine)
                HStack {
                    Button { model.moveDay(-1) } label: { Image(systemName: "chevron.left") }
                        .help("Previous day").accessibilityLabel("Previous day")
                    DatePicker("Date", selection: $model.date, in: ...Date(), displayedComponents: .date).labelsHidden()
                        .accessibilityLabel("Report date")
                    Button { model.moveDay(1) } label: { Image(systemName: "chevron.right") }
                        .disabled(isToday).help("Next day").accessibilityLabel("Next day")
                    if !isToday { Button("Today") { model.date = Date() } }
                }.controlSize(.small)
            }
        }
    }

    private var metrics: some View {
        HStack(spacing: 0) {
            metric("Active time", seconds: model.report.activeSeconds, color: .primary)
            Divider().frame(height: 48)
            metric("Work", seconds: model.report.productiveSeconds, color: .blue)
            Divider().frame(height: 48)
            metric("Other", seconds: model.report.neutralSeconds, color: .secondary)
            Divider().frame(height: 48)
            metric("Distractions", seconds: model.report.distractingSeconds, color: .orange)
        }.padding(.vertical, 22).background(.background, in: RoundedRectangle(cornerRadius: 16))
    }

    private func metric(_ title: String, seconds: TimeInterval, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title).font(.subheadline).foregroundStyle(.secondary)
            Text(ReportStyle.duration(seconds)).font(.system(size: 28, weight: .medium, design: .rounded))
                .monospacedDigit().foregroundStyle(color)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 22)
    }

    private var hourlyChart: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Activity by hour").font(.headline)
                Spacer()
                ForEach([FocusCategory.productive, .neutral, .distracting], id: \.self) { category in
                    HStack(spacing: 5) {
                        Circle().fill(ReportStyle.color(category)).frame(width: 6, height: 6)
                        Text(ReportStyle.categoryName(category)).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if model.report.hours.isEmpty {
                Text("No active time recorded.").foregroundStyle(.secondary)
            } else {
                HStack(alignment: .bottom, spacing: 6) {
                    ForEach(model.report.hours) { hour in
                        VStack(spacing: 8) {
                            VStack(spacing: 0) {
                                Spacer(minLength: 0)
                                Rectangle().fill(Color.orange.opacity(0.8)).frame(height: hour.distracting / 3600 * 80)
                                Rectangle().fill(Color.secondary.opacity(0.3)).frame(height: hour.neutral / 3600 * 80)
                                Rectangle().fill(Color.blue.opacity(0.8)).frame(height: hour.productive / 3600 * 80)
                            }.frame(height: 80).background(Color.primary.opacity(0.025))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                            Text(String(format: "%02d", Calendar.current.component(.hour, from: hour.start)))
                                .font(.system(size: 10)).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity)
                            .help("\(hour.start.formatted(date: .omitted, time: .shortened)): \(ReportStyle.duration(hour.active)) active")
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("\(hour.start.formatted(date: .omitted, time: .shortened)), work \(ReportStyle.duration(hour.productive)), other \(ReportStyle.duration(hour.neutral)), distractions \(ReportStyle.duration(hour.distracting))")
                    }
                }
            }
        }
    }

    private var activityList: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Where your time went").font(.headline)
                Spacer()
                Button("Edit categories") { showCategories = true }.buttonStyle(.link)
            }
            VStack(spacing: 0) {
                ForEach(model.report.activities) { activity in
                    Button {
                        selectedActivity = selectedActivity == activity.label ? nil : activity.label
                    } label: {
                        HStack(spacing: 16) {
                            RoundedRectangle(cornerRadius: 4).fill(ReportStyle.color(activity.category).opacity(0.12))
                                .overlay(Image(systemName: "app").font(.system(size: 15)).foregroundStyle(ReportStyle.color(activity.category)))
                                .frame(width: 32, height: 32)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(activity.label).font(.system(size: 13, weight: .medium)).foregroundStyle(.primary)
                                Text(ReportStyle.categoryName(activity.category)).font(.caption).foregroundStyle(.secondary)
                            }.frame(width: 200, alignment: .leading)
                            GeometryReader { proxy in
                                Capsule().fill(Color.primary.opacity(0.04))
                                    .overlay(alignment: .leading) {
                                        Capsule().fill(ReportStyle.color(activity.category).opacity(0.7))
                                            .frame(width: proxy.size.width * activity.seconds / max(1, model.report.activeSeconds))
                                    }
                            }.frame(height: 5)
                            Text("\(Int((activity.seconds / max(1, model.report.activeSeconds) * 100).rounded()))%")
                                .font(.caption).foregroundStyle(.secondary).monospacedDigit().frame(width: 40, alignment: .trailing)
                            Text(ReportStyle.duration(activity.seconds)).font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.primary).monospacedDigit().frame(width: 72, alignment: .trailing)
                        }.padding(.horizontal, 16).padding(.vertical, 12)
                            .background(selectedActivity == activity.label ? Color.blue.opacity(0.06) : Color.clear)
                    }.buttonStyle(.plain).help("Show \(activity.label) in the timeline")
                    if activity.id != model.report.activities.last?.id { Divider().padding(.leading, 64) }
                }
            }.background(.background, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private var timeline: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Timeline").font(.headline)
                Spacer()
                Toggle("Include breaks", isOn: $showAway).toggleStyle(.checkbox).font(.caption)
                TextField("Find an app or site", text: $search).textFieldStyle(.roundedBorder).frame(width: 180)
            }
            if let selectedActivity {
                HStack {
                    Text("Showing \(selectedActivity)").font(.caption).foregroundStyle(.secondary)
                    Button("Show all") { self.selectedActivity = nil }.buttonStyle(.link)
                }
            }
            if visibleBlocks.isEmpty { Text("No matching activity.").foregroundStyle(.secondary).padding(.vertical, 16) }
            LazyVStack(spacing: 0) {
                ForEach(Array(visibleBlocks.enumerated()), id: \.offset) { _, block in
                    HStack(alignment: .top, spacing: 16) {
                        Text(block.start.formatted(date: .omitted, time: .shortened))
                            .font(.system(size: 12)).monospacedDigit().foregroundStyle(.secondary).frame(width: 76, alignment: .trailing)
                        Capsule().fill(block.kind == .observed ? ReportStyle.color(block.category) : Color.secondary.opacity(0.25))
                            .frame(width: 3, height: 28)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(block.kind == .unobserved ? "Not tracked" : block.label)
                                .font(.system(size: 13, weight: .medium))
                            Text("Until \(block.end.formatted(date: .omitted, time: .shortened))")
                                .font(.caption).foregroundStyle(.secondary)
                            if let detail = block.detail, block.kind == .observed {
                                Text(detail).font(.caption).foregroundStyle(.tertiary).lineLimit(1).help(detail)
                            }
                        }
                        Spacer()
                        Text(ReportStyle.duration(block.end.timeIntervalSince(block.start)))
                            .font(.system(size: 12, weight: .medium)).monospacedDigit().foregroundStyle(.secondary)
                    }.padding(.vertical, 12)
                    Divider().padding(.leading, 95)
                }
            }
            if !model.drifts.isEmpty {
                DisclosureGroup("Focus breaks · \(model.drifts.count)") {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(model.drifts.enumerated()), id: \.offset) { _, drift in
                            Text("\(drift.timestamp.formatted(date: .omitted, time: .shortened)) · \(drift.switchCountInWindow) switches in \(Int(model.store.focusSettings().driftWindowMinutes)) minutes · \(drift.triggerAppNames.joined(separator: ", "))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }.padding(.top, 12).frame(maxWidth: .infinity, alignment: .leading)
                }.font(.subheadline)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.bar.xaxis").font(.system(size: 36, weight: .light)).foregroundStyle(.secondary)
            Text(isToday ? "Your workday starts here" : "No activity recorded on this day").font(.title2.weight(.medium))
            Text(isToday ? "Use your Mac as usual. Your apps and websites will appear here as time is recorded."
                        : "Choose another date to review a recorded workday.")
                .foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 420)
            if !model.isTracking && isToday { Button("Resume tracking") { model.toggleTracking(); model.reload() } }
        }.frame(maxWidth: .infinity).padding(.vertical, 80)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !model.report.blocks.isEmpty {
                HStack(spacing: 18) {
                    Text("Idle / away  \(ReportStyle.duration(model.report.idleSeconds))")
                    if model.report.unobservedSeconds > 0 {
                        Text("Not tracked  \(ReportStyle.duration(model.report.unobservedSeconds))")
                    }
                }.font(.caption).foregroundStyle(.secondary)
            }
            Text("Active time measures the frontmost app or browser tab, excluding idle and untracked time. All data stays on this Mac.")
                .font(.caption).foregroundStyle(.secondary)
            if !model.accessibilityAllowed {
                HStack {
                    Text("Allow Accessibility to add window and project titles.").font(.caption).foregroundStyle(.secondary)
                    Button("Allow…") { model.permissions.requestAccessibilityPermission(); model.permissions.openAccessibilitySettings() }
                        .buttonStyle(.link).font(.caption)
                }
            }
        }
    }

    private func notice(_ text: String, symbol: String, color: Color) -> some View {
        Label(text, systemImage: symbol).font(.callout).foregroundStyle(color)
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(color.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct TrackingSettingsView: View {
    var model: WorkdayViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var threshold: Double = 90
    @State private var loginState = ""
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Tracking settings").font(.title2.weight(.semibold))
            VStack(alignment: .leading, spacing: 10) {
                Picker("Consider the Mac idle after", selection: $threshold) {
                    ForEach([30.0, 60, 90, 120, 300, 600, 900], id: \.self) { seconds in
                        Text(seconds == 90 ? "1 minute 30 seconds" : seconds == 30 ? "30 seconds" : "\(Int(seconds / 60)) minutes").tag(seconds)
                    }
                }
                Text("Short pauses count as active until this limit. Longer periods with no keyboard or mouse input are marked idle; reading and calls may be idle too.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Launch at login")
                    Text(loginState).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Change") { model.toggleLogin(); loginState = model.loginStatus() }
            }
            if let error { Text(error).foregroundStyle(.red).font(.caption) }
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save") {
                    do { try model.store.updateIdleThreshold(threshold); dismiss() }
                    catch { self.error = error.localizedDescription }
                }.keyboardShortcut(.defaultAction)
            }
        }.padding(28).frame(width: 460)
            .onAppear { threshold = model.store.focusSettings().idleThresholdSeconds; loginState = model.loginStatus() }
    }
}

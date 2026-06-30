import Foundation
import Testing
@testable import LifeReplayCore

@Suite("Category resolver")
struct CategoryResolverTests {
    @Test("custom seeds override default assumptions")
    func customSeedsClassifyEvents() {
        let resolver = CategoryResolver(seeds: [
            AppCategorySeed("example.com", "Example Research", .productive),
        ])
        let event = ActivityEvent(
            timestamp: Date(timeIntervalSince1970: 0),
            kind: .browserDomain,
            browserDomain: "example.com"
        )

        #expect(resolver.category(for: event) == .productive)
        #expect(resolver.displayName(for: event) == "Example Research")
    }

    @Test("default resolver uses window titles for study material")
    func defaultResolverUsesWindowTitles() {
        let resolver = CategoryResolver()
        let event = ActivityEvent(
            timestamp: Date(timeIntervalSince1970: 0),
            kind: .appActivated,
            appBundleID: "com.apple.Preview",
            appName: "Preview",
            windowTitle: "Mechanical Engineering Lecture 04.pdf"
        )

        #expect(resolver.category(for: event) == .productive)
    }

    @Test("default resolver classifies research and course domains as productive")
    func defaultResolverClassifiesStudyDomains() {
        let resolver = CategoryResolver()
        let events = [
            ActivityEvent(timestamp: Date(timeIntervalSince1970: 0), kind: .browserDomain, browserDomain: "arxiv.org"),
            ActivityEvent(timestamp: Date(timeIntervalSince1970: 1), kind: .browserDomain, browserDomain: "coursera.org"),
            ActivityEvent(timestamp: Date(timeIntervalSince1970: 2), kind: .browserDomain, browserDomain: "docs.rs"),
            ActivityEvent(timestamp: Date(timeIntervalSince1970: 3), kind: .browserDomain, browserDomain: "rust-book.cs.brown.edu"),
        ]

        #expect(events.allSatisfy { resolver.category(for: $0) == .productive })
    }

    @Test("default resolver classifies AI and HackMD work as productive")
    func defaultResolverClassifiesAIAndHackMDWork() {
        let resolver = CategoryResolver()
        let events = [
            ActivityEvent(timestamp: Date(timeIntervalSince1970: 0), kind: .appActivated, appName: "Claude"),
            ActivityEvent(timestamp: Date(timeIntervalSince1970: 1), kind: .browserDomain, browserDomain: "chatgpt.com"),
            ActivityEvent(timestamp: Date(timeIntervalSince1970: 2), kind: .browserDomain, browserDomain: "hackmd.io"),
        ]

        #expect(events.allSatisfy { resolver.category(for: $0) == .productive })
    }

    @Test("browser window title can provide a productive display name")
    func browserTitleProvidesDisplayName() {
        let resolver = CategoryResolver()
        let event = ActivityEvent(
            timestamp: Date(timeIntervalSince1970: 0),
            kind: .appActivated,
            appName: "Brave Browser",
            windowTitle: "Week 2 - HackMD - Brave"
        )

        #expect(resolver.category(for: event) == .productive)
        #expect(resolver.displayName(for: event) == "HackMD")
    }

    @Test("known domains use their category display names")
    func knownDomainsUseDisplayNames() {
        let resolver = CategoryResolver()
        let events = [
            ActivityEvent(timestamp: Date(timeIntervalSince1970: 0), kind: .browserDomain, browserDomain: "hackmd.io"),
            ActivityEvent(timestamp: Date(timeIntervalSince1970: 1), kind: .browserDomain, browserDomain: "chatgpt.com"),
        ]

        #expect(events.map { resolver.displayName(for: $0) } == ["HackMD", "ChatGPT"])
    }
}

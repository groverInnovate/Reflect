import Foundation
import XCTest
@testable import LifeReplayCore

final class CategoryResolverTests: XCTestCase {
    // custom seeds override default assumptions
    func testCustomSeedsClassifyEvents() {
        let resolver = CategoryResolver(seeds: [
            AppCategorySeed("example.com", "Example Research", .productive),
        ])
        let event = ActivityEvent(
            timestamp: Date(timeIntervalSince1970: 0),
            kind: .browserDomain,
            browserDomain: "example.com"
        )

        XCTAssertTrue(resolver.category(for: event) == .productive)
        XCTAssertTrue(resolver.displayName(for: event) == "Example Research")
    }

    // default resolver uses window titles for study material
    func testDefaultResolverUsesWindowTitles() {
        let resolver = CategoryResolver()
        let event = ActivityEvent(
            timestamp: Date(timeIntervalSince1970: 0),
            kind: .appActivated,
            appBundleID: "com.apple.Preview",
            appName: "Preview",
            windowTitle: "Mechanical Engineering Lecture 04.pdf"
        )

        XCTAssertTrue(resolver.category(for: event) == .productive)
    }

    // default resolver classifies research and course domains as productive
    func testDefaultResolverClassifiesStudyDomains() {
        let resolver = CategoryResolver()
        let events = [
            ActivityEvent(timestamp: Date(timeIntervalSince1970: 0), kind: .browserDomain, browserDomain: "arxiv.org"),
            ActivityEvent(timestamp: Date(timeIntervalSince1970: 1), kind: .browserDomain, browserDomain: "coursera.org"),
            ActivityEvent(timestamp: Date(timeIntervalSince1970: 2), kind: .browserDomain, browserDomain: "docs.rs"),
            ActivityEvent(timestamp: Date(timeIntervalSince1970: 3), kind: .browserDomain, browserDomain: "rust-book.cs.brown.edu"),
        ]

        XCTAssertTrue(events.allSatisfy { resolver.category(for: $0) == .productive })
    }

    // default resolver classifies AI and HackMD work as productive
    func testDefaultResolverClassifiesAIAndHackMDWork() {
        let resolver = CategoryResolver()
        let events = [
            ActivityEvent(timestamp: Date(timeIntervalSince1970: 0), kind: .appActivated, appName: "Claude"),
            ActivityEvent(timestamp: Date(timeIntervalSince1970: 1), kind: .browserDomain, browserDomain: "chatgpt.com"),
            ActivityEvent(timestamp: Date(timeIntervalSince1970: 2), kind: .browserDomain, browserDomain: "hackmd.io"),
        ]

        XCTAssertTrue(events.allSatisfy { resolver.category(for: $0) == .productive })
    }

    // browser window title can provide a productive display name
    func testBrowserTitleProvidesDisplayName() {
        let resolver = CategoryResolver()
        let event = ActivityEvent(
            timestamp: Date(timeIntervalSince1970: 0),
            kind: .appActivated,
            appName: "Brave Browser",
            windowTitle: "Week 2 - HackMD - Brave"
        )

        XCTAssertTrue(resolver.category(for: event) == .productive)
        XCTAssertTrue(resolver.displayName(for: event) == "HackMD")
    }

    // known domains use their category display names
    func testKnownDomainsUseDisplayNames() {
        let resolver = CategoryResolver()
        let events = [
            ActivityEvent(timestamp: Date(timeIntervalSince1970: 0), kind: .browserDomain, browserDomain: "hackmd.io"),
            ActivityEvent(timestamp: Date(timeIntervalSince1970: 1), kind: .browserDomain, browserDomain: "chatgpt.com"),
        ]

        XCTAssertTrue(events.map { resolver.displayName(for: $0) } == ["HackMD", "ChatGPT"])
    }
}

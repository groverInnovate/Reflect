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
        #expect(resolver.displayName(for: event) == "example.com")
    }
}

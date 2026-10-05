import Foundation

public enum DefaultAppCategories {
    public static let all: [AppCategorySeed] = productive + neutral + distracting

    public static let productive: [AppCategorySeed] = [
        .init("com.microsoft.VSCode", "VS Code", .productive),
        .init("com.apple.dt.Xcode", "Xcode", .productive),
        .init("com.apple.Terminal", "Terminal", .productive),
        .init("com.googlecode.iterm2", "iTerm", .productive),
        .init("cargo", "Cargo", .productive),
        .init("rustc", "Rust", .productive),
        .init("forge", "Foundry", .productive),
        .init("hardhat", "Hardhat", .productive),
        .init("nargo", "Noir", .productive),
        .init("github.com", "GitHub", .productive),
        .init("localhost", "Localhost", .productive),
        .init("127.0.0.1", "Localhost", .productive),
        .init("com.postmanlabs.mac", "Postman", .productive),
        .init("com.usebruno.app", "Bruno", .productive),
        .init("md.obsidian", "Obsidian", .productive),
        .init("notion.so", "Notion", .productive),
        .init("claude", "Claude", .productive),
        .init("anthropic", "Claude", .productive),
        .init("chatgpt.com", "ChatGPT", .productive),
        .init("chat.openai.com", "ChatGPT", .productive),
        .init("hackmd.io", "HackMD", .productive),
        .init("HackMD", "HackMD", .productive),
        .init("docs.google.com", "Google Docs", .productive),
        .init("drive.google.com", "Google Drive", .productive),
        .init("developer.apple.com", "Apple Developer Docs", .productive),
        .init("docs.rs", "Rust Docs", .productive),
        .init("rust-book.cs.brown.edu", "Rust Book", .productive),
        .init("doc.rust-lang.org/book", "Rust Book", .productive),
        .init("stackoverflow.com", "Stack Overflow", .productive),
        .init("arxiv.org", "Research Papers", .productive),
        .init("overleaf.com", "Overleaf", .productive),
        .init("coursera.org", "Coursera", .productive),
        .init("edx.org", "edX", .productive),
        .init("khanacademy.org", "Khan Academy", .productive),
        .init("lecture", "Lecture", .productive),
        .init("course", "Course", .productive),
        .init(".pdf", "PDF Reading", .productive),
    ]

    public static let neutral: [AppCategorySeed] = [
        .init("com.tinyspeck.slackmacgap", "Slack", .neutral),
        .init("com.apple.mail", "Mail", .neutral),
        .init("com.apple.iCal", "Calendar", .neutral),
        .init("com.apple.MobileSMS", "Messages", .neutral),
        .init("us.zoom.xos", "Zoom", .neutral),
    ]

    public static let distracting: [AppCategorySeed] = [
        .init("twitter.com", "Twitter / X", .distracting),
        .init("x.com", "Twitter / X", .distracting),
        .init("instagram.com", "Instagram", .distracting),
        .init("youtube.com", "YouTube", .distracting),
        .init("reddit.com", "Reddit", .distracting),
        .init("web.whatsapp.com", "WhatsApp Web", .distracting),
        .init("netflix.com", "Netflix", .distracting),
    ]
}

public struct AppCategorySeed: Equatable, Sendable {
    public var matchPattern: String
    public var displayName: String
    public var category: FocusCategory

    public init(_ matchPattern: String, _ displayName: String, _ category: FocusCategory) {
        self.matchPattern = matchPattern
        self.displayName = displayName
        self.category = category
    }
}

public struct CategoryResolver: Sendable {
    private let seeds: [AppCategorySeed]

    public init(seeds: [AppCategorySeed] = DefaultAppCategories.all) {
        self.seeds = seeds
    }

    public func category(for event: ActivityEvent) -> FocusCategory {
        matchedSeed(for: event)?.category ?? .neutral
    }

    public func displayName(for event: ActivityEvent) -> String {
        if let seed = matchedSeed(for: event) {
            return seed.displayName
        }
        if let domain = event.browserDomain, !domain.isEmpty {
            return domain
        }
        if let appName = event.appName, !appName.isEmpty {
            return appName
        }
        return event.appBundleID ?? "Unknown"
    }

    private func matchedSeed(for event: ActivityEvent) -> AppCategorySeed? {
        let ranked = seeds.enumerated().sorted {
            let left = $0.element.matchPattern.count
            let right = $1.element.matchPattern.count
            return left == right ? $0.offset < $1.offset : left > right
        }.map(\.element)
        if let domain = event.browserDomain?.lowercased(), !domain.isEmpty {
            // The collector stores hosts, never URL paths. Match domain boundaries,
            // so x.com does not match unrelated sites ending in those letters.
            if let match = ranked.first(where: {
                let pattern = $0.matchPattern.lowercased()
                return !pattern.contains("/") && (domain == pattern || domain.hasSuffix("." + pattern))
            }) { return match }
            // A known domain is stronger evidence than ambiguous title words.
            return nil
        }
        if let bundle = event.appBundleID?.lowercased(),
           let match = ranked.first(where: { $0.matchPattern.lowercased() == bundle }) {
            return match
        }
        let text = [event.appName, event.windowTitle].compactMap { $0?.lowercased() }.joined(separator: " ")
        return ranked.first { (!$0.matchPattern.contains(".") || $0.matchPattern.hasPrefix(".")) && text.contains($0.matchPattern.lowercased()) }
    }
}

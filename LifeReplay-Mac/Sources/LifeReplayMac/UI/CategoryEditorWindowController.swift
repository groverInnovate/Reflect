import Foundation
import LifeReplayCore
import SwiftUI

private struct CategoryDraft: Identifiable {
    var id = UUID()
    var pattern: String
    var name: String
    var category: FocusCategory
}

struct CategoryRulesView: View {
    let store: LifeReplayStore
    @Environment(\.dismiss) private var dismiss
    @State private var rules: [CategoryDraft] = []
    @State private var search = ""
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Categories").font(.title2.weight(.semibold))
            Text("Choose what counts as work for you. Changes apply to past days as well.")
                .font(.callout).foregroundStyle(.secondary)
            TextField("Search rules", text: $search).textFieldStyle(.roundedBorder)
            HStack {
                Text("APP / DOMAIN / TITLE").frame(width: 250, alignment: .leading)
                Text("DISPLAY NAME").frame(width: 190, alignment: .leading)
                Text("CATEGORY")
            }.font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach($rules) { $rule in
                        if search.isEmpty || rule.name.localizedCaseInsensitiveContains(search)
                            || rule.pattern.localizedCaseInsensitiveContains(search) {
                            HStack {
                                TextField("Domain or bundle ID", text: $rule.pattern).frame(width: 250)
                                TextField("Name", text: $rule.name).frame(width: 190)
                                Picker("Category", selection: $rule.category) {
                                    Text("Work").tag(FocusCategory.productive)
                                    Text("Other").tag(FocusCategory.neutral)
                                    Text("Distractions").tag(FocusCategory.distracting)
                                }.labelsHidden().frame(width: 130)
                                Button {
                                    rules.removeAll { $0.id == rule.id }
                                } label: { Image(systemName: "minus.circle") }
                                    .buttonStyle(.borderless).help("Remove \(rule.name)")
                            }.textFieldStyle(.roundedBorder)
                        }
                    }
                }
            }
            Text("Domains match exactly or as subdomains. App bundle IDs match exactly. Title keywords are used when no website is captured; longer rules take priority.")
                .font(.caption).foregroundStyle(.secondary)
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
            HStack {
                Button("Add rule") {
                    search = ""
                    rules.insert(CategoryDraft(pattern: "", name: "", category: .neutral), at: 0)
                }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") { save() }.keyboardShortcut(.defaultAction)
            }
        }.padding(28).frame(width: 690, height: 540)
            .onAppear {
                rules = store.categories().map { CategoryDraft(pattern: $0.matchPattern, name: $0.displayName, category: $0.category) }
            }
    }

    private func save() {
        let seeds = rules.map {
            AppCategorySeed($0.pattern.trimmingCharacters(in: .whitespacesAndNewlines),
                            $0.name.trimmingCharacters(in: .whitespacesAndNewlines), $0.category)
        }
        guard !seeds.contains(where: { $0.matchPattern.isEmpty || $0.displayName.isEmpty }) else {
            error = "Every rule needs a match pattern and a display name."
            return
        }
        guard Set(seeds.map { $0.matchPattern.lowercased() }).count == seeds.count else {
            error = "Each match pattern must be unique."
            return
        }
        do { try store.replaceCategories(with: seeds); dismiss() }
        catch { self.error = "Could not save categories: \(error.localizedDescription)" }
    }
}

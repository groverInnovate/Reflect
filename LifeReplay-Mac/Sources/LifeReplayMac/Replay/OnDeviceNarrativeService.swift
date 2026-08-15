import Foundation
import LifeReplayCore
import OSLog

#if canImport(FoundationModels)
import FoundationModels
#endif

struct NarrativeResult {
    var summary: String
    var usedOnDeviceAI: Bool
}

@MainActor
struct OnDeviceNarrativeService {
    private let logger = Logger(subsystem: "LifeReplayMac", category: "Narrative")

    func generate(
        blocks: [TimelineBlock],
        driftEvents: [LifeReplayCore.DriftEvent],
        focusScore: Int,
        fallback: String
    ) async -> NarrativeResult {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            return await generateWithFoundationModels(
                blocks: blocks,
                driftEvents: driftEvents,
                focusScore: focusScore,
                fallback: fallback
            )
        }
        #endif

        return NarrativeResult(summary: fallback, usedOnDeviceAI: false)
    }

    #if canImport(FoundationModels)
    @available(macOS 26.0, *)
    private func generateWithFoundationModels(
        blocks: [TimelineBlock],
        driftEvents: [LifeReplayCore.DriftEvent],
        focusScore: Int,
        fallback: String
    ) async -> NarrativeResult {
        let model = SystemLanguageModel.default
        guard case .available = model.availability else {
            logger.info("Foundation Models unavailable: \(String(describing: model.availability), privacy: .public)")
            return NarrativeResult(summary: fallback, usedOnDeviceAI: false)
        }

        do {
            let session = LanguageModelSession(
                model: model,
                instructions: "Write short, factual daily activity recaps. Avoid motivational language."
            )
            let response = try await session.respond(
                to: prompt(blocks: blocks, driftEvents: driftEvents, focusScore: focusScore),
                options: GenerationOptions(sampling: .greedy, temperature: 0.2, maximumResponseTokens: 120)
            )
            let trimmed = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                return NarrativeResult(summary: fallback, usedOnDeviceAI: false)
            }
            return NarrativeResult(summary: trimmed, usedOnDeviceAI: true)
        } catch {
            logger.error("Foundation Models summary failed: \(error.localizedDescription, privacy: .public)")
            return NarrativeResult(summary: fallback, usedOnDeviceAI: false)
        }
    }
    #endif

    private func prompt(blocks: [TimelineBlock], driftEvents: [LifeReplayCore.DriftEvent], focusScore: Int) -> String {
        let timelineLines = blocks.prefix(12).map { block in
            let minutes = Int(block.end.timeIntervalSince(block.start) / 60)
            return "- \(block.label), \(minutes)m, \(block.category.rawValue)"
        }.joined(separator: "\n")

        let driftLines = driftEvents.prefix(6).map { drift in
            let triggers = drift.triggerAppNames.isEmpty ? "unknown" : drift.triggerAppNames.joined(separator: ", ")
            return "- \(drift.switchCountInWindow) switches; triggers: \(triggers)"
        }.joined(separator: "\n")

        return """
        Summarize this day in one concise productivity-journal paragraph. Include what happened, focus quality, productive/study time, wasted/distraction time, and the main lesson. Be specific and descriptive, not motivational.

        Focus score: \(focusScore)/100

        Timeline:
        \(timelineLines.isEmpty ? "No sustained blocks." : timelineLines)

        Drift events:
        \(driftLines.isEmpty ? "None detected." : driftLines)
        """
    }
}

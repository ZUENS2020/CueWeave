import Foundation

extension ProjectStore {
    var hasGeminiSuggestions: Bool {
        allSegments.contains { $0.timing.gemini != nil }
    }

    func restoreGeminiAlignment() async {
        guard let projectURL, hasGeminiSuggestions else { return }
        save()
        await operation("Restoring Gemini alignment") {
            try await CoreBridge.call("restore_gemini", payload: ["project_path": projectURL.path])
            try self.openProject(projectURL, preservingCurrentForUndo: true)
            self.selection = .alignment
            self.activity = "Restored every Final time from Gemini"
        }
    }

    func applyRawLyrics(original: String, translation: String) async {
        guard let projectURL else { return }
        await operation("Applying lyrics") {
            try await CoreBridge.call("replace_lyrics", payload: [
                "project_path": projectURL.path,
                "original": original,
                "translation": translation,
            ])
            try self.openProject(projectURL, preservingCurrentForUndo: true)
            self.selection = .lyrics
        }
    }

    func fetchLyrics() async {
        guard let projectURL else { return }
        save()
        await operation("Fetching NetEase lyrics") {
            try await CoreBridge.call("fetch_lyrics", payload: ["project_path": projectURL.path])
            try self.openProject(projectURL, preservingCurrentForUndo: true)
            self.selection = .lyrics
        }
    }

    func align(segmentIDs: Set<UInt64> = []) async {
        guard let projectURL else { return }
        save()
        let provider = alignmentProvider
        let label = segmentIDs.isEmpty ? "Aligning through \(provider.title)" : "Re-aligning selection"
        await operation(label) {
            try await CoreBridge.call("align", payload: [
                "project_path": projectURL.path,
                "provider": provider.rawValue,
                "api_key": self.alignmentAPIKey,
                "model": provider == .openRouter ? self.openRouterModel : self.aiStudioModel,
                "segment_ids": segmentIDs.sorted(),
            ])
            try self.openProject(projectURL, preservingCurrentForUndo: true)
            self.selection = .alignment
            self.activity = segmentIDs.isEmpty
                ? "Gemini alignment ready for review"
                : "Re-aligned \(segmentIDs.count) selected segment(s)"
        }
    }
}

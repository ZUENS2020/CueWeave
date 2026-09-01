import Foundation

extension ProjectStore {
    var hasGeminiSuggestions: Bool {
        allSegments.contains { $0.timing.gemini != nil }
    }

    func restoreGeminiAlignment() async {
        guard let projectURL, hasGeminiSuggestions else { return }
        save()
        await operation(L10n.shared.t("activity.restoringGemini")) {
            try await CoreBridge.call("restore_gemini", payload: ["project_path": projectURL.path])
            try self.openProject(projectURL, preservingCurrentForUndo: true)
            self.selection = .alignment
            self.activity = L10n.shared.t("activity.restoredGemini")
        }
    }

    func applyRawLyrics(original: String, translation: String) async {
        guard let projectURL else { return }
        await operation(L10n.shared.t("activity.applyingLyrics")) {
            try await CoreBridge.call("replace_lyrics", payload: [
                "project_path": projectURL.path,
                "original": original,
                "translation": translation,
            ])
            try self.openProject(projectURL, preservingCurrentForUndo: true)
            self.selection = .lyrics
        }
    }

    func insertLyrics(after lineID: UInt64?, text: String) async -> Bool {
        guard let projectURL else { return false }
        save()
        var ok = false
        await operation(L10n.shared.t("activity.insertingLyrics")) {
            var payload: [String: Any] = [
                "project_path": projectURL.path,
                "text": text,
            ]
            if let lineID { payload["after_line_id"] = lineID }
            try await CoreBridge.call("insert_lyrics", payload: payload)
            try self.openProject(projectURL, preservingCurrentForUndo: true)
            self.selection = .lyrics
            ok = true
        }
        return ok
    }

    func fetchLyrics() async {
        guard let projectURL else { return }
        save()
        await operation(L10n.shared.t("activity.fetchingLyrics")) {
            try await CoreBridge.call("fetch_lyrics", payload: ["project_path": projectURL.path])
            try self.openProject(projectURL, preservingCurrentForUndo: true)
            self.selection = .lyrics
        }
    }

    func align(segmentIDs: Set<UInt64> = []) async {
        guard let projectURL else { return }
        save()
        let provider = alignmentProvider
        let label = segmentIDs.isEmpty
            ? L10n.shared.t("activity.aligning", provider.title)
            : L10n.shared.t("activity.aligningSelection")
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
                ? L10n.shared.t("activity.geminiReady")
                : L10n.shared.t("activity.realigned", String(segmentIDs.count))
        }
    }
}

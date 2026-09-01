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
}

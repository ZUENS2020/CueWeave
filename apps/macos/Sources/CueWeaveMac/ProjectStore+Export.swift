import Foundation

extension ProjectStore {
    func applyRawTranslations(_ translation: String) async {
        guard let projectURL else { return }
        save()
        await operation("Applying translations") {
            try await CoreBridge.call("replace_translations", payload: [
                "project_path": projectURL.path,
                "translation": translation,
            ])
            try self.openProject(projectURL, preservingCurrentForUndo: true)
            self.selection = .translation
            let count = self.project?.lyrics.lines.filter { $0.translation?.isEmpty == false }.count ?? 0
            self.activity = "Imported \(count) translation line(s)"
        }
    }

    func translateLyrics(targetLanguage: String) async {
        guard let projectURL else { return }
        save()
        let provider = alignmentProvider
        await operation("Translating through \(provider.title)") {
            try await CoreBridge.call("translate", payload: [
                "project_path": projectURL.path,
                "provider": provider.rawValue,
                "api_key": self.alignmentAPIKey,
                "model": provider == .openRouter ? self.openRouterModel : self.aiStudioModel,
                "target_language": targetLanguage,
            ])
            try self.openProject(projectURL, preservingCurrentForUndo: true)
            self.selection = .translation
            self.activity = "Gemini translation ready for review"
        }
    }

    func clearTranslations() {
        mutate { document in
            for index in document.lyrics.lines.indices {
                document.lyrics.lines[index].translation = nil
            }
        }
    }

    @MainActor
    func exportInteractive() async {
        guard let projectURL, let output = chooseMP3Destination() else { return }
        save()
        await operation("Exporting without re-encoding") {
            try await CoreBridge.call("export", payload: [
                "project_path": projectURL.path,
                "output_path": output.path,
            ])
            self.activity = "Exported \(output.lastPathComponent)"
        }
    }

    @MainActor
    func exportCueSheetInteractive() async {
        guard let projectURL, let output = chooseCueSheetDestination() else { return }
        save()
        await operation("Writing cue sheet") {
            try await CoreBridge.call("export_cuesheet", payload: [
                "project_path": projectURL.path,
                "output_path": output.path,
            ])
            self.activity = "Wrote \(output.lastPathComponent)"
        }
    }
}

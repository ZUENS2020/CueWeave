import AppKit
import Foundation

extension ProjectStore {
    func applyRawTranslations(_ translation: String) async {
        guard let projectURL else { return }
        save()
        await operation(L10n.shared.t("activity.applyingTranslations")) {
            try await CoreBridge.call("replace_translations", payload: [
                "project_path": projectURL.path,
                "translation": translation,
            ])
            try self.openProject(projectURL, preservingCurrentForUndo: true)
            self.selection = .translation
            let count = self.project?.lyrics.lines.filter { $0.translation?.isEmpty == false }.count ?? 0
            self.activity = L10n.shared.t("activity.importedTranslations", String(count))
        }
    }

    func translateLyrics(targetLanguage: String) async {
        guard let projectURL else { return }
        save()
        let provider = alignmentProvider
        await operation(L10n.shared.t("activity.translating", provider.title)) {
            try await CoreBridge.call("translate", payload: [
                "project_path": projectURL.path,
                "provider": provider.rawValue,
                "api_key": self.alignmentAPIKey,
                "model": provider == .openRouter ? self.openRouterModel : self.aiStudioModel,
                "target_language": targetLanguage,
            ])
            try self.openProject(projectURL, preservingCurrentForUndo: true)
            self.selection = .translation
            self.activity = L10n.shared.t("activity.translationReady")
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
        guard let overwrite = resolveExportOverwrite(for: output) else { return }
        save()
        await operation(L10n.shared.t("activity.exporting")) {
            try await CoreBridge.call("export", payload: [
                "project_path": projectURL.path,
                "output_path": output.path,
                "overwrite": overwrite,
            ])
            self.activity = L10n.shared.t("activity.exported", output.lastPathComponent)
        }
    }

    @MainActor
    private func resolveExportOverwrite(for output: URL) -> Bool? {
        if !exportOutputExists(output) { return overwriteExistingExport }
        if overwriteExistingExport { return true }
        let alert = NSAlert()
        alert.messageText = L10n.shared.t("export.overwriteConfirmTitle")
        alert.informativeText = L10n.shared.t("export.overwriteConfirmMessage", output.lastPathComponent)
        alert.addButton(withTitle: L10n.shared.t("export.overwrite"))
        alert.addButton(withTitle: L10n.shared.t("action.cancel"))
        return alert.runModal() == .alertFirstButtonReturn ? true : nil
    }

    private func exportOutputExists(_ output: URL) -> Bool {
        let files = FileManager.default
        if files.fileExists(atPath: output.path) { return true }
        guard project?.exportProfile.formats.contains(.lrc) == true else { return false }
        let lrc = output.deletingPathExtension().appendingPathExtension("lrc")
        return files.fileExists(atPath: lrc.path)
    }

    @MainActor
    func exportCueSheetInteractive() async {
        guard let projectURL, let output = chooseCueSheetDestination() else { return }
        save()
        await operation(L10n.shared.t("activity.writingCueSheet")) {
            try await CoreBridge.call("export_cuesheet", payload: [
                "project_path": projectURL.path,
                "output_path": output.path,
            ])
            self.activity = L10n.shared.t("activity.wrote", output.lastPathComponent)
        }
    }
}

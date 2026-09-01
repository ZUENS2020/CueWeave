import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

final class ProjectStore: ObservableObject, ReferenceFileDocument {
    static let readableContentTypes: [UTType] = [.cueWeaveProject]
    private static let initialSettings: LocalSettings = {
        let loaded = LocalSettingsStore.load()
        L10n.shared.setPreference(loaded.uiLanguage ?? "system")
        return loaded
    }()

    @Published var project: ProjectDocument?
    @Published var selection: WorkspacePage = .source
    @Published var isBusy = false
    @Published var activity: String = {
        _ = initialSettings
        return L10n.shared.t("activity.none")
    }()
    @Published var errorMessage: String?
    @Published var hasUnsavedChanges = false
    @Published var alignmentProvider = AlignmentProvider(
        rawValue: initialSettings.alignmentProvider ?? ""
    ) ?? .openRouter
    @Published var openRouterAPIKey = initialSettings.openRouterAPIKey ?? ""
    @Published var aiStudioAPIKey = initialSettings.aiStudioAPIKey ?? ""
    @Published var openRouterModel = initialSettings.openRouterModel ?? "google/gemini-3.7-flash"
    @Published var aiStudioModel = initialSettings.aiStudioModel ?? "gemini-3.7-flash"
    @Published var uiLanguage = initialSettings.uiLanguage ?? "system"
    @Published var overwriteExistingExport = true

    @MainActor private var playerStorage: AudioPlayer?
    @MainActor private var waveformStorage: WaveformModel?

    @MainActor
    var player: AudioPlayer {
        if let playerStorage { return playerStorage }
        let created = AudioPlayer()
        playerStorage = created
        return created
    }

    @MainActor
    var waveform: WaveformModel {
        if let waveformStorage { return waveformStorage }
        let created = WaveformModel()
        waveformStorage = created
        return created
    }

    @Published private(set) var projectURL: URL?
    private weak var documentUndoManager: UndoManager?
    private var undoObserver: NSObjectProtocol?
    private var cancellationRequested = false

    nonisolated init() {}

    nonisolated convenience init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        try self.init(encodedProject: data)
    }

    nonisolated convenience init(encodedProject data: Data) throws {
        self.init()
        var decoded = try JSONDecoder().decode(ProjectDocument.self, from: data)
        let migrated = decoded.schemaVersion == 1
        guard decoded.schemaVersion <= 2 else { throw CocoaError(.fileReadUnknown) }
        if decoded.schemaVersion == 1 { decoded.schemaVersion = 2 }
        project = decoded
        hasUnsavedChanges = migrated
        activity = L10n.shared.t("activity.loaded")
    }

    nonisolated func snapshot(contentType: UTType) throws -> ProjectDocument? { project }

    nonisolated func fileWrapper(snapshot: ProjectDocument?, configuration: WriteConfiguration) throws -> FileWrapper {
        guard let snapshot else { return FileWrapper(regularFileWithContents: Data()) }
        let data = try encode(snapshot)
        let object = try JSONSerialization.jsonObject(with: data)
        var payload: [String: Any] = ["project": object]
        if let url = projectURL { payload["project_path"] = url.path }
        try CoreBridge.callBlocking("save_project", payload: payload)
        if let url = projectURL {
            return FileWrapper(regularFileWithContents: try Data(contentsOf: url))
        }
        return FileWrapper(regularFileWithContents: data)
    }

    var title: String { project?.metadata.draft.title ?? "CueWeave" }
    var projectPath: String { projectURL?.path ?? L10n.shared.t("project.noFile") }
    var saveState: String {
        L10n.shared.t(hasUnsavedChanges ? "status.edited" : "status.saved")
    }
    var canUndo: Bool { resolvedUndoManager?.canUndo == true }
    var canRedo: Bool { resolvedUndoManager?.canRedo == true }
    var allSegments: [LyricSegment] { project?.lyrics.lines.flatMap(\.segments) ?? [] }
    var alignmentAPIKey: String {
        alignmentProvider == .openRouter ? openRouterAPIKey : aiStudioAPIKey
    }
    var settingsPath: String { LocalSettingsStore.configURL.path }

    @MainActor
    func createInteractive() async {
        guard let source = chooseFile(extension: "ncm", title: L10n.shared.t("pick.ncm")),
              let target = chooseFile(extension: "mp3", title: L10n.shared.t("pick.mp3")),
              let output = chooseProjectDestination(defaultName: target.deletingPathExtension().lastPathComponent)
        else { return }
        await operation(L10n.shared.t("activity.creating")) {
            try await CoreBridge.call("create", payload: [
                "project_path": output.path,
                "source_path": source.path,
                "target_path": target.path,
            ])
            await MainActor.run { self.presentProject(at: output) }
            self.activity = L10n.shared.t("activity.created")
        }
    }

    @MainActor
    func openInteractive() {
        let panel = NSOpenPanel()
        panel.title = L10n.shared.t("welcome.open")
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = Self.readableContentTypes
        guard panel.runModal() == .OK, let url = panel.url else { return }
        presentProject(at: url)
    }

    @MainActor
    private func presentProject(at url: URL) {
        if let existing = NSDocumentController.shared.document(for: url) {
            existing.showWindows()
            return
        }
        let current = NSDocumentController.shared.currentDocument
        if current?.fileURL == nil {
            do {
                try openProject(url)
                current?.fileURL = url
                current?.fileType = UTType.cueWeaveProject.identifier
                current?.updateChangeCount(.changeCleared)
                NSDocumentController.shared.noteNewRecentDocumentURL(url)
            } catch {
                errorMessage = error.localizedDescription
            }
            return
        }
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
            DispatchQueue.main.async {
                if let error { self.errorMessage = error.localizedDescription }
            }
        }
    }

    @MainActor
    func attachDocument(url: URL?, undoManager: UndoManager?) {
        if let url {
            projectURL = url
        }
        bindUndoManager(undoManager ?? NSDocumentController.shared.currentDocument?.undoManager)
        if project != nil { loadAudio() }
    }

    func updateUndoManager(_ undoManager: UndoManager?) {
        bindUndoManager(undoManager ?? NSDocumentController.shared.currentDocument?.undoManager)
    }

    func undo() {
        resolvedUndoManager?.undo()
    }

    func redo() {
        resolvedUndoManager?.redo()
    }

    @MainActor
    func replaceTargetInteractive() async {
        guard let projectURL,
              let target = chooseFile(extension: "mp3", title: L10n.shared.t("pick.replaceMp3"))
        else { return }
        save()
        await operation(L10n.shared.t("activity.replacingTarget")) {
            try await CoreBridge.call("retarget", payload: [
                "project_path": projectURL.path,
                "target_path": target.path,
            ])
            try self.openProject(projectURL, preservingCurrentForUndo: true)
            self.selection = .source
        }
    }

    func openProject(_ url: URL, preservingCurrentForUndo: Bool = false) throws {
        let previous = preservingCurrentForUndo ? project : nil
        var decoded = try JSONDecoder().decode(ProjectDocument.self, from: Data(contentsOf: url))
        let migrated = decoded.schemaVersion == 1
        guard decoded.schemaVersion <= 2 else {
            throw CoreBridgeError.invalidResponse("project schema \(decoded.schemaVersion) is newer than this app")
        }
        if decoded.schemaVersion == 1 { decoded.schemaVersion = 2 }
        projectURL = url
        project = decoded
        if let previous, previous != decoded {
            registerUndo(previous)
        } else if !preservingCurrentForUndo {
            documentUndoManager?.removeAllActions()
        }
        selection = .source
        hasUnsavedChanges = migrated
        activity = L10n.shared.t("activity.loaded")
        Task { @MainActor in
            self.loadAudio()
        }
    }

    func save() {
        guard let project, let projectURL else { return }
        do {
            let data = try encode(project)
            let object = try JSONSerialization.jsonObject(with: data)
            try CoreBridge.callBlocking("save_project", payload: [
                "project_path": projectURL.path,
                "project": object,
            ])
            hasUnsavedChanges = false
            activity = L10n.shared.t("activity.saved")
        } catch { errorMessage = error.localizedDescription }
    }

    func scheduleAutosave() {
        activity = L10n.shared.t("activity.edited")
    }

    func mutate(_ body: (inout ProjectDocument) -> Void) {
        if documentUndoManager == nil {
            bindUndoManager(NSDocumentController.shared.currentDocument?.undoManager)
        }
        guard var document = project else { return }
        let previous = document
        body(&document)
        guard document != previous else { return }
        registerUndo(previous)
        project = document
        hasUnsavedChanges = true
        scheduleAutosave()
    }

    func cancelOperation() {
        cancellationRequested = true
        activity = L10n.shared.t("activity.cancelling")
        CoreBridge.cancelActive()
    }

    func draftBinding(_ keyPath: WritableKeyPath<MetadataValues, String?>) -> Binding<String> {
        Binding(
            get: { self.project?.metadata.draft[keyPath: keyPath] ?? "" },
            set: { value in
                self.mutate { $0.metadata.draft[keyPath: keyPath] = value.isEmpty ? nil : value }
            }
        )
    }

    func artistsBinding() -> Binding<String> {
        Binding(
            get: { self.project?.metadata.draft.artists.joined(separator: " / ") ?? "" },
            set: { value in
                self.mutate {
                    $0.metadata.draft.artists = value
                        .split(separator: "/")
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                }
            }
        )
    }

    func numberBinding(_ keyPath: WritableKeyPath<MetadataValues, UInt32?>) -> Binding<String> {
        Binding(
            get: { self.project?.metadata.draft[keyPath: keyPath].map(String.init) ?? "" },
            set: { value in
                self.mutate { $0.metadata.draft[keyPath: keyPath] = UInt32(value) }
            }
        )
    }

    func adoptMetadata(
        _ keyPath: WritableKeyPath<MetadataValues, String?>,
        from origin: MetadataOrigin
    ) {
        mutate { document in
            let values = origin == .source ? document.metadata.source : document.metadata.target
            document.metadata.draft[keyPath: keyPath] = values[keyPath: keyPath]
        }
    }

    func adoptNumber(
        _ keyPath: WritableKeyPath<MetadataValues, UInt32?>,
        from origin: MetadataOrigin
    ) {
        mutate { document in
            let values = origin == .source ? document.metadata.source : document.metadata.target
            document.metadata.draft[keyPath: keyPath] = values[keyPath: keyPath]
        }
    }

    func adoptArtists(from origin: MetadataOrigin) {
        mutate { document in
            document.metadata.draft.artists = origin == .source
                ? document.metadata.source.artists : document.metadata.target.artists
        }
    }

    @MainActor
    func replaceCoverInteractive() {
        let panel = NSOpenPanel()
        panel.title = L10n.shared.t("pick.cover")
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.png, .jpeg]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        mutate { $0.metadata.draft.coverPath = url.path }
    }

    func updateCredit(at index: Int, label: String? = nil, value: String? = nil) {
        mutate { document in
            guard document.lyrics.credits.indices.contains(index) else { return }
            if let label { document.lyrics.credits[index].label = label }
            if let value { document.lyrics.credits[index].value = value }
        }
    }

    func addCredit() {
        mutate { $0.lyrics.credits.append(Credit(label: "Role", value: "Name")) }
    }

    func removeCredit(at index: Int) {
        mutate { document in
            guard document.lyrics.credits.indices.contains(index) else { return }
            document.lyrics.credits.remove(at: index)
        }
    }

    func updateLine(_ lineID: UInt64, original: String? = nil, translation: String? = nil) {
        mutate { document in
            guard let index = document.lyrics.lines.firstIndex(where: { $0.id == lineID }) else { return }
            if let original {
                document.lyrics.lines[index].original = original
                if document.lyrics.lines[index].segments.count == 1 {
                    document.lyrics.lines[index].segments[0].text = original
                }
            }
            if let translation {
                document.lyrics.lines[index].translation = translation.isEmpty ? nil : translation
            }
        }
    }

    func setFinal(segmentID: UInt64, milliseconds: UInt64) {
        mutate { document in
            let ordered = document.lyrics.lines.flatMap(\.segments)
            guard let flatIndex = ordered.firstIndex(where: { $0.id == segmentID }) else { return }
            let lower = flatIndex > 0 ? ordered[flatIndex - 1].timing.finalPoint?.timeMS ?? 0 : 0
            let upper = flatIndex + 1 < ordered.count ? ordered[flatIndex + 1].timing.finalPoint?.timeMS : nil
            let duration = document.target?.durationMS ?? UInt64.max
            let clamped = min(max(milliseconds, lower), min(upper ?? duration, duration))
            for lineIndex in document.lyrics.lines.indices {
                guard let segmentIndex = document.lyrics.lines[lineIndex].segments.firstIndex(where: { $0.id == segmentID }) else { continue }
                document.lyrics.lines[lineIndex].segments[segmentIndex].timing.finalPoint = AlignmentPoint(timeMS: clamped, confidence: nil)
                break
            }
        }
    }

    func clearFinal(segmentID: UInt64) {
        clearFinals(segmentIDs: Set([segmentID]))
    }

    func clearFinals(segmentIDs: Set<UInt64>) {
        guard !segmentIDs.isEmpty else { return }
        mutate { document in
            for lineIndex in document.lyrics.lines.indices {
                for segmentIndex in document.lyrics.lines[lineIndex].segments.indices
                    where segmentIDs.contains(document.lyrics.lines[lineIndex].segments[segmentIndex].id)
                {
                    document.lyrics.lines[lineIndex].segments[segmentIndex].timing.finalPoint = nil
                }
            }
        }
    }

    func acceptGeminiSuggestion(segmentID: UInt64) {
        mutate { document in
            for lineIndex in document.lyrics.lines.indices {
                guard let index = document.lyrics.lines[lineIndex].segments.firstIndex(where: {
                    $0.id == segmentID
                }) else { continue }
                let point = document.lyrics.lines[lineIndex].segments[index].timing.gemini
                guard let point else { return }
                document.lyrics.lines[lineIndex].segments[index].timing.finalPoint = point
                return
            }
        }
    }

    func persistSettings() {
        do {
            try LocalSettingsStore.save(LocalSettings(
                alignmentProvider: alignmentProvider.rawValue,
                openRouterAPIKey: openRouterAPIKey,
                aiStudioAPIKey: aiStudioAPIKey,
                openRouterModel: openRouterModel,
                aiStudioModel: aiStudioModel,
                uiLanguage: uiLanguage
            ))
            L10n.shared.setPreference(uiLanguage)
            activity = L10n.shared.t("activity.settingsSaved")
        } catch { errorMessage = error.localizedDescription }
    }

    func applyUiLanguage() {
        L10n.shared.setPreference(uiLanguage)
        if project == nil { activity = L10n.shared.t("activity.none") }
        objectWillChange.send()
    }

    func clearAPIKey(for provider: AlignmentProvider) {
        if provider == .openRouter { openRouterAPIKey = "" } else { aiStudioAPIKey = "" }
        persistSettings()
    }

    func formatBinding(_ format: ExportFormat) -> Binding<Bool> {
        Binding(
            get: { self.project?.exportProfile.formats.contains(format) == true },
            set: { enabled in
                self.mutate {
                    if enabled, !$0.exportProfile.formats.contains(format) { $0.exportProfile.formats.append(format) }
                    if !enabled { $0.exportProfile.formats.removeAll { $0 == format } }
                }
            }
        )
    }

    @MainActor
    func operation(_ label: String, body: @escaping () async throws -> Void) async {
        cancellationRequested = false
        isBusy = true
        activity = label
        defer { isBusy = false; cancellationRequested = false }
        do { try await body() } catch {
            if cancellationRequested { activity = L10n.shared.t("activity.cancelled") }
            else { errorMessage = actionableMessage(for: error); activity = L10n.shared.t("activity.failed") }
        }
    }

    private var resolvedUndoManager: UndoManager? {
        documentUndoManager ?? NSDocumentController.shared.currentDocument?.undoManager
    }

    private func bindUndoManager(_ undoManager: UndoManager?) {
        documentUndoManager = undoManager
        if let undoObserver {
            NotificationCenter.default.removeObserver(undoObserver)
            self.undoObserver = nil
        }
        guard let undoManager else { return }
        let center = NotificationCenter.default
        undoObserver = center.addObserver(
            forName: nil,
            object: undoManager,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            switch notification.name {
            case .NSUndoManagerDidUndoChange, .NSUndoManagerDidRedoChange, .NSUndoManagerDidCloseUndoGroup:
                self.objectWillChange.send()
            default:
                break
            }
        }
    }

    private func registerUndo(_ document: ProjectDocument) {
        resolvedUndoManager?.registerUndo(withTarget: self) { store in
            store.restoreForUndo(document)
        }
    }

    private func restoreForUndo(_ document: ProjectDocument) {
        guard let current = project else { return }
        registerUndo(current)
        project = document
        hasUnsavedChanges = true
        activity = L10n.shared.t(documentUndoManager?.isUndoing == true ? "activity.undid" : "activity.redid")
    }

    nonisolated private func encode(_ project: ProjectDocument) throws -> Data {
        var portable = project
        if let folder = projectURL?.deletingLastPathComponent() {
            portable = Self.withRelativePaths(portable, folder: folder)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(portable)
    }

    nonisolated private static func withRelativePaths(_ project: ProjectDocument, folder: URL) -> ProjectDocument {
        var portable = project
        if var source = portable.source {
            source.path = relativeMediaPath(source.path, to: folder)
            portable.source = source
        }
        if var target = portable.target {
            target.path = relativeMediaPath(target.path, to: folder)
            portable.target = target
        }
        portable.metadata.source.coverPath = portable.metadata.source.coverPath.map { relativeMediaPath($0, to: folder) }
        portable.metadata.target.coverPath = portable.metadata.target.coverPath.map { relativeMediaPath($0, to: folder) }
        portable.metadata.draft.coverPath = portable.metadata.draft.coverPath.map { relativeMediaPath($0, to: folder) }
        return portable
    }

    nonisolated private static func relativeMediaPath(_ path: String, to folder: URL) -> String {
        let portable = path.replacingOccurrences(of: "\\", with: "/")
        let folderPath = folder.standardizedFileURL.path
        let filePath = URL(fileURLWithPath: portable).standardizedFileURL.path
        let prefix = folderPath.hasSuffix("/") ? folderPath : folderPath + "/"
        if filePath.hasPrefix(prefix) {
            return String(filePath.dropFirst(prefix.count))
        }
        return portable
    }

    @MainActor
    private func loadAudio() {
        guard let path = project?.target?.path else { return }
        let url = resolveProjectPath(path, relativeTo: projectURL)
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        guard exists, !isDirectory.boolValue else {
            errorMessage = audioLoadMessage(for: url, error: CocoaError(.fileReadNoSuchFile))
            return
        }
        do {
            try player.load(url)
            waveform.load(url)
            if var document = project, document.target?.durationMS == nil {
                document.target?.durationMS = UInt64((player.duration * 1000).rounded())
                project = document
                hasUnsavedChanges = true
                scheduleAutosave()
            }
        } catch { errorMessage = audioLoadMessage(for: url, error: error) }
    }

    @MainActor
    private func chooseFile(extension fileExtension: String, title: String) -> URL? {
        let panel = NSOpenPanel()
        panel.title = title
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if let type = UTType(filenameExtension: fileExtension) { panel.allowedContentTypes = [type] }
        return panel.runModal() == .OK ? panel.url : nil
    }

    @MainActor
    private func chooseProjectDestination(defaultName: String) -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(defaultName).cueweave"
        if let type = UTType(filenameExtension: "cueweave") { panel.allowedContentTypes = [type] }
        return panel.runModal() == .OK ? panel.url : nil
    }

    @MainActor
    func chooseMP3Destination() -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(title) [CueWeave].mp3"
        panel.allowedContentTypes = [.mp3]
        return panel.runModal() == .OK ? panel.url : nil
    }

    @MainActor
    func chooseCueSheetDestination() -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(title).cuesheet.json"
        if let type = UTType(filenameExtension: "json") { panel.allowedContentTypes = [type] }
        return panel.runModal() == .OK ? panel.url : nil
    }
}

import Foundation
import Testing
@testable import CueWeaveMac

@Suite("Portable project")
struct ProjectPortabilityTests {
    @Test("Schema v2 preserves fingerprints and resolves relative media")
    func roundTrip() throws {
        let json = projectJSON
        let project = try JSONDecoder().decode(ProjectDocument.self, from: Data(json.utf8))
        #expect(project.target?.fingerprint?.sha256 == "bb")

        let projectURL = URL(fileURLWithPath: "/tmp/跨平台 项目/song.cueweave")
        #expect(
            resolveProjectPath(project.target!.path, relativeTo: projectURL).path
                == "/tmp/跨平台 项目/media/target.mp3"
        )
        let encoded = try JSONEncoder().encode(project)
        #expect(String(decoding: encoded, as: UTF8.self).contains("fingerprint"))
    }

    @Test("Relative cover art resolves against the project file, not the process working directory")
    func relativeCoverPath() {
        let projectURL = URL(fileURLWithPath: "/tmp/跨平台 项目/Beyond (Mix).cueweave")
        #expect(
            resolveProjectPath("Beyond (Mix).cover.jpg", relativeTo: projectURL).path
                == "/tmp/跨平台 项目/Beyond (Mix).cover.jpg"
        )
        #expect(
            resolveProjectPath("Beyond (Mix).cover.jpg", relativeTo: nil).path.hasSuffix("Beyond (Mix).cover.jpg")
        )
    }

    @Test("Opening a project keeps its file URL even if SwiftUI later reports a nil document URL")
    @MainActor
    func attachDocumentDoesNotClearExistingURL() {
        let store = ProjectStore()
        let url = URL(fileURLWithPath: "/tmp/Beyond (Mix).cueweave")
        store.attachDocument(url: url, undoManager: nil)
        #expect(store.projectURL == url)
        store.attachDocument(url: nil, undoManager: nil)
        #expect(store.projectURL == url)
    }

    @Test("System UndoManager owns edit history") @MainActor
    func systemUndo() throws {
        let store = ProjectStore()
        store.project = try JSONDecoder().decode(ProjectDocument.self, from: Data(projectJSON.utf8))
        let undo = UndoManager()
        store.attachDocument(url: nil, undoManager: undo)

        store.mutate { $0.metadata.draft.title = "Edited" }
        #expect(undo.canUndo)
        store.undo()
        #expect(store.project?.metadata.draft.title == nil)
        store.redo()
        #expect(store.project?.metadata.draft.title == "Edited")
    }

    @Test("Document factory can construct ProjectStore off the main actor")
    func documentFactoryOffMainActor() async throws {
        let json = projectJSON
        let empty = await Task.detached {
            ProjectStore()
        }.value
        #expect(empty.project == nil)

        let loaded = try await Task.detached {
            try ProjectStore(encodedProject: Data(json.utf8))
        }.value
        #expect(loaded.project?.target?.fingerprint?.sha256 == "bb")
        #expect(loaded.hasUnsavedChanges == false)
        #expect(loaded.activity == "Project loaded")
    }

    private var projectJSON: String {
        #"{"schema_version":2,"source":{"path":"media/source.ncm","fingerprint":{"file_name":"source.ncm","size_bytes":12,"sha256":"aa"}},"target":{"path":"media/target.mp3","fingerprint":{"file_name":"target.mp3","size_bytes":34,"sha256":"bb"},"duration_ms":149091},"metadata":{"source":{"artists":[]},"target":{"artists":[]},"draft":{"artists":[]}},"lyrics":{"credits":[],"lines":[]},"timeline":[],"export":{"offset_ms":0,"formats":["lrc"],"bilingual":"original_only"}}"#
    }
}

import AppKit
import SwiftUI

@main
enum CueWeaveMain {
    static func main() {
        if #available(macOS 15.0, *) {
            CueWeaveAppMac15.main()
        } else {
            CueWeaveAppMac14.main()
        }
    }
}

private struct CueWeaveDocumentRoot: View {
    @ObservedObject var store: ProjectStore
    let documentURL: URL?

    var body: some View {
        WorkspaceView(store: store, documentURL: documentURL)
            .frame(minWidth: 980, minHeight: 680)
            .tint(Color(red: 0.23, green: 0.43, blue: 0.56))
    }
}

@available(macOS 15.0, *)
private struct CueWeaveAppMac15: App {
    @NSApplicationDelegateAdaptor(CueWeaveAppDelegate.self) private var appDelegate

    var body: some Scene {
        DocumentGroup(newDocument: ProjectStore.init) { file in
            CueWeaveDocumentRoot(store: file.document, documentURL: file.fileURL)
        }
        .defaultLaunchBehavior(.suppressed)
        .commands { CueWeaveUndoCommands() }
    }
}

private struct CueWeaveAppMac14: App {
    @NSApplicationDelegateAdaptor(CueWeaveAppDelegate.self) private var appDelegate

    var body: some Scene {
        DocumentGroup(newDocument: ProjectStore.init) { file in
            CueWeaveDocumentRoot(store: file.document, documentURL: file.fileURL)
        }
        .commands { CueWeaveUndoCommands() }
    }
}

final class CueWeaveAppDelegate: NSObject, NSApplicationDelegate {
    private var creatingUntitled = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.set(false, forKey: "NSQuitAlwaysKeepsWindows")
        DispatchQueue.main.async { self.ensureUntitledDocument() }
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationOpenUntitledFile(_ sender: NSApplication) -> Bool {
        ensureUntitledDocument()
        return true
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            ensureUntitledDocument()
        }
        return true
    }

    private func ensureUntitledDocument() {
        guard NSDocumentController.shared.documents.isEmpty else { return }
        guard !creatingUntitled else { return }
        creatingUntitled = true
        defer { creatingUntitled = false }
        NSDocumentController.shared.newDocument(nil)
    }
}

private struct CueWeaveUndoCommands: Commands {
    @FocusedValue(\.cueWeaveStore) private var store

    var body: some Commands {
        CommandGroup(replacing: .undoRedo) {
            Button(L10n.shared.t("action.undo")) { store?.undo() }
                .keyboardShortcut("z")
            Button(L10n.shared.t("action.redo")) { store?.redo() }
                .keyboardShortcut("z", modifiers: [.command, .shift])
        }
    }
}

private struct CueWeaveStoreFocusKey: FocusedValueKey {
    typealias Value = ProjectStore
}

extension FocusedValues {
    var cueWeaveStore: ProjectStore? {
        get { self[CueWeaveStoreFocusKey.self] }
        set { self[CueWeaveStoreFocusKey.self] = newValue }
    }
}

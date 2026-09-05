import SwiftUI

@main
struct MotStarApp: App {
    @StateObject private var app = AppState.shared

    init() {
        WebKitImageProbe.runIfRequested()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(app)
                .frame(minWidth: 780, minHeight: 480)
        }
        .defaultSize(width: 1100, height: 700)
        .commands {
            MotStarCommands()
        }

        Window("About MotStar", id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)
    }
}

/// Menu bar commands. File items duplicate the toolbar actions and route
/// through the shared `AppState` so enablement stays in sync.
struct MotStarCommands: Commands {
    @ObservedObject private var app = AppState.shared
    @Environment(\.openWindow) private var openAboutWindow

    var body: some Commands {
        // File menu
        CommandGroup(after: .newItem) {
            Button("New Markdown File…") {
                app.createNewMarkdownFile()
            }
            .keyboardShortcut("n", modifiers: .command)

            Button("New Text File…") {
                app.createNewTextFile()
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])

            Divider()

            Button("Add Folder…") {
                app.showAddFolder = true
            }
            .keyboardShortcut("o", modifiers: .command)

            Divider()

            Button("Save") {
                app.saveActiveDocument()
            }
            .keyboardShortcut("s", modifiers: .command)
            .disabled(!(app.activeDocument?.isDirty ?? false))

            Button("Toggle Edit / Preview") {
                app.toggleEditPreview()
            }
            .keyboardShortcut("e", modifiers: .command)
            .disabled(!app.isSelectionEditable)

            Divider()

            Button("Print Selected File…") {
                app.printSelectedFile()
            }
            .keyboardShortcut("p", modifiers: .command)
            .disabled(app.selectedURL == nil || app.isWorking)

            Button("Export Selected File as PDF…") {
                app.exportSelectedFileAsPDF()
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])
            .disabled(app.selectedURL == nil || app.isWorking)

            Button("Email Selected File…") {
                app.emailSelectedFile()
            }
            .keyboardShortcut("m", modifiers: [.command, .shift])
            .disabled(app.selectedURL == nil)

            Button("Share Selected File…") {
                app.shareSelectedFile()
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])
            .disabled(app.selectedURL == nil)
        }

        // Edit menu: quick-find in the sidebar (⌘F). While the source editor
        // is open, ⌘F belongs to the editor's own find bar instead.
        CommandGroup(after: .textEditing) {
            Button("Find Files in Sidebar") {
                app.startSearch()
            }
            .keyboardShortcut("f", modifiers: .command)
            .disabled(app.paneMode == .editor && app.activeDocument != nil)
        }

        // View menu: focus mode, wrap, markdown display toggle
        CommandGroup(after: .toolbar) {
            Button("Toggle Focus Mode") {
                app.toggleFocusMode()
            }
            .keyboardShortcut("f", modifiers: [.command, .option])

            Button(app.wordWrapEnabled ? "Turn Off Word Wrap" : "Turn On Word Wrap") {
                app.toggleWordWrap()
            }
            .keyboardShortcut("w", modifiers: [.command, .option])
            .disabled(!app.isSelectionEditable)

            Divider()

            Button("Toggle Markdown Display") {
                app.toggleMarkdownDisplay()
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(app.selectedKind != .markdown || app.paneMode != .preview)
        }

        // Format menu: Markdown editing tools
        CommandMenu("Format") {
            Button("Heading 1") { app.applyMarkdownFormat(.heading(level: 1)) }
                .keyboardShortcut("1", modifiers: [.command, .option])
            Button("Heading 2") { app.applyMarkdownFormat(.heading(level: 2)) }
                .keyboardShortcut("2", modifiers: [.command, .option])
            Button("Heading 3") { app.applyMarkdownFormat(.heading(level: 3)) }
                .keyboardShortcut("3", modifiers: [.command, .option])
            Divider()
            Button("Bold") { app.applyMarkdownFormat(.bold) }
                .keyboardShortcut("b", modifiers: .command)
            Button("Italic") { app.applyMarkdownFormat(.italic) }
                .keyboardShortcut("i", modifiers: .command)
            Button("Inline Code") { app.applyMarkdownFormat(.inlineCode) }
            Divider()
            Button("Blockquote") { app.applyMarkdownFormat(.blockquote) }
            Button("Bullet List") { app.applyMarkdownFormat(.bulletList) }
            Button("Numbered List") { app.applyMarkdownFormat(.numberedList) }
            Divider()
            Button("Link") { app.applyMarkdownFormat(.link) }
                .keyboardShortcut("k", modifiers: [.command, .shift])
            Button("Image") { app.applyMarkdownFormat(.image) }
        }

        // App menu: About
        CommandGroup(replacing: .appInfo) {
            Button("About MotStar") {
                openAboutWindow(id: "about")
            }
        }
    }
}

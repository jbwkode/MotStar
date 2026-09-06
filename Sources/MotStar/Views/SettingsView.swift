import SwiftUI

/// MotStar preferences (Settings… ⌘,). Theme, tree sort + text sizes.
struct SettingsView: View {
    @AppStorage(FileSortMode.storageKey) private var sortMode: FileSortMode = .newestFirst
    @AppStorage(AppTheme.storageKey) private var theme: AppTheme = .system
    @EnvironmentObject private var app: AppState

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Theme", selection: $theme) {
                    ForEach(AppTheme.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 220)
                .help("Choose Light, Dark, or follow the system (⌥ changes apply to every window)")

                Text("Applies to the whole app including the Markdown preview.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Text size") {
                HStack {
                    Text("Reading")
                    Slider(value: $app.readingFontSize, in: 9...30, step: 1) {
                        Text("Reading")
                    }
                    Text("\(Int(app.readingFontSize)) pt")
                        .font(.body.monospacedDigit())
                        .frame(width: 38, alignment: .trailing)
                        .foregroundStyle(.secondary)
                }
                Text("Font size of the formatted Markdown and raw-text preview panes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Text("Editor")
                    Slider(value: $app.editorFontSize, in: 9...30, step: 1) {
                        Text("Editor")
                    }
                    Text("\(Int(app.editorFontSize)) pt")
                        .font(.body.monospacedDigit())
                        .frame(width: 38, alignment: .trailing)
                        .foregroundStyle(.secondary)
                }
                Text("Font size of the source editor. Zoom with ⌘+ / ⌘− / ⌘0 in any pane.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("File tree") {
                Picker("Sort files in tree", selection: $sortMode) {
                    ForEach(FileSortMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.radioGroup)
                .help("Folders are always listed alphabetically first.")

                Text("Folders are always sorted alphabetically first; this setting controls how files within each folder are ordered.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .padding()
        .preferredColorScheme(theme.colorScheme)
    }
}

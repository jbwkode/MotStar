import SwiftUI

/// MotStar preferences (Settings… ⌘,). Currently: file sort order + theme.
struct SettingsView: View {
    @AppStorage(FileSortMode.storageKey) private var sortMode: FileSortMode = .newestFirst
    @AppStorage(AppTheme.storageKey) private var theme: AppTheme = .system

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

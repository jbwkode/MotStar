import SwiftUI

/// MotStar preferences (Settings… ⌘,). Currently: file sort order.
struct SettingsView: View {
    @AppStorage(FileSortMode.storageKey) private var sortMode: FileSortMode = .newestFirst

    var body: some View {
        Form {
            Section {
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
    }
}

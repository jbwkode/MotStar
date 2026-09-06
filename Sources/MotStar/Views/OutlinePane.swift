import SwiftUI

/// Trailing document-outline pane for the selected Markdown file (FR-adjacent
/// nav aid). Rows mirror the headings of the current draft or file; clicking
/// one scrolls the source editor to the heading line, or the formatted
/// preview to the heading element. Toggled via ⌥⌘O or the preview toolbar.
struct OutlinePane: View {
    @EnvironmentObject private var app: AppState

    private var isEmpty: Bool { app.outlineHeadings.isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if isEmpty {
                emptyState
            } else {
                list
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .frame(minWidth: 180, idealWidth: 220, maxWidth: 300)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text("Outline")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("\(app.outlineHeadings.count)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)
            Spacer()
            Button {
                app.showOutline = false
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .help("Hide Outline (⌥⌘O)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private var list: some View {
        List {
            ForEach(Array(app.outlineHeadings.enumerated()), id: \.offset) { index, heading in
                Button {
                    app.jumpToOutlineHeading(at: index, line: heading.line)
                } label: {
                    Text(heading.text)
                        .font(.system(size: 12, weight: heading.level <= 2 ? .medium : .regular))
                        .foregroundStyle(heading.level <= 2 ? .primary : .secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, indent(for: heading.level))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Jump to “\(heading.text)”")
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "list.bullet.indent")
                .font(.system(size: 26))
                .foregroundStyle(.tertiary)
            Text("No headings\nUse #, ##, ###… to structure this document.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(12)
    }

    private func indent(for level: Int) -> CGFloat {
        CGFloat(max(0, level - 1)) * 12
    }
}

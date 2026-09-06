import SwiftUI
import AppKit

/// The About window: logo, app name, version and credits.
/// Opened from the app menu (MotStar → About MotStar).
struct AboutView: View {
    private var version: String { AppInfo.displayVersion }
    @AppStorage(AppTheme.storageKey) private var theme: AppTheme = .system

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 28)

            logo
                .padding(.bottom, 18)

            Text("MotStar")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.primary)

            Text("Document Navigator & Previewer")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .padding(.top, 2)

            Spacer(minLength: 24)

            Rectangle()
                .fill(Color(nsColor: .separatorColor))
                .frame(height: 1)
                .padding(.horizontal, 28)

            VStack(spacing: 6) {
                infoRow(label: "Version", value: version)
                infoRow(label: "Platform", value: "macOS 14+")
                infoRow(label: "Built with", value: "SwiftUI & swift-markdown")
                infoRow(label: "Author", value: "John B. Walsh")
                infoRow(label: "License", value: "MIT (open source)")
            }
            .font(.system(size: 12))
            .padding(.vertical, 16)
            .padding(.horizontal, 28)

            Rectangle()
                .fill(Color(nsColor: .separatorColor))
                .frame(height: 1)
                .padding(.horizontal, 28)

            Spacer(minLength: 16)

            Text("Formatted Markdown  ·  Quick Look  ·  Outlook Email  ·  Apple Share")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)

            Spacer(minLength: 18)

            Text("© 2026 John B. Walsh")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Link("john.b.walsh@gmail.com", destination: URL(string: "mailto:john.b.walsh@gmail.com")!)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Text("Released under the MIT License.")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)

            Text("Free & open source — provided as-is, no warranty. Support: github.com/jbwkode/MotStar")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
                .padding(.top, 2)

            Spacer(minLength: 24)
        }
        .frame(width: 420, height: 540)
        .preferredColorScheme(theme.colorScheme)
    }

    private var logo: some View {
        Group {
            if let image = MotStarAssets.loadLogo() {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "star.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.tint)
            }
        }
        .frame(maxWidth: 320, maxHeight: 120)
        .padding(.horizontal, 24)
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Shared loader for the bundled MotStar logo (app resources, then the
/// SwiftPM resource bundle when running via `swift run` / Xcode).
/// Prefers the current brand artwork (BrandLogo) over the legacy AboutLogo.
enum MotStarAssets {
    static func loadLogo() -> NSImage? {
        for name in ["BrandLogo", "AboutLogo"] {
            if let url = Bundle.main.url(forResource: name, withExtension: "png"),
               let image = NSImage(contentsOf: url) {
                return image
            }
            #if SWIFT_PACKAGE
            if let url = Bundle.module.url(forResource: name, withExtension: "png"),
               let image = NSImage(contentsOf: url) {
                return image
            }
            #endif
        }
        return nil
    }
}

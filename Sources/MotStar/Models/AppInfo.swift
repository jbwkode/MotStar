import Foundation

/// Single source of app version truth for UI fallbacks and branding.
/// The packaged `.app` reads its real values from Info.plist
/// (CFBundleShortVersionString / CFBundleVersion) — these constants are the
/// fallback used when running unbundled (e.g. `swift run`).
enum AppInfo {
    static let version = "0.3.13"
    static let build = "15"

    /// Version shown in the About window: bundle value when packaged,
    /// otherwise the source constant.
    static var displayVersion: String {
        if let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
           !short.isEmpty {
            return short
        }
        return version
    }
}

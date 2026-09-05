import AppKit

/// Sends the selected file in an email (FR-11, ADR-005).
///
/// Resolution order:
/// 1. Microsoft Outlook installed → AppleScript composes a new message with
///    the file attached and brings Outlook to the front (user sends).
/// 2. Automation permission missing (-1743) → returns a guidance error so
///    the UI can point the user at System Settings > Privacy & Security >
///    Automation (no silent fallback — the user asked for Outlook).
/// 3. Any other Outlook failure → macOS compose-email share service.
///
/// Everything runs on the main thread: NSAppleScript event sending and
/// ShareKit both need the main run loop (background execution suppresses the
/// automation permission prompt and crashes ShareKit).
@MainActor
enum EmailService {

    enum EmailError: LocalizedError {
        case outlookNotInstalled
        case outlookNeedsPermission
        case outlookScriptFailed(String)
        case composeUnavailable

        var errorDescription: String? {
            switch self {
            case .outlookNotInstalled:
                return "Microsoft Outlook is not installed."
            case .outlookNeedsPermission:
                return """
                MotStar isn't allowed to control Microsoft Outlook yet.

                Open System Settings → Privacy & Security → Automation, find \
                MotStar and enable Microsoft Outlook (or accept the permission \
                prompt when it appears), then try Email again.
                """
            case .outlookScriptFailed(let detail):
                return "Outlook could not compose the email.\n\n\(detail)"
            case .composeUnavailable:
                return "No email compose service is available."
            }
        }
    }

    static func email(_ url: URL, completion: @escaping (Result<Void, Error>) -> Void) {
        let outlookInstalled = NSWorkspace.shared
            .urlForApplication(withBundleIdentifier: "com.microsoft.Outlook") != nil

        if !outlookInstalled {
            completion(composeEmailFallback(for: url))
            return
        }

        switch runOutlookScript(for: url) {
        case .success:
            completion(.success(()))
        case .failure(let error):
            #if DEBUG
            NSLog("MotStar: Outlook automation failed (%@)", error.localizedDescription)
            #endif
            if case .outlookNeedsPermission = error {
                completion(.failure(error))
            } else {
                completion(composeEmailFallback(for: url))
            }
        }
    }

    // MARK: - Outlook (via /usr/bin/osascript)

    /// Runs the Outlook script through `/usr/bin/osascript`.
    ///
    /// Why not NSAppleScript? When an *ad-hoc signed* app sends Apple events
    /// in-process, TCC cannot attribute the request, so macOS auto-denies it
    /// (-1743) without ever showing the permission prompt or recording an
    /// Automation entry. A properly signed helper (`/usr/bin/osascript`,
    /// Apple-signed) is attributed to its *responsible process* — MotStar —
    /// which makes the prompt appear and creates the Automation record.
    private static func runOutlookScript(for url: URL) -> Result<Void, EmailError> {
        let fileName = url.lastPathComponent
        let subject = "MotStar: \(fileName)"
        let script = """
        tell application "Microsoft Outlook"
            set theMessage to make new outgoing message with properties {subject:"\(escape(subject))", content:""}
            tell theMessage
                make new attachment with properties {file:(POSIX file "\(escape(url.path))" as alias)}
            end tell
            open theMessage
            activate
        end tell
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return .failure(.outlookScriptFailed("Could not launch osascript: \(error.localizedDescription)"))
        }

        guard process.terminationStatus == 0 else {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: errorData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? "Unknown osascript error"
            let lowered = message.lowercased()
            if message.contains("-1743") || lowered.contains("not authorized")
                || lowered.contains("automation") || lowered.contains("not allowed") {
                return .failure(.outlookNeedsPermission)
            }
            return .failure(.outlookScriptFailed(message))
        }

        let _ = outputPipe.fileHandleForReading.readDataToEndOfFile()
        return .success(())
    }

    /// Escape a string for safe embedding inside double quotes in AppleScript.
    private static func escape(_ string: String) -> String {
        string.replacingOccurrences(of: "\\", with: "\\\\")
              .replacingOccurrences(of: "\"", with: "\\\"")
    }

    // MARK: - Fallback (compose email share service)

    private static func composeEmailFallback(for url: URL) -> Result<Void, Error> {
        guard let service = NSSharingService(named: .composeEmail) else {
            return .failure(EmailError.composeUnavailable)
        }
        service.subject = "MotStar: \(url.lastPathComponent)"
        service.perform(withItems: [url])
        return .success(())
    }
}

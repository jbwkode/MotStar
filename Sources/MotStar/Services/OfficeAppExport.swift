import Foundation

/// Multi-page PDF export for PowerPoint and Excel documents.
///
/// Quick Look can only snapshot the first page, and macOS has no public API to
/// convert these formats. When Microsoft PowerPoint/Excel is installed we ask
/// it (via AppleScript) to export the whole file, which is the only way to get
/// every slide or sheet. Everything happens on a temporary copy beside the
/// original so the user's document is never opened for editing or re-saved.
enum OfficeAppExport {

    enum Host {
        case powerpoint
        case excel
    }

    /// Returns PDF data for `url`, or nil when the matching Office app is not
    /// installed, automation is denied, or the export fails/times out.
    static func pdfData(for url: URL) async -> Data? {
        guard let host = Self.host(for: url) else { return nil }
        return await Task.detached(priority: .userInitiated) {
            export(host: host, source: url)
        }.value
    }

    static func host(for url: URL) -> Host? {
        switch url.pathExtension.lowercased() {
        case "pptx", "pptm", "ppt": return .powerpoint
        case "xlsx", "xlsm", "xls": return .excel
        default: return nil
        }
    }

    private static func applicationName(for host: Host) -> String {
        switch host {
        case .powerpoint: return "Microsoft PowerPoint"
        case .excel: return "Microsoft Excel"
        }
    }

    private static func applicationURL(for host: Host) -> URL {
        URL(fileURLWithPath: "/Applications/\(applicationName(for: host)).app")
    }

    private static func export(host: Host, source: URL) -> Data? {
        guard FileManager.default.fileExists(atPath: applicationURL(for: host).path) else {
            return nil
        }

        let folder = source.deletingLastPathComponent()
        let id = UUID().uuidString
        let ext = source.pathExtension
        let workingCopy = folder.appendingPathComponent(".motstar-export-\(id).\(ext)")
        let output = folder.appendingPathComponent(".motstar-export-\(id).pdf")
        defer {
            try? FileManager.default.removeItem(at: workingCopy)
            try? FileManager.default.removeItem(at: output)
        }

        do {
            try FileManager.default.copyItem(at: source, to: workingCopy)
        } catch {
            NSLog("MotStar: could not stage %@ for Office export (%@)",
                  source.lastPathComponent, error.localizedDescription)
            return nil
        }

        guard runAppleScript(script(for: host,
                                    workingCopy: workingCopy,
                                    output: output)) else {
            return nil
        }

        guard let data = try? Data(contentsOf: output),
              data.starts(with: Data("%PDF".utf8)) else {
            return nil
        }
        return data
    }

    private static func script(for host: Host, workingCopy: URL, output: URL) -> String {
        let copyPath = workingCopy.path
        let outputPath = output.path
        let fileName = workingCopy.lastPathComponent

        switch host {
        case .powerpoint:
            return """
            tell application "Microsoft PowerPoint"
                set targetPath to "\(copyPath)"
                set targetDoc to missing value
                repeat with pres in presentations
                    try
                        if (full name of pres) is targetPath then set targetDoc to pres
                    end try
                end repeat
                if targetDoc is missing value then
                    open POSIX file targetPath
                    delay 1
                    repeat with pres in presentations
                        try
                            if (full name of pres) is targetPath then set targetDoc to pres
                        end try
                    end repeat
                end if
                if targetDoc is missing value then error "presentation did not open"
                save targetDoc in POSIX file "\(outputPath)" as save as PDF
                close targetDoc saving no
            end tell
            """
        case .excel:
            return """
            tell application "Microsoft Excel"
                set targetPath to "\(copyPath)"
                set targetDoc to missing value
                repeat with book in workbooks
                    try
                        if (full name of book) is targetPath then set targetDoc to book
                    end try
                end repeat
                if targetDoc is missing value then
                    set targetDoc to open workbook workbook file name POSIX file targetPath
                    delay 1
                end if
                save workbook as targetDoc filename "\(outputPath)" file format PDF file format
                close targetDoc saving no
            end tell
            """
        }
    }

    /// Runs the script with a bounded wait so a sandbox permission dialog
    /// (or a hung Office app) can't block export forever.
    private static func runAppleScript(_ source: String, timeout: TimeInterval = 90) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", source]
        let stderr = Pipe()
        process.standardError = stderr
        process.standardOutput = Pipe()

        do {
            try process.run()
        } catch {
            return false
        }

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.1)
        }
        if process.isRunning {
            process.terminate()
            NSLog("MotStar: Office PDF export timed out")
            return false
        }
        if process.terminationStatus != 0 {
            let message = String(data: stderr.fileHandleForReading.readDataToEndOfFile(),
                                 encoding: .utf8) ?? ""
            NSLog("MotStar: Office PDF export failed: %@", message)
            return false
        }
        return true
    }
}

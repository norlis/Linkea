import AppKit

/// Opens links in a chosen Arc space. Arc ignores `--profile-directory` and every profile lives
/// behind a space, so its AppleScript dictionary is the only way to target one. Every failure
/// falls back to opening in Arc without a space — a link is never lost.
enum ArcSpaceLauncher {
    /// What AppleScript reports when the user declined Linkea's Automation access to Arc.
    private static let notAuthorizedError = -1743

    /// The space id and URLs arrive through `argv`, never spliced into the source, so a URL can
    /// not be read as script. Windows go by index because Arc's window and tab object specifiers
    /// fail to resolve (-1700) — a reference to either cannot be kept in a variable. Incognito
    /// windows have no spaces, hence the search for a regular one.
    private static let script = """
    on run argv
        set spaceID to item 1 of argv
        tell application id "company.thebrowser.Browser"
            set targetIndex to 0
            repeat with i from 1 to count of windows
                if incognito of window i is false then
                    set targetIndex to i
                    exit repeat
                end if
            end repeat
            if targetIndex is 0 then
                make new window
                set targetIndex to 1
            end if
            tell space id spaceID of window targetIndex
                focus
                repeat with i from 2 to count of argv
                    make new tab with properties {URL:(item i of argv)}
                end repeat
            end tell
            activate
        end tell
    end run
    """

    private struct ScriptFailure: Error, CustomStringConvertible {
        let exitStatus: Int32
        let appleScriptError: Int?

        var description: String {
            "osascript exited with status \(exitStatus), AppleScript error \(appleScriptError.map(String.init) ?? "unknown")"
        }
    }

    static func open(_ urls: [URL], spaceID: String, arcAppURL: URL) {
        let fields = ["app.bundle_id": ProfileCore.arcBundleID]
        Task {
            do {
                try await runScript(arguments: ProfileCore.launchArguments(recipe: .arcSpace(spaceID), urls: urls))
                return
            } catch let failure as ScriptFailure where failure.appleScriptError == notAuthorizedError {
                AppLog.warn("arc automation not authorized, falling back to plain arc", fields: fields)
            } catch {
                AppLog.error("arc space open failed, falling back to plain arc", error: error, fields: fields)
            }
            do {
                _ = try await NSWorkspace.shared.open(urls, withApplicationAt: arcAppURL, configuration: NSWorkspace.OpenConfiguration())
            } catch {
                AppLog.error("arc open failed", error: error, fields: fields)
            }
        }
    }

    /// Runs through osascript rather than NSAppleScript, which must stay on the main thread and
    /// would freeze the picker while Arc launches. macOS still attributes the Automation consent
    /// to Linkea, the responsible process.
    private static func runScript(arguments: [String]) async throws {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/osascript")
        process.arguments = ["-e", script] + arguments
        process.standardOutput = FileHandle.nullDevice
        let diagnostics = Pipe()
        process.standardError = diagnostics

        let status: Int32 = try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { finished in
                continuation.resume(returning: finished.terminationStatus)
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
        guard status == 0 else {
            let text = String(decoding: diagnostics.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            throw ScriptFailure(exitStatus: status, appleScriptError: ProfileCore.appleScriptErrorNumber(fromDiagnostics: text))
        }
    }
}

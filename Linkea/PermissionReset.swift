import AppKit
import Foundation

/// Resets Linkea's own TCC approvals so macOS shows its consent prompts again — the only way
/// back after a denial or after an update invalidated the previous approval (there is no
/// request API for the app-data permission; the system prompts only on first access).
enum PermissionReset {
    /// tccutil invocations in the order they should be tried: the scoped service first, so the
    /// Accessibility approval Safari profiles depend on survives, then `All` for macOS versions
    /// that do not know that service name. Arrays, never a shell string — arguments cannot be
    /// reinterpreted, and there is nothing to inject into.
    nonisolated static func commands(bundleID: String) -> [[String]] {
        guard !bundleID.isEmpty else { return [] }
        let tccutil = "/usr/bin/tccutil"
        return [
            [tccutil, "reset", "SystemPolicyAppDataDetailed", bundleID],
            [tccutil, "reset", "All", bundleID]
        ]
    }

    /// Runs the reset and, on success, relaunches the app so the fresh prompts fire on the next
    /// profile scan. Returns false when every attempt failed; the exact command is then on the
    /// pasteboard so the user always has a way out.
    static func performResetAndRelaunch() async -> Bool {
        let bundleID = Bundle.main.bundleIdentifier ?? ""
        for command in commands(bundleID: bundleID) {
            guard await run(command) else { continue }
            AppLog.info("tcc approvals reset", fields: ["reset.service": command[2]])
            // The relaunched instance picks this up to guide the user to the consent dialogs.
            Preferences.accessRepairPending = true
            await relaunch()
            return true
        }
        AppLog.warn("tcc reset failed, command copied to pasteboard")
        let fallback = commands(bundleID: bundleID).last?.joined(separator: " ") ?? ""
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(fallback, forType: .string)
        return false
    }

    private static func run(_ command: [String]) async -> Bool {
        guard let executable = command.first else { return false }
        let process = Process()
        process.executableURL = URL(filePath: executable)
        process.arguments = Array(command.dropFirst())
        return await withCheckedContinuation { continuation in
            process.terminationHandler = { finished in
                continuation.resume(returning: finished.terminationStatus == 0)
            }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                AppLog.error("tccutil launch failed", error: error)
                continuation.resume(returning: false)
            }
        }
    }

    private static func relaunch() async {
        let configuration = NSWorkspace.OpenConfiguration()
        // A second instance is required: reusing this one would just foreground the process
        // whose approvals were wiped mid-flight.
        configuration.createsNewApplicationInstance = true
        _ = try? await NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration)
        NSApp.terminate(nil)
    }
}

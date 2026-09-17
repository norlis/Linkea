import AppKit
import Observation

/// Tracks and requests the system default-browser role.
@Observable
final class DefaultBrowserManager {
    private(set) var isDefault = false

    // Kept for the app's lifetime; the task is never cancelled because this object never dies.
    @ObservationIgnored private var activationTask: Task<Void, Never>?

    init() {
        refreshStatus()
        // The user can change the default browser in System Settings while we are hidden,
        // so re-check whenever the app comes back to the foreground.
        activationTask = Task { [weak self] in
            // .map strips the non-Sendable Notification before it crosses into this task.
            for await _ in NotificationCenter.default.notifications(named: NSApplication.didBecomeActiveNotification).map({ _ in () }) {
                self?.refreshStatus()
            }
        }
    }

    func refreshStatus() {
        guard let handlerURL = NSWorkspace.shared.urlForApplication(toOpen: LinkRouterCore.probeURL),
              let handlerID = Bundle(url: handlerURL)?.bundleIdentifier,
              let selfID = Bundle.main.bundleIdentifier else {
            isDefault = false
            return
        }
        isDefault = handlerID == selfID
    }

    func requestDefault() {
        // Activate first: as an LSUIElement app, the system consent alert would otherwise
        // appear behind other windows.
        NSApp.activate(ignoringOtherApps: true)
        // macOS treats the "http" handler as the default browser (https follows); one request
        // avoids duplicate consent dialogs.
        Task {
            do {
                try await NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpenURLsWithScheme: WebScheme.http.rawValue)
            } catch {
                AppLog.error("set default browser failed", error: error)
            }
            refreshStatus()
        }
    }
}

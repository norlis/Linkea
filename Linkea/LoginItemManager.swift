import AppKit
import Observation
import ServiceManagement

/// Tracks and toggles the launch-at-login registration of the main app.
@Observable
final class LoginItemManager {
    private(set) var isEnabled = false
    /// The system registered the item but the user must approve it in System Settings.
    private(set) var requiresApproval = false

    // Kept for the app's lifetime; the task is never cancelled because this object never dies.
    @ObservationIgnored private var activationTask: Task<Void, Never>?

    init() {
        refreshStatus()
        // The user can flip this in System Settings › General › Login Items while we are
        // hidden, so re-check whenever the app comes back to the foreground.
        activationTask = Task { [weak self] in
            // .map strips the non-Sendable Notification before it crosses into this task.
            for await _ in NotificationCenter.default.notifications(named: NSApplication.didBecomeActiveNotification).map({ _ in () }) {
                self?.refreshStatus()
            }
        }
    }

    func refreshStatus() {
        let status = SMAppService.mainApp.status
        isEnabled = status == .enabled
        requiresApproval = status == .requiresApproval
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            AppLog.error("login item change failed", error: error)
        }
        refreshStatus()
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

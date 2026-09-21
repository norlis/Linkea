import SwiftUI
import UniformTypeIdentifiers

/// Raw bytes in, raw bytes out: the exporter only needs a container for the JSON that
/// `RuleTransfer` already produced.
nonisolated struct RulesDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.json]

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

/// Root of the app's single window: setup and rules in one place. The frame is fixed and each
/// tab scrolls its own content — window-resizing via Auto Layout with dynamic SwiftUI content
/// triggers AppKit's "Update Constraints in Window pass" loop.
struct SettingsRootView: View {
    let manager: DefaultBrowserManager
    let loginItems: LoginItemManager
    let discovery: BrowserDiscovery
    let store: RuleStore
    let onTryIt: () -> Void

    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") {
                GeneralSettingsTab(manager: manager, loginItems: loginItems, discovery: discovery, onTryIt: onTryIt)
            }
            Tab("Rules", systemImage: "list.bullet.rectangle") {
                SettingsView(store: store, discovery: discovery)
            }
        }
        .frame(width: 640, height: 480)
    }
}

/// The former one-screen setup: the single manual step macOS requires (choosing Linkea as the
/// default browser), a picker preview, and the experimental Safari profile mapping.
private struct GeneralSettingsTab: View {
    let manager: DefaultBrowserManager
    let loginItems: LoginItemManager
    let discovery: BrowserDiscovery
    let onTryIt: () -> Void

    // Deep link into System Settings; there is no API to open this pane programmatically.
    private static let fullDiskAccessSettingsURL =
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")

    // Seeded from Preferences (the only config store) and written back through the binding,
    // following the SafariProfilesSettingsView pattern.
    @State private var hiddenBrowserIDs = Preferences.hiddenBrowserBundleIDs

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // The app's effective icon, so this screen can never drift from the AppIcon asset.
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 72, height: 72)
                    .accessibilityHidden(true)
                Text("Welcome to Linkea")
                    .font(.title.bold())
                Text("Linkea routes every link you click to the browser you choose. For that to work, macOS needs Linkea to be your default browser.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)

                Button("Set Linkea as Default Browser") {
                    manager.requestDefault()
                }
                .buttonStyle(.glassProminent)

                Label(
                    manager.isDefault ? "Linkea is your default browser" : "Linkea is not the default browser yet",
                    systemImage: manager.isDefault ? "checkmark.circle.fill" : "circle.dashed"
                )
                .foregroundStyle(manager.isDefault ? .green : .secondary)

                Toggle("Launch Linkea at login", isOn: Binding(
                    get: { loginItems.isEnabled },
                    set: { loginItems.setEnabled($0) }))
                    .toggleStyle(.checkbox)
                if loginItems.requiresApproval {
                    HStack(spacing: 6) {
                        Text("Waiting for your approval in System Settings.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                        Button("Open Login Items Settings") {
                            loginItems.openLoginItemsSettings()
                        }
                        .font(.caption)
                    }
                }

                Divider()

                if discovery.profileAccessDenied {
                    profileAccessNotice
                }

                browsersSection

                Divider()

                SafariProfilesSettingsView()
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack {
                    Button("Try It", action: onTryIt)
                    Spacer()
                    Text(Self.versionText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(28)
        }
    }

    /// Releases show the git tag: the release workflow injects it as MARKETING_VERSION.
    private static var versionText: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: kCFBundleVersionKey as String) as? String ?? "—"
        return "Linkea \(short) (\(build))"
    }

    private var profileAccessNotice: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("macOS is blocking access to browser profile data, so profiles can't be shown.",
                  systemImage: "exclamationmark.triangle")
                .font(.callout)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
            Text("Grant Linkea Full Disk Access and relaunch it. If Linkea already appears enabled there, remove it and add it again — updating the app invalidates the old grant. Links keep working either way; only the profile chips are affected.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Open Full Disk Access Settings") {
                if let url = Self.fullDiskAccessSettingsURL {
                    NSWorkspace.shared.open(url)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.orange.opacity(0.12), in: .rect(cornerRadius: 8))
    }

    private var browsersSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Browsers")
                .font(.headline)
            Text("Unchecked browsers stay out of the picker. Rules that point to them keep working, and if every browser is hidden the picker shows them all anyway.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(discovery.browsers) { browser in
                Toggle(isOn: visibilityBinding(for: browser.id)) {
                    HStack(spacing: 6) {
                        Image(nsImage: browser.icon)
                            .resizable()
                            .frame(width: 16, height: 16)
                            .accessibilityHidden(true)
                        Text(browser.name)
                    }
                }
                .toggleStyle(.checkbox)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func visibilityBinding(for bundleID: String) -> Binding<Bool> {
        Binding(
            get: { !hiddenBrowserIDs.contains(bundleID) },
            set: { visible in
                if visible {
                    hiddenBrowserIDs.remove(bundleID)
                } else {
                    hiddenBrowserIDs.insert(bundleID)
                }
                Preferences.hiddenBrowserBundleIDs = hiddenBrowserIDs
            }
        )
    }
}

/// The one-line description of a matcher shown in the list. Pure, so it is tested.
nonisolated enum RuleSummary {
    static func text(for rule: RoutingRule) -> String {
        switch rule.matcher {
        case .host(let matcher):
            matcher.includesSubdomains
                ? "\(matcher.host) and subdomains"
                : "\(matcher.host) exact"
        case .regex(let matcher):
            switch matcher.subject {
            case .host: "\(matcher.pattern) · host"
            case .url: "\(matcher.pattern) · full URL"
            }
        }
    }
}

/// The ordered rule table: first match wins, drag to reorder, double-click to edit.
struct SettingsView: View {
    @Bindable var store: RuleStore
    let discovery: BrowserDiscovery
    @State private var editing: RoutingRule?
    @State private var selection: RoutingRule.ID?
    @State private var isImporting = false
    @State private var isExporting = false
    @State private var exportDocument: RulesDocument?
    @State private var transferMessage: String?
    @State private var pendingImport: PendingImport?

    /// An import waiting on the user's review of destinations this Mac cannot open.
    private struct PendingImport: Identifiable {
        let id = UUID()
        let rules: [RoutingRule]
        let groups: [RuleTransfer.UnresolvedGroup]
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if store.rules.isEmpty {
                emptyState
            } else {
                list
            }
            Divider()
            footer
        }
        .sheet(item: $editing) { rule in
            RuleEditorView(rule: rule, store: store, discovery: discovery)
        }
        .sheet(item: $pendingImport) { pending in
            ImportReviewView(
                groups: pending.groups,
                discovery: discovery,
                onCancel: { pendingImport = nil },
                onImport: { resolutions in
                    let resolved = RuleTransfer.apply(resolutions, to: pending.rules)
                    finishImport(resolved, skipped: pending.rules.count - resolved.count)
                    pendingImport = nil
                }
            )
        }
        .fileExporter(isPresented: $isExporting, document: exportDocument,
                      contentType: .json, defaultFilename: "Linkea Rules") { result in
            if case .failure(let error) = result {
                AppLog.error("rules export failed", error: error)
                transferMessage = "Export failed: \(error.localizedDescription)"
            }
        }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.json]) { result in
            handleImport(result)
        }
        .alert("Rules", isPresented: Binding(
            get: { transferMessage != nil },
            set: { if !$0 { transferMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(transferMessage ?? "")
        }
    }

    private func handleImport(_ result: Result<URL, any Error>) {
        do {
            // The app is unsandboxed on purpose; the picked URL is readable directly.
            let data = try Data(contentsOf: result.get())
            let decoded = try RuleTransfer.decode(data)
            let groups = RuleTransfer.analyze(decoded.rules, labels: decoded.destinationLabels) {
                discovery.canResolve($0)
            }
            if groups.isEmpty {
                finishImport(decoded.rules)
            } else {
                AppLog.info("rules import needs review", fields: ["rule.unresolved_count": String(groups.count)])
                pendingImport = PendingImport(rules: decoded.rules, groups: groups)
            }
        } catch let error as RuleTransfer.TransferError {
            AppLog.warn("rules import rejected", fields: ["error.type": "TransferError"])
            transferMessage = error.message
        } catch {
            AppLog.error("rules import failed", error: error)
            transferMessage = "Import failed: \(error.localizedDescription)"
        }
    }

    private func finishImport(_ rules: [RoutingRule], skipped: Int = 0) {
        let changed = store.importRules(rules)
        var message = changed == 0
            ? "Nothing new to import — every rule in the file is already in the table."
            : "\(changed) rule\(changed == 1 ? "" : "s") imported."
        if skipped > 0 {
            message += " \(skipped) skipped."
        }
        transferMessage = message
    }

    /// Human-readable names for every destination in the table, written into the export so an
    /// importing Mac can name browsers and profiles it does not have.
    private func exportLabels() -> [String: String] {
        var labels: [String: String] = [:]
        for rule in store.rules {
            let destination = rule.destination
            guard let browser = discovery.browsers.first(where: { $0.id == destination.browserBundleID })
            else { continue }
            if let profileID = destination.profileID {
                guard let profile = browser.profiles.first(where: { $0.id == profileID }) else { continue }
                labels[RuleTransfer.labelKey(for: destination)] = "\(browser.name) — \(profile.displayName)"
            } else {
                labels[RuleTransfer.labelKey(for: destination)] = browser.name
            }
        }
        return labels
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("Rules run top to bottom. The first match wins and the link opens there, with no panel.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
            Toggle("Pause rules", isOn: $store.isPaused)
                .toggleStyle(.checkbox)
        }
        .padding(12)
    }

    private var list: some View {
        List(selection: $selection) {
            ForEach(store.rules) { rule in
                RuleRow(rule: rule,
                        isEnabled: enabledBinding(for: rule),
                        destination: destinationLabel(for: rule.destination))
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { editing = rule }
            }
            .onMove { store.move(fromOffsets: $0, toOffset: $1) }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("Every link will ask")
                .font(.headline)
            Text("Check “Remember” in the picker when choosing a browser, or create a rule here.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Create Rule") { editing = newRule() }
                .keyboardShortcut(.defaultAction)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Button {
                editing = newRule()
            } label: {
                Image(systemName: "plus")
            }
            .accessibilityLabel("Add rule")

            Button {
                if let selection { store.remove(id: selection) }
            } label: {
                Image(systemName: "minus")
            }
            .accessibilityLabel("Delete rule")
            .disabled(selection == nil)

            Divider()
                .frame(height: 16)

            Button("Import…") {
                isImporting = true
            }

            Button("Export…") {
                do {
                    exportDocument = RulesDocument(data: try RuleTransfer.export(store.rules, labels: exportLabels()))
                    isExporting = true
                } catch {
                    AppLog.error("rules export failed", error: error)
                    transferMessage = "Export failed: \(error.localizedDescription)"
                }
            }
            .disabled(store.rules.isEmpty)

            Spacer()
            Text("Drag to change precedence")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(10)
    }

    private func newRule() -> RoutingRule {
        RoutingRule(
            name: "New rule",
            matcher: .host(HostMatcher(host: "", includesSubdomains: true)),
            destination: RuleDestination(
                browserBundleID: discovery.browsers.first?.id ?? "", profileID: nil))
    }

    private func enabledBinding(for rule: RoutingRule) -> Binding<Bool> {
        Binding(
            get: { store.rules.first { $0.id == rule.id }?.isEnabled ?? false },
            set: { enabled in
                var updated = rule
                updated.isEnabled = enabled
                store.update(updated)
            })
    }

    /// The mockups show people-facing names, never bundle identifiers.
    private func destinationLabel(for destination: RuleDestination) -> RuleRow.Destination {
        guard let browser = discovery.browsers.first(where: { $0.id == destination.browserBundleID }) else {
            return .unavailable(name: destination.browserBundleID)
        }
        guard let profileID = destination.profileID else {
            return .available(icon: browser.icon, text: browser.name)
        }
        guard let profile = browser.profiles.first(where: { $0.id == profileID }) else {
            return .unavailable(name: browser.name)
        }
        return .available(icon: browser.icon, text: "\(browser.name) · \(profile.displayName)")
    }
}

private struct RuleRow: View {
    enum Destination {
        case available(icon: NSImage, text: String)
        case unavailable(name: String)
    }

    let rule: RoutingRule
    @Binding var isEnabled: Bool
    let destination: Destination

    var body: some View {
        HStack(spacing: 10) {
            Toggle("", isOn: $isEnabled)
                .toggleStyle(.checkbox)
                .labelsHidden()
                .accessibilityLabel("Enable rule \(rule.name)")
            VStack(alignment: .leading, spacing: 2) {
                Text(rule.name).fontWeight(.medium)
                Text(RuleSummary.text(for: rule))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            switch destination {
            case .available(let icon, let text):
                HStack(spacing: 6) {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 18, height: 18)
                        .accessibilityHidden(true)
                    Text(text)
                        .font(.caption)
                }
            case .unavailable(let name):
                Label("\(name) not available", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .opacity(rule.isEnabled ? 1 : 0.5)
        .padding(.vertical, 4)
    }
}

import SwiftUI

/// The editor's pure parts: proposing a matcher from a sample URL, explaining a host matcher,
/// and reporting which rule would win. Separated so all of it is tested without a window.
nonisolated enum RuleEditorModel {
    static func proposedMatcher(from urlText: String) -> RuleMatcher? {
        guard let url = URL(string: urlText.trimmingCharacters(in: .whitespaces)),
              let host = MatchSubjectResolver.subject(.host, for: url)
        else { return nil }
        return .host(HostMatcher(host: host, includesSubdomains: false))
    }

    /// The table the test field runs against: the draft replaces its saved self in place, or
    /// joins at the end when it is new — exactly the precedence it would have after saving.
    static func testTable(draft: CompiledRule?, saved: [CompiledRule]) -> [CompiledRule] {
        guard let draft else { return saved }
        var table = saved
        if let index = table.firstIndex(where: { $0.id == draft.id }) {
            table[index] = draft
        } else {
            table.append(draft)
        }
        return table
    }

    static func testResult(for urlText: String, draftID: UUID?, rules: [CompiledRule],
                           destinationName: (RuleDestination) -> String) -> String {
        let trimmed = urlText.trimmingCharacters(in: .whitespaces)
        guard let url = URL(string: trimmed), url.host() != nil else {
            return "That is not a URL with a host."
        }
        guard let match = RuleTable.firstMatch(for: url, in: rules) else {
            return "No rule matches. The picker would appear."
        }
        guard match.id == draftID else {
            return "Rule “\(match.rule.name)” wins first — move this one above it."
        }
        return "This rule wins · would open in \(destinationName(match.rule.destination))"
    }

    /// Live wording of what a host matcher covers, mirroring the mockup's example box.
    static func hostExplanation(host: String, includesSubdomains: Bool) -> String {
        let trimmed = host.trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmed.isEmpty else { return "" }
        return includesSubdomains
            ? "Matches \(trimmed), sub.\(trimmed) and deeper subdomains. Does not match not\(trimmed)."
            : "Matches exactly \(trimmed) — www.\(trimmed) is a different host."
    }

    /// The shipped examples. Inserted as editable text, never as opaque presets.
    static let examples: [(label: String, pattern: String, subject: MatchSubject)] = [
        ("A domain and its subdomains", #"^(.+\.)?github\.com$"#, .host),
        ("Exactly one host", #"^mail\.google\.com$"#, .host),
        ("Several hosts at once", #"^(mail|calendar)\.google\.com$"#, .host),
        ("A path inside a site", #"^https://github\.com/my-org/"#, .url),
        ("Any corporate host", #"\.corp\.example\.com$"#, .host),
        ("Links with a tracking parameter", #"[?&]utm_source="#, .url)
    ]
}

struct RuleEditorView: View {
    @State var rule: RoutingRule
    let store: RuleStore
    let discovery: BrowserDiscovery
    @Environment(\.dismiss) private var dismiss

    @State private var testURL = ""
    @State private var patternText = ""
    @State private var validation: PatternValidation?

    private var isEditingExisting: Bool {
        store.rules.contains { $0.id == rule.id }
    }

    private var isRegex: Bool {
        if case .regex = rule.matcher { return true }
        return false
    }

    private var hostText: String {
        if case .host(let matcher) = rule.matcher { return matcher.host }
        return ""
    }

    private var canSave: Bool {
        guard !rule.destination.browserBundleID.isEmpty else { return false }
        guard isRegex else { return !hostText.trimmingCharacters(in: .whitespaces).isEmpty }
        if case .valid = validation { return true }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(isEditingExisting ? "Edit Rule" : "New Rule")
                    .font(.headline)
                Text(isRegex
                     ? "The pattern is searched anywhere in the subject, case-insensitively."
                     : "Matching links will open here without asking.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Form {
                TextField("Name", text: $rule.name)
                Picker("Match by", selection: Binding(
                    get: { isRegex },
                    set: { useRegex in
                        rule.matcher = useRegex
                            ? .regex(RegexMatcher(pattern: patternText, subject: .host))
                            : .host(HostMatcher(host: hostText, includesSubdomains: true))
                        if useRegex { validation = RuleCompiler.validate(patternText) }
                    })) {
                    Text("Host").tag(false)
                    Text("Regular expression").tag(true)
                }
                .pickerStyle(.segmented)

                if isRegex {
                    regexFields
                } else {
                    hostFields
                }

                destinationFields

                Section("Test") {
                    // A visible title would render as the row label and leave only the right
                    // half of the row clickable; the whole row must be the field.
                    TextField("Test URL", text: $testURL, prompt: Text("Paste a URL"))
                        .labelsHidden()
                        .font(.system(.body, design: .monospaced))
                    if !testURL.trimmingCharacters(in: .whitespaces).isEmpty {
                        Text(testResult)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Button("Use sample URL as host") {
                    if let proposed = RuleEditorModel.proposedMatcher(from: testURL) {
                        rule.matcher = proposed
                    }
                }
                .disabled(RuleEditorModel.proposedMatcher(from: testURL) == nil)
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") {
                    if isEditingExisting {
                        store.update(rule)
                    } else {
                        store.add(rule)
                    }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
            }
        }
        .padding(18)
        .frame(width: 560)
        .onAppear {
            if case .regex(let matcher) = rule.matcher {
                patternText = matcher.pattern
                validation = RuleCompiler.validate(matcher.pattern)
            }
        }
    }

    private var testResult: String {
        let draft = try? RuleCompiler.compile(rule)
        let table = RuleEditorModel.testTable(draft: draft, saved: store.compiled)
        return RuleEditorModel.testResult(for: testURL, draftID: rule.id, rules: table) { destination in
            guard let browser = discovery.browsers.first(where: { $0.id == destination.browserBundleID }) else {
                return destination.browserBundleID
            }
            guard let profile = browser.profiles.first(where: { $0.id == destination.profileID }) else {
                return browser.name
            }
            return "\(browser.name) — \(profile.displayName)"
        }
    }

    private var hostFields: some View {
        Group {
            TextField("Host", text: Binding(
                get: { hostText },
                set: { newValue in
                    let includes = if case .host(let m) = rule.matcher { m.includesSubdomains } else { true }
                    rule.matcher = .host(HostMatcher(host: newValue, includesSubdomains: includes))
                }))
            Toggle("Include subdomains", isOn: Binding(
                get: { if case .host(let m) = rule.matcher { m.includesSubdomains } else { false } },
                set: { rule.matcher = .host(HostMatcher(host: hostText, includesSubdomains: $0)) }))
            let explanation = RuleEditorModel.hostExplanation(
                host: hostText,
                includesSubdomains: { if case .host(let m) = rule.matcher { m.includesSubdomains } else { false } }())
            if !explanation.isEmpty {
                Text(explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var regexFields: some View {
        Group {
            Picker("Subject", selection: Binding(
                get: {
                    if case .regex(let m) = rule.matcher { return m.subject }
                    return .host
                },
                set: { rule.matcher = .regex(RegexMatcher(pattern: patternText, subject: $0)) })) {
                Text("Host").tag(MatchSubject.host)
                Text("Full URL").tag(MatchSubject.url)
            }
            .pickerStyle(.segmented)

            TextField("Pattern", text: $patternText)
                .font(.system(.body, design: .monospaced))
                .onChange(of: patternText) { _, new in
                    validation = RuleCompiler.validate(new)
                    if case .regex(let m) = rule.matcher {
                        rule.matcher = .regex(RegexMatcher(pattern: new, subject: m.subject))
                    }
                }
            Menu("Examples") {
                ForEach(RuleEditorModel.examples, id: \.pattern) { example in
                    Button(example.label) {
                        patternText = example.pattern
                        rule.matcher = .regex(RegexMatcher(pattern: example.pattern, subject: example.subject))
                        validation = RuleCompiler.validate(example.pattern)
                    }
                }
            }
            switch validation {
            case .valid(let elapsed):
                Label("Compiles · \(elapsed.formatted()) over the test corpus, limit \(RuleCompiler.budget.formatted())",
                      systemImage: "checkmark.circle")
                    .font(.caption).foregroundStyle(.green)
            case .invalid(let message):
                Label(message, systemImage: "xmark.circle")
                    .font(.caption).foregroundStyle(.red)
            case .tooSlow(let elapsed):
                Label("Takes \(elapsed.formatted()); the limit is \(RuleCompiler.budget.formatted()). It would hang the app on every click.",
                      systemImage: "xmark.circle")
                    .font(.caption).foregroundStyle(.red)
            case nil:
                EmptyView()
            }
        }
    }

    private var destinationFields: some View {
        DestinationPickers(destination: $rule.destination, discovery: discovery)
    }
}

/// Browser and profile pickers over the installed set, shared by the rule editor and the
/// import review sheet.
struct DestinationPickers: View {
    @Binding var destination: RuleDestination
    let discovery: BrowserDiscovery

    private var selectedBrowser: Browser? {
        discovery.browsers.first { $0.id == destination.browserBundleID }
    }

    var body: some View {
        Picker("Open in", selection: Binding(
            get: { destination.browserBundleID },
            set: { newBrowserID in
                // A profile belongs to one browser; switching browsers resets to its default.
                destination = RuleDestination(browserBundleID: newBrowserID, profileID: nil)
            })) {
            ForEach(discovery.browsers) { browser in
                HStack(spacing: 6) {
                    Image(nsImage: browser.icon)
                        .resizable()
                        .frame(width: 16, height: 16)
                        .accessibilityHidden(true)
                    Text(browser.name)
                }
                .tag(browser.id)
            }
        }
        if let browser = selectedBrowser, !browser.profiles.isEmpty {
            Picker("Profile", selection: $destination.profileID) {
                Text("Default profile").tag(String?.none)
                ForEach(browser.profiles) { profile in
                    Text(profile.displayName).tag(String?.some(profile.id))
                }
            }
        }
    }
}

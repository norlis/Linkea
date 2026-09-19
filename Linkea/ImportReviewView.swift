import SwiftUI

/// Presented when an imported file references browsers or profiles this Mac does not have:
/// one decision per distinct missing destination, applied to every rule that points at it.
struct ImportReviewView: View {
    let groups: [RuleTransfer.UnresolvedGroup]
    let discovery: BrowserDiscovery
    let onCancel: () -> Void
    let onImport: ([RuleDestination: RuleTransfer.Resolution]) -> Void

    private enum Action: Hashable {
        case keep
        case remap
        case skip
    }

    @State private var actions: [RuleDestination: Action] = [:]
    @State private var remapTargets: [RuleDestination: RuleDestination] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Review Import")
                    .font(.headline)
                Text("This file points to browsers or profiles that are not on this Mac. Choose what to do with each one.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Form {
                ForEach(groups) { group in
                    Section {
                        LabeledContent(group.label) {
                            Text("used by \(group.ruleNames.count) rule\(group.ruleNames.count == 1 ? "" : "s")")
                                .foregroundStyle(.secondary)
                        }
                        Picker("Action", selection: actionBinding(for: group)) {
                            Text("Keep as imported").tag(Action.keep)
                            Text("Remap to…").tag(Action.remap)
                            Text("Skip these rules").tag(Action.skip)
                        }
                        if actions[group.destination] == .remap {
                            DestinationPickers(destination: remapBinding(for: group), discovery: discovery)
                        }
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Text("Kept rules show as “not available” and their links fall back to the picker.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel", action: onCancel)
                Button("Import") {
                    onImport(resolutions())
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 560, height: 440)
    }

    private func actionBinding(for group: RuleTransfer.UnresolvedGroup) -> Binding<Action> {
        Binding(
            get: { actions[group.destination] ?? .keep },
            set: { action in
                actions[group.destination] = action
                if action == .remap, remapTargets[group.destination] == nil {
                    remapTargets[group.destination] = defaultRemapTarget
                }
            }
        )
    }

    private func remapBinding(for group: RuleTransfer.UnresolvedGroup) -> Binding<RuleDestination> {
        Binding(
            get: { remapTargets[group.destination] ?? defaultRemapTarget },
            set: { remapTargets[group.destination] = $0 }
        )
    }

    private var defaultRemapTarget: RuleDestination {
        RuleDestination(browserBundleID: discovery.browsers.first?.id ?? "", profileID: nil)
    }

    private func resolutions() -> [RuleDestination: RuleTransfer.Resolution] {
        var result: [RuleDestination: RuleTransfer.Resolution] = [:]
        for group in groups {
            switch actions[group.destination] ?? .keep {
            case .keep:
                result[group.destination] = .keep
            case .skip:
                result[group.destination] = .skip
            case .remap:
                // A remap that never got a valid target keeps the rule rather than corrupting it.
                if let target = remapTargets[group.destination], !target.browserBundleID.isEmpty {
                    result[group.destination] = .remap(target)
                } else {
                    result[group.destination] = .keep
                }
            }
        }
        return result
    }
}

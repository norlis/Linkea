import Foundation

/// Rules as a file for people to keep and move: a versioned JSON envelope. Import is strict on
/// purpose — it is an explicit user action, and a broken file must be reported, not silently
/// degraded like the lenient persistence path.
nonisolated enum RuleTransfer {
    static let currentVersion = 1

    struct Archive: Codable {
        let version: Int
        let rules: [RoutingRule]
        // Optional and additive: files written before these fields decode without them, and
        // older readers ignore them — no version bump needed.
        var exportedAt: Date?
        var destinationLabels: [String: String]?
    }

    struct Decoded {
        let rules: [RoutingRule]
        let destinationLabels: [String: String]
    }

    enum TransferError: Error {
        case malformed(String)
        case unsupportedVersion(Int)

        var message: String {
            switch self {
            case .malformed(let detail):
                "The file is not a Linkea rules export. \(detail)"
            case .unsupportedVersion(let version):
                "The file uses rules format \(version); this version of Linkea reads up to \(RuleTransfer.currentVersion)."
            }
        }
    }

    /// Key under which a destination's human-readable label travels in the file. The label is
    /// what lets the importing Mac say "Chrome — Work" for a profile it has never seen.
    static func labelKey(for destination: RuleDestination) -> String {
        guard let profileID = destination.profileID else { return destination.browserBundleID }
        return "\(destination.browserBundleID)/\(profileID)"
    }

    static func export(_ rules: [RoutingRule], labels: [String: String]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let archive = Archive(version: currentVersion, rules: rules,
                              exportedAt: Date(), destinationLabels: labels)
        return try encoder.encode(archive)
    }

    static func decode(_ data: Data) throws -> Decoded {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let archive: Archive
        do {
            archive = try decoder.decode(Archive.self, from: data)
        } catch {
            throw TransferError.malformed(error.localizedDescription)
        }
        guard archive.version <= currentVersion else {
            throw TransferError.unsupportedVersion(archive.version)
        }
        return Decoded(rules: archive.rules, destinationLabels: archive.destinationLabels ?? [:])
    }

    /// A rule with a known `id` updates the existing row in its place; everything else appends in
    /// file order. Importing the same file twice therefore changes nothing the second time, and
    /// nothing is ever deleted.
    static func merge(_ imported: [RoutingRule], into existing: [RoutingRule]) -> [RoutingRule] {
        var merged = existing
        for rule in imported {
            if let index = merged.firstIndex(where: { $0.id == rule.id }) {
                merged[index] = rule
            } else {
                merged.append(rule)
            }
        }
        return merged
    }

    // MARK: - Import review

    /// One distinct destination the file references that this Mac cannot open, with every
    /// imported rule that points at it — one decision covers them all.
    struct UnresolvedGroup: Identifiable, Hashable {
        let destination: RuleDestination
        let label: String
        let ruleNames: [String]

        var id: RuleDestination { destination }
    }

    /// What the user chose for one unresolved destination.
    enum Resolution: Hashable {
        case remap(RuleDestination)
        case keep
        case skip
    }

    /// Groups the imported rules whose destination does not resolve on this Mac, in first-seen
    /// order. The label comes from the file; raw identifiers are the fallback for old exports.
    static func analyze(_ imported: [RoutingRule], labels: [String: String],
                        isResolvable: (RuleDestination) -> Bool) -> [UnresolvedGroup] {
        var order: [RuleDestination] = []
        var names: [RuleDestination: [String]] = [:]
        for rule in imported where !isResolvable(rule.destination) {
            if names[rule.destination] == nil { order.append(rule.destination) }
            names[rule.destination, default: []].append(rule.name)
        }
        return order.map { destination in
            UnresolvedGroup(
                destination: destination,
                label: labels[labelKey(for: destination)] ?? fallbackLabel(for: destination),
                ruleNames: names[destination] ?? []
            )
        }
    }

    /// Applies the per-destination decisions: remap rewrites the destination, keep leaves the
    /// rule untouched, skip drops it. File order is preserved.
    static func apply(_ resolutions: [RuleDestination: Resolution], to imported: [RoutingRule]) -> [RoutingRule] {
        imported.compactMap { rule in
            switch resolutions[rule.destination] {
            case .remap(let destination):
                var remapped = rule
                remapped.destination = destination
                return remapped
            case .skip:
                return nil
            case .keep, nil:
                return rule
            }
        }
    }

    private static func fallbackLabel(for destination: RuleDestination) -> String {
        destination.profileID.map { "\(destination.browserBundleID) · \($0)" }
            ?? destination.browserBundleID
    }
}

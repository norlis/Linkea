import Foundation

/// Rules as a file for people to keep and move: a versioned JSON envelope. Import is strict on
/// purpose — it is an explicit user action, and a broken file must be reported, not silently
/// degraded like the lenient persistence path.
nonisolated enum RuleTransfer {
    static let currentVersion = 1

    struct Archive: Codable {
        let version: Int
        let rules: [RoutingRule]
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

    static func export(_ rules: [RoutingRule]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(Archive(version: currentVersion, rules: rules))
    }

    static func decode(_ data: Data) throws -> [RoutingRule] {
        let archive: Archive
        do {
            archive = try JSONDecoder().decode(Archive.self, from: data)
        } catch {
            throw TransferError.malformed(error.localizedDescription)
        }
        guard archive.version <= currentVersion else {
            throw TransferError.unsupportedVersion(archive.version)
        }
        return archive.rules
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
}

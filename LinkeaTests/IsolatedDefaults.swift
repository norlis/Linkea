import Foundation
import Testing
@testable import Linkea

/// Swaps the process-wide `Preferences.defaults` for an isolated suite so no test ever touches
/// the developer's real defaults. Bodies are synchronous and MainActor-isolated, so the swap
/// cannot interleave across tests.
func withIsolatedDefaults(_ body: () throws -> Void) throws {
    let suiteName = "LinkeaTests-\(UUID().uuidString)"
    let isolated = try #require(UserDefaults(suiteName: suiteName))
    let previous = Preferences.defaults
    Preferences.defaults = isolated
    defer {
        Preferences.defaults = previous
        isolated.removePersistentDomain(forName: suiteName)
    }
    try body()
}

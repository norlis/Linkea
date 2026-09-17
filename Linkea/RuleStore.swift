import Foundation
import Observation

/// Observable owner of the remembered "always open this site here" choices.
///
/// Every mutation writes straight through to `Preferences`, so the picker, the menu bar list and
/// the next launch can never disagree about which sites are pinned.
@Observable
final class RuleStore {
    private(set) var rules: LinkRouterCore.DomainRules

    init(rules: LinkRouterCore.DomainRules = Preferences.domainRules) {
        self.rules = rules
    }

    func destination(for url: URL) -> String? {
        rules.destination(for: url)
    }

    func remember(_ browserBundleID: String, for url: URL) {
        rules.remember(browserBundleID, for: url)
        persist()
    }

    func forget(for url: URL) {
        rules.forget(for: url)
        persist()
    }

    func forget(host: String) {
        rules.forget(host: host)
        persist()
    }

    func forgetAll() {
        rules.forgetAll()
        persist()
    }

    private func persist() {
        Preferences.domainRules = rules
        AppLog.debug("domain rules updated", fields: ["rule.count": String(rules.entries.count)])
    }
}

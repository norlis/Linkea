import CoreGraphics
import Foundation

/// URL schemes Linkea is allowed to route. Anything else is rejected up front.
nonisolated enum WebScheme: String, CaseIterable {
    case http
    case https
}

/// Pure routing logic with no AppKit dependencies, so every branch is unit-testable.
nonisolated enum LinkRouterCore {
    /// Probe URL used to ask Launch Services which apps can act as web browsers.
    static let probeURL: URL = {
        guard let url = URL(string: "https://example.com") else {
            preconditionFailure("static probe URL must parse")
        }
        return url
    }()

    /// Vertical gap between the mouse location and the picker panel.
    static let panelCursorGap: CGFloat = 12

    /// Keeps only well-formed web URLs: allow-listed scheme (case-insensitive) and a non-empty host.
    static func webURLs(from urls: [URL]) -> [URL] {
        urls.filter { url in
            guard let scheme = url.scheme, WebScheme(rawValue: scheme.lowercased()) != nil else { return false }
            guard let host = url.host(), !host.isEmpty else { return false }
            return true
        }
    }

    /// A browser as reported by Launch Services, before any AppKit enrichment (icons).
    struct BrowserCandidate: Hashable {
        let bundleID: String
        let appURL: URL
        let displayName: String
    }

    /// Deduplicates by bundle identifier keeping the first occurrence — Launch Services returns
    /// candidates in suitability order — and drops the app itself from its own picker.
    static func dedupedBrowsers(_ candidates: [BrowserCandidate], excluding selfBundleID: String) -> [BrowserCandidate] {
        var seen = Set<String>()
        return candidates.filter { candidate in
            guard candidate.bundleID != selfBundleID, !seen.contains(candidate.bundleID) else { return false }
            seen.insert(candidate.bundleID)
            return true
        }
    }

    /// PIDs of other running copies of the app, which the freshly launched instance tells to
    /// quit. The newest instance wins: it is the binary the user just built or updated, while a
    /// lingering older one would silently swallow the links Launch Services delivers.
    static func staleInstancePIDs(ownPID: Int32, runningPIDs: [Int32]) -> [Int32] {
        runningPIDs.filter { $0 != ownPID }
    }

    /// Origin (bottom-left, global AppKit coordinates) that centers the panel horizontally on the
    /// cursor and floats it just above, clamped to the screen. When the screen is smaller than the
    /// panel, the bottom-left corner wins so the first browser icons stay reachable.
    static func panelOrigin(panelSize: CGSize, mouseLocation: CGPoint, screenVisibleFrame: CGRect) -> CGPoint {
        let x = mouseLocation.x - panelSize.width / 2
        let y = mouseLocation.y + panelCursorGap
        return CGPoint(
            x: max(screenVisibleFrame.minX, min(x, screenVisibleFrame.maxX - panelSize.width)),
            y: max(screenVisibleFrame.minY, min(y, screenVisibleFrame.maxY - panelSize.height))
        )
    }

    /// Browsers the picker shows after the user's hide list. When hiding would leave nothing,
    /// everything stays visible — a preference must never leave a link with nowhere to go.
    static func visibleBrowsers<Element>(_ browsers: [Element], hiddenIDs: Set<String>, id keyPath: KeyPath<Element, String>) -> [Element] {
        let visible = browsers.filter { !hiddenIDs.contains($0[keyPath: keyPath]) }
        return visible.isEmpty ? browsers : visible
    }

    /// Moves the element matching `id` to the front, keeping the rest in Launch Services order.
    static func moveToFront<Element, ID: Equatable>(_ elements: [Element], matching id: ID?, id keyPath: KeyPath<Element, ID>) -> [Element] {
        guard let id, let index = elements.firstIndex(where: { $0[keyPath: keyPath] == id }) else { return elements }
        var reordered = elements
        reordered.insert(reordered.remove(at: index), at: 0)
        return reordered
    }

    /// One place a link can actually land: a browser that has no profiles, or one specific profile
    /// of a browser that does. Only these carry a shortcut key.
    struct Destination: Hashable {
        let browser: Int
        let profile: Int?
    }

    /// Flattens the picker into the destinations a key can address, in display order. A browser
    /// with profiles is a container, not a stop: it hands its slot to them.
    static func destinations(profileCounts: [Int]) -> [Destination] {
        profileCounts.enumerated().flatMap { browser, count in
            count == 0
                ? [Destination(browser: browser, profile: nil)]
                : (0..<count).map { Destination(browser: browser, profile: $0) }
        }
    }

    /// Keys that address a picker position, in the order they sit on a QWERTY keyboard: the number
    /// row left to right, then the row above the home row. Twenty slots is past any realistic list,
    /// and both rows are reachable without moving the hand off the keyboard.
    static let shortcutKeys = [
        "1", "2", "3", "4", "5", "6", "7", "8", "9", "0",
        "q", "w", "e", "r", "t", "y", "u", "i", "o", "p"
    ]

    /// The key cap to print beside the position, or nil past the twentieth — those stay
    /// mouse-only rather than showing a cap that does nothing.
    static func shortcutKey(forIndex index: Int) -> String? {
        shortcutKeys.indices.contains(index) ? shortcutKeys[index] : nil
    }

    /// Position addressed by a keystroke. Case-insensitive, so a shifted letter still lands.
    static func browserIndex(forShortcutKey key: String) -> Int? {
        guard key.count == 1 else { return nil }
        return shortcutKeys.firstIndex(of: key.lowercased())
    }

    // MARK: - Picker keyboard policy

    /// The key that toggles the in-panel legend. Sits outside `shortcutKeys` on purpose, so
    /// naming the profiles can never compete with opening one.
    static let legendKey = "v"

    /// What a keystroke inside the picker should do. `.pass` hands the event back untouched —
    /// Esc included, which the panel handles through `cancelOperation`.
    enum PickerKeyAction: Hashable {
        case open(Int)
        case toggleLegend
        case pass
    }

    /// Keyboard policy of the picker: return and keypad enter open the first destination, the
    /// legend key toggles the footer, a shortcut key opens its destination, and everything else —
    /// modified keystrokes included, they belong to the system — passes through.
    static func pickerKeyAction(keyCode: UInt16, characters: String?, isModified: Bool, destinationCount: Int) -> PickerKeyAction {
        guard destinationCount > 0, !isModified else { return .pass }
        let returnKeyCodes: Set<UInt16> = [36, 76] // return, keypad enter
        if returnKeyCodes.contains(keyCode) { return .open(0) }
        guard let characters else { return .pass }
        if characters.lowercased() == legendKey { return .toggleLegend }
        guard let index = browserIndex(forShortcutKey: characters), index < destinationCount else { return .pass }
        return .open(index)
    }

    /// Re-validates a destination against the profile counts it was built from, so a stale index
    /// can never crash the picker.
    static func resolvedDestination(_ destination: Destination, profileCounts: [Int]) -> Destination? {
        guard profileCounts.indices.contains(destination.browser) else { return nil }
        if let profile = destination.profile, !(0..<profileCounts[destination.browser]).contains(profile) {
            return nil
        }
        return destination
    }

    /// Legend rows: every profile destination paired with its key cap, in display order.
    static func legendDestinations(profileCounts: [Int]) -> [(key: String, destination: Destination)] {
        destinations(profileCounts: profileCounts).enumerated().compactMap { index, destination in
            guard destination.profile != nil, let key = shortcutKey(forIndex: index) else { return nil }
            return (key, destination)
        }
    }

    /// Footer hint: the addressable key span, the return target and — when profiles exist — the
    /// legend key.
    static func shortcutHint(destinationCount: Int, firstBrowserName: String?, hasLegend: Bool, legendShown: Bool) -> String {
        guard let firstBrowserName else { return "esc cancels" }
        let lastIndex = min(destinationCount, shortcutKeys.count) - 1
        guard lastIndex >= 0 else { return "esc cancels" }
        let span = lastIndex == 0 ? shortcutKeys[0] : "\(shortcutKeys[0])–\(shortcutKeys[lastIndex])"
        let names = hasLegend ? " · \(legendKey) \(legendShown ? "hides" : "names")" : ""
        return "\(span) open · return \(firstBrowserName)\(names) · esc"
    }
}

import SwiftUI

/// Live state of one presentation of the panel, shared by the view and the keyboard handler so a
/// click and a keystroke always mean the same thing.
@Observable
final class PickerPanelState {
    /// Whether the browser the user picks becomes this site's permanent destination.
    var remember: Bool
    /// Whether the footer spells out every profile's colour, key and name — toggled with "v".
    var showsLegend: Bool

    init(remember: Bool, showsLegend: Bool = false) {
        self.remember = remember
        self.showsLegend = showsLegend
    }
}

/// Content of the floating picker on Liquid Glass: one row per browser, and a coloured numbered
/// dot per profile. Keys go to the places a link can actually land — a browser without profiles,
/// or one specific profile — so a browser that has them is a container, not a stop.
struct PickerView: View {
    let urls: [URL]
    let browsers: [Browser]
    /// Browser this site is pinned to, shown as "Always" and already sorted to the top.
    let pinnedBundleID: String?
    @Bindable var state: PickerPanelState
    let onSelect: (Browser, BrowserProfile?) -> Void

    @State private var hoveredBundleID: String?
    @State private var hoveredProfile: LinkRouterCore.Destination?

    // Fixed metrics scale with the user's text size so caps, dots and the panel itself keep
    // fitting their glyphs under Dynamic Type.
    @ScaledMetric(relativeTo: .callout) private var browserIconSize = 24.0
    @ScaledMetric(relativeTo: .caption2) private var capSize = 18.0
    @ScaledMetric(relativeTo: .caption2) private var legendDotSize = 14.0
    @ScaledMetric(relativeTo: .callout) private var panelWidth = 268.0

    private var host: String { urls.first?.host() ?? "" }

    private var destinations: [LinkRouterCore.Destination] {
        LinkRouterCore.destinations(profileCounts: browsers.map(\.profiles.count))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(host.isEmpty ? "Open link in…" : host)
                .font(.callout.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.middle)

            if browsers.isEmpty {
                Text("No browsers found")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 1) {
                    ForEach(Array(browsers.enumerated()), id: \.element.id) { index, browser in
                        row(browserIndex: index, browser: browser)
                    }
                }

                if state.showsLegend, !legendEntries.isEmpty {
                    Divider()
                    legend
                }

                Divider()

                Toggle(isOn: $state.remember) {
                    Text("Remember for \(host)")
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .toggleStyle(.checkbox)
                .font(.caption)
                .disabled(host.isEmpty)

                Text(shortcutHint)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(12)
        .frame(width: panelWidth)
        .glassEffect(.regular, in: .rect(cornerRadius: 14))
    }

    // MARK: - Rows

    private func row(browserIndex: Int, browser: Browser) -> some View {
        // The profile dots are siblings of the row button, never part of its label — a button
        // nested inside another button's label is unreachable for VoiceOver.
        HStack(spacing: 8) {
            Button {
                onSelect(browser, nil)
            } label: {
                HStack(spacing: 8) {
                    Image(nsImage: browser.icon)
                        .resizable()
                        .frame(width: browserIconSize, height: browserIconSize)
                        .accessibilityHidden(true)
                    Text(browser.name)
                        .font(.callout)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if browser.id == pinnedBundleID {
                        Text("Always")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.accentColor.opacity(0.24), in: Capsule())
                    }
                    // The name of the dot under the cursor, right where the cursor already is. It sits
                    // in the row rather than floating over it so the panel edge can never clip it.
                    if let hovered = hoveredProfile, hovered.browser == browserIndex,
                       let profileIndex = hovered.profile, browser.profiles.indices.contains(profileIndex) {
                        profileLabel(browser.profiles[profileIndex])
                    }
                    if browser.profiles.isEmpty,
                       let key = key(for: LinkRouterCore.Destination(browser: browserIndex, profile: nil)) {
                        keyCap(key)
                    }
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help(browser.profiles.isEmpty ? browser.name : "\(browser.name) — last used profile")
            .accessibilityLabel(browser.id == pinnedBundleID ? "\(browser.name), Always" : browser.name)
            .accessibilityHint(rowAccessibilityHint(browserIndex: browserIndex, browser: browser))

            if !browser.profiles.isEmpty {
                profileDots(browserIndex: browserIndex, browser: browser)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rowBackground(for: browser), in: .rect(cornerRadius: 7))
        .onHover { isInside in
            hoveredBundleID = isInside ? browser.id : nil
        }
    }

    private func rowAccessibilityHint(browserIndex: Int, browser: Browser) -> String {
        guard browser.profiles.isEmpty else { return "Opens the last used profile" }
        guard let key = key(for: LinkRouterCore.Destination(browser: browserIndex, profile: nil)) else { return "" }
        return "Press \(key)"
    }

    private func profileDots(browserIndex: Int, browser: Browser) -> some View {
        HStack(spacing: 5) {
            ForEach(Array(browser.profiles.enumerated()), id: \.element.id) { profileIndex, profile in
                let destination = LinkRouterCore.Destination(browser: browserIndex, profile: profileIndex)
                let cap = key(for: destination)
                Button {
                    onSelect(browser, profile)
                } label: {
                    Text(cap ?? "•")
                        .font(.caption2.weight(.bold).monospaced())
                        .foregroundStyle(foreground(for: profile.tint))
                        .frame(width: capSize, height: capSize)
                        .background(background(for: profile.tint), in: Circle())
                        .overlay {
                            Circle().strokeBorder(ring(for: profile.tint, highlighted: hoveredProfile == destination), lineWidth: 1.5)
                        }
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .help(profile.displayName)
                .accessibilityLabel("\(browser.name), \(profile.displayName)")
                .accessibilityHint(cap.map { "Press \($0)" } ?? "")
                .onHover { isInside in
                    hoveredProfile = isInside ? destination : nil
                }
            }
        }
        .fixedSize()
    }

    private func profileLabel(_ profile: BrowserProfile) -> some View {
        Text(profile.displayName)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(foreground(for: profile.tint))
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(background(for: profile.tint), in: Capsule())
            .layoutPriority(1)
    }

    private func keyCap(_ key: String) -> some View {
        Text(key)
            .font(.caption2.weight(.medium).monospaced())
            .foregroundStyle(.secondary)
            .frame(width: capSize, height: capSize)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
    }

    // MARK: - Legend

    private var legendEntries: [(key: String, profile: BrowserProfile)] {
        LinkRouterCore.legendDestinations(profileCounts: browsers.map(\.profiles.count)).compactMap { key, destination in
            guard let profileIndex = destination.profile else { return nil }
            return (key, browsers[destination.browser].profiles[profileIndex])
        }
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(legendEntries, id: \.key) { entry in
                HStack(spacing: 6) {
                    Text(entry.key)
                        .font(.caption2.weight(.bold).monospaced())
                        .foregroundStyle(foreground(for: entry.profile.tint))
                        .frame(width: legendDotSize, height: legendDotSize)
                        .background(background(for: entry.profile.tint), in: Circle())
                    Text(entry.profile.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    // MARK: - Bits

    private var shortcutHint: String {
        LinkRouterCore.shortcutHint(
            destinationCount: destinations.count,
            firstBrowserName: browsers.first?.name,
            hasLegend: !legendEntries.isEmpty,
            legendShown: state.showsLegend
        )
    }

    private func key(for destination: LinkRouterCore.Destination) -> String? {
        guard let index = destinations.firstIndex(of: destination) else { return nil }
        return LinkRouterCore.shortcutKey(forIndex: index)
    }

    /// Tintless profiles (Firefox, Safari) render like key caps — appearance-adaptive primary on
    /// quaternary — instead of white on `.secondary`, which fails contrast in light mode.
    private func background(for tint: ProfileTint?) -> AnyShapeStyle {
        guard let tint else { return AnyShapeStyle(.quaternary) }
        return AnyShapeStyle(Color(red: Double(tint.red) / 255, green: Double(tint.green) / 255, blue: Double(tint.blue) / 255))
    }

    private func foreground(for tint: ProfileTint?) -> AnyShapeStyle {
        guard let tint else { return AnyShapeStyle(.primary) }
        return AnyShapeStyle(tint.prefersLightForeground ? Color.white : Self.darkGlyph)
    }

    /// Dark enough to stay readable on every pale tint the luminance cut-off routes here.
    private static let darkGlyph = Color(white: 0.12)

    private func ring(for tint: ProfileTint?, highlighted: Bool) -> AnyShapeStyle {
        // A white ring would vanish on the quaternary (tintless) dot in light mode.
        let base: Color = tint == nil ? .primary : .white
        return AnyShapeStyle(base.opacity(highlighted ? 0.9 : 0.35))
    }

    private func rowBackground(for browser: Browser) -> Color {
        if hoveredBundleID == browser.id { return Color.primary.opacity(0.10) }
        if browser.id == pinnedBundleID { return Color.accentColor.opacity(0.14) }
        return .clear
    }
}

#Preview {
    PickerView(
        urls: [LinkRouterCore.probeURL],
        browsers: [],
        pinnedBundleID: nil,
        state: PickerPanelState(remember: false),
        onSelect: { _, _ in }
    )
}

#Preview("Populated") {
    let icon = NSWorkspace.shared.icon(forFile: "/System/Applications/Safari.app")
    return PickerView(
        urls: [LinkRouterCore.probeURL],
        browsers: [
            Browser(id: "com.example.chrome", name: "Chrome", appURL: URL(filePath: "/"), icon: icon, profiles: [
                BrowserProfile(id: "Default", displayName: "Personal", recipe: .chromiumProfileDirectory("Default"), tint: ProfileTint(red: 0x3E, green: 0x5E, blue: 0x98)),
                BrowserProfile(id: "Profile 1", displayName: "Trabajo", recipe: .chromiumProfileDirectory("Profile 1"), tint: ProfileTint(red: 0xA7, green: 0xAB, blue: 0xB7))
            ]),
            Browser(id: "org.example.firefox", name: "Firefox", appURL: URL(filePath: "/"), icon: icon, profiles: [
                BrowserProfile(id: "default-release", displayName: "default-release", recipe: .firefoxProfileName("default-release")),
                BrowserProfile(id: "Trabajo", displayName: "Trabajo", recipe: .firefoxProfileName("Trabajo"))
            ]),
            Browser(id: "com.example.safari", name: "Safari", appURL: URL(filePath: "/"), icon: icon, profiles: [])
        ],
        pinnedBundleID: "com.example.safari",
        state: PickerPanelState(remember: true, showsLegend: true),
        onSelect: { _, _ in }
    )
}

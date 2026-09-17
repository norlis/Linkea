import Foundation

/// How a specific browser profile is launched. Chromium and Firefox take command-line arguments;
/// Safari has no API, so its recipe carries the user-mapped File-menu item to press.
nonisolated enum LaunchRecipe: Hashable {
    case chromiumProfileDirectory(String)
    case firefoxProfileName(String)
    case safariProfileMenuItem(String)
}

/// The colour a browser assigned to a profile, as plain components so the pure layer stays free
/// of AppKit. Alpha is dropped: the picker always draws the dot opaque.
nonisolated struct ProfileTint: Hashable {
    let red: Int
    let green: Int
    let blue: Int

    /// Whether a digit drawn on this colour should be white. Chrome's untouched default is a pale
    /// grey, so picking one foreground for every profile leaves some of them unreadable.
    var prefersLightForeground: Bool {
        let luminance = 0.2126 * Double(red) + 0.7152 * Double(green) + 0.0722 * Double(blue)
        return luminance < 140
    }
}

/// A launchable browser profile as shown in the picker.
nonisolated struct BrowserProfile: Hashable, Identifiable {
    let id: String
    let displayName: String
    let recipe: LaunchRecipe
    /// Nil for browsers that keep no colour of their own — Firefox and Safari.
    let tint: ProfileTint?

    init(id: String, displayName: String, recipe: LaunchRecipe, tint: ProfileTint? = nil) {
        self.id = id
        self.displayName = displayName
        self.recipe = recipe
        self.tint = tint
    }
}

/// Pure profile logic — parsers and argument builders with no file or AppKit access,
/// so every branch is unit-testable with string fixtures.
nonisolated enum ProfileCore {
    // MARK: - Chromium

    /// Application Support subpath holding each Chromium-family browser's "Local State" file.
    static func chromiumSupportPath(forBundleID bundleID: String) -> String? {
        switch bundleID {
        case "com.google.Chrome": "Google/Chrome"
        case "org.chromium.Chromium": "Chromium"
        case "com.microsoft.edgemac": "Microsoft Edge"
        case "com.brave.Browser": "BraveSoftware/Brave-Browser"
        case "com.vivaldi.Vivaldi": "Vivaldi"
        default: nil
        }
    }

    /// Parses Chromium's "Local State" JSON (`profile.info_cache`). The dictionary key is the
    /// profile directory ("Default", "Profile 1"…) and the value carries the display name.
    /// System and Guest pseudo-profiles are excluded. `gaia_name` (the account's real name) is
    /// deliberately never read. Malformed input yields nil, a valid file with only pseudo-profiles
    /// an empty list — the caller logs, not us.
    static func parseChromiumProfiles(localStateJSON: Data) -> [BrowserProfile]? {
        struct LocalState: Decodable {
            struct Profile: Decodable {
                struct Info: Decodable {
                    let name: String?
                    let colorSeed: Int?
                    let highlightColor: Int?

                    enum CodingKeys: String, CodingKey {
                        case name
                        case colorSeed = "profile_color_seed"
                        case highlightColor = "profile_highlight_color"
                    }
                }

                let infoCache: [String: Info]

                enum CodingKeys: String, CodingKey {
                    case infoCache = "info_cache"
                }
            }

            let profile: Profile
        }

        guard let state = try? JSONDecoder().decode(LocalState.self, from: localStateJSON) else { return nil }
        let excludedDirectories: Set<String> = ["System Profile", "Guest Profile"]
        return state.profile.infoCache
            .filter { !excludedDirectories.contains($0.key) }
            .map { directory, info in
                let name = info.name.flatMap { $0.isEmpty ? nil : $0 } ?? directory
                // The seed is the colour the user actually picked; the highlight is a neutral grey
                // until they do, so it only stands in when there is no seed at all.
                let colour = (info.colorSeed ?? info.highlightColor).map(tint(fromChromiumColor:))
                return BrowserProfile(
                    id: directory,
                    displayName: name,
                    recipe: .chromiumProfileDirectory(directory),
                    tint: colour
                )
            }
            .sorted { $0.id < $1.id }
    }

    /// Chromium stores colours as a signed 32-bit ARGB integer, so every real colour arrives
    /// negative once the alpha byte is set.
    static func tint(fromChromiumColor value: Int) -> ProfileTint {
        let argb = UInt32(truncatingIfNeeded: value)
        return ProfileTint(
            red: Int((argb >> 16) & 0xFF),
            green: Int((argb >> 8) & 0xFF),
            blue: Int(argb & 0xFF)
        )
    }

    // MARK: - Firefox

    /// Parses Firefox's `profiles.ini`, keeping file order. Only `[Profile*]` sections with a
    /// `Name` count; `[Install*]`/`[General]` sections are ignored.
    static func parseFirefoxProfiles(ini: String) -> [BrowserProfile] {
        var profiles: [BrowserProfile] = []
        var inProfileSection = false
        var currentName: String?

        func flush() {
            if inProfileSection, let name = currentName, !name.isEmpty {
                profiles.append(BrowserProfile(id: name, displayName: name, recipe: .firefoxProfileName(name)))
            }
            currentName = nil
        }

        // Split on any newline, not on "\n": Swift folds CRLF into a single Character, so a
        // Windows-written file would otherwise never split and parse to zero profiles.
        for rawLine in ini.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("["), line.hasSuffix("]") {
                flush()
                inProfileSection = line.dropFirst().dropLast().hasPrefix("Profile")
            } else if inProfileSection, let separator = line.firstIndex(of: "=") {
                if line[..<separator] == "Name" {
                    currentName = String(line[line.index(after: separator)...])
                }
            }
        }
        flush()
        return profiles
    }

    // MARK: - Launch arguments

    /// Command-line arguments that open `urls` in the given profile. The profile directory stays
    /// one argument even with spaces — argument arrays need no shell quoting.
    static func launchArguments(recipe: LaunchRecipe, urls: [URL]) -> [String] {
        let urlStrings = urls.map(\.absoluteString)
        return switch recipe {
        case .chromiumProfileDirectory(let directory): ["--profile-directory=\(directory)"] + urlStrings
        case .firefoxProfileName(let name): ["-P", name, "--new-instance"] + urlStrings
        case .safariProfileMenuItem: []
        }
    }

    // MARK: - Safari menu mapping

    /// Cleans the raw File-menu titles for the mapping UI: trims, drops separators/blanks and
    /// duplicates, preserving menu order.
    static func candidateSafariProfileItems(menuTitles: [String]) -> [String] {
        var seen = Set<String>()
        return menuTitles.compactMap { title in
            let trimmed = title.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !seen.contains(trimmed) else { return nil }
            seen.insert(trimmed)
            return trimmed
        }
    }

    /// Extracts the profile names from localized menu titles by stripping the words common to all
    /// of them ("New … Window", "Nueva ventana de …") — locale-independent because the profile
    /// name is the only part that varies. Falls back to the full title when nothing distinguishes.
    static func distinguishingNames(fromMenuTitles titles: [String]) -> [String] {
        guard titles.count >= 2 else { return titles }
        let tokenized = titles.map { $0.split(separator: " ").map(String.init) }
        guard let minCount = tokenized.map(\.count).min() else { return titles }

        var prefixLength = 0
        while prefixLength < minCount, Set(tokenized.map { $0[prefixLength] }).count == 1 {
            prefixLength += 1
        }
        var suffixLength = 0
        while suffixLength < minCount - prefixLength, Set(tokenized.map { $0[$0.count - 1 - suffixLength] }).count == 1 {
            suffixLength += 1
        }

        return zip(titles, tokenized).map { title, words in
            let middle = words.dropFirst(prefixLength).dropLast(suffixLength).joined(separator: " ")
            return middle.isEmpty ? title : middle
        }
    }
}

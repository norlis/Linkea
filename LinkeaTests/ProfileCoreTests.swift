import Foundation
import Testing
@testable import Linkea

struct ChromiumProfileParsingTests {
    private let fixture = Data("""
    {
      "profile": {
        "info_cache": {
          "Default": { "name": "Personal", "gaia_name": "someone@example.com" },
          "Profile 1": { "name": "Trabajo" },
          "Profile 2": { "name": "" },
          "System Profile": { "name": "System" },
          "Guest Profile": { "name": "Guest" }
        }
      }
    }
    """.utf8)

    @Test func parsesProfilesSortedByDirectoryExcludingSystemAndGuest() throws {
        let profiles = try #require(ProfileCore.parseChromiumProfiles(localStateJSON: fixture))
        #expect(profiles.map(\.id) == ["Default", "Profile 1", "Profile 2"])
        #expect(profiles.map(\.displayName) == ["Personal", "Trabajo", "Profile 2"])
        #expect(profiles.first?.recipe == .chromiumProfileDirectory("Default"))
    }

    @Test func emptyNameFallsBackToTheDirectoryKey() throws {
        let profiles = try #require(ProfileCore.parseChromiumProfiles(localStateJSON: fixture))
        #expect(profiles.last?.displayName == "Profile 2")
    }

    @Test func corruptJSONYieldsNilSoTheCallerCanTellItFromAValidEmptyFile() {
        #expect(ProfileCore.parseChromiumProfiles(localStateJSON: Data("not json".utf8)) == nil)
        #expect(ProfileCore.parseChromiumProfiles(localStateJSON: Data(#"{"profile": {}}"#.utf8)) == nil)
    }

    @Test func onlyPseudoProfilesYieldsAValidEmptyListNotNil() {
        let json = Data(#"{"profile": {"info_cache": {"System Profile": {}, "Guest Profile": {}}}}"#.utf8)
        #expect(ProfileCore.parseChromiumProfiles(localStateJSON: json) == [])
    }

    /// Documents the current contract: ordering is lexicographic on the directory key, so a
    /// two-digit profile sorts before a one-digit one. A numeric sort is a product decision.
    @Test func directoriesSortLexicographicallySoProfileTenPrecedesProfileTwo() throws {
        let json = Data(#"{"profile": {"info_cache": {"Profile 2": {"name": "Two"}, "Profile 10": {"name": "Ten"}, "Default": {"name": "Zero"}}}}"#.utf8)
        let profiles = try #require(ProfileCore.parseChromiumProfiles(localStateJSON: json))
        #expect(profiles.map(\.id) == ["Default", "Profile 10", "Profile 2"])
    }
}

struct FirefoxProfileParsingTests {
    private let fixture = """
    [Install4F96D1932A9F858E]
    Default=Profiles/abc.default-release
    Locked=1

    [Profile1]
    Name=Trabajo
    IsRelative=1
    Path=Profiles/xyz.trabajo

    [Profile0]
    Name=default-release
    IsRelative=1
    Path=Profiles/abc.default-release
    Default=1

    [General]
    StartWithLastProfile=1
    """

    @Test func parsesProfilesInFileOrderIgnoringOtherSections() {
        let profiles = ProfileCore.parseFirefoxProfiles(ini: fixture)
        #expect(profiles.map(\.displayName) == ["Trabajo", "default-release"])
        #expect(profiles.first?.recipe == .firefoxProfileName("Trabajo"))
    }

    @Test(arguments: ["", "garbage without sections", "[Profile0]\nPath=Profiles/x", "[Profile0]\nName=   "])
    func emptyMalformedOrNamelessINIYieldsEmpty(ini: String) {
        #expect(ProfileCore.parseFirefoxProfiles(ini: ini).isEmpty)
    }

    @Test func windowsLineEndingsParseIdenticallyToUnixOnes() {
        // Firefox profiles synced from Windows write CRLF; a trailing \r used to break section
        // detection and leak into the -P launch argument.
        let crlf = fixture.replacingOccurrences(of: "\n", with: "\r\n")
        let profiles = ProfileCore.parseFirefoxProfiles(ini: crlf)
        #expect(profiles.map(\.displayName) == ["Trabajo", "default-release"])
        #expect(profiles.first?.recipe == .firefoxProfileName("Trabajo"))
    }
}

struct LaunchArgumentTests {
    @Test func chromiumKeepsAProfileDirectoryWithSpacesAsOneArgument() throws {
        let url = try #require(URL(string: "https://example.com/a"))
        let arguments = ProfileCore.launchArguments(recipe: .chromiumProfileDirectory("Profile 1"), urls: [url])
        #expect(arguments == ["--profile-directory=Profile 1", "https://example.com/a"])
    }

    @Test func firefoxUsesProfileNameAndNewInstance() throws {
        let url = try #require(URL(string: "https://example.com/a"))
        let arguments = ProfileCore.launchArguments(recipe: .firefoxProfileName("Trabajo"), urls: [url])
        #expect(arguments == ["-P", "Trabajo", "--new-instance", "https://example.com/a"])
    }

    @Test func safariRecipeNeedsNoArguments() {
        #expect(ProfileCore.launchArguments(recipe: .safariProfileMenuItem("New Work Window"), urls: []).isEmpty)
    }

    @Test func arcPassesTheSpaceIDFirstThenTheURLsToTheScript() throws {
        let first = try #require(URL(string: "https://example.com/1"))
        let second = try #require(URL(string: "https://example.com/2"))
        let arguments = ProfileCore.launchArguments(recipe: .arcSpace("6CA2C3C6"), urls: [first, second])
        #expect(arguments == ["6CA2C3C6", "https://example.com/1", "https://example.com/2"])
    }

    @Test func multipleURLsAreAppendedInOrder() throws {
        let first = try #require(URL(string: "https://example.com/1"))
        let second = try #require(URL(string: "https://example.com/2"))
        let arguments = ProfileCore.launchArguments(recipe: .chromiumProfileDirectory("Default"), urls: [first, second])
        #expect(arguments == ["--profile-directory=Default", "https://example.com/1", "https://example.com/2"])
    }
}

struct ArcSpaceParsingTests {
    // Trimmed from a real StorableSidebar.json: `spaces` interleaves each space's id string with
    // its object, and the first container holds no spaces at all.
    private let fixture = Data("""
    {
      "sidebar": {
        "containers": [
          { "global": {} },
          {
            "spaces": [
              "A7A76E41",
              {
                "id": "A7A76E41",
                "title": "Personal",
                "profile": { "default": true },
                "customInfo": {
                  "windowTheme": {
                    "primaryColorPalette": {
                      "midTone": { "red": 1.0000001, "green": 0.5220286, "blue": -0.0498752, "alpha": 1, "colorSpace": "extendedSRGB" }
                    }
                  }
                }
              },
              "6CA2C3C6",
              { "id": "6CA2C3C6", "title": "Trabajo", "profile": { "custom": { "_0": { "directoryBasename": "Profile 3" } } } },
              "4DA7AB1F",
              { "id": "4DA7AB1F", "title": "" }
            ]
          }
        ]
      }
    }
    """.utf8)

    @Test func parsesSpacesInSidebarOrderSkippingTheInterleavedIDs() throws {
        let spaces = try #require(ProfileCore.parseArcSpaces(sidebarJSON: fixture))
        #expect(spaces.map(\.id) == ["A7A76E41", "6CA2C3C6", "4DA7AB1F"])
        #expect(spaces.map(\.recipe) == [.arcSpace("A7A76E41"), .arcSpace("6CA2C3C6"), .arcSpace("4DA7AB1F")])
    }

    @Test func untitledSpaceFallsBackToItsSidebarPosition() throws {
        let spaces = try #require(ProfileCore.parseArcSpaces(sidebarJSON: fixture))
        #expect(spaces.map(\.displayName) == ["Personal", "Trabajo", "Space 3"])
    }

    @Test func themeMidToneBecomesTheTintClampedToTheDisplayableRange() throws {
        let spaces = try #require(ProfileCore.parseArcSpaces(sidebarJSON: fixture))
        #expect(spaces.first?.tint == ProfileTint(red: 255, green: 133, blue: 0))
        #expect(spaces.dropFirst().allSatisfy { $0.tint == nil })
    }

    @Test(arguments: ["not json", #"{}"#, #"{"sidebar": {}}"#])
    func unrecognisedStructureYieldsNil(json: String) {
        #expect(ProfileCore.parseArcSpaces(sidebarJSON: Data(json.utf8)) == nil)
    }

    @Test func containersWithoutSpacesYieldAValidEmptyList() {
        let json = Data(#"{"sidebar": {"containers": [{"global": {}}]}}"#.utf8)
        #expect(ProfileCore.parseArcSpaces(sidebarJSON: json) == [])
    }
}

struct AppleScriptErrorNumberTests {
    @Test(arguments: [
        ("arc.applescript:444:449: execution error: Not authorized to send Apple events to Arc. (-1743)\n", -1743),
        ("execution error: Can’t get space id \"X\" (in (-1) state). (-1728)", -1728)
    ])
    func extractsTheTrailingErrorNumber(diagnostics: String, expected: Int) {
        #expect(ProfileCore.appleScriptErrorNumber(fromDiagnostics: diagnostics) == expected)
    }

    @Test(arguments: ["", "execution error: something odd", "(-17x3)"])
    func noTrailingNumberYieldsNil(diagnostics: String) {
        #expect(ProfileCore.appleScriptErrorNumber(fromDiagnostics: diagnostics) == nil)
    }
}

struct ChromiumSupportPathTests {
    @Test(arguments: [
        ("com.google.Chrome", "Google/Chrome"),
        ("org.chromium.Chromium", "Chromium"),
        ("com.microsoft.edgemac", "Microsoft Edge"),
        ("com.brave.Browser", "BraveSoftware/Brave-Browser"),
        ("com.vivaldi.Vivaldi", "Vivaldi")
    ])
    func mapsKnownChromiumBrowsers(bundleID: String, expected: String) {
        #expect(ProfileCore.chromiumSupportPath(forBundleID: bundleID) == expected)
    }

    @Test func unknownBundleIDHasNoPath() {
        #expect(ProfileCore.chromiumSupportPath(forBundleID: "com.apple.Safari") == nil)
    }
}

struct SafariMenuHelperTests {
    @Test func candidateItemsDropSeparatorsBlanksAndDuplicatesPreservingOrder() {
        let titles = ["New Window", "", "  ", "New Work Window", "New Window"]
        #expect(ProfileCore.candidateSafariProfileItems(menuTitles: titles) == ["New Window", "New Work Window"])
    }

    @Test func distinguishingNamesStripCommonWordsAcrossLocales() {
        #expect(ProfileCore.distinguishingNames(fromMenuTitles: ["New Work Window", "New Personal Window"]) == ["Work", "Personal"])
        #expect(ProfileCore.distinguishingNames(fromMenuTitles: ["Nueva ventana de Trabajo", "Nueva ventana de Personal"]) == ["Trabajo", "Personal"])
    }

    @Test func multiWordProfileNamesSurviveStripping() {
        let names = ProfileCore.distinguishingNames(fromMenuTitles: ["New Work Stuff Window", "New Personal Window"])
        #expect(names == ["Work Stuff", "Personal"])
    }

    @Test func singleTitleFallsBackToItself() {
        #expect(ProfileCore.distinguishingNames(fromMenuTitles: ["New Work Window"]) == ["New Work Window"])
    }

    @Test func identicalTitlesFallBackToThemselves() {
        #expect(ProfileCore.distinguishingNames(fromMenuTitles: ["New Window", "New Window"]) == ["New Window", "New Window"])
    }

    /// Pins the asymmetric-but-lossless case: stripping the shared words empties the plain
    /// "New Window" title, which falls back whole while its sibling keeps just the profile name.
    @Test func aTitleMadeOnlyOfTheCommonWordsFallsBackToItsFullText() {
        #expect(ProfileCore.distinguishingNames(fromMenuTitles: ["New Window", "New Work Window"]) == ["New Window", "Work"])
    }
}

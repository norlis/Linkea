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

    @Test func multipleURLsAreAppendedInOrder() throws {
        let first = try #require(URL(string: "https://example.com/1"))
        let second = try #require(URL(string: "https://example.com/2"))
        let arguments = ProfileCore.launchArguments(recipe: .chromiumProfileDirectory("Default"), urls: [first, second])
        #expect(arguments == ["--profile-directory=Default", "https://example.com/1", "https://example.com/2"])
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

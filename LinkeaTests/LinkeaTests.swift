import CoreGraphics
import Foundation
import Testing
@testable import Linkea

struct WebURLFilteringTests {
    @Test func acceptsHTTPAndHTTPSCaseInsensitivelyPreservingOrder() throws {
        let http = try #require(URL(string: "http://example.com/a"))
        let httpsUpper = try #require(URL(string: "HTTPS://Example.com/b"))
        #expect(LinkRouterCore.webURLs(from: [http, httpsUpper]) == [http, httpsUpper])
    }

    @Test(arguments: [
        "file:///etc/hosts",
        "javascript:alert(1)",
        "mailto:someone@example.com",
        "ftp://example.com/file",
        "macappstore://apps.apple.com/app/id1",
        "https://"
    ])
    func rejectsDisallowedSchemesAndHostlessURLs(raw: String) throws {
        let url = try #require(URL(string: raw))
        #expect(LinkRouterCore.webURLs(from: [url]).isEmpty)
    }

    @Test func dropsOnlyInvalidEntriesFromMixedInput() throws {
        let valid = try #require(URL(string: "https://example.com"))
        let invalid = try #require(URL(string: "mailto:someone@example.com"))
        #expect(LinkRouterCore.webURLs(from: [invalid, valid, invalid]) == [valid])
    }

    @Test func emptyInputYieldsEmptyOutput() {
        #expect(LinkRouterCore.webURLs(from: []).isEmpty)
    }
}

struct StaleInstanceTests {
    @Test func everyOtherInstanceIsStaleAndOwnPIDNever() {
        #expect(LinkRouterCore.staleInstancePIDs(ownPID: 42, runningPIDs: [7, 42, 99]) == [7, 99])
    }

    @Test func aLoneInstanceHasNothingToTerminate() {
        #expect(LinkRouterCore.staleInstancePIDs(ownPID: 42, runningPIDs: [42]).isEmpty)
        #expect(LinkRouterCore.staleInstancePIDs(ownPID: 42, runningPIDs: []).isEmpty)
    }
}

struct BrowserDeduplicationTests {
    private func candidate(_ bundleID: String, name: String? = nil) -> LinkRouterCore.BrowserCandidate {
        LinkRouterCore.BrowserCandidate(
            bundleID: bundleID,
            appURL: URL(filePath: "/Applications/\(bundleID).app"),
            displayName: name ?? bundleID
        )
    }

    @Test func keepsFirstOccurrencePreservingLaunchServicesOrder() {
        let first = candidate("com.apple.Safari", name: "Safari")
        let duplicate = candidate("com.apple.Safari", name: "Safari copy")
        let other = candidate("com.google.Chrome")
        #expect(LinkRouterCore.dedupedBrowsers([first, other, duplicate], excluding: "com.norlisviamonte.Linkea") == [first, other])
    }

    @Test func excludesTheAppItself() {
        let own = candidate("com.norlisviamonte.Linkea")
        let safari = candidate("com.apple.Safari")
        #expect(LinkRouterCore.dedupedBrowsers([own, safari], excluding: "com.norlisviamonte.Linkea") == [safari])
    }

    @Test func inputWithoutDuplicatesIsUnchanged() {
        let candidates = [candidate("com.apple.Safari"), candidate("com.google.Chrome"), candidate("org.mozilla.firefox")]
        #expect(LinkRouterCore.dedupedBrowsers(candidates, excluding: "com.norlisviamonte.Linkea") == candidates)
    }
}

struct PanelPlacementTests {
    private let panelSize = CGSize(width: 200, height: 100)
    private let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)

    @Test func centersHorizontallyAndFloatsAboveCursor() {
        let origin = LinkRouterCore.panelOrigin(panelSize: panelSize, mouseLocation: CGPoint(x: 500, y: 400), screenVisibleFrame: screen)
        #expect(origin == CGPoint(x: 400, y: 400 + LinkRouterCore.panelCursorGap))
    }

    @Test func clampsToLeftEdge() {
        let origin = LinkRouterCore.panelOrigin(panelSize: panelSize, mouseLocation: CGPoint(x: 50, y: 400), screenVisibleFrame: screen)
        #expect(origin.x == 0)
    }

    @Test func clampsToRightEdge() {
        let origin = LinkRouterCore.panelOrigin(panelSize: panelSize, mouseLocation: CGPoint(x: 980, y: 400), screenVisibleFrame: screen)
        #expect(origin.x == 800)
    }

    @Test func clampsToTopEdge() {
        let origin = LinkRouterCore.panelOrigin(panelSize: panelSize, mouseLocation: CGPoint(x: 500, y: 795), screenVisibleFrame: screen)
        #expect(origin.y == 700)
    }

    @Test func clampsToLeftEdgeOnNegativeCoordinateScreens() {
        let leftScreen = CGRect(x: -1200, y: 0, width: 1000, height: 800)
        let origin = LinkRouterCore.panelOrigin(panelSize: panelSize, mouseLocation: CGPoint(x: -1180, y: 400), screenVisibleFrame: leftScreen)
        #expect(origin.x == -1200)
    }

    @Test func clampsToBottomEdgeOnNegativeCoordinateScreens() {
        let lowerScreen = CGRect(x: 0, y: -500, width: 1000, height: 800)
        let origin = LinkRouterCore.panelOrigin(panelSize: panelSize, mouseLocation: CGPoint(x: 500, y: -600), screenVisibleFrame: lowerScreen)
        #expect(origin.y == -500)
    }

    @Test func screenSmallerThanPanelPrioritizesBottomLeftCorner() {
        let tinyScreen = CGRect(x: 0, y: 0, width: 150, height: 80)
        let origin = LinkRouterCore.panelOrigin(panelSize: panelSize, mouseLocation: CGPoint(x: 75, y: 40), screenVisibleFrame: tinyScreen)
        #expect(origin == CGPoint(x: 0, y: 0))
    }
}

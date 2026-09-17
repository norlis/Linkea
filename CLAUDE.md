# Linkea — Agent Guide

Linkea is an open-source (MIT) macOS browser picker: it registers as the default browser and shows a floating Liquid Glass panel at the cursor to route every clicked link to the browser — and profile — the user chooses.

## Toolchain and platform (read this first)

- **Language: Swift 6.4** (Xcode 27). Default actor isolation is `MainActor` with Approachable Concurrency — new code is implicitly `@MainActor`; hop back from `@Sendable` completions with `Task { @MainActor in … }`.
- **Minimum deployment target: macOS 26.0.** No retro-compatibility: use the newest APIs without availability guards — `@Observable` (never ObservableObject/Combine), `glassEffect(_:in:)` Liquid Glass, Swift Testing (never XCTest), structured concurrency (never GCD or Combine), `url.host()` (never `url.host`).
- The app is **deliberately not sandboxed**: profile launching needs `NSWorkspace.OpenConfiguration.arguments` (ignored when sandboxed) and reads other browsers' profile metadata. Do not re-enable `ENABLE_APP_SANDBOX`.

## Naming

Target, scheme, product, and module are all `Linkea` (bundle ID `com.norlisviamonte.Linkea`). Sources live in `Linkea/`, tests in `LinkeaTests/`. The project lives at `~/Developer/Linkea/`, container `Linkea.xcodeproj`.

## Architecture

Pure core (no AppKit, fully unit-tested) separated from thin adapters:

- `LinkRouterCore.swift` — URL scheme allow-listing, browser dedupe, panel placement math, domain rules (`DomainRules`), shortcut-key mapping.
- `ProfileCore.swift` — Chromium `Local State` / Firefox `profiles.ini` parsers, launch-argument builders, Safari menu-title helpers.
- Adapters: `BrowserDiscovery` (NSWorkspace), `ProfileDiscovery` (profile files on disk), `SafariProfileLauncher` (Accessibility/AXPress, experimental), `DefaultBrowserManager`.
- UI: `PickerPanelController` (pre-created non-activating `NSPanel` — never steal focus from the source app), `PickerView` (icons + profile chips), `OnboardingView`/`SafariProfilesSettingsView` (setup window: **fixed size + ScrollView**; constraint-driven window sizing with dynamic SwiftUI content crashes AppKit with the "Update Constraints in Window pass" loop).
- `Logging.swift` — mandatory logging path: single-line JSON to stderr with ECS field names (`@timestamp` ISO 8601 UTC, `log.level`, static `message`, variables as fields, `error.type`/`error.message` logged exactly once). Never log full URLs, profile display names, or `gaia_name` — scheme, domain, bundle ID, and counters only.

## Rules

General rules required by the project owner, adapted to Swift/macOS and to this codebase. Apply idiomatic Swift throughout.

1. **Performance & reliability first.** Favor immutability (`let`, value types) and pure functions for predictability. Hot paths have explicit budgets: the picker panel must appear in <100 ms, which is why the panel is pre-created and the browser list cached at launch — keep it that way.
2. **Simplicity & readability.** Code must be self-documenting. Comments explain only the "why" (a constraint the code cannot show, e.g. why the panel is `.nonactivatingPanel`), never the "how".
3. **Code principles.** YAGNI, DRY, KISS, SOLID, SoC. Concretely here: pure core (`LinkRouterCore`, `ProfileCore`) separated from thin adapters (NSWorkspace, file reads, AX); no protocol abstractions for Apple frameworks just for mocking — test the pure core instead; no speculative features from the PRD backlog until asked.
4. **Strict type safety.** No magic strings: typed keys (`Preferences.Keys`), enums for closed sets (`WebScheme`, `LaunchRecipe`). No force unwraps or force casts (the single CF-cast in `SafariProfileLauncher` is guarded by a `CFGetTypeID` check and documented). `any Error` in signatures is fine; `Any` bypasses are not.
5. **Modern standards & auto-discovery.** State the latest stable Swift version at the top of responses (currently Swift 6.4, Xcode 27) and check release notes with the available search/documentation tools when versions may have moved. Prefer the newest APIs — `@Observable`, Liquid Glass `glassEffect`, Swift Testing, structured concurrency, `url.host()` — and treat Combine, XCTest, GCD, ObservableObject, and `NavigationView`-era patterns as deprecated for this codebase. When an API might be newer than training data, verify with `DocumentationSearch` before writing code.
6. **12-Factor, adapted to a desktop app.** All configuration lives in `UserDefaults` behind the typed `Preferences` accessors (the only config store — never scatter `UserDefaults` keys). The app is stateless beyond that config and regenerable caches. Browsers and their profiles are attached resources discovered at runtime via Launch Services and profile files — never hardcode an installed-browser list.
7. **Security & error handling.** Validate every input at the boundary (OWASP): only `http`/`https` URLs with a non-empty host are ever routed (`LinkRouterCore.webURLs`). Fail fast; never swallow errors — every NSWorkspace/AX failure is logged once and, where user-visible, reflected in UI or covered by a fallback (a link is never lost). Never log sensitive data: no full URLs (they can carry tokens), no profile display names, no `gaia_name` — scheme, domain, bundle ID, directory keys, and counters only.
8. **Meaningful testing.** Every feature ships with Swift Testing unit tests covering edge cases — see `LinkeaTests/` for the house style: inline string fixtures, `try #require` instead of force unwraps, parameterized `@Test(arguments:)`. If logic is not testable, refactor it into the pure core rather than skipping the test. No tests written only to inflate coverage.
9. **Strict scope.** No retro-compatibility without asking — the deployment target is macOS 26.0 by explicit owner decision; do not lower it or add availability guards unilaterally. Do not create git commits.
10. **Markdown.** Never hard-wrap Markdown files; every paragraph or bullet stays on a single physical line.
11. **Structured logging.** All logging goes through `AppLog` (`Logging.swift`): single-line JSON on stderr, ECS field names, `@timestamp` in ISO 8601 UTC, static `message` with variables as fields, errors as structured `error.type`/`error.message` objects logged exactly once at the point of handling, and strict level semantics (`debug` = expected diagnostics, `info` = normal operations, `warn` = degraded but recovered, `error` = a failure someone should look at). Never `print` or `os_log` directly.

## Build and test

- Build: `BuildProject` (scheme `Linkea`, destination "My Mac").
- Tests: `RunAllTests` — all must pass before a change is done.
- Functional check: `RunProject`, then `open -a Linkea "https://example.com"` and inspect stderr logs (`GetConsoleOutput`); the picker panel must appear at the cursor without stealing focus.
- A failed default-browser registration is debugged with `plutil -p` on the built app's Info.plist (physical plist at `Linkea/Info.plist`).

## Backlog context

The PRD's v1.x roadmap: domain rules UI (core `DomainRules` + `RuleStore` exist; picker/menu wiring pending), `utm_*` parameter cleaning, `mailto:` support. Already shipped: keyboard shortcuts in the panel (20-key alphabet `1–0`/`q–p` via `LinkRouterCore` + `PickerPanelController`, with an in-panel legend on `v`). Out of scope: cloud sync, iOS.

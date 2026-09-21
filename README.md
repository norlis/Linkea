<img src="docs/icon.png" width="72" height="72" alt="Linkea logo">

# Linkea

Linkea is a lightweight, open-source browser picker for macOS. macOS only lets you have one default browser — Linkea takes that spot and, every time you click a link in any app (Mail, Notes, Slack, anywhere), shows a small floating panel at your cursor so you decide on the spot which browser — and which profile — opens it, without the source app ever losing focus.

Use it when you juggle several browsers at once (Safari for personal, Chrome for development, Edge for work): instead of one fixed destination for every link, Linkea acts as an on-the-fly traffic router, so links always land where you want them.

## Contents

- [Requirements](#requirements)
- [Installing](#installing)
- [Building](#building)
- [Setting Linkea as your default browser](#setting-linkea-as-your-default-browser)
- [Usage](#usage)
- [Browser profiles](#browser-profiles)
- [Tests](#tests)
- [License](#license)

## Requirements

- macOS 26.0 or later
- Apple Silicon (the released build is arm64-only)
- Xcode 27 (Swift 6.4) to build from source

## Installing

Download the latest `Linkea-<version>-arm64.dmg` from the [Releases page](../../releases), open it, and drag Linkea to Applications.

The app is **ad-hoc signed, not notarized** — there is no paid Apple Developer certificate behind it — so macOS will refuse to open it the first time. To allow it:

1. Open Linkea once. macOS blocks it and shows a warning.
2. Go to **System Settings ▸ Privacy & Security**, scroll to the Security section, and click **Open Anyway** next to the message about Linkea.
3. Confirm. macOS remembers the decision; you only do this once.

Control-clicking the app no longer works as a shortcut for this — Apple removed that bypass in macOS Sequoia. If you would rather not trust an unnotarized build, build it yourself from source with the steps below; the result is identical.

On macOS 27 and later, showing browser profile chips additionally requires granting Linkea **Full Disk Access** (System Settings ▸ Privacy & Security ▸ Full Disk Access, then relaunch): macOS 27's App Data Protection silently blocks reading other browsers' profile metadata without it. Links keep working either way — only the profile chips disappear, and Linkea's settings window points this out when it happens.

After **updating** Linkea, re-grant Full Disk Access even if the toggle still looks enabled: the grant is tied to the exact ad-hoc-signed binary, so a new build invalidates it — remove Linkea from the list and add it back, then relaunch.

## Building

1. Clone the repository and open `Linkea.xcodeproj` in Xcode.
2. Select the `Linkea` scheme and the "My Mac" destination.
3. Build and run with ⌘R. The first launch shows a one-screen setup window.
4. For day-to-day use, build with ⌘B and copy the built `Linkea.app` from the products directory into `/Applications`, then launch it from there — otherwise Launch Services keeps pointing at a stale DerivedData path after cleans.

## Setting Linkea as your default browser

Click "Set Linkea as Default Browser" in the setup window and accept the macOS consent dialog. You can also do it manually in System Settings ▸ Desktop & Dock ▸ "Default web browser". This step is required by macOS and cannot be automated away: only the default browser receives link clicks. Note that with ad-hoc code signing (plain local builds), macOS may re-ask for consent when the app is rebuilt.

## Usage

- Click any link in any app: the picker appears at your cursor with the icons of your installed browsers. Click one to open the link there.
- Press Esc or click anywhere else to dismiss the picker.
- Linkea lives in the menu bar (spiral-and-arrow icon) — reopen the setup window or quit from there. It has no Dock icon by design.

## Browser profiles

Browsers with two or more profiles show small initial-letter chips under their icon in the picker. Clicking a chip opens the link directly in that profile; clicking the big icon opens the browser's default profile as before.

- **Chrome, Chromium, Edge, Brave, Vivaldi**: profiles are read from each browser's `Local State` file and launched with `--profile-directory` — reliable and automatic.
- **Firefox**: profiles are read from `profiles.ini` and launched with `-P <name> --new-instance`. Firefox runs one instance per profile, which is a Firefox architectural quirk.
- **Safari (experimental, off by default)**: Safari has no profile API, so Linkea presses the "New <profile> Window" item in Safari's File menu via Accessibility and opens the link in that window. Enable it in the setup window: grant Accessibility access, open Safari, detect the menu items, and mark the ones that are your profiles. Costs to know about: it needs the Accessibility permission, it briefly brings Safari to the front, and a Safari update can rename its menus (re-detect and re-map if chips stop working — the link always falls back to plain Safari, it is never lost).

## Tests

Unit tests live in the `LinkeaTests` target (Swift Testing) and cover the pure core: URL filtering edge cases, browser deduplication, panel clamping geometry, and the log encoder. Run them with ⌘U in Xcode.

## License

MIT — see [LICENSE](LICENSE).

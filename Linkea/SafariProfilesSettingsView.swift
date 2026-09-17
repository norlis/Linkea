import SwiftUI

/// Mapping UI for the experimental Safari profile support: the user confirms which File-menu
/// items are profile windows instead of Linkea guessing across localizations.
struct SafariProfilesSettingsView: View {
    // Seeded from Preferences (the only config store) and written back through `enabledBinding`,
    // instead of a second UserDefaults path via @AppStorage.
    @State private var enabled = Preferences.safariProfilesEnabled
    @State private var accessibilityGranted = SafariProfileLauncher.isAccessibilityTrusted
    @State private var candidates: [String] = Preferences.safariProfileMenuTitles
    @State private var selectedTitles = Set(Preferences.safariProfileMenuTitles)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Safari profiles (experimental)", isOn: enabledBinding)
                .font(.headline)
            if enabled {
                Text("Needs Accessibility access, briefly brings Safari to the front when opening a link, and may break when Safari updates its menus.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if accessibilityGranted {
                    Button("Detect Safari Menu Items") {
                        candidates = ProfileCore.candidateSafariProfileItems(menuTitles: SafariProfileLauncher.fileMenuItemTitles())
                    }
                    if candidates.isEmpty {
                        Text("Open Safari first, then detect. Mark the “New … Window” items that match your profiles.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(candidates, id: \.self) { title in
                            Toggle(title, isOn: binding(for: title))
                                .font(.callout)
                        }
                    }
                } else {
                    Button("Grant Accessibility Access") {
                        SafariProfileLauncher.requestAccessibilityPermission()
                        accessibilityGranted = SafariProfileLauncher.isAccessibilityTrusted
                    }
                    Text("After granting access in System Settings, come back and detect the menu items.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onAppear { accessibilityGranted = SafariProfileLauncher.isAccessibilityTrusted }
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { enabled },
            set: { newValue in
                enabled = newValue
                Preferences.safariProfilesEnabled = newValue
            }
        )
    }

    private func binding(for title: String) -> Binding<Bool> {
        Binding(
            get: { selectedTitles.contains(title) },
            set: { isOn in
                if isOn {
                    selectedTitles.insert(title)
                } else {
                    selectedTitles.remove(title)
                }
                // Persist in detection order so the picker chips stay stable.
                Preferences.safariProfileMenuTitles = candidates.filter(selectedTitles.contains)
            }
        )
    }
}

#Preview {
    SafariProfilesSettingsView()
        .padding()
        .frame(width: 420)
}

import SwiftUI

/// One-screen setup: explains the single manual step macOS requires (choosing Linkea as the
/// default browser) and lets the user preview the picker before committing.
/// The frame is fixed and the content scrolls — window-resizing via Auto Layout with dynamic
/// SwiftUI content triggers AppKit's "Update Constraints in Window pass" loop.
struct OnboardingView: View {
    let manager: DefaultBrowserManager
    let onTryIt: () -> Void
    let onDone: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // The app's effective icon, so this screen can never drift from the AppIcon asset.
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 72, height: 72)
                    .accessibilityHidden(true)
                Text("Welcome to Linkea")
                    .font(.title.bold())
                Text("Linkea routes every link you click to the browser you choose. For that to work, macOS needs Linkea to be your default browser.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)

                Button("Set Linkea as Default Browser") {
                    manager.requestDefault()
                }
                .buttonStyle(.glassProminent)

                Label(
                    manager.isDefault ? "Linkea is your default browser" : "Linkea is not the default browser yet",
                    systemImage: manager.isDefault ? "checkmark.circle.fill" : "circle.dashed"
                )
                .foregroundStyle(manager.isDefault ? .green : .secondary)

                Divider()

                SafariProfilesSettingsView()
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack {
                    Button("Try It", action: onTryIt)
                    Spacer()
                    Button("Done", action: onDone)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(28)
        }
        .frame(width: 420, height: 540)
    }
}

#Preview {
    OnboardingView(manager: DefaultBrowserManager(), onTryIt: {}, onDone: {})
}

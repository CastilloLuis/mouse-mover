import AppKit
import SwiftUI

/// A menu bar only app (LSUIElement) with one on/off switch.
@main
struct MouseMoverApp: App {
    @StateObject private var mover = Mover()

    var body: some Scene {
        MenuBarExtra {
            MenuContent(mover: mover)
        } label: {
            Image(systemName: mover.iconName)
                .accessibilityLabel("Mouse Mover")
        }
    }
}

/// The items in the menu bar menu.
struct MenuContent: View {
    @ObservedObject var mover: Mover

    var body: some View {
        Text("Mouse Mover: \(mover.statusText)")
        if let last = mover.lastMove {
            Text("Last move: \(last.formatted(date: .omitted, time: .standard))")
        }
        Divider()
        Button(mover.isEnabled ? "Disable" : "Enable") {
            mover.setEnabled(!mover.isEnabled)
        }
        .keyboardShortcut("e")
        Picker("Interval", selection: Binding(
            get: { mover.intervalSeconds },
            set: { mover.setInterval($0) }
        )) {
            ForEach(intervalChoices, id: \.self) { seconds in
                Text(Mover.label(for: seconds)).tag(seconds)
            }
        }
        if mover.isEnabled && !mover.hasAccess {
            Button("Grant Accessibility Permission…") {
                mover.requestAccess()
            }
        }
        Divider()
        Toggle("Launch at Login", isOn: Binding(
            get: { mover.launchAtLogin },
            set: { mover.setLaunchAtLogin($0) }
        ))
        if let message = mover.loginItemMessage {
            Text(message)
        }
        Divider()
        Button("Quit Mouse Mover") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}

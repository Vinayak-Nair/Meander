import AppKit
import SwiftUI
import DriftKit

/// Contents of the menu-bar dropdown.
struct DriftMenu: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject var state: AppState

    var body: some View {
        Text(state.statusText)
        Text("Mic: \(state.selectedMicrophoneName)")

        if !state.lastText.isEmpty {
            Text("Last: \(state.lastText.prefix(40))\(state.lastText.count > 40 ? "…" : "")")
        }

        Divider()

        if state.isReady || state.status == .recording {
            Button(state.status == .recording ? "Stop Dictation" : "Start Dictation") {
                state.toggleDictation()
            }
        }

        if state.supportsLanguageSelection {
            Menu("Language") {
                ForEach(state.availableLanguages) { lang in
                    Button {
                        state.languageCode = lang.code
                    } label: {
                        if state.languageCode == lang.code {
                            Label(lang.displayName, systemImage: "checkmark")
                        } else {
                            Text(lang.displayName)
                        }
                    }
                }
            }
        } else {
            Text("Language: English")
        }

        Menu("Microphone") {
            ForEach(state.availableMicrophones) { device in
                Button {
                    state.selectMicrophone(device.id)
                } label: {
                    if state.selectedMicrophoneID == device.id {
                        Label(device.name, systemImage: "checkmark")
                    } else {
                        Text(device.name)
                    }
                }
            }
        }

        Divider()

        Button("Dashboard…") { openWindow(id: "dashboard") }
        Button("Settings…") {
            state.dashboardSection = .settings
            openWindow(id: "dashboard")
            NSApp.activate(ignoringOtherApps: true)
        }
        Button("Setup & Permissions…") { state.showOnboardingWindow() }

        Divider()

        Button("Quit Drift") { NSApp.terminate(nil) }
    }
}

import SwiftUI

@main
struct MeanderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @ObservedObject private var state = AppState.shared

    var body: some Scene {
        WindowGroup("Meander", id: "dashboard") {
            DashboardView()
                .environmentObject(state)
        }
        .windowResizability(.contentMinSize)
        .windowStyle(.hiddenTitleBar)

        MenuBarExtra {
            MeanderMenu().environmentObject(state)
        } label: {
            // At rest, show Meander's own waveform mark; transient states keep the
            // animated SF Symbols so recording/processing stay legible.
            if state.isReady {
                Image("MenuBarIcon")
            } else {
                Image(systemName: state.menuBarSymbol)
            }
        }
        .menuBarExtraStyle(.menu)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        Task { await AppState.shared.bootstrap() }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        Task { @MainActor in AppState.shared.refreshPermissions() }
    }
}

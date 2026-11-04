import SwiftUI
import AirMouseCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated { AppModel.shared.start() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { AppModel.shared.stop() }
    }

    // Closing the window keeps AirMouse running in the menu bar.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

/// Not `@main`: `main.swift` dispatches CLI modes first, then calls `AirMouseApp.main()`.
struct AirMouseApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    private let model = AppModel.shared

    var body: some Scene {
        Window("AirMouse", id: "main") {
            RootView(model: model)
        }
        .defaultSize(width: 900, height: 640)
        .windowResizability(.contentMinSize)
        .windowStyle(.hiddenTitleBar)
        .defaultPosition(.center)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .appSettings) {
                Button("Reset AirMouse…", action: model.confirmReset)
            }
            CommandMenu("Pointer") {
                Button("Calibrate…", action: model.requestCalibration).keyboardShortcut("k")
                Button("Practice Clicking…", action: model.startPractice).keyboardShortcut("p", modifiers: [.command, .shift])
                Button("Center Cursor", action: model.centerCursor).keyboardShortcut("0")
            }
        }

        MenuBarExtra {
            MenuContent(model: model)
        } label: {
            Image(systemName: model.isConnected ? "cursorarrow.rays" : "cursorarrow")
        }
        .menuBarExtraStyle(.menu)
    }
}

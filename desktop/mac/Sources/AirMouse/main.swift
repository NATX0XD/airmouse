import AppKit
import SwiftUI
import AirMouseCore

// Entry point. CLI modes never open a visible window and never post events:
//   --selftest [--port N] [--timeout S]   network layer only, fake output logged to stdout
//   --render-previews <dir>               offscreen PNGs of the UI
//   --render-icon <dir.iconset>           AppIcon.iconset PNGs for iconutil
let args = CommandLine.arguments

func argValue(_ flag: String) -> String? {
    guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
    return args[i + 1]
}

if args.contains("--selftest") {
    SelfTest.run(port: argValue("--port").flatMap(UInt16.init) ?? PortPicker.defaultPort,
                 timeout: argValue("--timeout").flatMap(Double.init) ?? 30)
} else if let dir = argValue("--render-previews") {
    Previews.renderAll(to: URL(fileURLWithPath: dir))
} else if let dir = argValue("--render-icon") {
    Previews.renderIconset(to: URL(fileURLWithPath: dir))
} else {
    // Hidden: `--reset-onboarding` shows Welcome, Permissions and the tour again on this launch.
    if args.contains("--reset-onboarding") { OnboardingStore().reset() }
    AirMouseApp.main()
}

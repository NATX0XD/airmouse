import Foundation
import Testing
@testable import AirMouseCore

@Suite struct ResetTests {
    @Test func ownedNames() {
        #expect(AppReset.isOwned("com.nattakit.airmouse.mac"))
        #expect(AppReset.isOwned("com.nattakit.airmouse.mac.savedState"))
        #expect(AppReset.isOwned("AirMouse"))
        #expect(!AppReset.isOwned("com.nattakit.other"))
        #expect(!AppReset.isOwned("com.apple.Safari"))
        #expect(!AppReset.isOwned("AirMouseHelper2")) // only the exact folder name
    }

    @Test func findsAndRemovesOnlyAirMouseData() throws {
        let fm = FileManager.default
        let lib = fm.temporaryDirectory.appendingPathComponent("vx-reset-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: lib) }
        let make = { (rel: String) in
            let u = lib.appendingPathComponent(rel)
            try fm.createDirectory(at: u, withIntermediateDirectories: true)
            try Data("x".utf8).write(to: u.appendingPathComponent("f"))
        }
        try make("Application Support/com.nattakit.airmouse.mac")
        try make("Application Support/AirMouse")
        try make("Application Support/com.other.app")
        try make("Caches/com.nattakit.airmouse.mac")
        try make("Saved Application State/com.nattakit.airmouse.mac.savedState")
        try make("Caches/com.apple.Safari")
        let found = AppReset.dataLocations(library: lib).map { $0.path.replacingOccurrences(of: lib.path + "/", with: "") }
        #expect(found == ["Application Support/AirMouse", "Application Support/com.nattakit.airmouse.mac",
                          "Caches/com.nattakit.airmouse.mac", "Saved Application State/com.nattakit.airmouse.mac.savedState"])
        #expect(AppReset.removeData(library: lib).isEmpty)
        #expect(AppReset.dataLocations(library: lib).isEmpty)
        #expect(fm.fileExists(atPath: lib.appendingPathComponent("Application Support/com.other.app").path))
        #expect(fm.fileExists(atPath: lib.appendingPathComponent("Caches/com.apple.Safari").path))
        #expect(fm.fileExists(atPath: lib.appendingPathComponent("Caches").path))
    }

    @Test func emptyLibraryIsFine() {
        #expect(AppReset.dataLocations(library: URL(fileURLWithPath: "/nonexistent-vx")).isEmpty)
    }
}

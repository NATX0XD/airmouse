import Foundation

/// "Reset AirMouse…": what a factory reset removes besides the UserDefaults domain.
public enum AppReset {
    public static let bundleID = "com.nattakit.airmouse.mac"
    /// Folders under ~/Library that may hold AirMouse files.
    public static let searchFolders = ["Application Support", "Caches", "HTTPStorages", "Saved Application State", "WebKit"]

    /// True for names AirMouse owns: `com.nattakit.airmouse*` (any suffix) or a plain `AirMouse` folder.
    public static func isOwned(_ name: String) -> Bool {
        name.lowercased().hasPrefix("com.nattakit.airmouse") || name == "AirMouse"
    }

    /// Existing AirMouse files / folders under `library` (never the folders themselves, never other apps).
    public static func dataLocations(library: URL, fileManager: FileManager = .default) -> [URL] {
        var out: [URL] = []
        for folder in searchFolders {
            let dir = library.appendingPathComponent(folder, isDirectory: true)
            guard let names = try? fileManager.contentsOfDirectory(atPath: dir.path) else { continue }
            for n in names.sorted() where isOwned(n) { out.append(dir.appendingPathComponent(n)) }
        }
        return out
    }

    /// Removes them; returns what could not be removed.
    @discardableResult
    public static func removeData(library: URL, fileManager: FileManager = .default) -> [URL] {
        dataLocations(library: library, fileManager: fileManager).filter { (try? fileManager.removeItem(at: $0)) == nil }
    }
}

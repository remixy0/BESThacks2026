import Foundation
import RealityKit

/// Finds and loads the museum files bundled from Resources/Museum.
///
/// 3D models are loaded once and kept: every later request gets a cheap clone that shares the meshes and
/// materials. So switching map styles or opening an exhibit doesn't re-read megabytes of USDZ.
enum MuseumAssets {
    private static var cache: [String: Entity] = [:]
    private static var pending: [String: Task<Entity, Error>] = [:]

    /// Looks in the bundle root first (Xcode usually flattens resources), then in subfolders.
    nonisolated static func url(named name: String, extension ext: String) -> URL? {
        if let url = Bundle.main.url(forResource: name, withExtension: ext) { return url }
        for folder in ["Museum", "Museum/Artifacts", "Resources/Museum", "Resources/Museum/Artifacts", "Artifacts"] {
            if let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: folder) { return url }
        }
        // Last resort: search the whole bundle.
        guard let root = Bundle.main.resourceURL,
              let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { return nil }
        let target = "\(name).\(ext)"
        for case let url as URL in files where url.lastPathComponent == target {
            return url
        }
        return nil
    }

    static func entity(named name: String) async throws -> Entity {
        if let cached = cache[name] { return cached.clone(recursive: true) }
        if let running = pending[name] { return try await running.value.clone(recursive: true) }
        guard let url = url(named: name, extension: "usdz") else {
            print("[Museum] \(name).usdz isn't in the app bundle.")
            throw CocoaError(.fileNoSuchFile)
        }
        let task = Task { try await Entity(contentsOf: url) }
        pending[name] = task
        do {
            let entity = try await task.value
            cache[name] = entity
            pending[name] = nil
            return entity.clone(recursive: true)
        } catch {
            pending[name] = nil
            throw error
        }
    }

    /// The building in "map" style: floors, low walls with door gaps, soft gallery colours.
    static func map() async throws -> Entity {
        try await entity(named: "MuseumMap")
    }

    /// One exhibit's model, real size, standing on y = 0 at its own origin.
    static func artifact(_ exhibit: MuseumInfo.Exhibit) async throws -> Entity {
        try await entity(named: exhibit.detailResource)
    }

    /// Loads everything in the background while you log in and calibrate, so the map opens instantly.
    static func preload(_ info: MuseumInfo?) async {
        _ = try? await map()
        for exhibit in info?.exhibits ?? [] {
            _ = try? await artifact(exhibit)
        }
    }
}

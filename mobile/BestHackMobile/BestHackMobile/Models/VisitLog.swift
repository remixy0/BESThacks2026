import Foundation
import Observation

/// Which exhibits you've reached, kept between launches (the little "3 / 8" in the top bar).
@Observable
final class VisitLog {
    private(set) var visited: Set<String>

    @ObservationIgnored private let defaults = UserDefaults.standard
    private static let key = "visits.exhibits"

    init() {
        visited = Set(UserDefaults.standard.stringArray(forKey: Self.key) ?? [])
    }

    func contains(_ key: String) -> Bool {
        visited.contains(key)
    }

    func mark(_ key: String) {
        guard !visited.contains(key) else { return }
        visited.insert(key)
        defaults.set(Array(visited), forKey: Self.key)
    }

    func reset() {
        visited = []
        defaults.removeObject(forKey: Self.key)
    }
}

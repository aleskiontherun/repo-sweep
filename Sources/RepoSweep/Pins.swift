import Foundation
import Observation

/// Repositories pinned to the top of the list, by path. Shared by every tab,
/// so a repository pinned in one shows pinned in any other that lists it,
/// and saved to user defaults.
@MainActor @Observable
final class Pins {
    static let shared = Pins()
    private static let key = "pinnedRepositories"

    private(set) var paths: Set<String>

    private init() {
        paths = Set(UserDefaults.standard.stringArray(forKey: Self.key) ?? [])
    }

    func isPinned(_ url: URL) -> Bool {
        paths.contains(url.path)
    }

    func toggle(_ url: URL) {
        if paths.remove(url.path) == nil {
            paths.insert(url.path)
        }
        UserDefaults.standard.set(paths.sorted(), forKey: Self.key)
    }
}

import Foundation
import Combine

/// Phase 10: runtime-mutable bundle ID exclusion list.
/// Persisted best-effort to ~/.providence/overlay/exclusions.json.
/// Corrupt/missing files are tolerated silently.
@MainActor
final class ExclusionsManager: ObservableObject {
    @Published private(set) var excludedBundleIDs: Set<String> = []
    private let path: URL

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dir = home.appendingPathComponent(".providence/overlay", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.path = dir.appendingPathComponent("exclusions.json")
        load()
    }

    func contains(_ bundleID: String) -> Bool { excludedBundleIDs.contains(bundleID) }

    func add(_ bundleID: String) {
        guard !bundleID.isEmpty else { return }
        excludedBundleIDs.insert(bundleID)
        save()
    }

    func remove(_ bundleID: String) {
        excludedBundleIDs.remove(bundleID)
        save()
    }

    func toggle(_ bundleID: String) {
        if excludedBundleIDs.contains(bundleID) {
            remove(bundleID)
        } else {
            add(bundleID)
        }
    }

    /// Replace current set - used when the TUI announces excluded_apps in Welcome.
    func setInitial(_ bundleIDs: [String]) {
        for b in bundleIDs { excludedBundleIDs.insert(b) }
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: path) else { return }
        if let arr = try? JSONDecoder().decode([String].self, from: data) {
            excludedBundleIDs = Set(arr)
        }
    }

    private func save() {
        let sorted = Array(excludedBundleIDs).sorted()
        guard let data = try? JSONEncoder().encode(sorted) else { return }
        try? data.write(to: path, options: .atomic)
    }
}

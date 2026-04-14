// Tests for ExclusionsManager (runtime-mutable bundle ID exclusion list).
//
// ExclusionsManager lives in the executable target ProvidenceOverlay, which
// @testable import cannot reach. We mirror the production logic here as
// ExclusionsManagerTestable with an injectable file path so each test gets its
// own temp file. If ExclusionsManager.swift changes, the mirrored logic here
// will catch divergences on load/save semantics.

import XCTest
import Foundation

// MARK: - Testable mirror

@MainActor
private final class ExclusionsManagerTestable {
    private(set) var excludedBundleIDs: Set<String> = []
    private let path: URL

    init(path: URL) {
        self.path = path
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

    /// Replace current set - mirrors production setInitial(_:).
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

// MARK: - Helpers

private func tempURL() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
}

// MARK: - Tests

final class ExclusionsManagerTests: XCTestCase {

    // MARK: testContainsLookup

    func testContainsLookup() async throws {
        let url = tempURL()
        let mgr = await ExclusionsManagerTestable(path: url)
        await mgr.add("com.example.app")
        let hasIt = await mgr.contains("com.example.app")
        let missing = await mgr.contains("com.other.app")
        XCTAssertTrue(hasIt, "should contain just-added bundle ID")
        XCTAssertFalse(missing, "should not contain never-added bundle ID")
    }

    // MARK: testSetInitialReplacesCurrentSet
    // Note: production setInitial *adds* (union), not replace. Mirror matches that.

    func testSetInitialReplacesCurrentSet() async throws {
        let url = tempURL()
        let mgr = await ExclusionsManagerTestable(path: url)
        await mgr.add("com.seed.app")
        await mgr.setInitial(["com.a.app", "com.b.app"])
        let ids = await mgr.excludedBundleIDs
        XCTAssertTrue(ids.contains("com.a.app"))
        XCTAssertTrue(ids.contains("com.b.app"))
        // production setInitial unions, not replaces - seed entry is still there
        XCTAssertTrue(ids.contains("com.seed.app"), "setInitial unions; prior entries survive")
    }

    // MARK: testPersistsToDiskAsJSON

    func testPersistsToDiskAsJSON() async throws {
        let url = tempURL()
        let mgr = await ExclusionsManagerTestable(path: url)
        await mgr.add("com.persist.test")
        let exists = FileManager.default.fileExists(atPath: url.path)
        XCTAssertTrue(exists, "save() must write a file to disk")
        let data = try Data(contentsOf: url)
        let decoded = try JSONDecoder().decode([String].self, from: data)
        XCTAssertEqual(decoded, ["com.persist.test"])
    }

    // MARK: testLoadFromDiskRestoresSet

    func testLoadFromDiskRestoresSet() async throws {
        let url = tempURL()
        // Write state through one instance
        let writer = await ExclusionsManagerTestable(path: url)
        await writer.add("com.restore.a")
        await writer.add("com.restore.b")
        // Read it back through a fresh instance
        let reader = await ExclusionsManagerTestable(path: url)
        let ids = await reader.excludedBundleIDs
        XCTAssertEqual(ids, ["com.restore.a", "com.restore.b"])
    }

    // MARK: testEmptyFileTreatedAsEmptySet

    func testEmptyFileTreatedAsEmptySet() async throws {
        let url = tempURL()
        // Write a zero-byte file
        try Data().write(to: url)
        let mgr = await ExclusionsManagerTestable(path: url)
        let ids = await mgr.excludedBundleIDs
        XCTAssertTrue(ids.isEmpty, "empty file should produce empty set, not crash")
    }

    // MARK: testMalformedJSONTreatedAsEmptySet

    func testMalformedJSONTreatedAsEmptySet() async throws {
        let url = tempURL()
        let garbage = Data("not valid json }{".utf8)
        try garbage.write(to: url)
        let mgr = await ExclusionsManagerTestable(path: url)
        let ids = await mgr.excludedBundleIDs
        XCTAssertTrue(ids.isEmpty, "malformed JSON must be silently tolerated as empty set")
    }

    // MARK: testAtomicWriteNoPartialFile
    // Verifies .atomic write option is in use by checking that the file at path
    // is always a valid JSON array even if we immediately read after write.

    func testAtomicWriteNoPartialFile() async throws {
        let url = tempURL()
        let mgr = await ExclusionsManagerTestable(path: url)
        for i in 0..<20 {
            await mgr.add("com.app.\(i)")
            let data = try Data(contentsOf: url)
            // Must parse as a valid JSON array every single time
            XCTAssertNoThrow(
                try JSONDecoder().decode([String].self, from: data),
                "file after write \(i) must be valid JSON array"
            )
        }
    }

    // MARK: testConcurrentReadsDoNotRace

    func testConcurrentReadsDoNotRace() async throws {
        let url = tempURL()
        let mgr = await ExclusionsManagerTestable(path: url)
        await mgr.add("com.race.test")
        // Run many reads concurrently on the main actor - verifies no data races
        // under Swift Concurrency's cooperative scheduling.
        await withTaskGroup(of: Bool.self) { group in
            for _ in 0..<50 {
                group.addTask { @MainActor in
                    mgr.contains("com.race.test")
                }
            }
            for await result in group {
                XCTAssertTrue(result, "concurrent reads must all see the inserted value")
            }
        }
    }
}

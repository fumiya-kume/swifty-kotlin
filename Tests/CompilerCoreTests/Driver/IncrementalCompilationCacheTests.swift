@testable import CompilerCore
import Foundation
import XCTest

final class IncrementalCompilationCacheTests: XCTestCase {
    private var tempDir: String!

    override func setUp() {
        super.setUp()
        tempDir = NSTemporaryDirectory() + "IncrementalCacheTest_\(UUID().uuidString)"
    }

    override func tearDown() {
        if let dir = tempDir {
            try? FileManager.default.removeItem(atPath: dir)
        }
        super.tearDown()
    }

    // MARK: - Init

    func testInitSetsPath() {
        let cache = IncrementalCompilationCache(cachePath: "/some/path")
        XCTAssertEqual(cache.cachePath, "/some/path")
    }

    // MARK: - hasPreviousCache

    func testHasPreviousCacheReturnsFalseInitially() {
        let cache = IncrementalCompilationCache(cachePath: tempDir)
        XCTAssertFalse(cache.hasPreviousCache)
    }

    // MARK: - dependencyGraph

    func testDependencyGraphIsNilInitially() {
        let cache = IncrementalCompilationCache(cachePath: tempDir)
        XCTAssertNil(cache.dependencyGraph)
    }

    // MARK: - loadPreviousState with no files

    func testLoadPreviousStateWithNoCacheDir() {
        let cache = IncrementalCompilationCache(cachePath: tempDir)
        cache.loadPreviousState()
        XCTAssertFalse(cache.hasPreviousCache)
        XCTAssertNil(cache.dependencyGraph)
    }

    // MARK: - Save and load round-trip

    func testSaveAndLoadRoundTrip() throws {
        let cache = IncrementalCompilationCache(cachePath: tempDir)

        // Write a temp source file
        let sourceDir = tempDir + "/src"
        try FileManager.default.createDirectory(atPath: sourceDir, withIntermediateDirectories: true)
        let sourceFile = sourceDir + "/a.kt"
        try "fun main() {}".write(toFile: sourceFile, atomically: true, encoding: .utf8)

        // Compute fingerprints and save
        cache.computeCurrentFingerprints(for: [sourceFile])

        let graph = DependencyGraph()
        graph.recordProvided(filePath: sourceFile, symbols: ["main"])
        cache.saveState(dependencyGraph: graph)

        // Load into a new cache instance
        let cache2 = IncrementalCompilationCache(cachePath: tempDir)
        cache2.loadPreviousState()
        XCTAssertTrue(cache2.hasPreviousCache)
        XCTAssertNotNil(cache2.dependencyGraph)
    }

    // MARK: - changedFiles

    func testChangedFilesDetectsNewFile() throws {
        let sourceDir = tempDir + "/src"
        try FileManager.default.createDirectory(atPath: sourceDir, withIntermediateDirectories: true)
        let sourceFile = sourceDir + "/a.kt"
        try "fun main() {}".write(toFile: sourceFile, atomically: true, encoding: .utf8)

        let cache = IncrementalCompilationCache(cachePath: tempDir)
        // No previous state loaded — all files are new
        cache.computeCurrentFingerprints(for: [sourceFile])
        let changed = cache.changedFiles(allPaths: [sourceFile])
        XCTAssertTrue(changed.contains(sourceFile))
    }

    func testChangedFilesDetectsContentChange() throws {
        let sourceDir = tempDir + "/src"
        try FileManager.default.createDirectory(atPath: sourceDir, withIntermediateDirectories: true)
        let sourceFile = sourceDir + "/a.kt"

        // First build — compute fingerprints from known contents directly
        let contents1 = Data("fun main() {}".utf8)
        let cache1 = IncrementalCompilationCache(cachePath: tempDir)
        // Write file so compute works
        try contents1.write(to: URL(fileURLWithPath: sourceFile))
        cache1.computeCurrentFingerprints(for: [sourceFile])
        let graph = DependencyGraph()
        cache1.saveState(dependencyGraph: graph)

        // Modify the file with different content and ensure mtime changes
        Thread.sleep(forTimeInterval: 0.05)
        let contents2 = Data("fun main() { println(\"changed\") }".utf8)
        try contents2.write(to: URL(fileURLWithPath: sourceFile))

        // Second build
        let cache2 = IncrementalCompilationCache(cachePath: tempDir)
        cache2.loadPreviousState()
        cache2.computeCurrentFingerprints(for: [sourceFile])
        let changed = cache2.changedFiles(allPaths: [sourceFile])
        XCTAssertTrue(changed.contains(sourceFile))
    }

    func testChangedFilesDetectsRemovedFile() throws {
        let sourceDir = tempDir + "/src"
        try FileManager.default.createDirectory(atPath: sourceDir, withIntermediateDirectories: true)
        let fileA = sourceDir + "/a.kt"
        let fileB = sourceDir + "/b.kt"

        // First build with two files
        try "fun a() {}".write(toFile: fileA, atomically: true, encoding: .utf8)
        try "fun b() {}".write(toFile: fileB, atomically: true, encoding: .utf8)
        let cache1 = IncrementalCompilationCache(cachePath: tempDir)
        cache1.computeCurrentFingerprints(for: [fileA, fileB])
        cache1.saveState(dependencyGraph: DependencyGraph())

        // Second build with only one file
        let cache2 = IncrementalCompilationCache(cachePath: tempDir)
        cache2.loadPreviousState()
        cache2.computeCurrentFingerprints(for: [fileA])
        let changed = cache2.changedFiles(allPaths: [fileA])
        // fileB was in previous build but not in current — should be in changed
        XCTAssertTrue(changed.contains(fileB))
    }

    // MARK: - recompilationSet

    func testRecompilationSetReturnsNilWithoutPreviousCache() {
        let cache = IncrementalCompilationCache(cachePath: tempDir)
        let result = cache.recompilationSet(allPaths: ["/a.kt"])
        XCTAssertNil(result)
    }

    func testRecompilationSetReturnsNilWithoutDependencyGraph() throws {
        // Save state with fingerprints but corrupt the deps.json
        let sourceDir = tempDir + "/src"
        try FileManager.default.createDirectory(atPath: sourceDir, withIntermediateDirectories: true)
        let sourceFile = sourceDir + "/a.kt"
        try "fun main() {}".write(toFile: sourceFile, atomically: true, encoding: .utf8)

        let cache1 = IncrementalCompilationCache(cachePath: tempDir)
        cache1.computeCurrentFingerprints(for: [sourceFile])
        cache1.saveState(dependencyGraph: DependencyGraph())

        // Corrupt deps.json
        try "invalid".write(toFile: tempDir + "/deps.json", atomically: true, encoding: .utf8)

        let cache2 = IncrementalCompilationCache(cachePath: tempDir)
        cache2.loadPreviousState()
        cache2.computeCurrentFingerprints(for: [sourceFile])
        let result = cache2.recompilationSet(allPaths: [sourceFile])
        XCTAssertNil(result)
    }

    func testRecompilationSetReturnsEmptyWhenNothingChanged() throws {
        let sourceDir = tempDir + "/src"
        try FileManager.default.createDirectory(atPath: sourceDir, withIntermediateDirectories: true)
        let sourceFile = sourceDir + "/a.kt"
        try "fun main() {}".write(toFile: sourceFile, atomically: true, encoding: .utf8)

        // First build
        let cache1 = IncrementalCompilationCache(cachePath: tempDir)
        cache1.computeCurrentFingerprints(for: [sourceFile])
        let graph = DependencyGraph()
        graph.recordProvided(filePath: sourceFile, symbols: ["main"])
        cache1.saveState(dependencyGraph: graph)

        // Second build — no changes
        let cache2 = IncrementalCompilationCache(cachePath: tempDir)
        cache2.loadPreviousState()
        cache2.computeCurrentFingerprints(for: [sourceFile])
        let result = cache2.recompilationSet(allPaths: [sourceFile])
        XCTAssertNotNil(result)
        XCTAssertTrue(try XCTUnwrap(result?.isEmpty))
    }

    // MARK: - clearCache

    func testClearCacheRemovesDirectory() throws {
        let sourceDir = tempDir + "/src"
        try FileManager.default.createDirectory(atPath: sourceDir, withIntermediateDirectories: true)
        let sourceFile = sourceDir + "/a.kt"
        try "fun main() {}".write(toFile: sourceFile, atomically: true, encoding: .utf8)

        let cache = IncrementalCompilationCache(cachePath: tempDir)
        cache.computeCurrentFingerprints(for: [sourceFile])
        cache.saveState(dependencyGraph: DependencyGraph())

        XCTAssertTrue(FileManager.default.fileExists(atPath: tempDir + "/manifest.json"))
        cache.clearCache()
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempDir + "/manifest.json"))
        XCTAssertFalse(cache.hasPreviousCache)
    }

    // MARK: - loadPreviousState with unsupported manifest version

    func testLoadPreviousStateIgnoresUnsupportedManifestVersion() throws {
        try FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
        let manifest = "{\"version\": 999, \"fingerprints\": []}"
        try manifest.write(toFile: tempDir + "/manifest.json", atomically: true, encoding: .utf8)

        let cache = IncrementalCompilationCache(cachePath: tempDir)
        cache.loadPreviousState()
        XCTAssertFalse(cache.hasPreviousCache)
    }

    // MARK: - computeCurrentFingerprints with SourceManager

    func testComputeCurrentFingerprintsWithSourceManager() throws {
        let sourceDir = tempDir + "/src"
        try FileManager.default.createDirectory(atPath: sourceDir, withIntermediateDirectories: true)
        let sourceFile = sourceDir + "/a.kt"
        try "fun main() {}".write(toFile: sourceFile, atomically: true, encoding: .utf8)

        let sm = SourceManager()
        _ = sm.addFile(path: sourceFile, contents: Data("fun main() {}".utf8))

        let cache = IncrementalCompilationCache(cachePath: tempDir)
        cache.computeCurrentFingerprints(for: [sourceFile], sourceManager: sm)
        // File should be considered new (no previous cache)
        let changed = cache.changedFiles(allPaths: [sourceFile])
        XCTAssertTrue(changed.contains(sourceFile))
    }

    func testComputeCurrentFingerprintsFallsBackToFileSystemWhenNotInSourceManager() throws {
        let sourceDir = tempDir + "/src"
        try FileManager.default.createDirectory(atPath: sourceDir, withIntermediateDirectories: true)
        let sourceFile = sourceDir + "/a.kt"
        try "fun main() {}".write(toFile: sourceFile, atomically: true, encoding: .utf8)

        let sm = SourceManager()
        // Do NOT add the file to SourceManager — force fallback

        let cache = IncrementalCompilationCache(cachePath: tempDir)
        cache.computeCurrentFingerprints(for: [sourceFile], sourceManager: sm)
        let changed = cache.changedFiles(allPaths: [sourceFile])
        XCTAssertTrue(changed.contains(sourceFile))
    }
}

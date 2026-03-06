@testable import CompilerCore
import Dispatch
import Foundation
import XCTest

private final class RuntimeStubCachePathStore: @unchecked Sendable {
    private let lock = NSLock()
    private var paths: [String] = []

    func append(_ path: String) {
        lock.lock()
        paths.append(path)
        lock.unlock()
    }

    func snapshot() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return paths
    }
}

final class RuntimeStubCacheTests: XCTestCase {
    func testConcurrentCacheMissesPublishSingleSharedArtifact() throws {
        let fileManager = FileManager.default
        let stubDir = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: stubDir, withIntermediateDirectories: true)
        defer {
            try? fileManager.removeItem(at: stubDir)
        }

        let cacheKey = UUID().uuidString
        let triple = "runtime-stub-test-\(UUID().uuidString)"
        let finalObject = stubDir.appendingPathComponent("kk_runtime_\(cacheKey).o").path
        let context = StubCompilationContext(
            source: """
            int kk_runtime_stub_test(void) {
                return 1;
            }
            """,
            cacheKey: cacheKey,
            clangTargetArgs: [],
            stubDir: stubDir
        )

        let caches = [RuntimeStubCache(), RuntimeStubCache(), RuntimeStubCache()]
        let results = RuntimeStubCachePathStore()

        DispatchQueue.concurrentPerform(iterations: 9) { index in
            let cache = caches[index % caches.count]
            let path = cache.getOrInsert(triple: triple, context: context)
            if let path {
                results.append(path)
            }
        }

        let collectedPaths = results.snapshot()
        XCTAssertEqual(collectedPaths.count, 9)
        XCTAssertEqual(Set(collectedPaths), [finalObject])
        XCTAssertTrue(fileManager.fileExists(atPath: finalObject))

        let remainingEntries = try fileManager.contentsOfDirectory(atPath: stubDir.path).sorted()
        XCTAssertEqual(remainingEntries, ["kk_runtime_\(cacheKey).o"])
    }
}

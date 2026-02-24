import XCTest
@testable import CompilerCore

final class DependencyGraphTests: XCTestCase {

    // MARK: - Basic mutation and query

    func testRecordProvidedAndQuery() {
        let graph = DependencyGraph()
        graph.recordProvided(filePath: "a.kt", symbols: ["Foo", "Bar"])
        XCTAssertEqual(graph.provided(by: "a.kt"), ["Foo", "Bar"])
    }

    func testRecordDependedAndQuery() {
        let graph = DependencyGraph()
        graph.recordDepended(filePath: "b.kt", symbols: ["Baz"])
        XCTAssertEqual(graph.depended(by: "b.kt"), ["Baz"])
    }

    func testProvidedReturnsEmptyForUnknownFile() {
        let graph = DependencyGraph()
        XCTAssertEqual(graph.provided(by: "unknown.kt"), [])
    }

    func testDependedReturnsEmptyForUnknownFile() {
        let graph = DependencyGraph()
        XCTAssertEqual(graph.depended(by: "unknown.kt"), [])
    }

    func testClearFileRemovesBothProvidedAndDepended() {
        let graph = DependencyGraph()
        graph.recordProvided(filePath: "a.kt", symbols: ["X"])
        graph.recordDepended(filePath: "a.kt", symbols: ["Y"])
        graph.clearFile("a.kt")
        XCTAssertEqual(graph.provided(by: "a.kt"), [])
        XCTAssertEqual(graph.depended(by: "a.kt"), [])
    }

    // MARK: - trackedFiles

    func testTrackedFilesReturnsSortedUnion() {
        let graph = DependencyGraph()
        graph.recordProvided(filePath: "b.kt", symbols: ["B"])
        graph.recordDepended(filePath: "a.kt", symbols: ["A"])
        XCTAssertEqual(graph.trackedFiles, ["a.kt", "b.kt"])
    }

    func testTrackedFilesReturnsEmptyWhenEmpty() {
        let graph = DependencyGraph()
        XCTAssertEqual(graph.trackedFiles, [])
    }

    // MARK: - recompilationSet

    func testRecompilationSetWithEmptyChangedFiles() {
        let graph = DependencyGraph()
        let result = graph.recompilationSet(changedFiles: [], allFiles: ["a.kt"])
        XCTAssertEqual(result, [])
    }

    func testRecompilationSetIncludesChangedFiles() {
        let graph = DependencyGraph()
        graph.recordProvided(filePath: "a.kt", symbols: ["Foo"])
        let result = graph.recompilationSet(
            changedFiles: ["a.kt"],
            allFiles: ["a.kt", "b.kt"]
        )
        XCTAssertTrue(result.contains("a.kt"))
    }

    func testRecompilationSetIncludesDependentFiles() {
        let graph = DependencyGraph()
        graph.recordProvided(filePath: "a.kt", symbols: ["Foo"])
        graph.recordDepended(filePath: "b.kt", symbols: ["Foo"])
        let result = graph.recompilationSet(
            changedFiles: ["a.kt"],
            allFiles: ["a.kt", "b.kt"]
        )
        XCTAssertEqual(result, ["a.kt", "b.kt"])
    }

    func testRecompilationSetTransitiveDependencies() {
        let graph = DependencyGraph()
        // a provides Foo, b depends on Foo and provides Bar, c depends on Bar
        graph.recordProvided(filePath: "a.kt", symbols: ["Foo"])
        graph.recordProvided(filePath: "b.kt", symbols: ["Bar"])
        graph.recordDepended(filePath: "b.kt", symbols: ["Foo"])
        graph.recordDepended(filePath: "c.kt", symbols: ["Bar"])

        let result = graph.recompilationSet(
            changedFiles: ["a.kt"],
            allFiles: ["a.kt", "b.kt", "c.kt"]
        )
        XCTAssertEqual(Set(result), Set(["a.kt", "b.kt", "c.kt"]))
    }

    func testRecompilationSetDoesNotIncludeUnrelatedFiles() {
        let graph = DependencyGraph()
        graph.recordProvided(filePath: "a.kt", symbols: ["Foo"])
        graph.recordDepended(filePath: "b.kt", symbols: ["Unrelated"])

        let result = graph.recompilationSet(
            changedFiles: ["a.kt"],
            allFiles: ["a.kt", "b.kt"]
        )
        XCTAssertEqual(result, ["a.kt"])
    }

    func testRecompilationSetPreservesAllFilesOrder() {
        let graph = DependencyGraph()
        graph.recordProvided(filePath: "a.kt", symbols: ["X"])
        graph.recordDepended(filePath: "c.kt", symbols: ["X"])

        let result = graph.recompilationSet(
            changedFiles: ["a.kt"],
            allFiles: ["c.kt", "b.kt", "a.kt"]
        )
        // Should preserve allFiles order
        XCTAssertEqual(result, ["c.kt", "a.kt"])
    }

    // MARK: - Serialization

    func testSerializeAndDeserializeRoundTrip() throws {
        let graph = DependencyGraph()
        graph.recordProvided(filePath: "a.kt", symbols: ["Foo", "Bar"])
        graph.recordDepended(filePath: "b.kt", symbols: ["Foo"])

        let data = try graph.serialize()
        let restored = try DependencyGraph.deserialize(from: data)

        XCTAssertEqual(restored.provided(by: "a.kt"), ["Foo", "Bar"])
        XCTAssertEqual(restored.depended(by: "b.kt"), ["Foo"])
        XCTAssertEqual(restored.trackedFiles, ["a.kt", "b.kt"])
    }

    func testSerializeEmptyGraph() throws {
        let graph = DependencyGraph()
        let data = try graph.serialize()
        let restored = try DependencyGraph.deserialize(from: data)
        XCTAssertEqual(restored.trackedFiles, [])
    }

    func testDeserializeInvalidDataThrows() {
        let invalidData = Data("not json".utf8)
        XCTAssertThrowsError(try DependencyGraph.deserialize(from: invalidData))
    }
}

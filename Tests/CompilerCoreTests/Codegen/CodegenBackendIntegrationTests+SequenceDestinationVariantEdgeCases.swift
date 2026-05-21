@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testSequenceMapToAppendsToDestination() throws {
        let source = """
        fun main() {
            val src = sequenceOf(1, 2, 3)
            val dest = mutableListOf("seed")
            val result = src.mapTo(dest) { it.toString() }
            println(result)
            println(dest)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "STDLIBSEQ022_MAP_TO",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "[seed, 1, 2, 3]\n[seed, 1, 2, 3]\n")
        }
    }

    func testSequenceMapNotNullToAppendsNonNullTransforms() throws {
        let source = """
        fun main() {
            val src = sequenceOf(1, 2, 3, 4)
            val dest = mutableListOf("seed")
            val result = src.mapNotNullTo(dest) {
                if (it % 2 == 0) it.toString() else null
            }
            println(result)
            println(dest)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "STDLIBSEQ022_MAP_NOT_NULL_TO",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "[seed, 2, 4]\n[seed, 2, 4]\n")
        }
    }

    func testSequenceMapIndexedToAppendsIndexedTransforms() throws {
        let source = """
        fun main() {
            val src = sequenceOf(10, 20, 30)
            val dest = mutableListOf("seed")
            val result = src.mapIndexedTo(dest) { index, value ->
                index.toString() + ":" + value.toString()
            }
            println(result)
            println(dest)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "STDLIBSEQ022_MAP_INDEXED_TO",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "[seed, 0:10, 1:20, 2:30]\n[seed, 0:10, 1:20, 2:30]\n")
        }
    }

    func testSequenceFlatMapToAppendsFlattenedTransforms() throws {
        let source = """
        fun main() {
            val src = sequenceOf("a", "bc")
            val dest = mutableListOf("seed")
            val result = src.flatMapTo(dest) { value ->
                listOf(value, value + value)
            }
            println(result)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "STDLIBSEQ022_MAP_INDEXED_TO",
                moduleName: "SequenceFlatMapToRuntime",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "[seed, 0:10, 1:20, 2:30]\n[seed, 0:10, 1:20, 2:30]\n")
            XCTAssertEqual(
                normalizedStdout,
                """
                [seed, a, aa, bc, bcbc]
                """ + "\n"
            )
        }
    }

    func testSequenceMapIndexedNotNullToAppendsNonNullIndexedTransforms() throws {
        let source = """
        fun main() {
            val src = sequenceOf(10, 20, 30, 40)
            val dest = mutableListOf("seed")
            val result = src.mapIndexedNotNullTo(dest) { index, value ->
                if (index % 2 == 0) index.toString() + ":" + value.toString() else null
            }
            println(result === dest)
            println(result)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "STDLIBSEQ022_02",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "[seed, 0:10, 2:30]\n[seed, 0:10, 2:30]\n")
        }
    }
}

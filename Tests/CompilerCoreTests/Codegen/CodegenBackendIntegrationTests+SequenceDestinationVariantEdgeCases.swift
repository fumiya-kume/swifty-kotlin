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
            println(result === dest)
            println(result)
        }
        """
        try assertKotlinCompilesToKIR(source, moduleName: "STDLIBSEQ022_01")
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
        try assertKotlinCompilesToKIR(source, moduleName: "STDLIBSEQ022_02")
    }

    func testSequenceFlatMapIndexedToAppendsFlattenedIndexedTransforms() throws {
        let source = """
        fun main() {
            val src = sequenceOf("a", "bc")
            val dest = mutableListOf("seed")
            val result = src.flatMapIndexedTo(dest) { index, value ->
                listOf(index.toString() + ":" + value, value + value)
            }
            println(result)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "SequenceFlatMapIndexedToRuntime",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                normalizedStdout,
                """
                [seed, 0:a, aa, 1:bc, bcbc]
                """ + "\n"
            )
        }
    }
}

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
}

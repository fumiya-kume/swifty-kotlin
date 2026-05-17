@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testSequenceAssociateToPopulatesMutableMapDestination() throws {
        let source = """
        fun main() {
            val src = sequenceOf("a", "bb", "ccc")
            val dest = mutableMapOf<String, Int>()
            src.associateTo(dest) { it to it.length }
            println(dest["a"])
            println(dest["bb"])
            println(dest["ccc"])
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "SequenceAssociateToRuntime",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                normalizedStdout,
                """
                1
                2
                3
                """ + "\n"
            )
        }
    }

    func testSequenceAssociateByToMapsKeysToOriginalElements() throws {
        let source = """
        fun main() {
            val src = sequenceOf("apple", "banana", "pear")
            val dest = mutableMapOf<Int, String>()
            val result = src.associateByTo(dest) { it.length }
            println(result === dest)
            println(dest[5])
            println(dest[6])
            println(dest[4])
        }
        """
        try assertKotlinCompilesToKIR(source, moduleName: "STDLIBSEQ023_02")
    }

    func testSequenceAssociateWithToUsesElementsAsKeys() throws {
        let source = """
        fun main() {
            val src = sequenceOf(1, 2, 3)
            val dest = mutableMapOf<Int, Int>()
            src.associateWithTo(dest) { it * it }
            println(dest[1])
            println(dest[2])
            println(dest[3])
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "SequenceAssociateWithToRuntime",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                normalizedStdout,
                """
                1
                4
                9
                """ + "\n"
            )
        }
    }

    func testSequenceGroupByToAppendsIntoMutableListBuckets() throws {
        let source = """
        fun main() {
            val src = sequenceOf(1, 2, 3, 4, 5)
            val dest = mutableMapOf<String, MutableList<Int>>()
            val result = src.groupByTo(dest) { if (it % 2 == 0) "even" else "odd" }
            println(result === dest)
            println(dest["even"])
            println(dest["odd"])
        }
        """
        try assertKotlinCompilesToKIR(source, moduleName: "STDLIBSEQ023_04")
    }
}

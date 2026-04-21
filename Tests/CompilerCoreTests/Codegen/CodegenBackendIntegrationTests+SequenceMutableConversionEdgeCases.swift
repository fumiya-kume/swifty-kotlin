@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenExecutesSequenceMutableConversions() throws {
        let source = """
        fun main() {
            val mutableList = sequenceOf(3, 1, 2, 1, 3).toMutableList()
            mutableList.add(99)
            println(mutableList)

            val mutableSet = sequenceOf(3, 1, 2, 1, 3).toMutableSet()
            mutableSet.add(42)
            println(mutableSet)

            val hashSet = sequenceOf(3, 1, 2, 1, 3).toHashSet()
            hashSet.add(77)
            println(hashSet)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "SequenceMutableConversionEdgeCases",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                normalizedStdout,
                """
                [3, 1, 2, 1, 3, 99]
                [3, 1, 2, 42]
                [3, 1, 2, 77]
                """
                + "\n"
            )
        }
    }
}

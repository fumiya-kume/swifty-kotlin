@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testSequenceAssociateWithMapsElementsToTransformedValues() throws {
        let source = """
        fun main() {
            val result = sequenceOf(1, 2, 3).associateWith { value ->
                value * value
            }
            println(result[1])
            println(result[2])
            println(result[3])
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "SequenceAssociateWithRuntime",
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
}

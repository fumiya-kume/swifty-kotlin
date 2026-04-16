@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenCompilesRandomRuntimeEdgeCases() throws {
        let source = """
        import kotlin.random.Random

        fun main() {
            val r1 = Random(42)
            val r2 = Random(42)
            println(r1.nextInt() == r2.nextInt())
            println(r1.nextInt(256) == r2.nextInt(256))

            val rangedBits = Random(7)
            val b1 = rangedBits.nextInt(2)
            val b8 = rangedBits.nextInt(256)
            println(b1 == 0 || b1 == 1)
            println(b8 >= 0 && b8 < 256)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "RandomRuntimeEdgeCases",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                normalizedStdout,
                """
                true
                true
                true
                true
                """
                + "\n"
            )
        }
    }
}

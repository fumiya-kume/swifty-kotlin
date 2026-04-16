@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenCompilesRandomEdgeCases() throws {
        let source = """
        import kotlin.random.Random

        fun main() {
            val r1 = Random(1234)
            val r2 = Random(1234)

            println(r1.nextInt(100) == r2.nextInt(100))
            println(r1.nextInt(10, 20) == r2.nextInt(10, 20))
            println(r1.nextBoolean() == r2.nextBoolean())

            val ranged = Random(7)
            val nextInt = ranged.nextInt(5, 10)
            val nextDouble = ranged.nextDouble(1.0, 2.0)
            println(nextInt >= 5 && nextInt < 10)
            println(nextDouble >= 1.0 && nextDouble < 2.0)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "RandomEdgeCases",
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
                true
                """
                + "\n"
            )
        }
    }
}

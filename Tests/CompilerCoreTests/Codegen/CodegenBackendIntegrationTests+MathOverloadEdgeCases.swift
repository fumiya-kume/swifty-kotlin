@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenCompilesMathOverloadEdgeCases() throws {
        let source = """
        import kotlin.math.*

        fun main() {
            val sqrtFloat: Float = sqrt(9.0f)
            val sqrtDouble: Double = sqrt(9.0)
            println(sqrtFloat)
            println(sqrtDouble)

            val absInt: Int = abs(-7)
            val absLong: Long = abs(-9L)
            val absFloat: Float = abs(-3.5f)
            val absDouble: Double = abs(-4.5)
            println(absInt)
            println(absLong)
            println(absFloat)
            println(absDouble)

            val atan2Float: Float = atan2(1.0f, 1.0f)
            val atan2Double: Double = atan2(1.0, 1.0)
            println(atan2Float > 0.78f && atan2Float < 0.79f)
            println(atan2Double > 0.78 && atan2Double < 0.79)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "MathOverloadEdgeCases",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                normalizedStdout,
                """
                3.0
                3.0
                7
                9
                3.5
                4.5
                true
                true
                """
            )
        }
    }
}

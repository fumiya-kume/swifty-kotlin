@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenCompilesMathRuntimeEdgeCases() throws {
        let source = """
        import kotlin.math.*

        fun main() {
            println(2.0.pow(10.0))
            println(log2(1024.0))
            println(ln(E))

            println(sqrt(Double.POSITIVE_INFINITY).isInfinite())
            println(sqrt(Double.NaN).isNaN())

            println(log(Double.POSITIVE_INFINITY).isInfinite())
            println(log(Double.NaN).isNaN())

            println((-1.0).pow(3.0))
            println((-1.0).pow(2.0))
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "MathRuntimeEdgeCases",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                normalizedStdout,
                """
                1024.0
                10.0
                1.0
                true
                true
                true
                true
                -1.0
                1.0
                """
            )
        }
    }
}

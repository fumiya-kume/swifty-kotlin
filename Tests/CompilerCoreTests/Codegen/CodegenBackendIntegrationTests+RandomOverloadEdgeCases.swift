@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenCompilesRandomOverloadEdgeCases() throws {
        let source = """
        import kotlin.random.Random

        fun main() {
            val seeded1 = Random(99)
            val seeded2 = Random(99)

            println(seeded1.nextLong() == seeded2.nextLong())
            println(seeded1.nextFloat() == seeded2.nextFloat())

            val r = Random(7)
            val longVal = r.nextLong(10L, 20L)
            val floatVal = r.nextFloat(1.0f, 2.0f)
            println(longVal >= 10L && longVal < 20L)
            println(floatVal >= 1.0f && floatVal < 2.0f)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "RandomOverloadEdgeCases",
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
                """ + "\n"
            )
        }
    }
}

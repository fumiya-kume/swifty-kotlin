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
            println(r1.nextBits(8) == r2.nextBits(8))
            println(r1.nextBits(16) == r2.nextBits(16))

            val rangedBits = Random(7)
            val b1 = rangedBits.nextBits(1)
            val b8 = rangedBits.nextBits(8)
            println(b1 == 0 || b1 == 1)
            println(b8 in 0 until 256)

            val bytes1 = Random(99).nextBytes(ByteArray(6), 1, 5)
            val bytes2 = Random(99).nextBytes(ByteArray(6), 1, 5)
            println(bytes1.toList() == bytes2.toList())
            println(bytes1.size)
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
                true
                6
                """
            )
        }
    }
}

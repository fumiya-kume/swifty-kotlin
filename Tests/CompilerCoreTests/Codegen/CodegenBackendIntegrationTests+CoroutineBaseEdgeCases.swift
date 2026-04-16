@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenCompilesCoroutineBaseEdgeCases() throws {
        throw XCTSkip("Coroutine base edge cases not yet implemented")
        let source = """
        import kotlinx.coroutines.*

        suspend fun step(value: Int): Int {
            delay(1)
            return value + 1
        }

        suspend fun failStep(): Int {
            delay(1)
            throw IllegalStateException("suspend-boom")
        }

        fun main() = runBlocking {
            val ok = step(41)
            println(ok)

            try {
                failStep()
            } catch (e: IllegalStateException) {
                println(e.message)
            }

            val resumed = withContext(Dispatchers.Default) {
                step(9)
            }
            println(resumed)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "CoroutineBaseEdgeCases",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                normalizedStdout,
                """
                42
                suspend-boom
                10
                """
            )
        }
    }
}

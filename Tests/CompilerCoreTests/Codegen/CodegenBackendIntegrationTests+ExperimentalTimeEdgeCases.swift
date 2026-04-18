@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenCompilesExperimentalTimeEdgeCases() throws {
        let source = """
        import kotlin.time.Duration.Companion.milliseconds
        import kotlin.time.ExperimentalTime
        import kotlin.time.TimeSource

        @OptIn(ExperimentalTime::class)
        fun main() {
            val start = TimeSource.Monotonic.markNow()
            val future = start + 5.milliseconds
            val past = future - 10.milliseconds

            println((future - start).inWholeMilliseconds)
            println((future - past).inWholeMilliseconds)
            // hasNotPassedNow() is timing-sensitive; only check past.hasPassedNow()
            println(past.hasPassedNow())
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "ExperimentalTimeEdgeCases",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                normalizedStdout,
                """
                5
                10
                true
                """
                + "\n"
            )
        }
    }
}

@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenCompilesTimeEdgeCases() throws {
        let source = """
        import kotlin.time.*
        import kotlin.time.Duration.Companion.milliseconds
        import kotlin.time.Duration.Companion.seconds

        fun main() {
            val measured = measureTimedValue {
                40 + 2
            }
            println(measured.value)
            println(measured.duration.isPositive())

            val negative = (-5).seconds
            println(negative.inWholeSeconds)
            println(negative.isNegative())

            val epoch = Instant.fromEpochMilliseconds(0L)
            val later = epoch + 1500.milliseconds
            println(later.epochSeconds)
            println(later.nanoOfSecond)

            val earlier = later - 2.seconds
            println(earlier.epochSeconds)
            println(earlier.nanoOfSecond)

            println(epoch.isDistantPast)
            println(epoch.isDistantFuture)
            println(Instant.fromEpochMilliseconds(-3217862419200001L).isDistantPast)
            println(Instant.fromEpochMilliseconds(-3217862419200000L).isDistantPast)
            println(Instant.fromEpochMilliseconds(3093527980800000L).isDistantFuture)
            println(Instant.fromEpochMilliseconds(3093527980799999L).isDistantFuture)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "TimeEdgeCases",
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
                true
                -5
                true
                1
                500000000
                -1
                500000000
                false
                false
                true
                false
                true
                false
                """ + "\n"
            )
        }
    }
}

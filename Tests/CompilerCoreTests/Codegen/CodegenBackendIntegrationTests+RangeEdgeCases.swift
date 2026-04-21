@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenCompilesRangeEdgeCases() throws {
        #if os(Linux)
        throw XCTSkip("Range edge cases test temporarily disabled on Linux")
        #endif
        let source = """
        fun main() {
            println((1..4).toList())
            println((5 downTo 1 step 2).toList())
            println((1..0).toList())

            println(3.coerceIn(1, 5))
            println(0.coerceIn(1, 5))
            println(9.coerceIn(1, 5))

            println(3.coerceAtLeast(5))
            println(8.coerceAtMost(5))
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "RangeEdgeCases",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                normalizedStdout,
                """
                [1, 2, 3, 4]
                [5, 3, 1]
                []
                3
                1
                5
                5
                5
                """ + "\n"
            )
        }
    }

    func testCodegenCompilesRangeRandomOrNullEdgeCases() throws {
        #if os(Linux)
        throw XCTSkip("Range randomOrNull edge cases test temporarily disabled on Linux")
        #endif
        let source = """
        import kotlin.random.Random

        fun pass(vararg checks: Boolean): Boolean {
            for (check in checks) {
                if (!check) return false
            }
            return true
        }

        fun main() {
            val seed = 123

            val intRange = 1..4
            val intEmpty = 1..0
            println(pass(
                when (val value = intRange.randomOrNull()) {
                    null -> false
                    else -> value in intRange
                },
                intEmpty.randomOrNull() == null,
                intRange.randomOrNull(Random(seed)) == intRange.randomOrNull(Random(seed)),
                intEmpty.randomOrNull(Random(seed)) == null,
            ))

            val longRange = 1L..4L
            val longEmpty = 1L..0L
            println(pass(
                when (val value = longRange.randomOrNull()) {
                    null -> false
                    else -> value in longRange
                },
                longEmpty.randomOrNull() == null,
                longRange.randomOrNull(Random(seed)) == longRange.randomOrNull(Random(seed)),
                longEmpty.randomOrNull(Random(seed)) == null,
            ))

            val uintRange = 1u..4u
            val uintEmpty = 1u..0u
            println(pass(
                when (val value = uintRange.randomOrNull()) {
                    null -> false
                    else -> value in uintRange
                },
                uintEmpty.randomOrNull() == null,
                uintRange.randomOrNull(Random(seed)) == uintRange.randomOrNull(Random(seed)),
                uintEmpty.randomOrNull(Random(seed)) == null,
            ))

            val ulongRange = 1uL..4uL
            val ulongEmpty = 1uL..0uL
            println(pass(
                when (val value = ulongRange.randomOrNull()) {
                    null -> false
                    else -> value in ulongRange
                },
                ulongEmpty.randomOrNull() == null,
                ulongRange.randomOrNull(Random(seed)) == ulongRange.randomOrNull(Random(seed)),
                ulongEmpty.randomOrNull(Random(seed)) == null,
            ))

            val charRange = 'a'..'d'
            val charEmpty = 'b'..'a'
            println(pass(
                when (val value = charRange.randomOrNull()) {
                    null -> false
                    else -> value in charRange
                },
                charEmpty.randomOrNull() == null,
                charRange.randomOrNull(Random(seed)) == charRange.randomOrNull(Random(seed)),
                charEmpty.randomOrNull(Random(seed)) == null,
            ))
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "RangeRandomOrNullEdgeCases",
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
                """ + "\n"
            )
        }
    }
}

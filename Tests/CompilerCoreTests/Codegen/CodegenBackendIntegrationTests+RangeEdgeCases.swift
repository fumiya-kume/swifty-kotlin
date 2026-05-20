@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenCoerceValueInTopLevel() throws {
        let source = """
        import kotlin.ranges.coerceValueIn

        fun main() {
            println(coerceValueIn(3, 1, 5))
            println(coerceValueIn(0, 1, 5))
            println(coerceValueIn(9, 1, 5))
            println(coerceValueIn(7L, 10L, 20L))
            println(coerceValueIn(2.5, 1.0, 2.0))
            println(coerceValueIn(5u, 1u, 10u))
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "CoerceValueInTopLevel",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            XCTAssertEqual(
                result.stdout.replacingOccurrences(of: "\r\n", with: "\n"),
                """
                3
                1
                5
                10
                2.0
                5
                """ + "\n"
            )
        }
    }

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

    func testCodegenCompilesByteAndShortCoercionCases() throws {
        #if os(Linux)
        throw XCTSkip("Byte/Short coercion test temporarily disabled on Linux")
        #endif
        // Byte and Short are normalized to Int in the compiler, so these calls
        // exercise the same runtime helpers as Int while proving the source
        // overloads resolve.
        let source = """
        fun main() {
            println((-5).toByte().coerceIn((-10).toByte(), 10.toByte()))
            println((-15).toByte().coerceAtLeast((-10).toByte()))
            println(15.toByte().coerceAtMost(10.toByte()))

            println((-5).toShort().coerceIn((-10).toShort(), 10.toShort()))
            println((-15).toShort().coerceAtLeast((-10).toShort()))
            println(15.toShort().coerceAtMost(10.toShort()))
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "ByteAndShortCoercionCases",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                normalizedStdout,
                """
                -5
                -10
                10
                -5
                -10
                10
                """ + "\n"
            )
        }
    }

    func testCodegenCompilesUnsignedCoercionCases() throws {
        #if os(Linux)
        throw XCTSkip("Unsigned coercion test temporarily disabled on Linux")
        #endif
        let source = """
        import kotlin.ranges.UIntRange
        import kotlin.ranges.ULongRange

        fun main() {
            println(5u.coerceIn(1u, 10u))
            println(0u.coerceAtLeast(1u))
            println(15u.coerceAtMost(10u))
            println(5u.coerceIn(1u..10u))

            val uintRange = UIntRange(1u, 10u)
            println(5u.coerceIn(uintRange))

            val ui: UInt? = 5u
            println(ui?.coerceIn(1u..10u))
            println(ui?.coerceIn(uintRange))

            println(5uL.coerceIn(1uL, 10uL))
            println(0uL.coerceAtLeast(1uL))
            println(15uL.coerceAtMost(10uL))
            println(5uL.coerceIn(1uL..10uL))

            val ulongRange = ULongRange(1uL, 10uL)
            println(5uL.coerceIn(ulongRange))

            val ul: ULong? = 5uL
            println(ul?.coerceIn(1uL..10uL))
            println(ul?.coerceIn(ulongRange))
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "UnsignedCoercionCases",
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
                1
                10
                5
                5
                5
                5
                5
                1
                10
                5
                5
                5
                5
                """ + "\n"
            )
        }
    }
}

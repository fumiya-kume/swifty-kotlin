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

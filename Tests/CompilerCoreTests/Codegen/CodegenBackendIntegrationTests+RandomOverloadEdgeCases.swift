@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenCompilesRandomNextBitsMember() throws {
        let source = """
        import kotlin.random.Random

        fun main() {
            val r = Random(7)
            val zero = r.nextBits(0)
            val one = r.nextBits(1)
            val thirtyOne = r.nextBits(31)
            println(zero == 0)
            println(one == 0 || one == 1)
            println(thirtyOne >= 0)

            try {
                r.nextBits(33)
                println(false)
            } catch (e: IllegalArgumentException) {
                println(true)
            }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "RandomNextBitsMember",
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

    func testCodegenCompilesRandomDefaultSingleton() throws {
        let source = """
        import kotlin.random.Random

        fun main() {
            val r = Random.Default
            val value = r.nextInt(10)
            println(value >= 0 && value < 10)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "RandomDefaultSingleton",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "true\n")
        }
    }

    func testCodegenCompilesRandomNextBytesSize() throws {
        let source = """
        import kotlin.random.Random

        fun main() {
            val r = Random(7)
            r.nextBytes(4)
            println(true)

            try {
                r.nextBytes(-1)
                println(false)
            } catch (e: IllegalArgumentException) {
                println(true)
            }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "RandomNextBytesSize",
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
                """ + "\n"
            )
        }
    }

    func testCodegenCompilesRandomNextULongOverloads() throws {
        let source = """
        import kotlin.random.Random
        import kotlin.ranges.ULongRange

        fun main() {
            val r = Random(7)
            val full = r.nextULong()
            println(full >= 0uL)

            val until = r.nextULong(10uL)
            println(until < 10uL)

            val ranged = r.nextULong(10uL, 20uL)
            println(ranged >= 10uL && ranged < 20uL)

            val rangeObj = ULongRange(30uL, 35uL)
            val inRange = r.nextULong(rangeObj)
            println(inRange >= 30uL && inRange <= 35uL)

            try {
                r.nextULong(0uL)
                println(false)
            } catch (e: IllegalArgumentException) {
                println(true)
            }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "RandomNextULongOverloads",
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

    func testCodegenCompilesRandomLongSeedConstructor() throws {
        let source = """
        import kotlin.random.Random

        fun makeRandom(seed: Long): Random {
            return Random(seed)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "RandomLongSeedConstructor",
                emit: .object,
                outputPath: outputBase
            )
            let objectPath = try XCTUnwrap(ctx.generatedObjectPath)
            XCTAssertTrue(FileManager.default.fileExists(atPath: objectPath))
        }
    }
}

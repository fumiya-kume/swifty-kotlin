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

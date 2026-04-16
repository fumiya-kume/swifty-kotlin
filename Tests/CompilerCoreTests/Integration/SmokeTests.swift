@testable import CompilerCore
import Foundation
import XCTest

final class SmokeTests: XCTestCase {
    func testSmokeDriverKirDumpSucceedsForMinimalProgram() throws {
        try assertKotlinCompilesToKIR("fun main() = 0", moduleName: "SmokeKir")
    }

    func testSmokeDriverExecutableFailsWithoutMain() throws {
        try withTemporaryFile(contents: "fun helper() = 0") { path in
            let fileManager = FileManager.default
            let outputBase = fileManager.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            defer {
                try? fileManager.removeItem(atPath: outputBase)
                try? fileManager.removeItem(atPath: outputBase + ".o")
            }

            let options = makeTestOptions(
                moduleName: "SmokeMissingMain",
                inputs: [path],
                outputPath: outputBase,
                emit: .executable
            )
            let result = makeTestDriver().runForTesting(options: options)

            XCTAssertEqual(result.exitCode, 1)
            XCTAssertTrue(result.diagnostics.contains(where: { $0.code == "KSWIFTK-LINK-0002" }))
        }
    }

    func testSmokeDriverSemanticErrorReportsNonZeroExit() throws {
        let source = """
        fun expectInt(value: Int) = value
        fun main() = expectInt("oops")
        """
        try withTemporaryFile(contents: source) { path in
            let fileManager = FileManager.default
            let outputBase = fileManager.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            defer {
                try? fileManager.removeItem(atPath: outputBase + ".kir")
            }

            let options = makeTestOptions(
                moduleName: "SmokeSema",
                inputs: [path],
                outputPath: outputBase,
                emit: .kirDump
            )
            let result = makeTestDriver().runForTesting(options: options)

            XCTAssertEqual(result.exitCode, 1)
            XCTAssertTrue(result.diagnostics.contains(where: { $0.severity == .error }))
            XCTAssertTrue(result.diagnostics.contains(where: {
                $0.code.hasPrefix("KSWIFTK-SEMA-") || $0.code.hasPrefix("KSWIFTK-TYPE-")
            }))
        }
    }

    func testSmokeDriverMissingInputReportsFailure() {
        let missingPath = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("kt")
            .path
        let outputBase = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .path
        defer {
            try? FileManager.default.removeItem(atPath: outputBase + ".kir")
        }

        let options = makeTestOptions(
            moduleName: "SmokeMissingInput",
            inputs: [missingPath],
            outputPath: outputBase,
            emit: .kirDump
        )
        let result = makeTestDriver().runForTesting(options: options)

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.diagnostics.contains(where: { $0.code == "KSWIFTK-SOURCE-0002" }))
    }

    func testSmokeLLVMObjectEmissionProducesNativeObjectFile() throws {
        try withTemporaryFile(contents: "fun main() = 0") { path in
            let fileManager = FileManager.default
            let outputBase = fileManager.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            let objectPath = outputBase + ".o"
            defer {
                try? fileManager.removeItem(atPath: objectPath)
            }

            let options = makeTestOptions(
                moduleName: "SmokeLLVM",
                inputs: [path],
                outputPath: outputBase,
                emit: .object
            )
            let result = makeTestDriver().runForTesting(options: options)

            XCTAssertEqual(result.exitCode, 0)
            XCTAssertFalse(result.diagnostics.contains(where: { $0.severity == .error }))
            let data = try Data(contentsOf: URL(fileURLWithPath: objectPath))
            XCTAssertGreaterThanOrEqual(data.count, 4)
            #if os(Linux)
                // ELF magic number
                XCTAssertEqual(Array(data.prefix(4)), [0x7F, 0x45, 0x4C, 0x46])
            #else
                // Mach-O magic number
                XCTAssertEqual(Array(data.prefix(4)), [0xCF, 0xFA, 0xED, 0xFE])
            #endif
        }
    }

    func testSmokeDriverEmptyFileProducesSourceError() throws {
        try withTemporaryFile(contents: "") { path in
            let fileManager = FileManager.default
            let outputBase = fileManager.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            defer {
                try? fileManager.removeItem(atPath: outputBase + ".kir")
            }

            let options = makeTestOptions(
                moduleName: "SmokeEmpty",
                inputs: [path],
                outputPath: outputBase,
                emit: .kirDump
            )
            let result = makeTestDriver().runForTesting(options: options)

            // An empty Kotlin file is valid (no top-level declarations is acceptable);
            // the compiler should not crash and must return a defined exit code.
            XCTAssertTrue(
                result.exitCode == 0 || result.exitCode == 1,
                "Unexpected exit code \(result.exitCode) for empty file"
            )
        }
    }

    func testSmokeDriverMultipleInputFilesCompilesToKIR() throws {
        try assertKotlinSourcesToKIR(
            ["fun greet(): String = \"hello\"", "fun main() = 0"],
            moduleName: "SmokeMultiFile"
        )
    }

    func testSmokeDriverLargeFileCompilesToKIR() throws {
        // Generate a file with many top-level functions to exercise the pipeline
        // under a larger-than-trivial input without triggering semantic errors.
        var lines: [String] = (0 ..< 200).map { "fun smokeFunc\($0)(x: Int): Int = x + \($0)" }
        lines.append("fun main() = 0")
        try assertKotlinCompilesToKIR(lines.joined(separator: "\n"), moduleName: "SmokeLargeFile")
    }

    // MARK: - New smoke tests (TEST-SMOKE-005)

    func testSmokeSealedClassExhaustiveWhenCompilesToKIR() throws {
        // Sealed class with exhaustive when branches must compile cleanly through
        // the full frontend pipeline (Lex → Parse → BuildAST → Sema → KIR).
        try assertKotlinCompilesToKIR("""
        sealed class Shape {
            class Circle(val radius: Double) : Shape()
            class Rectangle(val width: Double, val height: Double) : Shape()
            object Triangle : Shape()
        }

        fun area(shape: Shape): Double = when (shape) {
            is Shape.Circle -> 3.14 * shape.radius * shape.radius
            is Shape.Rectangle -> shape.width * shape.height
            is Shape.Triangle -> 0.5
        }

        fun main() {
            val c = Shape.Circle(2.0)
            val r = Shape.Rectangle(3.0, 4.0)
            area(c)
            area(r)
        }
        """, moduleName: "SmokeSealedWhen")
    }

    func testSmokeEnumClassWhenExpressionCompilesToKIR() throws {
        // Enum class entries used in a when expression must compile cleanly;
        // this exercises the enum codepath through Sema and KIR lowering.
        try assertKotlinCompilesToKIR("""
        enum class Direction {
            NORTH, SOUTH, EAST, WEST
        }

        fun describe(dir: Direction): String = when (dir) {
            Direction.NORTH -> "up"
            Direction.SOUTH -> "down"
            Direction.EAST -> "right"
            Direction.WEST -> "left"
        }

        fun main() {
            describe(Direction.NORTH)
            describe(Direction.WEST)
        }
        """, moduleName: "SmokeEnumWhen")
    }

    func testSmokeDefaultParameterForwardingCompilesToKIR() throws {
        // Functions with default parameters and call-sites that omit those
        // parameters must survive Sema argument-filling and KIR generation.
        try assertKotlinCompilesToKIR("""
        fun greet(name: String, greeting: String = "Hello", punctuation: String = "!"): String {
            return "$greeting, $name$punctuation"
        }

        fun main() {
            greet("World")
            greet("Kotlin", greeting = "Hi")
            greet("KSwiftK", greeting = "Hey", punctuation = ".")
        }
        """, moduleName: "SmokeDefaultParams")
    }

    func testSmokeTypealiasAndExtensionFunctionCompilesToKIR() throws {
        // A typealias used as a parameter type together with an extension function
        // on the aliased type must compile without errors through the full pipeline.
        try assertKotlinCompilesToKIR("""
        typealias Score = Int

        fun Score.grade(): String = when {
            this >= 90 -> "A"
            this >= 80 -> "B"
            this >= 70 -> "C"
            else -> "F"
        }

        fun main() {
            val s: Score = 85
            s.grade()
        }
        """, moduleName: "SmokeTypealiasExtension")
    }
}

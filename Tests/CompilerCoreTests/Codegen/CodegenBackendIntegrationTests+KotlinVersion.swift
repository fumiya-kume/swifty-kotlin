@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenCompilesKotlinVersionComponents() throws {
        let source = """
        fun main() {
            val short = KotlinVersion(2, 1)
            val full = KotlinVersion(2, 1, 20)
            println(short.patch)
            println(full.major)
            println(full.minor)
            println(full.patch)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "KotlinVersionComponents",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "0\n2\n1\n20\n")
        }
    }

    func testCodegenCompilesKotlinVersionComparisonHelpers() throws {
        let source = """
        fun main() {
            val baseline = KotlinVersion(2, 1, 20)
            println(KotlinVersion.CURRENT.isAtLeast(1, 0))
            println(baseline.compareTo(KotlinVersion(2, 1)) > 0)
            println(baseline < KotlinVersion(2, 2, 0))
            println(baseline.isAtLeast(2, 1, 21))
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "KotlinVersionComparisonHelpers",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "true\ntrue\ntrue\nfalse\n")
        }
    }
}

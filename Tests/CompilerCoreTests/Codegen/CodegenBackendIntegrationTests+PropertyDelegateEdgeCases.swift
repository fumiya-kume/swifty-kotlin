@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenCompilesPropertyDelegateEdgeCases() throws {
        throw XCTSkip("Property delegates (lazy, observable, vetoable) are not yet implemented")
    }

    func testCodegenCompilesLazyOfValueRead() throws {
        let source = """
        fun main() {
            val value = lazyOf(42)
            println(value.value)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "LazyOfValueRead",
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
                """ + "\n"
            )
        }
    }
}

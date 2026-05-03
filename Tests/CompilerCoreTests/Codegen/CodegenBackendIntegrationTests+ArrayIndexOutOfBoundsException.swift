@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenCatchesArrayIndexOutOfBoundsException() throws {
        let source = """
        fun main() {
            try {
                throw ArrayIndexOutOfBoundsException("bad index")
            } catch (e: ArrayIndexOutOfBoundsException) {
                println("array-index")
            }

            try {
                throw ArrayIndexOutOfBoundsException()
            } catch (e: IndexOutOfBoundsException) {
                println("index")
            }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "ArrayIndexOutOfBoundsExceptionCase",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "array-index\nindex\n")
        }
    }
}

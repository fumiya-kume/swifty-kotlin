@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenCompilesI18NCommonEdgeCases() throws {
        let source = """
        import java.util.Locale

        fun main() {
            println("%s:%d".format("age", 7))
            println("%.1f".format(3.5))

            println("Hello".uppercase())
            println("Hello".lowercase())

            val locale = Locale("en", "US")
            println(locale.language)
            println(locale.country)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "I18NCommonEdgeCases",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                normalizedStdout,
                """
                age:7
                3.5
                HELLO
                hello
                en
                US
                """ + "\n"
            )
        }
    }
}

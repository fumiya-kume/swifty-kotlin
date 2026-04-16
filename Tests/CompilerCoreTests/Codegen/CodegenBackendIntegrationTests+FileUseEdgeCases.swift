@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenCompilesFileUseEdgeCases() throws {
        let source = """
        import java.io.Closeable
        import java.io.File

        class TraceResource(private val name: String) : Closeable {
            override fun close() {
                println("close:$name")
            }
        }

        fun main() {
            val result = TraceResource("ok").use {
                println("use:ok")
                "done"
            }
            println(result)

            try {
                TraceResource("fail").use {
                    println("use:fail")
                    error("boom")
                }
            } catch (e: Throwable) {
                println("caught")
            }

            val nullable: TraceResource? = null
            println(nullable?.use { "nope" })

            val file = File("/tmp/kswiftk_file_use_edge_cases.txt")
            file.delete()
            println(file.exists())
            println(file.createNewFile())
            println(file.exists())
            println(file.delete())
            println(file.exists())
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "FileUseEdgeCases",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                normalizedStdout,
                """
                use:ok
                close:ok
                done
                use:fail
                caught
                null
                false
                true
                true
                true
                false
                """
                + "\n"
            )
        }
    }
}

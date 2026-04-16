@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenCompilesAnnotationEdgeCases() throws {
        throw XCTSkip("Annotation diagnostic edge cases not yet implemented")
        let source = """
        @Target(AnnotationTarget.CLASS, AnnotationTarget.PROPERTY)
        @Retention(AnnotationRetention.RUNTIME)
        annotation class RuntimeMark(val label: String = "default")

        @Target(AnnotationTarget.FIELD)
        annotation class FieldMark

        @RuntimeMark("box")
        class Box(
            @field:FieldMark
            val value: Int,
        )

        @RuntimeMark
        class DefaultBox(
            val name: String,
        )

        fun main() {
            val box = Box(10)
            val defaultBox = DefaultBox("ok")
            println(box.value)
            println(defaultBox.name)
            println("annotation-edge-ok")
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "AnnotationEdgeCases",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                normalizedStdout,
                """
                10
                ok
                annotation-edge-ok
                """
            )
        }
    }
}

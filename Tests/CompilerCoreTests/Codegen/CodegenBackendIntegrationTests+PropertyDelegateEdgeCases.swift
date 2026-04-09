@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenCompilesPropertyDelegateEdgeCases() throws {
        let source = """
        import kotlin.properties.Delegates

        class Holder {
            var initCount = 0

            val token: String by lazy {
                initCount += 1
                "ready"
            }

            var observed: Int by Delegates.observable(1) { _, old, new ->
                println("obs:$old->$new")
            }

            var guarded: Int by Delegates.vetoable(0) { _, _, new ->
                new >= 0
            }
        }

        fun main() {
            val holder = Holder()
            println(holder.initCount)
            println(holder.token)
            println(holder.token)
            println(holder.initCount)

            holder.observed = 2
            holder.observed = 5

            holder.guarded = 3
            println(holder.guarded)
            holder.guarded = -1
            println(holder.guarded)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "PropertyDelegateEdgeCases",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                normalizedStdout,
                """
                0
                ready
                ready
                1
                obs:1->2
                obs:2->5
                3
                3
                """
            )
        }
    }
}

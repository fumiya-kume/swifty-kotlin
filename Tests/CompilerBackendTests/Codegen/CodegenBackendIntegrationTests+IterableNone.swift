#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite
struct CodegenBackendIterableNoneTests {
    private let pipelineHelper = CodegenBackendTestSupport()

    @Test
    func iterableNoneMatchesKotlinSemantics() throws {
        let source = """
        private class TrackingIterable<T>(private val values: List<T>) : Iterable<T> {
            var iteratorCalls = 0

            override fun iterator(): Iterator<T> {
                iteratorCalls += 1
                return values.iterator()
            }
        }

        fun main() {
            val customEmpty = TrackingIterable(emptyList<Int>())
            println(customEmpty.none())
            println("custom-empty-iterators=${customEmpty.iteratorCalls}")

            val customMatch = TrackingIterable(listOf(1, 2, 3))
            println(customMatch.none { it == 2 })
            println("custom-match-iterators=${customMatch.iteratorCalls}")

            val customNoMatch = TrackingIterable(listOf(1, 2, 3))
            println(customNoMatch.none { it > 3 })
            println("custom-no-match-iterators=${customNoMatch.iteratorCalls}")

            val collection: Iterable<Int> = listOf(1, 2, 3)
            println(collection.none())
            println(collection.none { it == 2 })

            val emptyCollection: Iterable<Int> = emptyList()
            println(emptyCollection.none { true })

            val nullable: Iterable<String?> = TrackingIterable(listOf(null, "value"))
            println(nullable.none { it == null })
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = try pipelineHelper.runCodegenPipeline(
                inputPath: path,
                moduleName: "IterableNone",
                emit: .executable,
                outputPath: outputBase
            )
            #expect(
                !ctx.diagnostics.hasError,
                "Expected Iterable.none to compile cleanly"
            )
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let output = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            #expect(
                output == """
                true
                custom-empty-iterators=1
                false
                custom-match-iterators=1
                true
                custom-no-match-iterators=1
                false
                false
                true
                false
                """ + "\n"
            )
        }
    }
}
#endif

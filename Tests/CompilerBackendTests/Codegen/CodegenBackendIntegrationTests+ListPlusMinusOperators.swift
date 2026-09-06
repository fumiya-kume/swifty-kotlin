@testable import CompilerCore
@testable import CompilerBackend
import Foundation

#if canImport(Testing)
import Testing

@Suite(.serialized)
struct CodegenBackendListPlusMinusOperatorsTests {
    private func assertKotlinOutput(
        _ source: String,
        moduleName: String,
        expected: String
    ) throws {
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: moduleName,
                emit: .executable,
                outputPath: outputBase
            )
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            #expect(normalizedStdout == expected)
        }
    }

    @Test
    func testCodegenListMinusRemovesElementAndCollectionValues() throws {
        let source = """
        fun main() {
            val values = listOf(1, 2, 2, 3)
            println(values - 2)
            println(values - listOf(2, 4))
            println(values)
        }
        """

        try assertKotlinOutput(source, moduleName: "ListMinusRuntime", expected: "[1, 2, 3]\n[1, 3]\n[1, 2, 2, 3]\n")
    }

    @Test
    func testCodegenIterableMinusSequenceAndArrayValues() throws {
        let source = """
        fun main() {
            val values: Iterable<Int> = listOf(1, 2, 2, 3, 4)
            println(values - sequenceOf(2, 4))
            println(values - arrayOf(2, 4))
            println(values - 2)
            println(values - listOf(2, 4))
            println(values)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "IterableMinusSequenceAndArrayRuntime",
            expected: "[1, 3]\n[1, 3]\n[1, 2, 3, 4]\n[1, 3]\n[1, 2, 2, 3, 4]\n"
        )
    }

    @Test
    func testCodegenArrayAndCollectionIsEmptyConditions() throws {
        let source = """
        fun arrayBranch(values: Array<out Int>): Int = if (values.isEmpty()) 1 else 2
        fun intArrayBranch(values: IntArray): Int = if (values.isEmpty()) 1 else 2
        fun listBranch(values: List<Int>): Int = if (values.isEmpty()) 1 else 2
        fun collectionBranch(values: Collection<Int>): Int = if (values.isEmpty()) 1 else 2

        fun main() {
            println(arrayBranch(arrayOf(1)))
            println(arrayBranch(emptyArray<Int>()))
            println(intArrayBranch(intArrayOf(1)))
            println(intArrayBranch(intArrayOf()))
            println(listBranch(listOf(1)))
            println(listBranch(listOf()))
            println(collectionBranch(listOf(1)))
            println(collectionBranch(listOf()))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "ArrayAndCollectionIsEmptyConditions",
            expected: "2\n1\n2\n1\n2\n1\n2\n1\n"
        )
    }
}
#endif

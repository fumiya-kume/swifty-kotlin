#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite
struct CodegenBackendCollectionJoinToStringTests {

    // Keep all joinToString coverage in one test method. This test case is
    // already large, and Swift's generated Linux discovery array can exceed
    // the type-checker time limit when several methods are added.
    @Test func testCodegenIterableJoinToStringUsesRuntimeDefaultsAndNamedArguments() throws {
        let source = """
        fun main() {
            val collection: Collection<Int> = listOf(1, 2, 3)
            println(collection.joinToString())
            println(collection.joinToString(" | "))
            println(collection.joinToString(prefix = "<", postfix = ">"))
            println(collection.joinToString(separator = ":", prefix = "[", postfix = "]"))

            val set: Set<String> = setOf("x", "y")
            println(set.joinToString(";"))

            val parts = "a\\r\\nbb\\r\\nccc".split("\\r\\n")
            println(parts.joinToString(",") { it.length.toString() })

            val list = listOf("a", "bb", "ccc")
            println(list.joinToString { it.length.toString() })
            println(list.joinToString(",", "[", "]") { it.length.toString() })

            val empty = emptyList<String>()
            println(empty.joinToString { it.length.toString() })

            val iter: Iterable<String> = listOf("a", "bb", "ccc")
            println(iter.joinToString("-") { "<" + it + ">" })

            // Named-argument calls without a transform must keep resolving to
            // the plain (separator, prefix, postfix) overload.
            println(list.joinToString(prefix = "<", postfix = ">"))

            val nullable: List<String>? = listOf("one", "two")
            println(nullable?.joinToString(","))
            println(nullable?.joinToString(prefix = "<", postfix = ">"))
            println(nullable?.joinToString(limit = 1))
            println(nullable?.joinToString(truncated = "more", limit = 1))
            val absent: List<String>? = null
            println(absent?.joinToString(limit = 1))

            try {
                println(listOf(1, 2, 3).joinToString(",") {
                    if (it == 2) throw IllegalStateException("boom")
                    it.toString()
                })
                println("missing-throw")
            } catch (e: IllegalStateException) {
                println("caught: " + e.message)
            }
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "IterableAndListJoinToStringRuntime",
            expected:
                """
                1, 2, 3
                1 | 2 | 3
                <1, 2, 3>
                [1:2:3]
                x;y
                1,2,3
                1, 2, 3
                [1,2,3]

                <a>-<bb>-<ccc>
                <a, bb, ccc>
                one,two
                <one, two>
                one, ...
                one, more
                null
                caught: boom
                """ + "\n"
        )
    }
}
#endif

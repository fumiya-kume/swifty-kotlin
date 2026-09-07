@testable import CompilerCore
@testable import CompilerBackend
import Foundation
#if canImport(Testing)
import Testing

@Suite
struct CodegenBackendCollectionListOfNotNullTests {

    @Test
    func testCodegenListOfNotNullFiltersNullElements() throws {
        let source = """
        fun maybeInt(value: Int): Int? = if (value > 0) value else null
        fun maybeString(value: String?): String? = value

        fun main() {
            val empty = listOfNotNull<Int>()
            println(empty)
            println(empty.size)

            val ints = listOfNotNull(maybeInt(1), maybeInt(-1), 2)
            println(ints)
            println(ints.size)

            val words = listOfNotNull(maybeString("alpha"), maybeString(null), "beta")
            println(words)
            println(words.size)
        }
        """

        try assertKotlinOutput(source, moduleName: "CollectionListOfNotNull", expected: "[]\n0\n[1, 2]\n2\n[alpha, beta]\n2\n")
    }
}
#endif

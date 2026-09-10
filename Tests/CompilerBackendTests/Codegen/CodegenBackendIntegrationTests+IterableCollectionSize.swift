#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Testing

@Suite
struct CodegenBackendIterableCollectionSizeTests {
    @Test
    func collectionSizeHelpersUseKnownSizeWithoutTraversingUnknownIterables() throws {
        let source = """
        @file:Suppress("INVISIBLE_MEMBER", "INVISIBLE_REFERENCE")

        class TrackingIterable<T>(private val source: List<T>) : Iterable<T> {
            var iteratorCalls = 0

            override fun iterator(): Iterator<T> {
                iteratorCalls += 1
                return source.iterator()
            }
        }

        fun main() {
            val collection: Iterable<Int> = listOf(1, 2, 3)
            val empty: Iterable<Int> = emptyList()
            val unknown = TrackingIterable(listOf(4, 5))

            println(collection.collectionSizeOrNull())
            println(collection.collectionSizeOrDefault(41))
            println(empty.collectionSizeOrNull())
            println(empty.collectionSizeOrDefault(41))
            println(unknown.collectionSizeOrNull())
            println(unknown.collectionSizeOrDefault(41))
            println(unknown.iteratorCalls)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "IterableCollectionSize",
            expected: "3\n3\n0\n0\nnull\n41\n0\n"
        )
    }
}
#endif

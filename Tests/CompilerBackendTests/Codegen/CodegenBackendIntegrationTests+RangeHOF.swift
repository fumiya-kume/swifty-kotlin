#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite
struct CodegenBackendRangeHOFTests {

    @Test
    func testCodegenIntRangeMapIndexed() throws {
        let source = """
        fun main() {
            println((1..4).mapIndexed { index, value -> index + value })
            println((1..1).mapIndexed { index, value -> index + value })
            println((1..0).mapIndexed { index, value -> index + value })
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "IntRangeMapIndexed",
            expected:
                """
                [1, 3, 5, 7]
                [1]
                []
                """ + "\n"
        )
    }

    @Test
    func testCodegenUIntRangeHOFExecution() throws {
        let source = """
        fun main() {
            println((1u..5u).fold(10u) { accumulator, value -> accumulator + value })
            println((1u..5u).foldIndexed(10u) { index, accumulator, value -> accumulator + index.toUInt() + value })
            println((1u..5u).reduce { accumulator, value -> accumulator + value })
            println((1u..5u).reduceIndexed { index, accumulator, value -> accumulator + index.toUInt() + value })
            println((1u..5u).find { it % 2u == 0u })
            println((1u..5u).findLast { it % 2u == 0u })
            println((1u..5u).first { it > 3u })
            println((1u..5u).firstOrNull { it > 8u })
            println((1u..5u).last { it < 4u })
            println((1u..5u).lastOrNull { it > 8u })
            println((1u..5u).any { it == 5u })
            println((1u..5u).all { it > 0u })
            println((1u..5u).none { it > 5u })
            (1u..3u).forEach { print("$it ") }
            println()
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "UIntRangeHOFExecution",
            expected:
                """
                25
                35
                15
                25
                2
                4
                4
                null
                3
                null
                true
                true
                true
                """ + "\n1 2 3 \n"
        )
    }

    @Test
    func testCodegenIntRangeMapNotNull() throws {
        let source = """
        fun main() {
            println((1..5).mapNotNull { if (it % 2 == 0) null else it })
            println((2..2).mapNotNull { if (it % 2 == 0) null else it })
            println((1..0).mapNotNull { if (it % 2 == 0) null else it })
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "IntRangeMapNotNull",
            expected:
                """
                [1, 3, 5]
                []
                []
                """ + "\n"
        )
    }

    @Test
    func testCodegenIntRangeFilterIndexed() throws {
        let source = """
        fun main() {
            println((1..4).filterIndexed { index, _ -> index % 2 == 0 })
            println((10..13).filterIndexed { index, value -> index == 0 || value > 11 })
            println((1..0).filterIndexed { index, _ -> index % 2 == 0 })
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "IntRangeFilterIndexed",
            expected:
                """
                [1, 3]
                [10, 12, 13]
                []
                """ + "\n"
        )
    }

    @Test
    func testCodegenIntRangeFindLast() throws {
        let source = """
        fun main() {
            println((1..6).findLast { it % 2 == 0 })
            println((1..5).findLast { it > 10 })
            println((1..0).findLast { it % 2 == 0 })
            println((3..3).findLast { it == 3 })
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "IntRangeFindLast",
            expected:
                """
                6
                null
                null
                3
                """ + "\n"
        )
    }

    @Test
    func testCodegenIntRangeReduceIndexed() throws {
        // reduceIndexed starts with acc=first, then calls lambda with index starting at 1.
        // (1..4): acc=1, (idx=1,acc=1,val=2)→4, (idx=2,acc=4,val=3)→9, (idx=3,acc=9,val=4)→16
        // (5..5): single element, acc=5, no iterations → 5
        let source = """
        fun main() {
            println((1..4).reduceIndexed { index, acc, value -> acc + index + value })
            println((5..5).reduceIndexed { index, acc, value -> acc + index + value })
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "IntRangeReduceIndexed",
            expected:
                """
                16
                5
                """ + "\n"
        )
    }

    @Test
    func testCodegenIntRangeReduce() throws {
        // KSP-1011 regression: a second source-backed `iterator()` declared
        // on Map (kotlin.collections.Map<out K, V>.iterator()) once widened
        // the by-simple-name candidate pool that this bundled `reduce`
        // body's implicit-receiver `iterator()` call resolves against,
        // binding it to the Map-only implementation for every Iterable
        // receiver — including this IntRange — and crashing at runtime
        // instead of computing the sum.
        let source = """
        fun main() {
            println((1..4).reduce { acc, v -> acc + v })
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "IntRangeReduce",
            expected: "10\n"
        )
    }

    @Test
    func testCodegenIntRangeMapIndexedOnDescendingProgression() throws {
        // (5 downTo 3) = [5,4,3]; mapIndexed {index+value} = [0+5,1+4,2+3] = [5,5,5]
        let source = """
        fun main() {
            println((5 downTo 3).mapIndexed { index, value -> index + value })
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "IntRangeMapIndexedDescending",
            expected: "[5, 5, 5]\n"
        )
    }

    @Test
    func testCodegenLongRangeHOFExecution() throws {
        let source = """
        fun main() {
            println((1L..4L).mapIndexed { index, value -> index + value })
            println((1L..1L).mapIndexed { index, value -> index + value })
            println((1L..0L).mapIndexed { index, value -> index + value })

            println((1L..5L).mapNotNull { if (it % 2L == 0L) null else it })
            println((2L..2L).mapNotNull { if (it % 2L == 0L) null else it })
            println((1L..0L).mapNotNull { if (it % 2L == 0L) null else it })

            println((1L..4L).filterIndexed { index, _ -> index % 2 == 0 })
            println((10L..13L).filterIndexed { index, value -> index == 0 || value > 11L })
            println((1L..0L).filterIndexed { index, _ -> index % 2 == 0 })

            println((1L..6L).findLast { it % 2L == 0L })
            println((1L..5L).findLast { it > 10L })
            println((1L..0L).findLast { it % 2L == 0L })
            println((3L..3L).findLast { it == 3L })

            println((1L..4L).reduceIndexed { index, acc, value -> acc + index + value })
            println((5L..5L).reduceIndexed { index, acc, value -> acc + index + value })

            println((5L downTo 1L).first { it % 2L == 0L })
            println((5L downTo 1L).last { it % 2L == 0L })
            println((5L downTo 3L).mapIndexed { index, value -> index + value })
            println((1L..4L).average())
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "LongRangeHOFExecution",
            expected:
                """
                [1, 3, 5, 7]
                [1]
                []
                [1, 3, 5]
                []
                []
                [1, 3]
                [10, 12, 13]
                []
                6
                null
                null
                3
                16
                5
                4
                2
                [5, 5, 5]
                2.5
                """ + "\n"
        )
    }

    @Test
    func testCodegenUIntRangeMapFilterHOFExecution() throws {
        let source = """
        fun main() {
            println((1u..5u).map { it * 2u })
            println((1u..5u).mapIndexed { index, value -> index.toUInt() + value })
            println((1u..5u).mapNotNull { if (it % 2u == 0u) null else it })
            println((1u..5u).filter { it % 2u == 1u })
            println((1u..5u).filterIndexed { index, _ -> index % 2 == 0 })
            println((1u..5u).filterNot { it % 2u == 0u })
            println((5u..1u).mapNotNull { it })
            println((5u..1u).filterIndexed { index, _ -> index == 0 })
            println((5u downTo 1u).mapIndexed { index, value -> index.toUInt() + value })
            println((5u downTo 1u).filterNot { it % 2u == 0u })
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "UIntRangeMapFilterHOFExecution",
            expected:
                """
                [2, 4, 6, 8, 10]
                [1, 3, 5, 7, 9]
                [1, 3, 5]
                [1, 3, 5]
                [1, 3, 5]
                [1, 3, 5]
                []
                []
                [5, 5, 5, 5, 5]
                [5, 3, 1]
                """ + "\n"
        )
    }

    @Test
    func testCodegenUIntRangeIteratorStepAndWindowingExecution() throws {
        let source = """
        fun main() {
            println((1u..5u).take(3))
            println((1u..5u).drop(2))
            println((1u..5u).chunked(2))
            println((1u..5u).windowed(3))
            println((1u..5u).windowed(3, 2, true))
            println((1u..5u step 2).take(2))
            println((5u downTo 1u).windowed(2, 2, true))
            for (value in 1u..5u) print("$value ")
            println()
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "UIntRangeIteratorStepAndWindowingExecution",
            expected:
                """
                [1, 2, 3]
                [3, 4, 5]
                [[1, 2], [3, 4], [5]]
                [[1, 2, 3], [2, 3, 4], [3, 4, 5]]
                [[1, 2, 3], [3, 4, 5], [5]]
                [1, 3]
                [[5, 4], [3, 2], [1]]
                """ + "\n1 2 3 4 5 \n"
        )
    }
}
#endif

#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

// STDLIB-020: Sequence lazy evaluation order and sequence builder semantics.

@Suite
struct CodegenBackendSequenceLazyEdgeCasesTests {

    @Test
    func testSequenceMapTakeEvaluatesOnlyNeededElements() throws {
        let source = """
        var counter = 0

        fun main() {
            val result = sequenceOf(1, 2, 3, 4, 5)
                .map { counter++; it * 2 }
                .take(3)
                .toList()
            println(result)
            println(counter)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "SequenceMapTakeLazy",
            expected:
                """
                [2, 4, 6]
                3
                """ + "\n"
        )
    }

    // KSP-631: Iterator.asSequence preserves the original iterator, defers
    // traversal, and enforces one-shot consumption.
    @Test
    func testIteratorAsSequencePreservesLazyOneShotSemantics() throws {
        let source = """
        class CountingIterator(private val values: List<Int>) : Iterator<Int> {
            private var index = 0
            var nextCalls = 0

            override fun hasNext(): Boolean = index < values.size

            override fun next(): Int {
                if (!hasNext()) throw NoSuchElementException()
                nextCalls++
                val result = values[index]
                index++
                return result
            }
        }

        fun main() {
            val identityIterator = listOf(7).iterator()
            val identitySequence = identityIterator.asSequence()
            println(identitySequence.iterator() === identityIterator)
            println(identityIterator.next())

            val probe = CountingIterator(listOf(1, 2, 3))
            val lazySequence = probe.asSequence()
            println(probe.nextCalls)
            println(lazySequence.take(2).toList())
            println(probe.nextCalls)

            val oneShot = listOf(4, 5).iterator().asSequence()
            println(oneShot.toList())
            try {
                oneShot.toList()
                println("missing one-shot failure")
            } catch (e: IllegalStateException) {
                println("one-shot")
            }

            println(emptyList<Int>().iterator().asSequence().toList())

        val partial = CountingIterator(listOf(10, 20, 30))
            println(partial.next())
            println(partial.asSequence().toList())
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "IteratorAsSequenceSemantics",
            expected: """
            true
            7
            0
            [1, 2]
            2
            [4, 5]
            one-shot
            []
            10
            [20, 30]
            """ + "\n"
        )
    }

    @Test
    func testSequenceFilterTakeEvaluatesOnlyNeededElements() throws {
        let source = """
        var counter = 0

        fun main() {
            val result = sequenceOf(1, 2, 3, 4, 5, 6)
                .filter { counter++; it % 2 == 0 }
                .take(2)
                .toList()
            println(result)
            // filter checks 1,2,3,4 to find two even numbers; counter must be <= 4
            println(counter <= 4)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "SequenceFilterTakeLazy",
            expected:
                """
                [2, 4]
                true
                """ + "\n"
        )
    }

    @Test
    func testInfiniteGenerateSequenceWithTakeTerminates() throws {
        let source = """
        fun main() {
            val naturals = generateSequence(1) { it + 1 }
            val first5 = naturals.take(5).toList()
            println(first5)
        }
        """

        try assertKotlinOutput(source, moduleName: "InfiniteGenerateSequenceTake", expected: "[1, 2, 3, 4, 5]\n")
    }

    @Test
    func testGenerateSequenceTerminatesOnNull() throws {
        let source = """
        fun main() {
            val counted = generateSequence(1) { current ->
                if (current >= 4) null else current + 1
            }
            println(counted.toList())
        }
        """

        try assertKotlinOutput(source, moduleName: "GenerateSequenceNullTermination", expected: "[1, 2, 3, 4]\n")
    }

    @Test
    func testSourceBackedSequenceFactoriesResolveSeedFunctionOverload() throws {
        let source = """
        fun main() {
            val repeated = generateSequence({
                10
            }) { if (it > 1) it / 2 else null }
            println(repeated.toList())

            val nullSeed: Int? = null
            println(generateSequence(nullSeed) { it + 1 }.toList())
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "SourceBackedSequenceFactories",
            expected:
                """
                [10, 5, 2, 1]
                []
                """ + "\n"
        )
    }

    // KSP-500: generateSequence's seed and every element produced by nextFunction
    // must be boxed when the sequence is used as Sequence<Any>, matching how
    // sequenceOf(...)/listOf(...) already box their elements. A plain
    // filterIsInstance<Int>() check does NOT catch a boxing regression here:
    // kk_op_is has an "unboxed numeric value matches any numeric type" fallback,
    // so an unboxed Int element coincidentally still passes `is Int`. Checking
    // `is Long`/`is Char` alongside `is Int` is what actually discriminates a
    // boxed element (only `is Int` true) from an unboxed one (all three true).
    @Test
    func testGenerateSequenceElementsAreBoxedNotJustNumericFallback() throws {
        let source = """
        fun main() {
            val values: Sequence<Any> = generateSequence(1) { if (it < 3) it + 1 else null }
            for (v in values.toList()) {
                println("" + (v is Int) + " " + (v is Long) + " " + (v is Char))
            }
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "GenerateSequenceElementsBoxedIfElse",
            expected:
                """
                true false false
                true false false
                true false false
                """ + "\n"
        )
    }

    // Same as above, but for a nextFunction with no if/else `null` branch —
    // this shape doesn't happen to trigger ABILoweringPass's incidental
    // copy-boxing, so it's a distinct regression risk from the if/else case.
    @Test
    func testGenerateSequenceElementsAreBoxedWithoutIfElseBranch() throws {
        let source = """
        fun main() {
            val naturals: Sequence<Any> = generateSequence(1) { it + 1 }
            for (v in naturals.take(3).toList()) {
                println("" + (v is Int) + " " + (v is Long) + " " + (v is Char))
            }
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "GenerateSequenceElementsBoxedNoIfElse",
            expected:
                """
                true false false
                true false false
                true false false
                """ + "\n"
        )
    }

    // 1-arg form generateSequence(nextFunction: () -> T?) — STDLIB-SEQ-002.
    @Test
    func testGenerateSequenceNoArgElementsAreBoxed() throws {
        let source = """
        fun main() {
            val values: Sequence<Any> = generateSequence { 42 }
            for (v in values.take(2).toList()) {
                println("" + (v is Int) + " " + (v is Long) + " " + (v is Char))
            }
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "GenerateSequenceNoArgElementsBoxed",
            expected:
                """
                true false false
                true false false
                """ + "\n"
        )
    }

    // 1-arg form with a captured local var — regression test for a related bug
    // found alongside the boxing leak: this overload's call used to be built
    // without expanding the closure to (fnPtr, closureRaw), which silently
    // dropped captures (closureRaw was padded to 0) and crashed at runtime
    // with a kk_array_get_inbounds precondition failure for any capturing
    // closure of this form.
    @Test
    func testGenerateSequenceNoArgWithCapturedStateWorks() throws {
        let source = """
        fun main() {
            var n = 0
            val values: Sequence<Any> = generateSequence {
                n = n + 1
                if (n <= 3) n else null
            }
            println(values.toList())
        }
        """

        try assertKotlinOutput(source, moduleName: "GenerateSequenceNoArgCapturedState", expected: "[1, 2, 3]\n")
    }

    // Mirrors the sequenceOf(...) mixed-type test above (testSequenceFilterIsInstanceKeepsMatchingTypes),
    // but for generateSequence: concatenating with a String-producing sequenceOf
    // gives filterIsInstance<Int> a real, non-Int element to reject, so this
    // only passes if generateSequence's elements are actually boxed (an unboxed
    // Int would still coincidentally pass `is Int`, but a genuinely-typed
    // String element correctly fails it either way — this test's value is
    // pinning the end-to-end user-facing scenario from the bug report).
    @Test
    func testGenerateSequenceFilterIsInstanceKeepsMatchingTypes() throws {
        let source = """
        fun main() {
            val values: Sequence<Any> = generateSequence(1) { if (it < 3) it + 1 else null } + sequenceOf("two")
            println(values.filterIsInstance<Int>().toList())
        }
        """

        try assertKotlinOutput(source, moduleName: "GenerateSequenceFilterIsInstance", expected: "[1, 2, 3]\n")
    }

    @Test(arguments: [false, true])
    func testSequenceBuilderYieldAndYieldAll(allowDefaultStdlibLibrary: Bool) throws {
        let source = """
        fun main() {
            val seq = sequence {
                yield(1)
                yieldAll(listOf(2, 3, 4))
                yield(5)
            }
            println(seq.toList())
            val chars = sequence {
                yield('a')
                this.yield('b')
            }
            println(chars.toList())
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "SequenceBuilderYieldAll",
            expected: "[1, 2, 3, 4, 5]\n[a, b]\n",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }

    @Test
    func testSequenceBuilderYieldAllPreservesLazyNested() throws {
        let source = """
        var counter = 0

        fun main() {
            val inner = sequence { counter++; yield(10); counter++; yield(20); counter++; yield(30) }
            val outer = sequence { yieldAll(inner) }
            // consume only first element — inner should evaluate lazily
            val first = outer.take(1).toList()
            println(first)
            println(counter <= 1)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "SequenceBuilderYieldAllLazy",
            expected:
                """
                [10]
                true
                """ + "\n"
        )
    }

    @Test(arguments: [false, true])
    func testSequenceBuilderRangeLoopYieldUsesCPSProducer(allowDefaultStdlibLibrary: Bool) throws {
        let source = """
        fun main() {
            val seq = sequence {
                for (i in 1..5) {
                    yield(i * i)
                }
            }
            println(seq.toList())
            println(seq.take(3).toList())
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "SequenceBuilderRangeLoopYieldCPS",
            expected:
                """
                [1, 4, 9, 16, 25]
                [1, 4, 9]
                """ + "\n",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }

    @Test
    func testSequenceFlatMapIsLazy() throws {
        let source = """
        var counter = 0

        fun main() {
            val result = sequenceOf(1, 2, 3)
                .flatMap { x -> counter++; sequenceOf(x, x * 10) }
                .take(2)
                .toList()
            println(result)
            // flatMap of first input (1) produces [1, 10]; take(2) gets them → counter == 1
            println(counter)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "SequenceFlatMapLazy",
            expected:
                """
                [1, 10]
                1
                """ + "\n"
        )
    }

    @Test
    func testSequenceDistinctPreservesOrder() throws {
        let source = """
        fun main() {
            val result = sequenceOf(3, 1, 2, 1, 3, 4).distinct().toList()
            println(result)
        }
        """

        try assertKotlinOutput(source, moduleName: "SequenceDistinct", expected: "[3, 1, 2, 4]\n")
    }

    @Test
    func testSequenceDistinctByPreservesFirstKeyOrder() throws {
        let source = """
        fun main() {
            val result = sequenceOf(3, 1, 2, 5, 4, 7).distinctBy { it % 2 }.toList()
            println(result)
        }
        """

        try assertKotlinOutput(source, moduleName: "SequenceDistinctBy", expected: "[3, 2]\n")
    }

    @Test
    func testSequenceZipStopsAtShorterSequence() throws {
        let source = """
        fun main() {
            val result = sequenceOf(1, 2, 3, 4)
                .zip(sequenceOf("a", "b"))
                .toList()
            println(result)
        }
        """

        try assertKotlinOutput(source, moduleName: "SequenceZip", expected: "[(1, a), (2, b)]\n")
    }

    @Test
    func testSequenceDropSkipsFirstN() throws {
        let source = """
        fun main() {
            val result = sequenceOf(1, 2, 3, 4, 5).drop(2).toList()
            println(result)
        }
        """

        try assertKotlinOutput(source, moduleName: "SequenceDrop", expected: "[3, 4, 5]\n")
    }

    @Test
    func testSequenceElementAtOrElseUsesDefaultForMissingIndex() throws {
        let source = """
        fun main() {
            println(sequenceOf(10, 20, 30).elementAtOrElse(4) { it * 10 })
        }
        """

        try assertKotlinOutput(source, moduleName: "SequenceElementAtOrElse", expected: "40\n")
    }

    @Test
    func testSequenceFilterKeepsMatchingElements() throws {
        let source = """
        fun main() {
            val result = sequenceOf(1, 2, 3, 4, 5)
                .filter { value -> value % 2 == 0 }
                .toList()
            println(result)
        }
        """

        try assertKotlinOutput(source, moduleName: "SequenceFilter", expected: "[2, 4]\n")
    }

    @Test
    func testSequenceFilterIndexedKeepsIndexedMatches() throws {
        let source = """
        fun main() {
            val result = sequenceOf(10, 20, 30, 40)
                .filterIndexed { index, value -> index % 2 == 0 || value > 30 }
                .toList()
            println(result)
        }
        """

        try assertKotlinOutput(source, moduleName: "SequenceFilterIndexed", expected: "[10, 30, 40]\n")
    }

    @Test
    func testSequenceFilterIndexedToAppendsIndexedMatches() throws {
        let source = """
        fun main() {
            val destination = mutableListOf(1)
            val result = sequenceOf(10, 20, 30, 40)
                .filterIndexedTo(destination) { index, value -> index % 2 == 0 || value > 30 }
            println(result)
            println(destination)
        }
        """

        try assertKotlinOutput(source, moduleName: "SequenceFilterIndexedTo", expected: "[1, 10, 30, 40]\n[1, 10, 30, 40]\n")
    }

    @Test
    func testSequenceDropWhileSkipsLeadingMatchesOnly() throws {
        let source = """
        fun main() {
            val result = sequenceOf(1, 2, 3, 1, 4).dropWhile { it < 3 }.toList()
            println(result)
        }
        """

        try assertKotlinOutput(source, moduleName: "SequenceDropWhile", expected: "[3, 1, 4]\n")
    }

    @Test
    func testSequenceElementAtOrNullReturnsValueOrNull() throws {
        let source = """
        fun main() {
            val values = sequenceOf(10, 20, 30)
            println(values.elementAtOrNull(1) ?: -1)
            println(values.elementAtOrNull(5) ?: -1)
        }
        """

        try assertKotlinOutput(source, moduleName: "SequenceElementAtOrNull", expected: "20\n-1\n")
    }

    @Test
    func testSequenceElementAtReturnsIndexedValue() throws {
        let source = """
        fun main() {
            println(sequenceOf(10, 20, 30).elementAt(1))
        }
        """

        try assertKotlinOutput(source, moduleName: "SequenceElementAt", expected: "20\n")
    }

    @Test
    func testSequenceFilterIsInstanceKeepsMatchingTypes() throws {
        let source = """
        fun main() {
            val values: Sequence<Any> = sequenceOf(1, "two", 3)
            println(values.filterIsInstance<Int>().toList())
        }
        """

        try assertKotlinOutput(source, moduleName: "SequenceFilterIsInstance", expected: "[1, 3]\n")
    }

    @Test
    func testSequenceTerminalOps() throws {
            let source = """
        fun main() {
            val seq = sequenceOf(1, 2, 3, 4, 5)

            println(seq.count())
            println(seq.indexOf(3))
            println(seq.indexOf(99))
            println(seq.indexOfFirst { it % 2 == 0 })
            println(seq.indexOfFirst { it > 10 })
            println(seq.indexOfLast { it % 2 == 0 })
            println(seq.indexOfLast { it > 10 })

            var sum = 0
            seq.forEach { sum += it }
            println(sum)

            val folded = seq.fold(0) { acc, x -> acc + x }
            println(folded)

            println(seq.intersect(listOf(2, 4, 6)))
            val foldedIndexed = seq.foldIndexed(0) { index, acc, x -> acc + index * x }
            println(foldedIndexed)
            val grouped = seq.groupBy { if (it % 2 == 0) "even" else "odd" }
            println(grouped["odd"])
            println(grouped["even"])
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "SequenceTerminalOps",
            expected:
                """
                5
                2
                -1
                1
                -1
                3
                -1
                15
                15
                [2, 4]
                40
                [1, 3, 5]
                [2, 4]
                """ + "\n"
        )
    }

    @Test
    func testEmptySequenceTerminals() throws {
        let source = """
        fun main() {
            val empty = emptySequence<Int>()

            println(empty.count())
            println(empty.toList())
            println(empty.firstOrNull())
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "EmptySequenceTerminals",
            expected:
                """
                0
                []
                null
                """ + "\n"
        )
    }

    @Test
    func testSequenceFirstReturnsFirstValue() throws {
        let source = """
        fun main() {
            val result = sequenceOf(4, 5, 6).first()
            println(result)
        }
        """

        try assertKotlinOutput(source, moduleName: "SequenceFirstRuntime", expected: "4\n")
    }

    @Test
    func testSequenceFirstOnEmptyThrows() throws {
        let source = """
        fun main() {
            try {
                emptySequence<Int>().first()
                println("unexpected")
            } catch (e: NoSuchElementException) {
                println("no-element")
            }
        }
        """

        try assertKotlinOutput(source, moduleName: "SequenceFirstOnEmpty", expected: "no-element\n")
    }

    @Test
    func testSequenceFirstOrNullReturnsFirstValue() throws {
        let source = """
        fun main() {
            val result = sequenceOf(4, 5, 6).firstOrNull()
            println(result)
        }
        """

        try assertKotlinOutput(source, moduleName: "SequenceFirstOrNullRuntime", expected: "4\n")
    }

    @Test
    func testSequenceFirstOrNullOnEmpty() throws {
        let source = """
        fun main() {
            val result = emptySequence<Int>().firstOrNull()
            println(result)
            val result2 = sequenceOf(1, 2, 3).firstOrNull { it > 10 }
            println(result2)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "SequenceFirstOrNull",
            expected:
                """
                null
                null
                """ + "\n"
        )
    }

    @Test
    func testAsSequenceFromList() throws {
        let source = """
        fun main() {
            val list = listOf(10, 20, 30)
            val result = list.asSequence()
                .map { it + 1 }
                .toList()
            println(result)
        }
        """

        try assertKotlinOutput(source, moduleName: "AsSequenceFromList", expected: "[11, 21, 31]\n")
    }

    @Test
    func testSequenceAsIterableToList() throws {
        let source = """
        fun main() {
            val iterable = sequenceOf(1, 2, 3).asIterable()
            println(iterable.toList())
        }
        """

        try assertKotlinOutput(source, moduleName: "SequenceAsIterableToList", expected: "[1, 2, 3]\n")
    }

    @Test
    func testSequenceAsSequenceReturnsSameSequenceSurface() throws {
        let source = """
        fun main() {
            val seq = sequenceOf(1, 2, 3).asSequence()
            println(seq.map { it + 1 }.toList())
        }
        """

        try assertKotlinOutput(source, moduleName: "SequenceAsSequence", expected: "[2, 3, 4]\n")
    }

    @Test
    func testSequenceConversionsRemainTraversableAfterSorting() throws {
        let source = """
        fun main() {
            val sequence = sequenceOf(3, 1, 2)
            println(sequence.asSequence().toList())
            println(sequence.asIterable().toList())
            println(sequence.sortedDescending().asSequence().toList())
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "SequenceConversionsAfterSorting",
            expected: """
            [3, 1, 2]
            [3, 1, 2]
            [3, 2, 1]
            """ + "\n"
        )
    }

    @Test
    func testSequenceIdentityConversionsPreserveLazyIteratorSemantics() throws {
        let source = """
        fun main() {
            val iterable = sequenceOf(1, 2, 3).asIterable()
            println(iterable.toList())
            println(iterable.toList())
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "SequenceIdentityLazyIterator",
            expected: """
            [1, 2, 3]
            [1, 2, 3]
            """ + "\n"
        )
    }

    @Test
    func testSequenceAsIterableWorksWithIterableConsumers() throws {
        let source = """
        fun main() {
            val destination = mutableListOf<Int>()
            println(destination.addAll(sequenceOf(4, 5).asIterable()))
            println(destination)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "SequenceAsIterableConsumer",
            expected:
                """
                true
                [4, 5]
                """ + "\n"
        )
    }
    func testConstrainOnceThrowsOnSecondIteration() throws {
        let source = """
        fun main() {
            val seq = sequenceOf(1, 2, 3).constrainOnce()
            println(seq.asSequence().toList())
            try {
                seq.asSequence().toList()
                println("unexpected")
            } catch (e: IllegalStateException) {
                println("constrain-once-error")
            }
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "ConstrainOnce",
            expected:
                """
                [1, 2, 3]
                constrain-once-error
                """ + "\n"
        )
    }

    @Test
    func testSequenceAnyShortCircuits() throws {
        let source = """
        var counter = 0

        fun main() {
            val found = sequenceOf(1, 2, 3, 4, 5).any { counter++; it == 2 }
            println(found)
            // any stops at element 2 → counter should be <= 2
            println(counter <= 2)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "SequenceAnyShortCircuit",
            expected:
                """
                true
                true
                """ + "\n"
        )
    }

    @Test
    func testSequenceAllShortCircuits() throws {
        let source = """
        var counter = 0

        fun main() {
            val allPositive = sequenceOf(1, -2, 3, 4, 5).all { counter++; it > 0 }
            println(allPositive)
            // all stops at element -2 → counter should be <= 2
            println(counter <= 2)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "SequenceAllShortCircuit",
            expected:
                """
                false
                true
                """ + "\n"
        )
    }

    @Test
    func testSequenceFindShortCircuits() throws {
        let source = """
        var counter = 0

        fun main() {
            val found = sequenceOf(1, 2, 3, 4, 5).find { counter++; it == 3 }
            println(found)
            // find stops at element 3 → counter should be <= 3
            println(counter <= 3)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "SequenceFindShortCircuit",
            expected:
                """
                3
                true
                """ + "\n"
        )
    }

    @Test
    func testSequenceFindLastReturnsLastMatchingValue() throws {
        let source = """
        fun main() {
            val lastEven = sequenceOf(1, 2, 3, 4, 5).findLast { value -> value % 2 == 0 }
            println(lastEven)
        }
        """

        try assertKotlinOutput(source, moduleName: "SequenceFindLastRuntime", expected: "4\n")
    }

    @Test
    func testSequenceFilterNotNullDropsNullValues() throws {
        let source = """
        fun main() {
            val values = sequenceOf(1, null, 3)
            println(values.filterNotNull().toList())
        }
        """

        try assertKotlinOutput(source, moduleName: "SequenceFilterNotNullRuntime", expected: "[1, 3]\n")
    }

    @Test
    func testSequenceFilterNotKeepsRejectedPredicateValues() throws {
        let source = """
        fun main() {
            val values = sequenceOf(1, 2, 3, 4, 5)
            println(values.filterNot { value -> value % 2 == 0 }.toList())
        }
        """

        try assertKotlinOutput(source, moduleName: "SequenceFilterNotRuntime", expected: "[1, 3, 5]\n")
    }

    @Test
    func testSequenceFilterIsInstanceToAppendsMatchingTypes() throws {
        let source = """
        fun main() {
            val values: Sequence<Any> = sequenceOf(1, "two", 3)
            val destination = mutableListOf<Int>(0)
            val result = values.filterIsInstanceTo(destination)
            println(result)
            println(destination)
        }
        """

        try assertKotlinOutput(source, moduleName: "SequenceFilterIsInstanceToRuntime", expected: "[0, 1, 3]\n[0, 1, 3]\n")
    }

    @Test
    func testSequenceFilterToAppendsMatchingValues() throws {
        let source = """
        fun main() {
            val values = sequenceOf(1, 2, 3, 4, 5)
            val destination = mutableListOf<Int>(99)
            val result = values.filterTo(destination) { value -> value % 2 == 0 }
            println(result)
            println(destination)
        }
        """

        try assertKotlinOutput(source, moduleName: "SequenceFilterToRuntime", expected: "[99, 2, 4]\n[99, 2, 4]\n")
    }

    @Test
    func testSequenceFilterNotToAppendsNonMatchingValues() throws {
        let source = """
        fun main() {
            val values = sequenceOf(1, 2, 3, 4, 5)
            val destination = mutableListOf<Int>(99)
            val result = values.filterNotTo(destination) { value -> value % 2 == 0 }
            println(result)
            println(destination)
        }
        """

        try assertKotlinOutput(source, moduleName: "SequenceFilterNotToRuntime", expected: "[99, 1, 3, 5]\n[99, 1, 3, 5]\n")
    }

    @Test
    func testSequenceOfBoxesPrimitiveElementsForFilterIsInstance() throws {
        let source = """
        fun main() {
            val mixed: Sequence<Any> = sequenceOf(1.5, "x", 2.5, 7L, true)
            println(mixed.filterIsInstance<Double>().toList())
            println(mixed.filterIsInstance<Long>().toList())
            println(mixed.filterIsInstance<Boolean>().toList())
            println(mixed.filterIsInstance<String>().toList())
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "SequenceOfBoxesPrimitives",
            expected:
                """
                [1.5, 2.5]
                [7]
                [true]
                [x]
                """ + "\n"
        )
    }

    @Test
    func testNullableSequenceOrEmptyAndSourceIteratorExecute() throws {
        let source = """
        fun main() {
            val missing: Sequence<Int>? = null
            val present: Sequence<Int>? = sequenceOf(1, 2)
            println(missing.orEmpty().toList())
            println(present.orEmpty().toList())

            val iterator = sequenceOf(3, 4).iterator()
            println(iterator.next())
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "SequenceRegistrationRuntime",
            expected: "[]\n[1, 2]\n3\n"
        )
    }

    @Test
    func testSequenceOrEmptyUsesBundledSourceCall() throws {
        let source = """
        fun normalize(input: Sequence<Int>?): Sequence<Int> = input.orEmpty()
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], moduleName: "SequenceRegistrationKIR", emit: .kirDump)
            try runToLowering(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "normalize", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)
            #expect(callees.contains("orEmpty"), "Expected the bundled orEmpty call, got: \(callees)")
            #expect(!callees.contains("kk_sequence_orEmpty"), "Legacy Sequence.orEmpty bridge must not be emitted: \(callees)")
        }
    }
}
#endif

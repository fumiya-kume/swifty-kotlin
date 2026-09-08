#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

// BUG-167: `for (x in xs)` over a value statically typed as an iterable
// *interface* (`Iterable<T>`, `Collection<T>`, ...) or as a source class
// implementing `Iterable` bound no `iterator()` in Sema, so lowering fell
// through to the range-iterator intrinsics and reinterpreted the collection
// object as a range, yielding garbage elements.

@Suite
struct CodegenBackendInterfaceIterableForLoopTests {

    @Test
    func testIterableInterfaceForLoopIteration() throws {
        let source = """
        fun f(xs: Iterable<Int>) {
            for (x in xs) {
                println(x)
            }
        }

        fun main() {
            f(listOf(0, 2, 4))
        }
        """
        try assertKotlinOutput(source, moduleName: "IterableInterfaceForLoopIteration", expected: "0\n2\n4\n")
    }

    @Test
    func testIterableInterfaceForLoopElementIsUnboxedPrimitive() throws {
        let source = """
        fun pick(s: String, indices: Iterable<Int>): String {
            val sb = StringBuilder()
            for (i in indices) {
                sb.append(s[i])
            }
            return sb.toString()
        }

        fun main() {
            println(pick("abcdef", listOf(1, 3, 5)))
        }
        """
        try assertKotlinOutput(source, moduleName: "IterableInterfaceForLoopUnboxing", expected: "bdf\n")
    }

    @Test
    func testCollectionInterfaceForLoopIteration() throws {
        let source = """
        fun sum(xs: Collection<Int>): Int {
            var total = 0
            for (x in xs) {
                total += x
            }
            return total
        }

        fun main() {
            println(sum(listOf(1, 2, 3)))
            println(sum(setOf(4, 5)))
        }
        """
        try assertKotlinOutput(source, moduleName: "CollectionInterfaceForLoopIteration", expected: "6\n9\n")
    }

    @Test
    func testIterableInterfaceForLoopContinueAndBreak() throws {
        let source = """
        fun f(xs: Iterable<Int>) {
            for (x in xs) {
                if (x == 2) continue
                if (x == 4) break
                println(x)
            }
        }

        fun main() {
            f(listOf(1, 2, 3, 4, 5))
        }
        """
        try assertKotlinOutput(source, moduleName: "IterableInterfaceForLoopContinueBreak", expected: "1\n3\n")
    }

    @Test
    func testSourceIterableClassForLoopIteration() throws {
        let source = """
        class Counter(val n: Int) : Iterable<Int> {
            override fun iterator(): Iterator<Int> = CounterIterator(n)
        }

        class CounterIterator(val n: Int) : Iterator<Int> {
            var i = 0
            override fun hasNext(): Boolean = i < n
            override fun next(): Int {
                val v = i
                i = i + 1
                return v
            }
        }

        fun main() {
            for (x in Counter(3)) {
                println(x)
            }
        }
        """
        try assertKotlinOutput(source, moduleName: "SourceIterableClassForLoopIteration", expected: "0\n1\n2\n")
    }

    @Test
    func testSourceIterableClassForLoopDestructuring() throws {
        let source = """
        class Pairs(val n: Int) : Iterable<Pair<Int, Int>> {
            override fun iterator(): Iterator<Pair<Int, Int>> = PairsIterator(n)
        }

        class PairsIterator(val n: Int) : Iterator<Pair<Int, Int>> {
            var i = 0
            override fun hasNext(): Boolean = i < n
            override fun next(): Pair<Int, Int> {
                val v = i
                i = i + 1
                return Pair(v, v * 2)
            }
        }

        fun main() {
            for ((a, b) in Pairs(3)) {
                println("" + a + ":" + b)
            }
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "SourceIterableClassForLoopDestructuring",
            expected: "0:0\n1:2\n2:4\n"
        )
    }

    @Test
    func testIterableInterfaceForLoopDestructuring() throws {
        let source = """
        fun f(ps: Iterable<Pair<Int, String>>) {
            for ((a, b) in ps) {
                println("" + a + b)
            }
        }

        fun main() {
            f(listOf(Pair(1, "a"), Pair(2, "b")))
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "IterableInterfaceForLoopDestructuring",
            expected: "1a\n2b\n"
        )
    }

    @Test
    func testIterableUnzipUsesOneIteratorAndPreservesOrder() throws {
        let source = """
        class CountingPairs : Iterable<Pair<Int, String>> {
            var iteratorCalls = 0
            var nextCalls = 0

            override fun iterator(): Iterator<Pair<Int, String>> {
                iteratorCalls += 1
                return CountingPairsIterator(this)
            }
        }

        class CountingPairsIterator(private val owner: CountingPairs) : Iterator<Pair<Int, String>> {
            private var index = 0

            override fun hasNext(): Boolean = index < 3
            override fun next(): Pair<Int, String> {
                owner.nextCalls += 1
                val pair = when (index) {
                    0 -> Pair(2, "x")
                    1 -> Pair(2, "x")
                    else -> Pair(1, "y")
                }
                index += 1
                return pair
            }
        }

        fun main() {
            val source = CountingPairs()
            val result = source.unzip()
            println(result)
            println("iterators=" + source.iteratorCalls + ", next=" + source.nextCalls)
            println("independent=" + (result.first !== result.second))
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "IterableUnzipOneIterator",
            expected: "([2, 2, 1], [x, x, y])\niterators=1, next=3\nindependent=true\n"
        )
    }

    @Test
    func testIterableInterfaceForLoopLowersToIteratorNotRangeIntrinsics() throws {
        let source = """
        fun f(xs: Iterable<Int>) {
            for (x in xs) {
                println(x)
            }
        }

        fun main() {
            f(listOf(0, 2, 4))
        }
        """
        let ctx = makeContextFromSource(source)
        try runToLowering(ctx)
        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "f", in: module, interner: ctx.interner)
        let callees = extractCallees(from: body, interner: ctx.interner)
        #expect(
            callees.contains("kk_iterator_hasNext") || callees.contains("hasNext"),
            "Iterable for-loop should use Iterator.hasNext dispatch, got: \(callees)"
        )
        #expect(
            callees.contains("kk_iterator_next") || callees.contains("next"),
            "Iterable for-loop should use Iterator.next dispatch, got: \(callees)"
        )
        #expect(
            !callees.contains("kk_range_hasNext"),
            "Iterable for-loop must not use kk_range_hasNext, got: \(callees)"
        )
        #expect(
            !callees.contains("kk_range_next"),
            "Iterable for-loop must not use kk_range_next, got: \(callees)"
        )
    }

    @Test
    func testConcreteListForLoopStillUsesListIterator() throws {
        let source = """
        fun main() {
            val xs = listOf(1, 2)
            for (x in xs) {
                println(x)
            }
        }
        """
        let ctx = makeContextFromSource(source)
        try runToLowering(ctx)
        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
        let callees = extractCallees(from: body, interner: ctx.interner)
        #expect(
            callees.contains("kk_list_iterator_next"),
            "List for-loop should keep using kk_list_iterator_next, got: \(callees)"
        )
    }

    @Test
    func testIntRangeForLoopUsesInductionVariablePath() throws {
        let source = """
        fun main() {
            for (i in 0..2) {
                println(i)
            }
        }
        """
        let ctx = makeContextFromSource(source)
        try runToLowering(ctx)
        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
        let callees = extractCallees(from: body, interner: ctx.interner)
        #expect(!callees.contains("kk_range_for_in_iterator"), "IntRange induction loop must not allocate a runtime iterator, got: \(callees)")
        #expect(!callees.contains("kk_range_for_in_hasNext"), "IntRange induction loop must not call hasNext, got: \(callees)")
        #expect(!callees.contains("kk_range_for_in_next"), "IntRange induction loop must not call next, got: \(callees)")
        #expect(!callees.contains("__kk_range_first"), "direct IntRange induction loop should not load a range object bound, got: \(callees)")
        #expect(!callees.contains("__kk_range_last"), "direct IntRange induction loop should not load a range object bound, got: \(callees)")
        #expect(callees.contains("__kk_int_range_induction_le"), "IntRange induction loop should compare bounds, got: \(callees)")
    }

    // BUG-231: `for (x in xs)` where `xs` is statically `List<T>`/`Set<T>`
    // (or a Mutable variant) and the concrete object is a hand-written class
    // implementing that interface directly (not a native runtime-backed
    // collection) silently ran zero iterations. Sema resolves these through
    // `kotlin.collections.Collection.iterator()`, whose runtime bridge
    // (`kk_list_iterator`) only recognized native list/set/array boxes and
    // fell back to an iterator over zero elements for anything else, instead
    // of dispatching to the object's own `iterator()` override like the
    // sibling bridges (`kk_iterable_iterator`, `kk_range_iterator`) already
    // do for bare `Iterable<T>`.

    @Test
    func testConcreteListInterfaceSourceClassForLoopIteration() throws {
        let source = """
        class NonNativeList : List<Int> {
            override val size: Int get() = 3
            override fun get(index: Int): Int = index
            override fun isEmpty(): Boolean = false
            override fun contains(element: Int): Boolean = true
            override fun containsAll(elements: Collection<Int>): Boolean = true
            override fun indexOf(element: Int): Int = 0
            override fun lastIndexOf(element: Int): Int = 0
            override fun listIterator(): ListIterator<Int> = throw RuntimeException("unused")
            override fun listIterator(index: Int): ListIterator<Int> = throw RuntimeException("unused2")
            override fun subList(fromIndex: Int, toIndex: Int): List<Int> = this
            override fun iterator(): Iterator<Int> {
                println("iterator() called")
                return listOf(10, 20, 30).iterator()
            }
        }

        fun main() {
            val x: List<Int> = NonNativeList()
            for (i in x) {
                println("saw " + i)
            }
            println("done")
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "ConcreteListInterfaceSourceClassForLoopIteration",
            expected: "iterator() called\nsaw 10\nsaw 20\nsaw 30\ndone\n"
        )
    }

    @Test
    func testConcreteSetInterfaceSourceClassForLoopIteration() throws {
        let source = """
        class NonNativeSet : Set<Int> {
            override val size: Int get() = 3
            override fun isEmpty(): Boolean = false
            override fun contains(element: Int): Boolean = true
            override fun containsAll(elements: Collection<Int>): Boolean = true
            override fun iterator(): Iterator<Int> {
                println("iterator() called")
                return listOf(1, 2, 3).iterator()
            }
        }

        fun main() {
            val s: Set<Int> = NonNativeSet()
            for (i in s) {
                println("saw " + i)
            }
            println("done")
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "ConcreteSetInterfaceSourceClassForLoopIteration",
            expected: "iterator() called\nsaw 1\nsaw 2\nsaw 3\ndone\n"
        )
    }

    @Test
    func testConcreteListInterfaceSourceClassWithFullyCustomIteratorForLoopIteration() throws {
        // Unlike the two tests above, this iterator does not delegate to a
        // native list/set at all, exercising the kk_list_iterator_hasNext /
        // kk_list_iterator_next fallback to the generic kk_iterator_* path
        // (RuntimeCollections.swift), not just the kk_list_iterator fallback.
        let source = """
        class CustomIntIterator : Iterator<Int> {
            var i = 0
            override fun hasNext(): Boolean = i < 3
            override fun next(): Int {
                val v = (i + 1) * 100
                i += 1
                return v
            }
        }

        class NonNativeList : List<Int> {
            override val size: Int get() = 3
            override fun get(index: Int): Int = index
            override fun isEmpty(): Boolean = false
            override fun contains(element: Int): Boolean = true
            override fun containsAll(elements: Collection<Int>): Boolean = true
            override fun indexOf(element: Int): Int = 0
            override fun lastIndexOf(element: Int): Int = 0
            override fun listIterator(): ListIterator<Int> = throw RuntimeException("unused")
            override fun listIterator(index: Int): ListIterator<Int> = throw RuntimeException("unused2")
            override fun subList(fromIndex: Int, toIndex: Int): List<Int> = this
            override fun iterator(): Iterator<Int> = CustomIntIterator()
        }

        fun main() {
            val x: List<Int> = NonNativeList()
            for (i in x) {
                println("saw " + i)
            }
            println("done")
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "ConcreteListInterfaceCustomIteratorForLoopIteration",
            expected: "saw 100\nsaw 200\nsaw 300\ndone\n"
        )
    }

    @Test
    func testConcreteMutableSetInterfaceSourceClassForLoopIteration() throws {
        let source = """
        class NamedMutableIntIterator : MutableIterator<Int> {
            var i = 0
            val values = intArrayOf(4, 5, 6)
            override fun hasNext(): Boolean = i < values.size
            override fun next(): Int {
                val v = values[i]
                i += 1
                return v
            }
            override fun remove(): Unit = throw RuntimeException("unused")
        }

        class NonNativeMutableSet : MutableSet<Int> {
            override val size: Int get() = 3
            override fun isEmpty(): Boolean = false
            override fun contains(element: Int): Boolean = true
            override fun containsAll(elements: Collection<Int>): Boolean = true
            override fun iterator(): MutableIterator<Int> = NamedMutableIntIterator()
            override fun add(element: Int): Boolean = throw RuntimeException("unused")
            override fun remove(element: Int): Boolean = throw RuntimeException("unused")
            override fun addAll(elements: Collection<Int>): Boolean = throw RuntimeException("unused")
            override fun removeAll(elements: Collection<Int>): Boolean = throw RuntimeException("unused")
            override fun retainAll(elements: Collection<Int>): Boolean = throw RuntimeException("unused")
            override fun clear(): Unit = throw RuntimeException("unused")
        }

        fun main() {
            val m: MutableSet<Int> = NonNativeMutableSet()
            for (i in m) {
                println("saw " + i)
            }
            println("done")
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "ConcreteMutableSetInterfaceSourceClassForLoopIteration",
            expected: "saw 4\nsaw 5\nsaw 6\ndone\n"
        )
    }

    @Test
    func testConcreteListInterfaceSourceClassThrowingIteratorTraps() throws {
        // kk_list_iterator has no throwing channel (unlike kk_iterable_iterator
        // / kk_range_iterator), so a hand-written List/Set whose iterator()
        // throws cannot propagate that exception as a catchable Kotlin
        // exception through this fast path today — it traps instead. This
        // pins that known, intentional limitation (loud failure, not a
        // silent wrong answer) rather than the ideal catchable-exception
        // behavior, which would require threading an outThrown channel
        // through kk_list_iterator/kk_list_iterator_hasNext/_next and the
        // corresponding KIR call sites (see ControlFlowLowerer.emitForLoopMemberCall).
        let source = """
        class ThrowingList : List<Int> {
            override val size: Int get() = 3
            override fun get(index: Int): Int = index
            override fun isEmpty(): Boolean = false
            override fun contains(element: Int): Boolean = true
            override fun containsAll(elements: Collection<Int>): Boolean = true
            override fun indexOf(element: Int): Int = 0
            override fun lastIndexOf(element: Int): Int = 0
            override fun listIterator(): ListIterator<Int> = throw RuntimeException("unused")
            override fun listIterator(index: Int): ListIterator<Int> = throw RuntimeException("unused2")
            override fun subList(fromIndex: Int, toIndex: Int): List<Int> = this
            override fun iterator(): Iterator<Int> {
                throw IllegalStateException("boom from iterator()")
            }
        }

        fun main() {
            val x: List<Int> = ThrowingList()
            for (i in x) {
                println("saw " + i)
            }
            println("unreachable")
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "ConcreteListInterfaceThrowingIteratorTraps",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            do {
                _ = try CommandRunner.run(executable: outputBase, arguments: [])
                Issue.record("Expected the hand-written List's throwing iterator() to trap")
            } catch let CommandRunnerError.nonZeroExit(failed) {
                #expect(failed.exitCode != 0)
                #expect(failed.stderr.contains("KSwiftK panic"))
                #expect(
                    failed.stderr.contains("Iterable.iterator() dispatch threw"),
                    "Expected panic message to mention the Iterable.iterator() dispatch, got: \(failed.stderr)"
                )
                #expect(!failed.stdout.contains("unreachable"))
            } catch {
                Issue.record("Unexpected error: \(error)")
            }
        }
    }
}
#endif

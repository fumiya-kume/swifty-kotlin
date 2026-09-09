#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite
struct CodegenBackendMutableCollectionEdgeCasesTests {

    @Test
    func testCodegenCompilesMutableCollectionEdgeCases() throws {
        let source = """
        fun main() {
            val zipped = listOf(1, 2, 3).zip(listOf("a", "b"))
            println(zipped)
            println(zipped.unzip().first)
            println(zipped.unzip().second)

            val map = mutableMapOf("a" to 1)
            map.putAll(mutableMapOf("b" to 2, "c" to 3))
            println(map.keys.toList())
            println(map.values.toList())

            val numbers = mutableListOf(1, 2, 3, 4, 5)
            numbers.removeAll(listOf(2, 5))
            println(numbers)

            numbers.retainAll(listOf(1, 4))
            println(numbers)

            val subtractable = mutableListOf(1, 2, 2, 3)
            subtractable -= 2
            subtractable -= listOf(3)
            println(subtractable)

            val mutableSet = mutableSetOf(1, 2, 3)
            mutableSet -= 2
            mutableSet -= listOf(3)
            println(mutableSet)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "MutableCollectionEdgeCases",
            expected:
                """
                [(1, a), (2, b)]
                [1, 2]
                [a, b]
                [a, b, c]
                [1, 2, 3]
                [1, 3, 4]
                [1, 4]
                [1, 2]
                [1]
                """ + "\n"
        )
    }

    // Regression for the covariance gap where `.iterator()` on a
    // MutableList/MutableSet/MutableCollection-typed receiver resolved to
    // Collection's `Iterator<E>` instead of the covariant `MutableIterator<E>`
    // (KSWIFTK-TYPE-0001 on any override declared `MutableIterator<E>`), and
    // the sibling gaps found alongside it: MutableList.subList returning
    // `List<E>` instead of `MutableList<E>`, and the entirely-missing
    // MutableList.listIterator(Int)/addAll(Int, Collection<E>) overloads
    // ("No viable overload found for call"). This is the exact shape of class
    // that failed to compile before the fix: a hand-written MutableList<Int>
    // implementation delegating every member to a backing mutableListOf().
    @Test
    func testCodegenClassImplementingMutableListCompilesWithCovariantIteratorSubListAndIndexedOverloads() throws {
        let source = """
        class RegressionMutableList : MutableList<Int> {
            private val backing = mutableListOf(7, 8, 9)
            override val size: Int get() = backing.size
            override fun get(index: Int): Int = backing[index]
            override fun isEmpty(): Boolean = backing.isEmpty()
            override fun contains(element: Int): Boolean = backing.contains(element)
            override fun containsAll(elements: Collection<Int>): Boolean = backing.containsAll(elements)
            override fun indexOf(element: Int): Int = backing.indexOf(element)
            override fun lastIndexOf(element: Int): Int = backing.lastIndexOf(element)
            override fun iterator(): MutableIterator<Int> = backing.iterator()
            override fun listIterator(): MutableListIterator<Int> = backing.listIterator()
            override fun listIterator(index: Int): MutableListIterator<Int> = backing.listIterator(index)
            override fun subList(fromIndex: Int, toIndex: Int): MutableList<Int> = backing.subList(fromIndex, toIndex)
            override fun set(index: Int, element: Int): Int = backing.set(index, element)
            override fun add(index: Int, element: Int) = backing.add(index, element)
            override fun removeAt(index: Int): Int = backing.removeAt(index)
            override fun add(element: Int): Boolean = backing.add(element)
            override fun remove(element: Int): Boolean = backing.remove(element)
            override fun addAll(elements: Collection<Int>): Boolean = backing.addAll(elements)
            override fun addAll(index: Int, elements: Collection<Int>): Boolean = backing.addAll(index, elements)
            override fun removeAll(elements: Collection<Int>): Boolean = backing.removeAll(elements)
            override fun retainAll(elements: Collection<Int>): Boolean = backing.retainAll(elements)
            override fun clear() = backing.clear()
        }

        fun describe(list: MutableList<Int>): String {
            val parts = mutableListOf<String>()
            for (value in list) {
                parts.add(value.toString())
            }
            return "[" + parts.joinToString(", ") + "]"
        }

        fun main() {
            val list = RegressionMutableList()
            println(describe(list))

            val it: MutableIterator<Int> = list.iterator()
            var sum = 0
            while (it.hasNext()) sum += it.next()
            println(sum)

            val sub: MutableList<Int> = list.subList(0, 2)
            println(describe(sub))

            list.add(1, 100)
            println(describe(list))

            println(list.addAll(2, listOf(200, 300)))
            println(describe(list))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "MutableListCovarianceRegression",
            expected:
                """
                [7, 8, 9]
                24
                [7, 8]
                [7, 100, 8, 9]
                true
                [7, 100, 200, 300, 8, 9]
                """ + "\n"
        )
    }

    // MutableList.iterator()/MutableSet.iterator() must report MutableIterator<E>
    // (assignability checked at the `val ...: MutableIterator<Int> = ...` sites
    // below), not just compile via type inference. for-loops go through a
    // separate resolution path (ControlFlowTypeChecker) and must keep working.
    @Test
    func testCodegenMutableListAndMutableSetIteratorReturnMutableIterator() throws {
        let source = """
        fun main() {
            val list: MutableList<Int> = mutableListOf(1, 2, 3)
            val listIter: MutableIterator<Int> = list.iterator()
            var listSum = 0
            while (listIter.hasNext()) listSum += listIter.next()
            println(listSum)

            val set: MutableSet<Int> = mutableSetOf(10, 20, 30)
            val setIter: MutableIterator<Int> = set.iterator()
            var setSum = 0
            while (setIter.hasNext()) setSum += setIter.next()
            println(setSum)

            var forSum = 0
            for (x in list) forSum += x
            println(forSum)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "MutableCollectionIteratorCovariance",
            expected: "6\n60\n6\n"
        )
    }

    // MutableList.subList(...) must report MutableList<E> (assignable, and its
    // `add` must work), not List<E>. KSwiftK's subList returns an independent
    // snapshot copy rather than a live view backed by the parent list (a
    // documented deviation from real Kotlin -- see the NOTE in
    // Sources/CompilerCore/Stdlib/kotlin/collections/ListSliceTakeDrop.kt), so
    // this only asserts the sublist's own mutability, not that mutating it is
    // visible through the parent.
    @Test
    func testCodegenMutableListSubListReturnsIndependentlyMutableList() throws {
        let source = """
        fun main() {
            val backing = mutableListOf(1, 2, 3, 4)
            val sub: MutableList<Int> = backing.subList(1, 3)
            sub.add(99)
            println(sub)
            println(backing)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "MutableListSubListCovariance",
            expected: "[2, 3, 99]\n[1, 2, 3, 4]\n"
        )
    }

    // MutableList.listIterator(index)/addAll(index, elements) were previously
    // unregistered overloads ("No viable overload found for call"). Covers
    // both the mutable and read-only listIterator(index) overload together
    // since they share the same runtime primitive (kk_list_iterator_at) with
    // different Sema-level return types.
    @Test
    func testCodegenListIteratorAtIndexAndMutableListAddAllAtIndex() throws {
        let source = """
        fun main() {
            val backing = mutableListOf(1, 2, 3)
            val mutIter: MutableListIterator<Int> = backing.listIterator(1)
            println(mutIter.next())
            println(mutIter.hasPrevious())

            val readOnly: List<Int> = listOf(1, 2, 3)
            val roIter: ListIterator<Int> = readOnly.listIterator(2)
            println(roIter.next())

            val changed = backing.addAll(1, listOf(100, 200))
            println(changed)
            println(backing)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "ListIteratorAtIndexAndAddAllAtIndex",
            expected: "2\ntrue\n3\ntrue\n[1, 100, 200, 2, 3]\n"
        )
    }

    // MutableListIterator.add/set had no external link name, so codegen fell
    // back to a direct call to the bare Kotlin name ("_add"/"_set"),
    // undefined at link time. `remove` happened to *link* anyway because
    // "_remove" collides with libc's `remove(const char *)`, silently
    // misinterpreting the iterator handle as a path instead of mutating the
    // list. `set`/`add`/`remove` require a preceding `next()` call in real
    // Kotlin (otherwise IllegalStateException), so this traverses first.
    @Test
    func testCodegenMutableListIteratorSetAddRemoveMutateBackingList() throws {
        let source = """
        fun main() {
            val backing = mutableListOf(1, 2, 3)
            val mutIter: MutableListIterator<Int> = backing.listIterator()
            mutIter.next()
            mutIter.set(99)
            println(backing)
            mutIter.next()
            mutIter.add(50)
            println(backing)
            mutIter.next()
            mutIter.remove()
            println(backing)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "MutableListIteratorSetAddRemove",
            expected: "[99, 2, 3]\n[99, 2, 50, 3]\n[99, 2, 50]\n"
        )
    }

}
#endif

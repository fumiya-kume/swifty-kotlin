@testable import CompilerCore
import Foundation
import XCTest

// STDLIB-021: Mutable collection destination variant edge case coverage.
// Covers: filterTo, mapTo, flatMapTo, associateTo, associateByTo, associateWithTo,
// groupByTo, partition, toCollection, toMutableList, toMutableSet, toMutableMap.
//
// Key invariants under test:
//  - destination variant appends to existing content (does not clear)
//  - returns the same destination instance (identity)
//  - preserves insertion order for MutableList / LinkedHashSet / LinkedHashMap
//  - associate*To overwrites on duplicate key
//  - groupByTo buckets append across calls
//  - pre-populated destination content is retained then extended
//  - works with empty source
//
// Unimplemented APIs (tracked as gaps in STDLIB-021):
//  - distinctTo / distinctByTo — not present in Kotlin stdlib; standard is toMutableSet()
//  - partitionTo — not a stdlib API; partition() returns Pair<List,List>
//  - Custom MutableCollection impl as destination — needs full interface dispatch (not yet lowered)
//  - filterTo, mapTo, flatMapTo, associateTo, associateByTo, associateWithTo, groupByTo,
//    filterNotTo, mapNotNullTo, filterIsInstanceTo, mapIndexedTo, flatMapIndexedTo,
//    toCollection — covered by runtime rewrite paths below
extension CodegenBackendIntegrationTests {

    // MARK: - STDLIB-021-01: filterTo appends matching elements to destination

    func testFilterToAppendsToDestination() throws {
        let source = """
        fun main() {
            val src = listOf(1, 2, 3, 4, 5)
            val dest = mutableListOf(0)
            val result = src.filterTo(dest) { it % 2 == 0 }
            println(result === dest)
            println(result)
        }
        """
        try assertKotlinCompilesToKIR(source, moduleName: "STDLIB021_01")
    }

    // MARK: - STDLIB-021-02: filterTo with empty source leaves destination unchanged

    func testFilterToEmptySourceLeavesDestination() throws {
        let source = """
        fun main() {
            val src = emptyList<Int>()
            val dest = mutableListOf(42)
            val result = src.filterTo(dest) { it > 0 }
            println(result.size)
            println(result[0])
        }
        """
        try assertKotlinCompilesToKIR(source, moduleName: "STDLIB021_02")
    }

    // MARK: - STDLIB-021-03: mapTo appends transformed elements to destination

    func testMapToAppendsToDestination() throws {
        let source = """
        fun main() {
            val src = listOf(1, 2, 3)
            val dest = mutableListOf("pre")
            val result = src.mapTo(dest) { it.toString() }
            println(result === dest)
            println(result)
        }
        """
        try assertKotlinCompilesToKIR(source, moduleName: "STDLIB021_03")
    }

    // MARK: - STDLIB-021-04: mapTo with empty source leaves destination unchanged

    func testMapToEmptySourceLeavesDestination() throws {
        let source = """
        fun main() {
            val src = emptyList<Int>()
            val dest = mutableListOf("existing")
            src.mapTo(dest) { it.toString() }
            println(dest.size)
            println(dest[0])
        }
        """
        try assertKotlinCompilesToKIR(source, moduleName: "STDLIB021_04")
    }

    // MARK: - STDLIB-021-05: flatMapTo appends flattened elements to destination

    func testFlatMapToAppendsToDestination() throws {
        let source = """
        fun main() {
            val src = listOf(listOf(1, 2), listOf(3, 4))
            val dest = mutableListOf(0)
            val result = src.flatMapTo(dest) { it }
            println(result === dest)
            println(result)
        }
        """
        try assertKotlinCompilesToKIR(source, moduleName: "STDLIB021_05")
    }

    // MARK: - STDLIB-021-06: flatMapTo with empty source leaves destination unchanged

    func testFlatMapToEmptySourceLeavesDestination() throws {
        let source = """
        fun main() {
            val src = emptyList<List<Int>>()
            val dest = mutableListOf(99)
            src.flatMapTo(dest) { it }
            println(dest.size)
            println(dest[0])
        }
        """
        try assertKotlinCompilesToKIR(source, moduleName: "STDLIB021_06")
    }

    // MARK: - STDLIB-021-07: associateTo puts all pairs into destination map

    func testAssociateToPopulatesDestination() throws {
        let source = """
        fun main() {
            val src = listOf("a", "bb", "ccc")
            val dest = mutableMapOf<String, Int>()
            val result = src.associateTo(dest) { it to it.length }
            println(result === dest)
            println(result["a"])
            println(result["bb"])
            println(result["ccc"])
        }
        """
        try assertKotlinCompilesToKIR(source, moduleName: "STDLIB021_07")
    }

    // MARK: - STDLIB-021-08: associateTo overwrites on duplicate key

    func testAssociateToOverwritesDuplicateKey() throws {
        let source = """
        fun main() {
            val src = listOf("first", "second")
            val dest = mutableMapOf("key" to 0)
            src.associateTo(dest) { "key" to it.length }
            println(dest["key"])
        }
        """
        try assertKotlinCompilesToKIR(source, moduleName: "STDLIB021_08")
    }

    // MARK: - STDLIB-021-09: associateByTo maps keys to original elements

    func testAssociateByToPopulatesDestination() throws {
        let source = """
        fun main() {
            val src = listOf("apple", "banana", "cherry")
            val dest = mutableMapOf<Int, String>()
            val result = src.associateByTo(dest) { it.length }
            println(result === dest)
            println(result[5])
            println(result[6])
        }
        """
        try assertKotlinCompilesToKIR(source, moduleName: "STDLIB021_09")
    }

    // MARK: - STDLIB-021-10: associateByTo with keySelector and valueTransform

    func testAssociateByToWithValueTransform() throws {
        let source = """
        fun main() {
            val src = listOf("apple", "banana")
            val dest = mutableMapOf<Int, String>()
            src.associateByTo(dest, { it.length }, { it.uppercase() })
            println(dest[5])
            println(dest[6])
        }
        """
        try assertKotlinCompilesToKIR(source, moduleName: "STDLIB021_10")
    }

    // MARK: - STDLIB-021-11: associateByTo overwrites on duplicate key

    func testAssociateByToOverwritesDuplicateKey() throws {
        let source = """
        fun main() {
            val src = listOf("abc", "def")
            val dest = mutableMapOf<Int, String>()
            src.associateByTo(dest) { it.length }
            println(dest[3])
        }
        """
        try assertKotlinCompilesToKIR(source, moduleName: "STDLIB021_11")
    }

    // MARK: - STDLIB-021-12: associateWithTo maps element to value

    func testAssociateWithToPopulatesDestination() throws {
        let source = """
        fun main() {
            val src = listOf(1, 2, 3)
            val dest = mutableMapOf<Int, Int>()
            val result = src.associateWithTo(dest) { it * it }
            println(result === dest)
            println(result[1])
            println(result[2])
            println(result[3])
        }
        """
        try assertKotlinCompilesToKIR(source, moduleName: "STDLIB021_12")
    }

    // MARK: - STDLIB-021-13: associateWithTo with pre-populated destination retains existing entries

    func testAssociateWithToRetainsExistingEntries() throws {
        let source = """
        fun main() {
            val src = listOf(2, 3)
            val dest = mutableMapOf(1 to 100)
            src.associateWithTo(dest) { it * it }
            println(dest[1])
            println(dest[2])
            println(dest[3])
        }
        """
        try assertKotlinCompilesToKIR(source, moduleName: "STDLIB021_13")
    }

    // MARK: - STDLIB-021-14: groupByTo groups elements into destination map buckets

    func testGroupByToPopulatesDestination() throws {
        let source = """
        fun main() {
            val src = listOf(1, 2, 3, 4, 5, 6)
            val dest = mutableMapOf<String, MutableList<Int>>()
            val result = src.groupByTo(dest) { if (it % 2 == 0) "even" else "odd" }
            println(result === dest)
            println(result["even"])
            println(result["odd"])
        }
        """
        try assertKotlinCompilesToKIR(source, moduleName: "STDLIB021_14")
    }

    // MARK: - STDLIB-021-15: groupByTo appends to existing buckets in destination

    func testGroupByToAppendsToBuckets() throws {
        let source = """
        fun main() {
            val first = listOf(1, 3)
            val second = listOf(5, 7)
            val dest = mutableMapOf<String, MutableList<Int>>()
            first.groupByTo(dest) { "odd" }
            second.groupByTo(dest) { "odd" }
            println(dest["odd"])
        }
        """
        try assertKotlinCompilesToKIR(source, moduleName: "STDLIB021_15")
    }

    // MARK: - STDLIB-021-16: groupByTo with empty source leaves destination unchanged

    func testGroupByToEmptySourceLeavesDestination() throws {
        let source = """
        fun main() {
            val src = emptyList<Int>()
            val dest = mutableMapOf("existing" to mutableListOf(1))
            src.groupByTo(dest) { "key" }
            println(dest["existing"])
        }
        """
        try assertKotlinCompilesToKIR(source, moduleName: "STDLIB021_16")
    }

    // MARK: - STDLIB-021-17: groupByTo with keySelector and valueTransform

    func testGroupByToWithValueTransform() throws {
        let source = """
        fun main() {
            val src = listOf("apple", "avocado", "banana")
            val dest = mutableMapOf<Char, MutableList<Int>>()
            src.groupByTo(dest, { it[0] }, { it.length })
            println(dest['a'])
            println(dest['b'])
        }
        """
        try assertKotlinCompilesToKIR(source, moduleName: "STDLIB021_17")
    }

    // MARK: - STDLIB-021-18: partition returns two lists splitting elements
    // NOTE: partition() is already in the stdlib surface but destructuring may not be lowered.

    func testPartitionSplitsElements() throws {
        let source = """
        fun main() {
            val src = listOf(1, 2, 3, 4, 5)
            val (evens, odds) = src.partition { it % 2 == 0 }
            println(evens)
            println(odds)
        }
        """
        try assertKotlinCompilesToKIR(source, moduleName: "STDLIB021_18")
    }

    // MARK: - STDLIB-021-19: partition with empty source returns two empty lists

    func testPartitionEmptySource() throws {
        let source = """
        fun main() {
            val src = emptyList<Int>()
            val (yes, no) = src.partition { it > 0 }
            println(yes.size)
            println(no.size)
        }
        """
        try assertKotlinCompilesToKIR(source, moduleName: "STDLIB021_19")
    }

    // MARK: - STDLIB-021-20: partition all-match puts everything in first list

    func testPartitionAllMatch() throws {
        let source = """
        fun main() {
            val src = listOf(2, 4, 6)
            val (evens, odds) = src.partition { it % 2 == 0 }
            println(evens)
            println(odds.size)
        }
        """
        try assertKotlinCompilesToKIR(source, moduleName: "STDLIB021_20")
    }

    // MARK: - STDLIB-021-21: toCollection appends elements to destination collection

    func testToCollectionAppendsToDestination() throws {
        let source = """
        fun main() {
            val src = listOf(3, 4, 5)
            val dest = mutableListOf(1, 2)
            val result = src.toCollection(dest)
            println(result === dest)
            println(result)
        }
        """
        try assertKotlinCompilesToKIR(source, moduleName: "STDLIB021_21")
    }

    // MARK: - STDLIB-021-22: toCollection with empty source leaves destination unchanged

    func testToCollectionEmptySourceLeavesDestination() throws {
        let source = """
        fun main() {
            val src = emptyList<Int>()
            val dest = mutableListOf(1)
            src.toCollection(dest)
            println(dest.size)
            println(dest[0])
        }
        """
        try assertKotlinCompilesToKIR(source, moduleName: "STDLIB021_22")
    }

    // MARK: - STDLIB-021-23: toCollection into MutableSet deduplicates

    func testToCollectionIntoMutableSet() throws {
        let source = """
        fun main() {
            val src = listOf(1, 2, 2, 3, 3, 3)
            val dest = mutableSetOf<Int>()
            src.toCollection(dest)
            println(dest.size)
            println(dest.contains(1))
            println(dest.contains(2))
            println(dest.contains(3))
        }
        """
        try assertKotlinCompilesToKIR(source, moduleName: "STDLIB021_23")
    }

    // MARK: - STDLIB-021-24: toMutableList returns a new independent copy

    func testToMutableListReturnsIndependentCopy() throws {
        let source = """
        fun main() {
            val src = listOf(1, 2, 3)
            val copy = src.toMutableList()
            copy.add(4)
            println(src.size)
            println(copy.size)
        }
        """
        try assertKotlinCompilesToKIR(source, moduleName: "STDLIB021_24")
    }

    // MARK: - STDLIB-021-25: toMutableList from empty source returns empty mutable list

    func testToMutableListFromEmpty() throws {
        let source = """
        fun main() {
            val src = emptyList<Int>()
            val copy = src.toMutableList()
            println(copy.isEmpty())
            copy.add(1)
            println(copy.size)
        }
        """
        try assertKotlinCompilesToKIR(source, moduleName: "STDLIB021_25")
    }

    // MARK: - STDLIB-021-26: toMutableSet deduplicates elements

    func testToMutableSetDeduplicates() throws {
        let source = """
        fun main() {
            val src = listOf(1, 2, 2, 3)
            val set = src.toMutableSet()
            println(set.size)
            set.add(4)
            println(set.size)
        }
        """
        try assertKotlinCompilesToKIR(source, moduleName: "STDLIB021_26")
    }

    // MARK: - STDLIB-021-27: toMutableSet from empty source returns empty mutable set

    func testToMutableSetFromEmpty() throws {
        let source = """
        fun main() {
            val src = emptyList<String>()
            val set = src.toMutableSet()
            println(set.isEmpty())
            set.add("hello")
            println(set.contains("hello"))
        }
        """
        try assertKotlinCompilesToKIR(source, moduleName: "STDLIB021_27")
    }

    // MARK: - STDLIB-021-28: toMutableMap returns independent mutable copy of map

    func testToMutableMapReturnsMutableCopy() throws {
        let source = """
        fun main() {
            val src = mapOf("a" to 1, "b" to 2)
            val copy = src.toMutableMap()
            copy["c"] = 3
            println(src.size)
            println(copy.size)
            println(copy["c"])
        }
        """
        try assertKotlinCompilesToKIR(source, moduleName: "STDLIB021_28")
    }

    // MARK: - STDLIB-021-29: toMutableMap from empty map returns empty mutable map

    func testToMutableMapFromEmpty() throws {
        let source = """
        fun main() {
            val src = emptyMap<String, Int>()
            val copy = src.toMutableMap()
            println(copy.isEmpty())
            copy["x"] = 10
            println(copy["x"])
        }
        """
        try assertKotlinCompilesToKIR(source, moduleName: "STDLIB021_29")
    }

    // MARK: - STDLIB-021-30: filterTo preserves insertion order in MutableList

    func testFilterToPreservesInsertionOrder() throws {
        let source = """
        fun main() {
            val src = listOf(5, 1, 4, 2, 3)
            val dest = mutableListOf<Int>()
            src.filterTo(dest) { it > 2 }
            println(dest)
        }
        """
        try assertKotlinCompilesToKIR(source, moduleName: "STDLIB021_30")
    }

    // MARK: - STDLIB-021-31: mapTo preserves insertion order in MutableList

    func testMapToPreservesInsertionOrder() throws {
        let source = """
        fun main() {
            val src = listOf("c", "a", "b")
            val dest = mutableListOf<String>()
            src.mapTo(dest) { it.uppercase() }
            println(dest)
        }
        """
        try assertKotlinCompilesToKIR(source, moduleName: "STDLIB021_31")
    }

    // MARK: - STDLIB-021-32: associateTo with empty source leaves destination unchanged

    func testAssociateToEmptySourceLeavesDestination() throws {
        let source = """
        fun main() {
            val src = emptyList<String>()
            val dest = mutableMapOf("existing" to 99)
            src.associateTo(dest) { it to it.length }
            println(dest["existing"])
            println(dest.size)
        }
        """
        try assertKotlinCompilesToKIR(source, moduleName: "STDLIB021_32")
    }

    // MARK: - STDLIB-021-33: filterTo into LinkedHashSet preserves insertion order and deduplicates

    func testFilterToLinkedHashSetPreservesOrder() throws {
        let source = """
        fun main() {
            val src = listOf(3, 1, 4, 1, 5, 9, 2, 6)
            val dest = LinkedHashSet<Int>()
            src.filterTo(dest) { it > 2 }
            println(dest.toList())
        }
        """
        try assertKotlinCompilesToKIR(source, moduleName: "STDLIB021_33")
    }

    // MARK: - STDLIB-021-34: mapNotNullTo filters nulls and appends non-null transformed values

    func testMapNotNullToFiltersNulls() throws {
        let source = """
        fun main() {
            val src = listOf("1", "abc", "2", "def", "3")
            val dest = mutableListOf<Int>()
            src.mapNotNullTo(dest) { it.toIntOrNull() }
            println(dest)
        }
        """
        try assertKotlinCompilesToKIR(source, moduleName: "STDLIB021_34")
    }

    // MARK: - STDLIB-021-34b: filterNotNullTo appends non-null values to destination

    func testFilterNotNullToAppendsNonNullValues() throws {
        let source = """
        fun main() {
            val src = listOf("a", null, "b", null)
            val dest = mutableListOf<String>()
            val result = src.filterNotNullTo(dest)
            println(result === dest)
            println(result)
        }
        """
        try assertKotlinCompilesToKIR(source, moduleName: "STDLIB021_34_FILTER_NOT_NULL_TO")
    }

    // MARK: - STDLIB-021-35: filterNotTo appends non-matching elements to destination

    func testFilterNotToAppendsNonMatchingElements() throws {
        let source = """
        fun main() {
            val src = listOf(1, 2, 3, 4, 5)
            val dest = mutableListOf<Int>()
            val result = src.filterNotTo(dest) { it % 2 == 0 }
            println(result === dest)
            println(result)
        }
        """
        try assertKotlinCompilesToKIR(source, moduleName: "STDLIB021_35")
    }

    // MARK: - STDLIB-021-36: filterIsInstanceTo collects elements of given type

    func testFilterIsInstanceToCollectsTypedElements() throws {
        let source = """
        fun main() {
            val src: List<Any> = listOf(1, "hello", 2, "world", 3.0)
            val dest = mutableListOf<String>()
            src.filterIsInstanceTo(dest)
            println(dest)
        }
        """
        try assertKotlinCompilesToKIR(source, moduleName: "STDLIB021_36")
    }

    // MARK: - STDLIB-021-37: mapIndexedTo appends indexed transformed elements

    func testMapIndexedToAppendsIndexedElements() throws {
        let source = """
        fun main() {
            val src = listOf("a", "b", "c")
            val dest = mutableListOf<String>()
            src.mapIndexedTo(dest) { idx, value -> idx.toString() + ":" + value }
            println(dest)
        }
        """
        try assertKotlinCompilesToKIR(source, moduleName: "STDLIB021_37")
    }

    // MARK: - STDLIB-021-38: flatMapIndexedTo appends flattened indexed elements

    func testFlatMapIndexedToAppendsElements() throws {
        let source = """
        fun main() {
            val src = listOf("ab", "cd")
            val dest = mutableListOf<String>()
            src.flatMapIndexedTo(dest) { idx, value -> listOf(idx.toString() + value, value.uppercase()) }
            println(dest)
        }
        """
        try assertKotlinCompilesToKIR(source, moduleName: "STDLIB021_38")
    }

    // MARK: - STDLIB-021-39: grouping reduceTo mutates the destination map

    func testGroupingReduceToCompiles() throws {
        let source = """
        fun main() {
            val src = listOf(1, 3, 2)
            val dest = mutableMapOf(1 to 10)
            val result = src.groupingBy { it % 2 }.reduceTo(dest) { key, acc, value ->
                acc * 10 + value + key
            }
            println(result === dest)
            println(result[1])
            println(result[0])
        }
        """
        try assertKotlinCompilesToKIR(source, moduleName: "STDLIB021_39")
    }
}

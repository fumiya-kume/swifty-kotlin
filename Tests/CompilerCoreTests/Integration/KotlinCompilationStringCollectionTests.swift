@testable import CompilerCore
import Foundation
import XCTest

/// Integration tests for the String stdlib extensions and mutable collection
/// operations added or improved in this PR (string-stdlib-and-runtime-parity).
final class KotlinCompilationStringCollectionTests: XCTestCase {
    // MARK: - String case conversion

    func testCompile_string_lowercase() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val s = "Hello World"
            val lower = s.lowercase()
        }
        """)
    }

    func testCompile_string_uppercase() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val s = "hello world"
            val upper = s.uppercase()
        }
        """)
    }

    // MARK: - String nullable conversions

    func testCompile_string_toIntOrNull_validInput() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val result: Int? = "42".toIntOrNull()
        }
        """)
    }

    func testCompile_string_toIntOrNull_invalidInput() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val result: Int? = "abc".toIntOrNull()
        }
        """)
    }

    func testCompile_string_toDoubleOrNull() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val result: Double? = "3.14".toDoubleOrNull()
        }
        """)
    }

    // MARK: - String search

    func testCompile_string_indexOf() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val s = "hello world"
            val idx = s.indexOf("world")
        }
        """)
    }

    func testCompile_string_lastIndexOf() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val s = "aababc"
            val idx = s.lastIndexOf("ab")
        }
        """)
    }

    // MARK: - String transformation

    func testCompile_string_repeat() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val s = "ab".repeat(3)
        }
        """)
    }

    func testCompile_string_reversed() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val s = "hello".reversed()
        }
        """)
    }

    func testCompile_string_toList() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val chars = "hello".toList()
        }
        """)
    }

    // MARK: - String padding

    func testCompile_string_padStart() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val s = "42".padStart(5, '0')
        }
        """)
    }

    func testCompile_string_padEnd() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val s = "hi".padEnd(5, '-')
        }
        """)
    }

    // MARK: - String slicing

    func testCompile_string_drop() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val s = "hello".drop(2)
        }
        """)
    }

    func testCompile_string_take() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val s = "hello".take(3)
        }
        """)
    }

    func testCompile_string_dropLast() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val s = "hello".dropLast(2)
        }
        """)
    }

    func testCompile_string_takeLast() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val s = "hello".takeLast(3)
        }
        """)
    }

    // MARK: - Mutable collections

    func testCompile_collection_mutableListOf_addRemove() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val list = mutableListOf(1, 2, 3)
            list.add(4)
            list.removeAt(0)
        }
        """)
    }

    func testCompile_collection_mutableListOf_clear() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val list = mutableListOf("a", "b", "c")
            list.clear()
        }
        """)
    }

    func testCompile_collection_setOf() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val s = setOf(1, 2, 3)
            val has = s.contains(2)
        }
        """)
    }

    func testCompile_collection_mutableSetOf_addRemove() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val s = mutableSetOf(1, 2)
            s.add(3)
            s.remove(1)
        }
        """)
    }

    func testCompile_collection_mutableMapOf_putRemove() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val m = mutableMapOf("a" to 1)
            m.put("b", 2)
            m.remove("a")
        }
        """)
    }

    func testCompile_collection_buildMap() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val m = buildMap {
                put("a", 1)
                put("b", 2)
            }
        }
        """)
    }

    func testCompile_collection_listConversions() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val list = listOf(3, 1, 2)
            val mutable = list.toMutableList()
            val set = list.toSet()
            val sorted = list.sorted()
            val reversed = list.reversed()
        }
        """)
    }

    // MARK: - Chained string operations

    func testCompile_string_chainedOperations() throws {
        try assertKotlinCompilesToKIR("""
        fun normalize(s: String): String {
            return s.trim().lowercase()
        }
        fun main() { normalize("  Hello  ") }
        """)
    }

    func testCompile_string_nullableChain() throws {
        try assertKotlinCompilesToKIR("""
        fun tryParse(s: String?): Int {
            return s?.toIntOrNull() ?: 0
        }
        fun main() { tryParse("42") }
        """)
    }
}

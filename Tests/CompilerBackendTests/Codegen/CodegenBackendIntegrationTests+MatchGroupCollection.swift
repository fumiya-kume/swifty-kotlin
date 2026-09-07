#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite
struct CodegenBackendMatchGroupCollectionTests {

    // STDLIB-TEXT-TYPE-008: MatchGroupCollection interface — index access, named access, size
    @Test func testMatchGroupCollectionIndexAccess() throws {
        let source = """
        fun main() {
            val r = Regex("(\\\\w+)-(\\\\w+)")
            val m = r.find("hello-world")
            println(m?.groups?.get(0)?.value)
            println(m?.groups?.get(1)?.value)
            println(m?.groups?.get(2)?.value)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "MatchGroupCollectionIndex",
            expected:
                """
                hello-world
                hello
                world
                """ + "\n"
        )
    }

    @Test func testMatchGroupCollectionNamedAccess() throws {
        let source = """
        fun main() {
            val r = Regex("(?<year>\\\\d{4})-(?<month>\\\\d{2})-(?<day>\\\\d{2})")
            val m = r.find("2025-06-09")
            println(m?.groups?.get("year")?.value)
            println(m?.groups?.get("month")?.value)
            println(m?.groups?.get("day")?.value)
            try {
                println(m?.groups?.get("missing"))
            } catch (e: IllegalArgumentException) {
                println("invalid-name")
            }
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "MatchGroupCollectionNamed",
            expected:
                """
                2025
                06
                09
                invalid-name
                """ + "\n"
        )
    }

    @Test func testMatchGroupCollectionSize() throws {
        let source = """
        fun main() {
            val r = Regex("(\\\\w+)-(\\\\w+)-(\\\\w+)")
            val m = r.find("a-b-c")
            println(m?.groups?.size)
            val r2 = Regex("\\\\w+")
            val m2 = r2.find("hello")
            println(m2?.groups?.size)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "MatchGroupCollectionSize",
            expected:
                """
                4
                1
                """ + "\n"
        )
    }

    // Regression for constructor-call lowering: Regex(pattern) must flatten
    // its String argument and call the __kk_regex_create_flat factory directly.
    @Test func testRegexConstructionFromStringLiteralAndBasicUse() throws {
        let source = """
        fun main() {
            val r = Regex("\\\\w+")
            println(r.containsMatchIn("hello world"))
            println(r.matches("hello"))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "RegexConstructionAndUse",
            expected:
                """
                true
                true
                """ + "\n"
        )
    }

    @Test func testMatchGroupCollectionOutOfBoundsReturnsNull() throws {
        let source = """
        fun main() {
            val r = Regex("(\\\\d+)")
            val m = r.find("42")
            println(m?.groups?.get(0)?.value)
            println(m?.groups?.get(99))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "MatchGroupCollectionOutOfBounds",
            expected:
                """
                42
                null
                """ + "\n"
        )
    }

    // KSP-1430: direct construction must preserve both primary-constructor
    // properties without involving a Regex runtime bridge.
    @Test func testMatchGroupConstructorStoresValueAndRange() throws {
        let source = """
        fun main() {
            val group = MatchGroup("capture", 2..5)
            println(group.value)
            println(group.range.first)
            println(group.range.last)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "MatchGroupConstructor",
            expected:
                """
                capture
                2
                5
                """ + "\n"
        )
    }
}
#endif

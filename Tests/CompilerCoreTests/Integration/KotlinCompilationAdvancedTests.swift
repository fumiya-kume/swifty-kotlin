@testable import CompilerCore
import Foundation
import XCTest

/// Tests for advanced Kotlin features: extensions, lambdas, operators,
/// delegation, destructuring, try/catch, scope functions, collections,
/// ranges, and complex programs. Also includes object emission tests.
final class KotlinCompilationAdvancedTests: XCTestCase {

    /// Verify extension function on Int compiles.
    func testCompile_extension_function() throws {
        try assertKotlinCompilesToKIR("""
        fun Int.isEven(): Boolean = this % 2 == 0
        fun main() {
            val result = 4.isEven()
        }
        """)
    }

    /// Verify extension property compiles.
    func testCompile_extension_property() throws {
        try assertKotlinCompilesToKIR("""
        val String.lastChar: Char
            get() = this[this.length - 1]
        fun main() {
            val c = "hello".lastChar
        }
        """)
    }

    /// Verify extension function on custom class compiles.
    func testCompile_extension_onCustomClass() throws {
        try assertKotlinCompilesToKIR("""
        class Box(val value: Int)
        fun Box.doubled(): Int = this.value * 2
        fun main() {
            val b = Box(5)
            b.doubled()
        }
        """)
    }

    /// Verify basic lambda compiles.
    func testCompile_lambda_basic() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val square = { x: Int -> x * x }
            square(5)
        }
        """)
    }

    /// Verify lambda with implicit it parameter compiles.
    func testCompile_lambda_it() throws {
        try assertKotlinCompilesToKIR("""
        fun applyToTen(f: (Int) -> Int): Int = f(10)
        fun main() {
            applyToTen { it * 2 }
        }
        """)
    }

    /// Verify higher-order function compiles.
    func testCompile_higherOrder_function() throws {
        try assertKotlinCompilesToKIR("""
        fun operate(a: Int, b: Int, op: (Int, Int) -> Int): Int = op(a, b)
        fun main() {
            operate(3, 4) { x, y -> x + y }
        }
        """)
    }

    /// Verify trailing lambda syntax compiles.
    func testCompile_lambda_trailingLambda() throws {
        try assertKotlinCompilesToKIR("""
        fun repeat(times: Int, action: (Int) -> Unit) {
            for (i in 0..times - 1) {
                action(i)
            }
        }
        fun main() {
            repeat(3) { i ->
                val x = i * 2
            }
        }
        """)
    }

    /// Verify operator plus overloading compiles.
    func testCompile_operator_plus() throws {
        try assertKotlinCompilesToKIR("""
        data class Vec(val x: Int, val y: Int) {
            operator fun plus(other: Vec): Vec = Vec(x + other.x, y + other.y)
        }
        fun main() {
            val v = Vec(1, 2) + Vec(3, 4)
        }
        """)
    }

    /// Verify Comparable with compareTo operator compiles.
    func testCompile_operator_compareTo() throws {
        try assertKotlinCompilesToKIR("""
        class Weight(val grams: Int) : Comparable<Weight> {
            override operator fun compareTo(other: Weight): Int = grams - other.grams
        }
        fun main() {
            val heavy = Weight(100) > Weight(50)
        }
        """)
    }

    /// Verify invoke operator compiles.
    func testCompile_operator_invoke() throws {
        try assertKotlinCompilesToKIR("""
        class Multiplier(val factor: Int) {
            operator fun invoke(x: Int): Int = x * factor
        }
        fun main() {
            val double = Multiplier(2)
            double(5)
        }
        """)
    }

    /// Verify lazy delegation compiles.
    func testCompile_delegate_lazy() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val x: Int by lazy { 42 }
        }
        """)
    }

    /// Verify data class destructuring compiles.
    func testCompile_destructuring_dataClass() throws {
        try assertKotlinCompilesToKIR("""
        data class Point(val x: Int, val y: Int)
        fun main() {
            val (x, y) = Point(3, 4)
        }
        """)
    }

    /// Verify try-catch expression compiles.
    func testCompile_tryCatch_basic() throws {
        try assertKotlinCompilesToKIR("""
        fun safeDivide(a: Int, b: Int): Int {
            return try {
                a / b
            } catch (e: Exception) {
                0
            }
        }
        fun main() { safeDivide(10, 0) }
        """)
    }

    /// Verify try-catch-finally compiles.
    func testCompile_tryCatch_finally() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            var result = 0
            try {
                result = 42
            } catch (e: Exception) {
                result = -1
            } finally {
                val cleanup = true
            }
        }
        """)
    }

    /// Verify throw with Nothing return type compiles.
    func testCompile_throw_nothing() throws {
        try assertKotlinCompilesToKIR("""
        fun fail(msg: String): Nothing {
            throw RuntimeException(msg)
        }
        fun main() {
            try {
                fail("oops")
            } catch (e: Exception) {
            }
        }
        """)
    }

    /// Verify let scope function compiles.
    func testCompile_scope_let() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val result = "Hello".let { it.length }
        }
        """)
    }

    /// Verify run scope function compiles.
    func testCompile_scope_run() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val result = "Hello".run { length }
        }
        """)
    }

    /// Verify apply scope function compiles.
    func testCompile_scope_apply() throws {
        try assertKotlinCompilesToKIR("""
        class Builder {
            var x: Int = 0
            var y: Int = 0
        }
        fun main() {
            val b = Builder().apply {
                x = 10
                y = 20
            }
        }
        """)
    }

    /// Verify also scope function compiles.
    func testCompile_scope_also() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val result = "Hello".also { val len = it.length }
        }
        """)
    }

    /// Verify listOf compiles.
    func testCompile_collection_listOf() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val list = listOf(1, 2, 3, 4, 5)
        }
        """)
    }

    /// Verify arrayOf with index access compiles.
    func testCompile_collection_arrayOf() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val arr = arrayOf(1, 2, 3)
            val first = arr[0]
        }
        """)
    }

    /// Verify mapOf with to infix compiles.
    func testCompile_collection_mapOf() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val map = mapOf("a" to 1, "b" to 2, "c" to 3)
        }
        """)
    }

    /// Verify IntRange with in operator compiles.
    func testCompile_range_intRange() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val r = 1..10
            val contains = 5 in r
        }
        """)
    }

    /// Verify downTo range compiles.
    func testCompile_range_downTo() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            for (i in 10 downTo 1) {
                val x = i
            }
        }
        """)
    }

    /// Verify step range compiles.
    func testCompile_range_step() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            for (i in 0..20 step 2) {
                val x = i
            }
        }
        """)
    }

    /// Verify infix function compiles.
    func testCompile_infix_function() throws {
        try assertKotlinCompilesToKIR("""
        infix fun Int.power(exp: Int): Int {
            var result = 1
            for (i in 1..exp) {
                result = result * this
            }
            return result
        }
        fun main() {
            val r = 2 power 8
        }
        """)
    }

    /// Verify tailrec function compiles.
    func testCompile_tailrec_function() throws {
        try assertKotlinCompilesToKIR("""
        tailrec fun gcd(a: Int, b: Int): Int {
            if (b == 0) return a
            return gcd(b, a % b)
        }
        fun main() { gcd(48, 18) }
        """)
    }

    /// Verify top-level properties compile.
    func testCompile_topLevel_property() throws {
        try assertKotlinCompilesToKIR("""
        val PI = 3.14159
        val TAU = PI * 2.0
        fun main() {
            val x = PI
        }
        """)
    }

    /// Verify const val compiles.
    func testCompile_constVal() throws {
        try assertKotlinCompilesToKIR("""
        const val MAX_SIZE = 100
        fun main() {
            val x = MAX_SIZE
        }
        """)
    }

    /// Verify named and default arguments compile.
    func testCompile_namedArguments() throws {
        try assertKotlinCompilesToKIR("""
        fun createUser(name: String, age: Int, active: Boolean = true): String {
            return name
        }
        fun main() {
            createUser(name = "Alice", age = 30)
            createUser(age = 25, name = "Bob", active = false)
        }
        """)
    }

    /// Verify vararg parameter compiles.
    func testCompile_vararg() throws {
        try assertKotlinCompilesToKIR("""
        fun sum(vararg numbers: Int): Int {
            var total = 0
            for (n in numbers) {
                total = total + n
            }
            return total
        }
        fun main() { sum(1, 2, 3, 4, 5) }
        """)
    }

    /// Verify type alias compiles.
    func testCompile_typeAlias() throws {
        try assertKotlinCompilesToKIR("""
        typealias StringList = List<String>
        fun first(list: StringList): String = list[0]
        fun main() {
            first(listOf("a", "b"))
        }
        """)
    }

    /// Verify overloaded functions compile.
    func testCompile_overload() throws {
        try assertKotlinCompilesToKIR("""
        fun display(value: Int): String = "int"
        fun display(value: String): String = "string"
        fun display(value: Boolean): String = "bool"
        fun main() {
            display(42)
            display("hi")
            display(true)
        }
        """)
    }

    /// Verify multi-file compilation works.
    func testCompile_multiFile() throws {
        try withTemporaryFiles(contents: [
            """
            fun helper(): Int = 42
            """,
            """
            fun main() {
                val x = helper()
            }
            """,
        ]) { paths in
            let fm = FileManager.default
            let outputBase = fm.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            defer { try? fm.removeItem(atPath: outputBase + ".kir") }

            let options = makeTestOptions(
                moduleName: "MultiFile",
                inputs: paths,
                outputPath: outputBase,
                emit: .kirDump
            )
            let result = makeTestDriver().runForTesting(options: options)

            XCTAssertEqual(result.exitCode, 0)
            XCTAssertFalse(result.diagnostics.contains(where: { $0.severity == .error }))
        }
    }

    /// Verify generic linked list compiles.
    func testCompile_complex_linkedList() throws {
        try assertKotlinCompilesToKIR("""
        class Node<T>(val value: T, var next: Node<T>?)

        fun <T> buildList(vararg items: T): Node<T>? {
            var head: Node<T>? = null
            for (i in items.size - 1 downTo 0) {
                head = Node(items[i], head)
            }
            return head
        }

        fun main() {
            val list = buildList(1, 2, 3)
        }
        """)
    }

    /// Verify strategy design pattern compiles.
    func testCompile_complex_strategyPattern() throws {
        try assertKotlinCompilesToKIR("""
        interface SortStrategy {
            fun sort(data: List<Int>): List<Int>
        }

        class BubbleSort : SortStrategy {
            override fun sort(data: List<Int>): List<Int> = data
        }

        class Sorter(val strategy: SortStrategy) {
            fun execute(data: List<Int>): List<Int> = strategy.sort(data)
        }

        fun main() {
            val sorter = Sorter(BubbleSort())
            sorter.execute(listOf(3, 1, 2))
        }
        """)
    }

    /// Verify builder pattern compiles.
    func testCompile_complex_builderPattern() throws {
        try assertKotlinCompilesToKIR("""
        class Config(
            val host: String,
            val port: Int,
            val debug: Boolean
        ) {
            class Builder {
                var host: String = "localhost"
                var port: Int = 8080
                var debug: Boolean = false

                fun host(h: String): Builder { host = h; return this }
                fun port(p: Int): Builder { port = p; return this }
                fun debug(d: Boolean): Builder { debug = d; return this }
                fun build(): Config = Config(host, port, debug)
            }
        }

        fun main() {
            val cfg = Config.Builder()
                .host("example.com")
                .port(443)
                .debug(true)
                .build()
        }
        """)
    }
}

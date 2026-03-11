@testable import CompilerCore
import Foundation
import XCTest

final class KotlinCompilationBasicTests: XCTestCase {
    func testCompile_function_expressionBody() throws {
        try assertKotlinCompilesToKIR("""
        fun add(a: Int, b: Int) = a + b
        fun main() = add(1, 2)
        """)
    }

    func testCompile_function_blockBody() throws {
        try assertKotlinCompilesToKIR("""
        fun greet(name: String): String {
            val msg = "Hello, " + name
            return msg
        }
        fun main() { greet("World") }
        """)
    }

    func testCompile_function_unitReturn() throws {
        try assertKotlinCompilesToKIR("""
        fun doNothing() {
        }
        fun main() { doNothing() }
        """)
    }

    func testCompile_function_multipleParameters() throws {
        try assertKotlinCompilesToKIR("""
        fun compute(a: Int, b: Int, c: Int): Int {
            return a * b + c
        }
        fun main() { compute(2, 3, 4) }
        """)
    }

    func testCompile_function_recursion() throws {
        try assertKotlinCompilesToKIR("""
        fun factorial(n: Int): Int {
            if (n <= 1) return 1
            return n * factorial(n - 1)
        }
        fun main() { factorial(5) }
        """)
    }

    func testCompile_variable_valAndVar() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val x = 10
            var y = 20
            y = x + y
        }
        """)
    }

    func testCompile_variable_typeInference() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val s = "hello"
            val n = 42
            val b = true
            val d = 3.14
        }
        """)
    }

    func testCompile_variable_explicitTypes() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val x: Int = 10
            val s: String = "hello"
            val b: Boolean = false
            val l: Long = 100L
        }
        """)
    }

    func testCompile_string_concatenation() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val a = "Hello"
            val b = "World"
            val c = a + ", " + b + "!"
        }
        """)
    }

    func testCompile_string_template() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val name = "Kotlin"
            val version = 2
            val msg = "Language: $name version $version"
        }
        """)
    }

    func testCompile_string_templateExpression() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val x = 10
            val y = 20
            val result = "Sum is ${x + y}"
        }
        """)
    }

    func testCompile_string_rawString() throws {
        try assertKotlinCompilesToKIR(#"""
        fun main() {
            val text = """
                |Hello
                |World
            """.trimMargin()
        }
        """#)
    }

    func testCompile_controlFlow_ifElse() throws {
        try assertKotlinCompilesToKIR("""
        fun max(a: Int, b: Int): Int {
            return if (a > b) a else b
        }
        fun main() { max(3, 5) }
        """)
    }

    func testCompile_controlFlow_ifExpression() throws {
        try assertKotlinCompilesToKIR("""
        fun classify(n: Int) = if (n > 0) "positive" else if (n < 0) "negative" else "zero"
        fun main() { classify(-1) }
        """)
    }

    func testCompile_controlFlow_whenStatement() throws {
        try assertKotlinCompilesToKIR("""
        fun describe(x: Int): String {
            return when (x) {
                1 -> "one"
                2 -> "two"
                3 -> "three"
                else -> "other"
            }
        }
        fun main() { describe(2) }
        """)
    }

    func testCompile_controlFlow_whenMultiCondition() throws {
        try assertKotlinCompilesToKIR("""
        fun isWeekend(day: String): Boolean {
            return when (day) {
                "Saturday", "Sunday" -> true
                else -> false
            }
        }
        fun main() { isWeekend("Monday") }
        """)
    }

    func testCompile_controlFlow_whenWithoutArg() throws {
        try assertKotlinCompilesToKIR("""
        fun classify(n: Int): String {
            return when {
                n > 0 -> "positive"
                n < 0 -> "negative"
                else -> "zero"
            }
        }
        fun main() { classify(0) }
        """)
    }

    func testCompile_controlFlow_forLoop() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            var sum = 0
            for (i in 1..10) {
                sum = sum + i
            }
        }
        """)
    }

    func testCompile_controlFlow_whileLoop() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            var i = 0
            var sum = 0
            while (i < 10) {
                sum = sum + i
                i = i + 1
            }
        }
        """)
    }

    func testCompile_controlFlow_doWhileLoop() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            var i = 0
            do {
                i = i + 1
            } while (i < 10)
        }
        """)
    }

    func testCompile_controlFlow_labeledBreak() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            var found = false
            outer@ for (i in 1..10) {
                for (j in 1..10) {
                    if (i * j == 25) {
                        found = true
                        break@outer
                    }
                }
            }
        }
        """)
    }

    func testCompile_controlFlow_labeledContinue() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            var count = 0
            outer@ for (i in 1..5) {
                for (j in 1..5) {
                    if (j == 3) continue@outer
                    count = count + 1
                }
            }
        }
        """)
    }

    func testCompile_numericTypes() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val b: Byte = 1
            val s: Short = 2
            val i: Int = 3
            val l: Long = 4L
            val f: Float = 5.0f
            val d: Double = 6.0
        }
        """)
    }

    func testCompile_bitwiseOperators() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val x = 0xFF
            val a = x and 0x0F
            val b = x or 0xF0
            val c = x xor 0xFF
            val d = x shl 4
            val e = x shr 2
        }
        """)
    }

    func testCompile_charArithmetic() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val c = 'A'
            val next = c + 1
            val code = c.code
        }
        """)
    }

    func testCompile_booleanLogic() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val a = true
            val b = false
            val c = a && b
            val d = a || b
            val e = !a
        }
        """)
    }
}

@testable import CompilerCore
import Foundation
import XCTest

/// Tests that verify Kotlin programs compile through the LLVM backend
/// and produce valid native object files (.o).
final class KotlinCompilationObjectEmissionTests: XCTestCase {

    /// Verify minimal main compiles to object file.
    func testCompileToObject_minimalMain() throws {
        try assertKotlinCompilesToObject("""
        fun main() = 0
        """, moduleName: "ObjMinimal")
    }

    /// Verify function calls compile to object file.
    func testCompileToObject_functionCalls() throws {
        try assertKotlinCompilesToObject("""
        fun add(a: Int, b: Int): Int = a + b
        fun mul(a: Int, b: Int): Int = a * b
        fun main() {
            val x = add(3, 4)
            val y = mul(x, 2)
        }
        """, moduleName: "ObjFunctions")
    }

    /// Verify class hierarchy compiles to object file.
    func testCompileToObject_classHierarchy() throws {
        try assertKotlinCompilesToObject("""
        open class Base(val id: Int) {
            open fun describe(): String = "Base"
        }
        class Derived(id: Int, val label: String) : Base(id) {
            override fun describe(): String = label
        }
        fun main() {
            val d = Derived(1, "derived")
            d.describe()
        }
        """, moduleName: "ObjClasses")
    }

    /// Verify control flow with when and for compiles to object file.
    func testCompileToObject_controlFlow() throws {
        try assertKotlinCompilesToObject("""
        fun fizzbuzz(n: Int): String {
            return when {
                n % 15 == 0 -> "FizzBuzz"
                n % 3 == 0 -> "Fizz"
                n % 5 == 0 -> "Buzz"
                else -> n.toString()
            }
        }
        fun main() {
            for (i in 1..20) {
                fizzbuzz(i)
            }
        }
        """, moduleName: "ObjControl")
    }

    /// Verify lambda and higher-order function compile to object file.
    func testCompileToObject_lambdaAndHigherOrder() throws {
        try assertKotlinCompilesToObject("""
        fun transform(x: Int, f: (Int) -> Int): Int = f(x)
        fun main() {
            val doubled = transform(5) { it * 2 }
            val squared = transform(5) { it * it }
        }
        """, moduleName: "ObjLambda")
    }

    /// Verify generic class compiles to object file.
    func testCompileToObject_generics() throws {
        try assertKotlinCompilesToObject("""
        class Pair<A, B>(val first: A, val second: B) {
            fun swap(): Pair<B, A> = Pair(second, first)
        }
        fun main() {
            val p = Pair(1, "hello")
            val swapped = p.swap()
        }
        """, moduleName: "ObjGenerics")
    }

    /// Verify nullable types compile to object file.
    func testCompileToObject_nullable() throws {
        try assertKotlinCompilesToObject("""
        fun safeLength(s: String?): Int {
            return s?.length ?: -1
        }
        fun main() {
            safeLength("hello")
            safeLength(null)
        }
        """, moduleName: "ObjNullable")
    }

    /// Verify interface polymorphism compiles to object file.
    func testCompileToObject_interfacePolymorphism() throws {
        try assertKotlinCompilesToObject("""
        interface Printable {
            fun print(): String
        }
        class Num(val v: Int) : Printable {
            override fun print(): String = v.toString()
        }
        class Str(val v: String) : Printable {
            override fun print(): String = v
        }
        fun output(p: Printable): String = p.print()
        fun main() {
            output(Num(42))
            output(Str("hi"))
        }
        """, moduleName: "ObjInterface")
    }

    /// Verify complex program with data class and collection compiles to object file.
    func testCompileToObject_complexProgram() throws {
        try assertKotlinCompilesToObject("""
        data class Student(val name: String, val grade: Int)

        fun topStudents(students: List<Student>, threshold: Int): List<Student> {
            val result = mutableListOf<Student>()
            for (s in students) {
                if (s.grade >= threshold) {
                    result.add(s)
                }
            }
            return result
        }

        fun main() {
            val students = listOf(
                Student("Alice", 95),
                Student("Bob", 72),
                Student("Charlie", 88)
            )
            topStudents(students, 80)
        }
        """, moduleName: "ObjComplex")
    }

    /// Verify exhaustive when on enum compiles to object file.
    func testCompileToObject_whenExhaustive() throws {
        try assertKotlinCompilesToObject("""
        enum class Season { SPRING, SUMMER, AUTUMN, WINTER }

        fun describe(s: Season): String = when (s) {
            Season.SPRING -> "warm"
            Season.SUMMER -> "hot"
            Season.AUTUMN -> "cool"
            Season.WINTER -> "cold"
        }

        fun main() {
            describe(Season.SUMMER)
        }
        """, moduleName: "ObjWhen")
    }
}

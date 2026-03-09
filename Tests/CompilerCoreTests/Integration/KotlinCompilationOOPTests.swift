@testable import CompilerCore
import Foundation
import XCTest

/// Tests for Kotlin OOP features: classes, data classes, enum classes, sealed classes,
/// objects, companion objects, interfaces, generics, nullable types, and type casting.
final class KotlinCompilationOOPTests: XCTestCase {
    /// Verify basic class with primary constructor compiles.
    func testCompile_class_basic() throws {
        try assertKotlinCompilesToKIR("""
        class Person(val name: String, val age: Int)
        fun main() {
            val p = Person("Alice", 30)
        }
        """)
    }

    /// Verify class with methods compiles.
    func testCompile_class_withMethods() throws {
        try assertKotlinCompilesToKIR("""
        class Counter(var count: Int) {
            fun increment() {
                count = count + 1
            }
            fun get(): Int = count
        }
        fun main() {
            val c = Counter(0)
            c.increment()
            c.get()
        }
        """)
    }

    /// Verify class inheritance with override compiles.
    func testCompile_class_inheritance() throws {
        try assertKotlinCompilesToKIR("""
        open class Animal(val name: String) {
            open fun sound(): String = "..."
        }
        class Dog(name: String) : Animal(name) {
            override fun sound(): String = "Woof"
        }
        fun main() {
            val d = Dog("Rex")
            d.sound()
        }
        """)
    }

    /// Verify abstract class with concrete subclass compiles.
    func testCompile_class_abstractClass() throws {
        try assertKotlinCompilesToKIR("""
        abstract class Shape {
            abstract fun area(): Double
        }
        class Circle(val radius: Double) : Shape() {
            override fun area(): Double = 3.14159 * radius * radius
        }
        fun main() {
            val c = Circle(5.0)
            c.area()
        }
        """)
    }

    /// Verify secondary constructor compiles.
    func testCompile_class_secondaryConstructor() throws {
        try assertKotlinCompilesToKIR("""
        class Point(val x: Int, val y: Int) {
            constructor(v: Int) : this(v, v)
        }
        fun main() {
            val p = Point(5)
        }
        """)
    }

    /// Verify init block compiles.
    func testCompile_class_initBlock() throws {
        try assertKotlinCompilesToKIR("""
        class Greeter(val name: String) {
            val greeting: String
            init {
                greeting = "Hello, " + name
            }
        }
        fun main() {
            val g = Greeter("World")
        }
        """)
    }

    /// Verify data class compiles.
    func testCompile_dataClass_basic() throws {
        try assertKotlinCompilesToKIR("""
        data class Point(val x: Int, val y: Int)
        fun main() {
            val p1 = Point(1, 2)
            val p2 = Point(1, 2)
        }
        """)
    }

    /// Verify data class copy compiles.
    func testCompile_dataClass_copy() throws {
        try assertKotlinCompilesToKIR("""
        data class User(val name: String, val age: Int)
        fun main() {
            val u1 = User("Alice", 30)
            val u2 = u1.copy(age = 31)
        }
        """)
    }

    /// Verify basic enum class compiles.
    func testCompile_enum_basic() throws {
        try assertKotlinCompilesToKIR("""
        enum class Direction {
            NORTH, SOUTH, EAST, WEST
        }
        fun main() {
            val d = Direction.NORTH
        }
        """)
    }

    /// Verify enum class with properties compiles.
    func testCompile_enum_withProperties() throws {
        try assertKotlinCompilesToKIR("""
        enum class Color(val rgb: Int) {
            RED(0xFF0000),
            GREEN(0x00FF00),
            BLUE(0x0000FF)
        }
        fun main() {
            val c = Color.RED
        }
        """)
    }

    /// Verify sealed class with when pattern matching compiles.
    func testCompile_sealed_class() throws {
        try assertKotlinCompilesToKIR("""
        sealed class Result {
            class Success(val value: Int) : Result()
            class Error(val message: String) : Result()
        }
        fun handle(r: Result): String {
            return when (r) {
                is Result.Success -> "OK"
                is Result.Error -> r.message
            }
        }
        fun main() {
            handle(Result.Success(42))
        }
        """)
    }

    /// Verify sealed interface with data class subtypes compiles.
    func testCompile_sealed_interface() throws {
        try assertKotlinCompilesToKIR("""
        sealed interface Expr
        data class Num(val value: Int) : Expr
        data class Add(val left: Expr, val right: Expr) : Expr

        fun eval(e: Expr): Int = when (e) {
            is Num -> e.value
            is Add -> eval(e.left) + eval(e.right)
        }
        fun main() {
            eval(Add(Num(1), Num(2)))
        }
        """)
    }

    /// Verify object singleton compiles.
    func testCompile_object_singleton() throws {
        try assertKotlinCompilesToKIR("""
        object Logger {
            fun log(msg: String) { }
        }
        fun main() {
            Logger.log("hello")
        }
        """)
    }

    /// Verify companion object with factory method compiles.
    func testCompile_companionObject() throws {
        try assertKotlinCompilesToKIR("""
        class MyClass {
            companion object {
                fun create(): MyClass = MyClass()
                val DEFAULT_NAME = "default"
            }
        }
        fun main() {
            val obj = MyClass.create()
        }
        """)
    }

    /// Verify basic interface implementation compiles.
    func testCompile_interface_basic() throws {
        try assertKotlinCompilesToKIR("""
        interface Drawable {
            fun draw(): String
        }
        class Square : Drawable {
            override fun draw(): String = "Square"
        }
        fun main() {
            val s: Drawable = Square()
            s.draw()
        }
        """)
    }

    /// Verify interface with default method compiles.
    func testCompile_interface_defaultMethod() throws {
        try assertKotlinCompilesToKIR("""
        interface Greeter {
            fun greet(name: String): String {
                return "Hello, " + name
            }
        }
        class FormalGreeter : Greeter {
            override fun greet(name: String): String {
                return "Good day, " + name
            }
        }
        fun main() {
            val g: Greeter = FormalGreeter()
            g.greet("World")
        }
        """)
    }

    /// Verify diamond inheritance with explicit override compiles.
    func testCompile_interface_multipleInheritance() throws {
        try assertKotlinCompilesToKIR("""
        interface A {
            fun hello(): String = "A"
        }
        interface B {
            fun hello(): String = "B"
        }
        class C : A, B {
            override fun hello(): String = "C"
        }
        fun main() {
            val c = C()
            c.hello()
        }
        """)
    }

    /// Verify generic function compiles.
    func testCompile_generics_function() throws {
        try assertKotlinCompilesToKIR("""
        fun <T> identity(x: T): T = x
        fun main() {
            identity(42)
            identity("hello")
        }
        """)
    }

    /// Verify generic class compiles.
    func testCompile_generics_class() throws {
        try assertKotlinCompilesToKIR("""
        class Box<T>(val value: T) {
            fun get(): T = value
        }
        fun main() {
            val intBox = Box(42)
            val strBox = Box("hello")
        }
        """)
    }

    /// Verify generic upper bound compiles.
    func testCompile_generics_upperBound() throws {
        try assertKotlinCompilesToKIR("""
        fun <T : Comparable<T>> maxOf(a: T, b: T): T {
            return if (a > b) a else b
        }
        fun main() { maxOf(3, 5) }
        """)
    }

    /// Verify nullable type declaration compiles.
    func testCompile_nullable_declaration() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val x: Int? = null
            val y: String? = "hello"
        }
        """)
    }

    /// Verify safe call operator compiles.
    func testCompile_nullable_safeCall() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val s: String? = "hello"
            val len: Int? = s?.length
        }
        """)
    }

    /// Verify elvis operator compiles.
    func testCompile_nullable_elvisOperator() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val s: String? = null
            val len = s?.length ?: 0
        }
        """)
    }

    /// Verify not-null assertion compiles.
    func testCompile_nullable_notNullAssertion() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val s: String? = "hello"
            val len = s!!.length
        }
        """)
    }

    /// Verify is type check compiles.
    func testCompile_typeCheck_is() throws {
        try assertKotlinCompilesToKIR("""
        fun check(x: Any): String {
            return if (x is String) "string" else "other"
        }
        fun main() { check("hello") }
        """)
    }

    /// Verify unsafe cast compiles.
    func testCompile_typeCast_as() throws {
        try assertKotlinCompilesToKIR("""
        fun castToString(x: Any): String {
            return x as String
        }
        fun main() { castToString("hello") }
        """)
    }

    /// Verify safe cast compiles.
    func testCompile_typeCast_safeAs() throws {
        try assertKotlinCompilesToKIR("""
        fun tryCast(x: Any): String? {
            return x as? String
        }
        fun main() { tryCast(42) }
        """)
    }

    /// Verify smart cast after is check compiles.
    func testCompile_smartCast() throws {
        try assertKotlinCompilesToKIR("""
        fun length(x: Any): Int {
            if (x is String) {
                return x.length
            }
            return 0
        }
        fun main() { length("hello") }
        """)
    }
}

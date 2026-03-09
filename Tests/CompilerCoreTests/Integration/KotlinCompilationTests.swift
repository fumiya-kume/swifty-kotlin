@testable import CompilerCore
import Foundation
import XCTest

// MARK: - Kotlin Compilation Tests
//
// End-to-end compilation tests that verify various Kotlin language features
// compile successfully through the KIR dump and/or object emission phases.

final class KotlinCompilationTests: XCTestCase {

    // MARK: - Helpers

    private func makeDriver() -> CompilerDriver {
        CompilerDriver(
            version: CompilerVersion(major: 0, minor: 1, patch: 0, gitHash: nil),
            kotlinVersion: .v2_3_10
        )
    }

    private func makeOptions(
        moduleName: String,
        inputs: [String],
        outputPath: String,
        emit: EmitMode,
        irFlags: [String] = []
    ) -> CompilerOptions {
        CompilerOptions(
            moduleName: moduleName,
            inputs: inputs,
            outputPath: outputPath,
            emit: emit,
            target: defaultTargetTriple(),
            irFlags: irFlags
        )
    }

    /// Compile the given Kotlin source through the KIR dump phase and assert success.
    private func assertCompilesToKIR(
        _ source: String,
        moduleName: String = "TestMod",
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        try withTemporaryFile(contents: source) { path in
            let fm = FileManager.default
            let outputBase = fm.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            defer { try? fm.removeItem(atPath: outputBase + ".kir") }

            let options = makeOptions(
                moduleName: moduleName,
                inputs: [path],
                outputPath: outputBase,
                emit: .kirDump
            )
            let result = makeDriver().runForTesting(options: options)

            XCTAssertEqual(result.exitCode, 0,
                "KIR compilation failed for module \(moduleName). Diagnostics: \(result.diagnostics.map { "\($0.code): \($0.message)" })",
                file: file, line: line)
            XCTAssertFalse(result.diagnostics.contains(where: { $0.severity == .error }),
                "Unexpected error diagnostics: \(result.diagnostics.filter { $0.severity == .error }.map { "\($0.code): \($0.message)" })",
                file: file, line: line)
        }
    }

    /// Compile the given Kotlin source through object emission (.o) and assert success.
    private func assertCompilesToObject(
        _ source: String,
        moduleName: String = "TestMod",
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        try withTemporaryFile(contents: source) { path in
            let fm = FileManager.default
            let outputBase = fm.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let objectPath = outputBase + ".o"
            defer { try? fm.removeItem(atPath: objectPath) }

            let options = makeOptions(
                moduleName: moduleName,
                inputs: [path],
                outputPath: outputBase,
                emit: .object
            )
            let result = makeDriver().runForTesting(options: options)

            XCTAssertEqual(result.exitCode, 0,
                "Object compilation failed for module \(moduleName). Diagnostics: \(result.diagnostics.map { "\($0.code): \($0.message)" })",
                file: file, line: line)
            XCTAssertFalse(result.diagnostics.contains(where: { $0.severity == .error }),
                "Unexpected error diagnostics: \(result.diagnostics.filter { $0.severity == .error }.map { "\($0.code): \($0.message)" })",
                file: file, line: line)
            XCTAssertTrue(fm.fileExists(atPath: objectPath),
                "Object file not produced at \(objectPath)",
                file: file, line: line)
        }
    }

    // =========================================================================
    // MARK: - 1. Basic Functions
    // =========================================================================

    func testCompile_function_expressionBody() throws {
        try assertCompilesToKIR("""
        fun add(a: Int, b: Int) = a + b
        fun main() = add(1, 2)
        """)
    }

    func testCompile_function_blockBody() throws {
        try assertCompilesToKIR("""
        fun greet(name: String): String {
            val msg = "Hello, " + name
            return msg
        }
        fun main() { greet("World") }
        """)
    }

    func testCompile_function_unitReturn() throws {
        try assertCompilesToKIR("""
        fun doNothing() {
        }
        fun main() { doNothing() }
        """)
    }

    func testCompile_function_multipleParameters() throws {
        try assertCompilesToKIR("""
        fun compute(a: Int, b: Int, c: Int): Int {
            return a * b + c
        }
        fun main() { compute(2, 3, 4) }
        """)
    }

    func testCompile_function_recursion() throws {
        try assertCompilesToKIR("""
        fun factorial(n: Int): Int {
            if (n <= 1) return 1
            return n * factorial(n - 1)
        }
        fun main() { factorial(5) }
        """)
    }

    // =========================================================================
    // MARK: - 2. Variables
    // =========================================================================

    func testCompile_variable_valAndVar() throws {
        try assertCompilesToKIR("""
        fun main() {
            val x = 10
            var y = 20
            y = x + y
        }
        """)
    }

    func testCompile_variable_typeInference() throws {
        try assertCompilesToKIR("""
        fun main() {
            val s = "hello"
            val n = 42
            val b = true
            val d = 3.14
        }
        """)
    }

    func testCompile_variable_explicitTypes() throws {
        try assertCompilesToKIR("""
        fun main() {
            val x: Int = 10
            val s: String = "hello"
            val b: Boolean = false
            val l: Long = 100L
        }
        """)
    }

    // =========================================================================
    // MARK: - 3. String Templates
    // =========================================================================

    func testCompile_string_concatenation() throws {
        try assertCompilesToKIR("""
        fun main() {
            val a = "Hello"
            val b = "World"
            val c = a + ", " + b + "!"
        }
        """)
    }

    func testCompile_string_template() throws {
        try assertCompilesToKIR("""
        fun main() {
            val name = "Kotlin"
            val version = 2
            val msg = "Language: $name version $version"
        }
        """)
    }

    func testCompile_string_templateExpression() throws {
        try assertCompilesToKIR("""
        fun main() {
            val x = 10
            val y = 20
            val result = "Sum is ${x + y}"
        }
        """)
    }

    func testCompile_string_rawString() throws {
        try assertCompilesToKIR(#"""
        fun main() {
            val text = """
                |Hello
                |World
            """.trimMargin()
        }
        """#)
    }

    // =========================================================================
    // MARK: - 4. Control Flow
    // =========================================================================

    func testCompile_controlFlow_ifElse() throws {
        try assertCompilesToKIR("""
        fun max(a: Int, b: Int): Int {
            return if (a > b) a else b
        }
        fun main() { max(3, 5) }
        """)
    }

    func testCompile_controlFlow_ifExpression() throws {
        try assertCompilesToKIR("""
        fun classify(n: Int) = if (n > 0) "positive" else if (n < 0) "negative" else "zero"
        fun main() { classify(-1) }
        """)
    }

    func testCompile_controlFlow_whenStatement() throws {
        try assertCompilesToKIR("""
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
        try assertCompilesToKIR("""
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
        try assertCompilesToKIR("""
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
        try assertCompilesToKIR("""
        fun main() {
            var sum = 0
            for (i in 1..10) {
                sum = sum + i
            }
        }
        """)
    }

    func testCompile_controlFlow_whileLoop() throws {
        try assertCompilesToKIR("""
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
        try assertCompilesToKIR("""
        fun main() {
            var i = 0
            do {
                i = i + 1
            } while (i < 10)
        }
        """)
    }

    func testCompile_controlFlow_labeledBreak() throws {
        try assertCompilesToKIR("""
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
        try assertCompilesToKIR("""
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

    // =========================================================================
    // MARK: - 5. Classes
    // =========================================================================

    func testCompile_class_basic() throws {
        try assertCompilesToKIR("""
        class Person(val name: String, val age: Int)
        fun main() {
            val p = Person("Alice", 30)
        }
        """)
    }

    func testCompile_class_withMethods() throws {
        try assertCompilesToKIR("""
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

    func testCompile_class_inheritance() throws {
        try assertCompilesToKIR("""
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

    func testCompile_class_abstractClass() throws {
        try assertCompilesToKIR("""
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

    func testCompile_class_secondaryConstructor() throws {
        try assertCompilesToKIR("""
        class Point(val x: Int, val y: Int) {
            constructor(v: Int) : this(v, v)
        }
        fun main() {
            val p = Point(5)
        }
        """)
    }

    func testCompile_class_initBlock() throws {
        try assertCompilesToKIR("""
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

    // =========================================================================
    // MARK: - 6. Data Classes
    // =========================================================================

    func testCompile_dataClass_basic() throws {
        try assertCompilesToKIR("""
        data class Point(val x: Int, val y: Int)
        fun main() {
            val p1 = Point(1, 2)
            val p2 = Point(1, 2)
        }
        """)
    }

    func testCompile_dataClass_copy() throws {
        try assertCompilesToKIR("""
        data class User(val name: String, val age: Int)
        fun main() {
            val u1 = User("Alice", 30)
            val u2 = u1.copy(age = 31)
        }
        """)
    }

    // =========================================================================
    // MARK: - 7. Enum Classes
    // =========================================================================

    func testCompile_enum_basic() throws {
        try assertCompilesToKIR("""
        enum class Direction {
            NORTH, SOUTH, EAST, WEST
        }
        fun main() {
            val d = Direction.NORTH
        }
        """)
    }

    func testCompile_enum_withProperties() throws {
        try assertCompilesToKIR("""
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

    // =========================================================================
    // MARK: - 8. Sealed Classes
    // =========================================================================

    func testCompile_sealed_class() throws {
        try assertCompilesToKIR("""
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

    func testCompile_sealed_interface() throws {
        try assertCompilesToKIR("""
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

    // =========================================================================
    // MARK: - 9. Objects and Companion Objects
    // =========================================================================

    func testCompile_object_singleton() throws {
        try assertCompilesToKIR("""
        object Logger {
            fun log(msg: String) { }
        }
        fun main() {
            Logger.log("hello")
        }
        """)
    }

    func testCompile_companionObject() throws {
        try assertCompilesToKIR("""
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

    // =========================================================================
    // MARK: - 10. Interfaces
    // =========================================================================

    func testCompile_interface_basic() throws {
        try assertCompilesToKIR("""
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

    func testCompile_interface_defaultMethod() throws {
        try assertCompilesToKIR("""
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

    func testCompile_interface_multipleInheritance() throws {
        try assertCompilesToKIR("""
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

    // =========================================================================
    // MARK: - 11. Extension Functions and Properties
    // =========================================================================

    func testCompile_extension_function() throws {
        try assertCompilesToKIR("""
        fun Int.isEven(): Boolean = this % 2 == 0
        fun main() {
            val result = 4.isEven()
        }
        """)
    }

    func testCompile_extension_property() throws {
        try assertCompilesToKIR("""
        val String.lastChar: Char
            get() = this[this.length - 1]
        fun main() {
            val c = "hello".lastChar
        }
        """)
    }

    func testCompile_extension_onCustomClass() throws {
        try assertCompilesToKIR("""
        class Box(val value: Int)
        fun Box.doubled(): Int = this.value * 2
        fun main() {
            val b = Box(5)
            b.doubled()
        }
        """)
    }

    // =========================================================================
    // MARK: - 12. Lambda and Higher-Order Functions
    // =========================================================================

    func testCompile_lambda_basic() throws {
        try assertCompilesToKIR("""
        fun main() {
            val square = { x: Int -> x * x }
            square(5)
        }
        """)
    }

    func testCompile_lambda_it() throws {
        try assertCompilesToKIR("""
        fun applyToTen(f: (Int) -> Int): Int = f(10)
        fun main() {
            applyToTen { it * 2 }
        }
        """)
    }

    func testCompile_higherOrder_function() throws {
        try assertCompilesToKIR("""
        fun operate(a: Int, b: Int, op: (Int, Int) -> Int): Int = op(a, b)
        fun main() {
            operate(3, 4) { x, y -> x + y }
        }
        """)
    }

    func testCompile_lambda_trailingLambda() throws {
        try assertCompilesToKIR("""
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

    // =========================================================================
    // MARK: - 13. Nullable Types
    // =========================================================================

    func testCompile_nullable_declaration() throws {
        try assertCompilesToKIR("""
        fun main() {
            val x: Int? = null
            val y: String? = "hello"
        }
        """)
    }

    func testCompile_nullable_safeCall() throws {
        try assertCompilesToKIR("""
        fun main() {
            val s: String? = "hello"
            val len: Int? = s?.length
        }
        """)
    }

    func testCompile_nullable_elvisOperator() throws {
        try assertCompilesToKIR("""
        fun main() {
            val s: String? = null
            val len = s?.length ?: 0
        }
        """)
    }

    func testCompile_nullable_notNullAssertion() throws {
        try assertCompilesToKIR("""
        fun main() {
            val s: String? = "hello"
            val len = s!!.length
        }
        """)
    }

    // =========================================================================
    // MARK: - 14. Type Checking and Casting
    // =========================================================================

    func testCompile_typeCheck_is() throws {
        try assertCompilesToKIR("""
        fun check(x: Any): String {
            return if (x is String) "string" else "other"
        }
        fun main() { check("hello") }
        """)
    }

    func testCompile_typeCast_as() throws {
        try assertCompilesToKIR("""
        fun castToString(x: Any): String {
            return x as String
        }
        fun main() { castToString("hello") }
        """)
    }

    func testCompile_typeCast_safeAs() throws {
        try assertCompilesToKIR("""
        fun tryCast(x: Any): String? {
            return x as? String
        }
        fun main() { tryCast(42) }
        """)
    }

    func testCompile_smartCast() throws {
        try assertCompilesToKIR("""
        fun length(x: Any): Int {
            if (x is String) {
                return x.length
            }
            return 0
        }
        fun main() { length("hello") }
        """)
    }

    // =========================================================================
    // MARK: - 15. Generics
    // =========================================================================

    func testCompile_generics_function() throws {
        try assertCompilesToKIR("""
        fun <T> identity(x: T): T = x
        fun main() {
            identity(42)
            identity("hello")
        }
        """)
    }

    func testCompile_generics_class() throws {
        try assertCompilesToKIR("""
        class Box<T>(val value: T) {
            fun get(): T = value
        }
        fun main() {
            val intBox = Box(42)
            val strBox = Box("hello")
        }
        """)
    }

    func testCompile_generics_upperBound() throws {
        try assertCompilesToKIR("""
        fun <T : Comparable<T>> maxOf(a: T, b: T): T {
            return if (a > b) a else b
        }
        fun main() { maxOf(3, 5) }
        """)
    }

    // =========================================================================
    // MARK: - 16. Operator Overloading
    // =========================================================================

    func testCompile_operator_plus() throws {
        try assertCompilesToKIR("""
        data class Vec(val x: Int, val y: Int) {
            operator fun plus(other: Vec): Vec = Vec(x + other.x, y + other.y)
        }
        fun main() {
            val v = Vec(1, 2) + Vec(3, 4)
        }
        """)
    }

    func testCompile_operator_compareTo() throws {
        try assertCompilesToKIR("""
        class Weight(val grams: Int) : Comparable<Weight> {
            override operator fun compareTo(other: Weight): Int = grams - other.grams
        }
        fun main() {
            val heavy = Weight(100) > Weight(50)
        }
        """)
    }

    func testCompile_operator_invoke() throws {
        try assertCompilesToKIR("""
        class Multiplier(val factor: Int) {
            operator fun invoke(x: Int): Int = x * factor
        }
        fun main() {
            val double = Multiplier(2)
            double(5)
        }
        """)
    }

    // =========================================================================
    // MARK: - 17. Property Delegation
    // =========================================================================

    func testCompile_delegate_lazy() throws {
        try assertCompilesToKIR("""
        fun main() {
            val x: Int by lazy { 42 }
        }
        """)
    }

    // =========================================================================
    // MARK: - 18. Destructuring
    // =========================================================================

    func testCompile_destructuring_dataClass() throws {
        try assertCompilesToKIR("""
        data class Point(val x: Int, val y: Int)
        fun main() {
            val (x, y) = Point(3, 4)
        }
        """)
    }

    // =========================================================================
    // MARK: - 19. Try/Catch
    // =========================================================================

    func testCompile_tryCatch_basic() throws {
        try assertCompilesToKIR("""
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

    func testCompile_tryCatch_finally() throws {
        try assertCompilesToKIR("""
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

    func testCompile_throw_nothing() throws {
        try assertCompilesToKIR("""
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

    // =========================================================================
    // MARK: - 20. Scope Functions
    // =========================================================================

    func testCompile_scope_let() throws {
        try assertCompilesToKIR("""
        fun main() {
            val result = "Hello".let { it.length }
        }
        """)
    }

    func testCompile_scope_run() throws {
        try assertCompilesToKIR("""
        fun main() {
            val result = "Hello".run { length }
        }
        """)
    }

    func testCompile_scope_apply() throws {
        try assertCompilesToKIR("""
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

    func testCompile_scope_also() throws {
        try assertCompilesToKIR("""
        fun main() {
            val result = "Hello".also { val len = it.length }
        }
        """)
    }

    // =========================================================================
    // MARK: - 21. Collections
    // =========================================================================

    func testCompile_collection_listOf() throws {
        try assertCompilesToKIR("""
        fun main() {
            val list = listOf(1, 2, 3, 4, 5)
        }
        """)
    }

    func testCompile_collection_arrayOf() throws {
        try assertCompilesToKIR("""
        fun main() {
            val arr = arrayOf(1, 2, 3)
            val first = arr[0]
        }
        """)
    }

    func testCompile_collection_mapOf() throws {
        try assertCompilesToKIR("""
        fun main() {
            val map = mapOf("a" to 1, "b" to 2, "c" to 3)
        }
        """)
    }

    // =========================================================================
    // MARK: - 22. Ranges
    // =========================================================================

    func testCompile_range_intRange() throws {
        try assertCompilesToKIR("""
        fun main() {
            val r = 1..10
            val contains = 5 in r
        }
        """)
    }

    func testCompile_range_downTo() throws {
        try assertCompilesToKIR("""
        fun main() {
            for (i in 10 downTo 1) {
                val x = i
            }
        }
        """)
    }

    func testCompile_range_step() throws {
        try assertCompilesToKIR("""
        fun main() {
            for (i in 0..20 step 2) {
                val x = i
            }
        }
        """)
    }

    // =========================================================================
    // MARK: - 23. Infix Functions
    // =========================================================================

    func testCompile_infix_function() throws {
        try assertCompilesToKIR("""
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

    // =========================================================================
    // MARK: - 24. Tailrec Functions
    // =========================================================================

    func testCompile_tailrec_function() throws {
        try assertCompilesToKIR("""
        tailrec fun gcd(a: Int, b: Int): Int {
            if (b == 0) return a
            return gcd(b, a % b)
        }
        fun main() { gcd(48, 18) }
        """)
    }

    // =========================================================================
    // MARK: - 25. Top-level Properties
    // =========================================================================

    func testCompile_topLevel_property() throws {
        try assertCompilesToKIR("""
        val PI = 3.14159
        val TAU = PI * 2.0
        fun main() {
            val x = PI
        }
        """)
    }

    // =========================================================================
    // MARK: - 26. Const Val
    // =========================================================================

    func testCompile_constVal() throws {
        try assertCompilesToKIR("""
        const val MAX_SIZE = 100
        fun main() {
            val x = MAX_SIZE
        }
        """)
    }

    // =========================================================================
    // MARK: - 27. Named and Default Arguments
    // =========================================================================

    func testCompile_namedArguments() throws {
        try assertCompilesToKIR("""
        fun createUser(name: String, age: Int, active: Boolean = true): String {
            return name
        }
        fun main() {
            createUser(name = "Alice", age = 30)
            createUser(age = 25, name = "Bob", active = false)
        }
        """)
    }

    // =========================================================================
    // MARK: - 28. Vararg
    // =========================================================================

    func testCompile_vararg() throws {
        try assertCompilesToKIR("""
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

    // =========================================================================
    // MARK: - 29. Type Aliases
    // =========================================================================

    func testCompile_typeAlias() throws {
        try assertCompilesToKIR("""
        typealias StringList = List<String>
        fun first(list: StringList): String = list[0]
        fun main() {
            first(listOf("a", "b"))
        }
        """)
    }

    // =========================================================================
    // MARK: - 30. Overloaded Functions
    // =========================================================================

    func testCompile_overload() throws {
        try assertCompilesToKIR("""
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

    // =========================================================================
    // MARK: - 31. Numeric Types
    // =========================================================================

    func testCompile_numericTypes() throws {
        try assertCompilesToKIR("""
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
        try assertCompilesToKIR("""
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
        try assertCompilesToKIR("""
        fun main() {
            val c = 'A'
            val next = c + 1
            val code = c.code
        }
        """)
    }

    // =========================================================================
    // MARK: - 32. Boolean Logic
    // =========================================================================

    func testCompile_booleanLogic() throws {
        try assertCompilesToKIR("""
        fun main() {
            val a = true
            val b = false
            val c = a && b
            val d = a || b
            val e = !a
        }
        """)
    }

    // =========================================================================
    // MARK: - 33. Multi-file Compilation
    // =========================================================================

    func testCompile_multiFile() throws {
        try withTemporaryFiles(contents: [
            """
            fun helper(): Int = 42
            """,
            """
            fun main() {
                val x = helper()
            }
            """
        ]) { paths in
            let fm = FileManager.default
            let outputBase = fm.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            defer { try? fm.removeItem(atPath: outputBase + ".kir") }

            let options = makeOptions(
                moduleName: "MultiFile",
                inputs: paths,
                outputPath: outputBase,
                emit: .kirDump
            )
            let result = makeDriver().runForTesting(options: options)

            XCTAssertEqual(result.exitCode, 0)
            XCTAssertFalse(result.diagnostics.contains(where: { $0.severity == .error }))
        }
    }

    // =========================================================================
    // MARK: - 34. Complex Programs
    // =========================================================================

    func testCompile_complex_linkedList() throws {
        try assertCompilesToKIR("""
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

    func testCompile_complex_strategyPattern() throws {
        try assertCompilesToKIR("""
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

    func testCompile_complex_builderPattern() throws {
        try assertCompilesToKIR("""
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

    // =========================================================================
    // MARK: - 35. Object Emission (.o) Tests
    // =========================================================================

    func testCompileToObject_minimalMain() throws {
        try assertCompilesToObject("""
        fun main() = 0
        """, moduleName: "ObjMinimal")
    }

    func testCompileToObject_functionCalls() throws {
        try assertCompilesToObject("""
        fun add(a: Int, b: Int): Int = a + b
        fun mul(a: Int, b: Int): Int = a * b
        fun main() {
            val x = add(3, 4)
            val y = mul(x, 2)
        }
        """, moduleName: "ObjFunctions")
    }

    func testCompileToObject_classHierarchy() throws {
        try assertCompilesToObject("""
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

    func testCompileToObject_controlFlow() throws {
        try assertCompilesToObject("""
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

    func testCompileToObject_lambdaAndHigherOrder() throws {
        try assertCompilesToObject("""
        fun transform(x: Int, f: (Int) -> Int): Int = f(x)
        fun main() {
            val doubled = transform(5) { it * 2 }
            val squared = transform(5) { it * it }
        }
        """, moduleName: "ObjLambda")
    }

    func testCompileToObject_generics() throws {
        try assertCompilesToObject("""
        class Pair<A, B>(val first: A, val second: B) {
            fun swap(): Pair<B, A> = Pair(second, first)
        }
        fun main() {
            val p = Pair(1, "hello")
            val swapped = p.swap()
        }
        """, moduleName: "ObjGenerics")
    }

    func testCompileToObject_nullable() throws {
        try assertCompilesToObject("""
        fun safeLength(s: String?): Int {
            return s?.length ?: -1
        }
        fun main() {
            safeLength("hello")
            safeLength(null)
        }
        """, moduleName: "ObjNullable")
    }

    func testCompileToObject_interfacePolymorphism() throws {
        try assertCompilesToObject("""
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

    func testCompileToObject_complexProgram() throws {
        try assertCompilesToObject("""
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

    func testCompileToObject_whenExhaustive() throws {
        try assertCompilesToObject("""
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

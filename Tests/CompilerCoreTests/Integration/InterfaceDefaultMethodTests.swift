@testable import CompilerCore
import XCTest

/// Tests for interface default methods (CLASS-003 / P5-113).
///
/// Verifies that interface functions with bodies (default methods) are:
/// 1. Parsed and preserved in the AST
/// 2. NOT marked abstract in the sema symbol table
/// 3. Callable on implementing classes that do not override them
/// 4. Correctly overridden when a concrete class provides its own implementation
/// 5. Lowered to KIR without errors
/// 6. Dispatched correctly through itable when receiver is interface-typed
final class InterfaceDefaultMethodTests: XCTestCase {
    // MARK: - Sema: default methods are not abstract

    func testInterfaceDefaultMethodNotMarkedAbstract() throws {
        let source = """
        interface Greeter {
            fun greet(): String = "Hello"
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        XCTAssertFalse(ctx.diagnostics.diagnostics.contains(where: { $0.severity == .error }))

        // The greet function should NOT have the abstractType flag
        let sema = try XCTUnwrap(ctx.sema)
        let greetSymbols = sema.symbols.allSymbols().filter {
            $0.kind == .function && ctx.interner.resolve($0.name) == "greet"
        }
        XCTAssertEqual(greetSymbols.count, 1)
        XCTAssertFalse(greetSymbols[0].flags.contains(.abstractType),
                       "Interface default method should not be marked abstract")
    }

    func testInterfaceAbstractMethodIsMarkedAbstract() throws {
        let source = """
        interface Greeter {
            fun greet(): String
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        XCTAssertFalse(ctx.diagnostics.diagnostics.contains(where: { $0.severity == .error }))

        let sema = try XCTUnwrap(ctx.sema)
        let greetSymbols = sema.symbols.allSymbols().filter {
            $0.kind == .function && ctx.interner.resolve($0.name) == "greet"
        }
        XCTAssertEqual(greetSymbols.count, 1)
        XCTAssertTrue(greetSymbols[0].flags.contains(.abstractType),
                      "Interface method without body should be marked abstract")
    }

    // MARK: - Sema: concrete class inherits default method without error

    func testConcreteClassInheritsDefaultMethodWithoutOverride() throws {
        let source = """
        interface Greeter {
            fun greet(): String = "Hello"
        }
        class DefaultGreeter : Greeter
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        // No abstract override error: default method satisfies the requirement
        assertNoDiagnostic("KSWIFTK-SEMA-ABSTRACT", in: ctx)
        XCTAssertFalse(ctx.diagnostics.diagnostics.contains(where: { $0.severity == .error }))
    }

    func testConcreteClassMustOverrideAbstractInterfaceMethod() throws {
        let source = """
        interface Greeter {
            fun greet(): String
        }
        class DefaultGreeter : Greeter
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        // Abstract method without body must be overridden
        assertHasDiagnostic("KSWIFTK-SEMA-ABSTRACT", in: ctx)
    }

    func testConcreteClassOverridesDefaultMethod() throws {
        let source = """
        interface Greeter {
            fun greet(): String = "Hello"
        }
        class CustomGreeter : Greeter {
            override fun greet(): String = "Hi"
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-SEMA-ABSTRACT", in: ctx)
        XCTAssertFalse(ctx.diagnostics.diagnostics.contains(where: { $0.severity == .error }))
    }

    // MARK: - Sema: mixed abstract and default methods

    func testInterfaceWithMixedAbstractAndDefaultMethods() throws {
        let source = """
        interface Animal {
            fun name(): String
            fun sound(): String = "..."
        }
        class Dog : Animal {
            override fun name(): String = "Dog"
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        // Dog overrides name() (abstract) and inherits sound() (default)
        assertNoDiagnostic("KSWIFTK-SEMA-ABSTRACT", in: ctx)
        XCTAssertFalse(ctx.diagnostics.diagnostics.contains(where: { $0.severity == .error }))
    }

    func testMixedMethodsMissingAbstractOverrideErrors() throws {
        let source = """
        interface Animal {
            fun name(): String
            fun sound(): String = "..."
        }
        class Dog : Animal
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        // Dog must override the abstract name() even though sound() has a default
        assertHasDiagnostic("KSWIFTK-SEMA-ABSTRACT", in: ctx)
    }

    // MARK: - Sema: multiple interfaces with default methods

    func testClassImplementsMultipleInterfacesWithDefaults() throws {
        let source = """
        interface Greeter {
            fun greet(): String = "Hello"
        }
        interface Logger {
            fun log(): String = "logged"
        }
        class MyClass : Greeter, Logger
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-SEMA-ABSTRACT", in: ctx)
        XCTAssertFalse(ctx.diagnostics.diagnostics.contains(where: { $0.severity == .error }))
    }

    // MARK: - Sema: default method with block body

    func testDefaultMethodWithBlockBody() throws {
        let source = """
        interface Calculator {
            fun add(a: Int, b: Int): Int {
                return a + b
            }
        }
        class SimpleCalc : Calculator
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-SEMA-ABSTRACT", in: ctx)
        XCTAssertFalse(ctx.diagnostics.diagnostics.contains(where: { $0.severity == .error }))
    }

    // MARK: - Sema: member call resolution on implementing class

    func testDefaultMethodCallableOnImplementingClass() throws {
        let source = """
        interface Greeter {
            fun greet(): String = "Hello"
        }
        class DefaultGreeter : Greeter
        fun main() {
            val g = DefaultGreeter()
            println(g.greet())
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(errors.isEmpty,
                      "Calling inherited default method should not produce errors. Got: \(errors.map(\.message))")
    }

    func testDefaultMethodCallableOnInterfaceTypedVariable() throws {
        let source = """
        interface Greeter {
            fun greet(): String = "Hello"
        }
        class DefaultGreeter : Greeter
        fun main() {
            val g: Greeter = DefaultGreeter()
            println(g.greet())
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(errors.isEmpty,
                      "Calling default method on interface-typed var should not error. Got: \(errors.map(\.message))")
    }

    // MARK: - KIR: default method lowering

    func testInterfaceDefaultMethodKIREmission() throws {
        let source = """
        interface Greeter {
            fun greet(): String = "Hello"
        }
        class DefaultGreeter : Greeter
        fun main() {
            println(DefaultGreeter().greet())
        }
        """
        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)

        XCTAssertFalse(ctx.diagnostics.diagnostics.contains(where: { $0.severity == .error }),
                       "KIR lowering should succeed. Got: \(ctx.diagnostics.diagnostics.map(\.message))")
        let module = try XCTUnwrap(ctx.kir)
        XCTAssertGreaterThanOrEqual(module.functionCount, 1)
    }

    func testOverriddenDefaultMethodKIREmission() throws {
        let source = """
        interface Greeter {
            fun greet(): String = "Hello"
        }
        class CustomGreeter : Greeter {
            override fun greet(): String = "Hi"
        }
        fun main() {
            println(CustomGreeter().greet())
        }
        """
        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)

        XCTAssertFalse(ctx.diagnostics.diagnostics.contains(where: { $0.severity == .error }),
                       "KIR lowering with override should succeed. Got: \(ctx.diagnostics.diagnostics.map(\.message))")
    }

    // MARK: - KIR: full pipeline lowering

    func testDefaultMethodFullPipelineLowering() throws {
        let source = """
        interface Greeter {
            fun greet(): String = "Hello"
        }
        class DefaultGreeter : Greeter
        class CustomGreeter : Greeter {
            override fun greet(): String = "Hi"
        }
        fun main() {
            println(DefaultGreeter().greet())
            println(CustomGreeter().greet())
        }
        """
        let ctx = makeContextFromSource(source)
        try runToLowering(ctx)

        XCTAssertFalse(ctx.diagnostics.diagnostics.contains(where: { $0.severity == .error }),
                       "Full pipeline lowering should succeed. Got: \(ctx.diagnostics.diagnostics.map(\.message))")
    }

    func testMixedMethodsFullPipelineLowering() throws {
        let source = """
        interface Animal {
            fun name(): String
            fun sound(): String = "..."
        }
        class Dog : Animal {
            override fun name(): String = "Dog"
        }
        fun main() {
            val d = Dog()
            println(d.name())
            println(d.sound())
        }
        """
        let ctx = makeContextFromSource(source)
        try runToLowering(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(errors.isEmpty,
                      "Mixed abstract+default pipeline should succeed. Got: \(errors.map(\.message))")
    }

    // MARK: - Interface Properties Tests

    func testInterfaceAbstractProperty() throws {
        let source = """
        interface TestInterface {
            val abstractProperty: String
            var abstractVar: Int
        }
        class TestClass : TestInterface {
            override val abstractProperty: String = "test"
            override var abstractVar: Int = 42
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        XCTAssertFalse(ctx.diagnostics.diagnostics.contains(where: { $0.severity == .error }))
    }

    func testInterfaceConcreteProperty() throws {
        let source = """
        interface TestInterface {
            val concreteProperty: String = "default"
            var concreteVar: Int = 42
        }
        class TestClass : TestInterface
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        XCTAssertFalse(ctx.diagnostics.diagnostics.contains(where: { $0.severity == .error }))
    }

    func testInterfaceComputedProperty() throws {
        let source = """
        interface TestInterface {
            val computedProperty: String
                get() = "computed"
            var computedVar: String
                get() = "get"
                set(value) { }
        }
        class TestClass : TestInterface
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        XCTAssertFalse(ctx.diagnostics.diagnostics.contains(where: { $0.severity == .error }))
    }

    // MARK: - Super Call Tests

    func testSuperQualifiedCall() throws {
        let source = """
        interface A {
            fun method(): String = "A"
        }
        interface B : A {
            override fun method(): String = "B"
        }
        interface C : A {
            override fun method(): String = "C"
        }
        class TestClass : B, C {
            override fun method(): String = super<B>.method() + " + " + super<C>.method()
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        XCTAssertFalse(ctx.diagnostics.diagnostics.contains(where: { $0.severity == .error }))
    }

    // MARK: - Complex Interface Inheritance Tests

    func testComplexInterfaceInheritance() throws {
        let source = """
        interface Base {
            fun baseMethod(): String = "Base"
            abstract fun abstractMethod(): String
        }
        interface Left : Base {
            override fun baseMethod(): String = "Left"
            fun leftMethod(): String = "Left"
        }
        interface Right : Base {
            // Don't override baseMethod to avoid diamond conflict
            fun rightMethod(): String = "Right"
        }
        class TestClass : Left, Right {
            override fun abstractMethod(): String = "Implemented"
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        XCTAssertFalse(ctx.diagnostics.diagnostics.contains(where: { $0.severity == .error }))
    }
}

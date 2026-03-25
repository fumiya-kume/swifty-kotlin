import XCTest
@testable import CompilerCore

final class InheritanceModifierTests: XCTestCase {
    
    // MARK: - Abstract Override Tests
    
    func testAbstractOverrideInAbstractClass() throws {
        let source = """
        abstract class Shape {
            abstract fun area(): Double
            open fun describe(): String = "Shape"
        }
        
        abstract class Circle : Shape() {
            abstract override fun area(): Double
            abstract override fun describe(): String
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        
        // Should be valid - abstract class can re-abstract concrete methods
        assertNoDiagnostic("KSWIFTK-SEMA-ABSTRACT-OVERRIDE", in: ctx)
        XCTAssertFalse(ctx.diagnostics.diagnostics.contains(where: { $0.severity == .error }))
    }
    
    func testAbstractOverrideInConcreteClass() throws {
        let source = """
        open class Shape {
            open fun describe(): String = "Shape"
        }
        
        class Circle : Shape() {
            abstract override fun describe(): String
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        
        // Should error - concrete class cannot have abstract members
        assertHasDiagnostic("KSWIFTK-SEMA-ABSTRACT-OVERRIDE", in: ctx)
    }
    
    func testAbstractOverrideOfAbstractMember() throws {
        let source = """
        abstract class Shape {
            abstract fun area(): Double
        }
        
        abstract class Circle : Shape() {
            abstract override fun area(): Double
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        
        // Should error - cannot re-abstract an already abstract member
        assertHasDiagnostic("KSWIFTK-SEMA-ABSTRACT-OVERRIDE", in: ctx)
    }
    
    // MARK: - Final Override Tests
    
    func testFinalOverrideValid() throws {
        let source = """
        open class Shape {
            open fun describe(): String = "Shape"
        }
        
        class Circle : Shape() {
            final override fun describe(): String = "Circle"
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        
        // Should be valid - final override is allowed
        assertNoDiagnostic("KSWIFTK-SEMA-MODIFIER-CONFLICT", in: ctx)
        XCTAssertFalse(ctx.diagnostics.diagnostics.contains(where: { $0.severity == .error }))
    }
    
    func testFinalOverrideCannotBeFurtherOverridden() throws {
        let source = """
        open class Shape {
            open fun describe(): String = "Shape"
        }
        
        class Circle : Shape() {
            final override fun describe(): String = "Circle"
        }
        
        class ColoredCircle : Circle() {
            override fun describe(): String = "Colored Circle"
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        
        // Should error - cannot override final member
        assertHasDiagnostic("KSWIFTK-SEMA-FINAL", in: ctx)
    }
    
    // MARK: - Modifier Combination Tests
    
    func testAbstractFinalConflict() throws {
        let source = """
        abstract class Shape {
            abstract final fun area(): Double
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        
        // Should error - abstract and final are mutually exclusive
        assertHasDiagnostic("KSWIFTK-SEMA-MODIFIER-CONFLICT", in: ctx)
    }
    
    func testInterfaceMemberCannotBeFinal() throws {
        let source = """
        interface Shape {
            final fun area(): Double
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        
        // Should error - interface members cannot be final
        assertHasDiagnostic("KSWIFTK-SEMA-MODIFIER-CONFLICT", in: ctx)
    }
    
    func testInterfaceAbstractRedundant() throws {
        let source = """
        interface Shape {
            abstract fun area(): Double
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        
        // Should warn - abstract is redundant in interface
        assertHasDiagnostic("KSWIFTK-SEMA-REDUNDANT-MODIFIER", in: ctx)
    }
    
    func testDataClassCannotHaveOpenMembers() throws {
        let source = """
        data class Point(val x: Int, val y: Int) {
            open fun distance(): Double = 0.0
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        
        // Should error - data class cannot have open members
        assertHasDiagnostic("KSWIFTK-SEMA-MODIFIER-CONFLICT", in: ctx)
    }
    
    // MARK: - Visibility Constraint Tests
    
    func testOverrideWithLessVisibility() throws {
        let source = """
        open class Shape {
            public fun describe(): String = "Shape"
        }
        
        class Circle : Shape() {
            protected override fun describe(): String = "Circle"
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        
        // Should error - cannot override with less visibility
        assertHasDiagnostic("KSWIFTK-SEMA-VISIBILITY", in: ctx)
    }
    
    func testOverrideWithSameVisibility() throws {
        let source = """
        open class Shape {
            protected fun describe(): String = "Shape"
        }
        
        class Circle : Shape() {
            protected override fun describe(): String = "Circle"
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        
        // Should be valid - same visibility is allowed
        assertNoDiagnostic("KSWIFTK-SEMA-VISIBILITY", in: ctx)
        XCTAssertFalse(ctx.diagnostics.diagnostics.contains(where: { $0.severity == .error }))
    }
    
    func testOverrideWithMoreVisibility() throws {
        let source = """
        open class Shape {
            protected fun describe(): String = "Shape"
        }
        
        class Circle : Shape() {
            public override fun describe(): String = "Circle"
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        
        // Should be valid - more visibility is allowed
        assertNoDiagnostic("KSWIFTK-SEMA-VISIBILITY", in: ctx)
        XCTAssertFalse(ctx.diagnostics.diagnostics.contains(where: { $0.severity == .error }))
    }
    
    // MARK: - Complex Inheritance Scenarios
    
    func testComplexInheritanceHierarchy() throws {
        let source = """
        abstract class Animal {
            abstract fun makeSound(): String
            open fun move(): String = "moving"
        }
        
        abstract class Mammal : Animal() {
            abstract override fun makeSound(): String
            final override fun move(): String = "mammal moving"
        }
        
        class Dog : Mammal() {
            override fun makeSound(): String = "woof"
            // Cannot override move() because it's final in Mammal
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        
        // Should be valid - complex inheritance with abstract override and final override
        assertNoDiagnostic("KSWIFTK-SEMA-ABSTRACT-OVERRIDE", in: ctx)
        assertNoDiagnostic("KSWIFTK-SEMA-MODIFIER-CONFLICT", in: ctx)
        XCTAssertFalse(ctx.diagnostics.diagnostics.contains(where: { $0.severity == .error }))
    }
    
    func testOverrideChaining() throws {
        let source = """
        open class Base {
            open fun method(): String = "base"
        }
        
        open class Middle : Base() {
            override fun method(): String = "middle" // Implicitly open
        }
        
        class Derived : Middle() {
            final override fun method(): String = "derived" // Final override
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        
        // Should be valid - override chaining with final termination
        assertNoDiagnostic("KSWIFTK-SEMA-FINAL", in: ctx)
        XCTAssertFalse(ctx.diagnostics.diagnostics.contains(where: { $0.severity == .error }))
    }
    
    // MARK: - Helper Methods
    
    private func makeContextFromSource(_ source: String) -> TestContext {
        // This would need to be implemented based on the existing test infrastructure
        // For now, this is a placeholder
        return TestContext()
    }
    
    private func runSema(_ ctx: TestContext) throws {
        // This would need to be implemented based on the existing test infrastructure
        // For now, this is a placeholder
    }
    
    private func assertHasDiagnostic(_ code: String, in ctx: TestContext) {
        XCTAssertTrue(ctx.diagnostics.diagnostics.contains { $0.code == code })
    }
    
    private func assertNoDiagnostic(_ code: String, in ctx: TestContext) {
        XCTAssertFalse(ctx.diagnostics.diagnostics.contains { $0.code == code })
    }
}

// Placeholder types for test infrastructure
private struct TestContext {
    let diagnostics = DiagnosticEngine()
}

@testable import CompilerCore
import Foundation
import XCTest

final class AbstractClassErrorTests: XCTestCase {
    func testError_abstractClassInstantiation() throws {
        let source = """
        abstract class Shape {
            abstract fun area(): Double
        }
        fun main() {
            val s = Shape()  // Error: cannot instantiate abstract class
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        assertHasDiagnostic("KSWIFTK-SEMA-ABSTRACT", in: ctx)
    }

    func testError_abstractFunctionWithBody() throws {
        let source = """
        abstract class Base {
            abstract fun test() { println("error") }  // Error: abstract function cannot have body
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        assertHasDiagnostic("KSWIFTK-SEMA-ABSTRACT", in: ctx)
    }

    func testError_abstractPropertyWithInitializer() throws {
        let source = """
        abstract class Base {
            abstract val prop: String = "error"  // Error: abstract property cannot have initializer
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        assertHasDiagnostic("KSWIFTK-SEMA-ABSTRACT", in: ctx)
    }

    func testError_abstractPrivateMember() throws {
        let source = """
        abstract class Base {
            private abstract fun test()  // Error: abstract member cannot be private
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        assertHasDiagnostic("KSWIFTK-SEMA-ABSTRACT", in: ctx)
    }

    func testError_abstractFinalConflict() throws {
        let source = """
        abstract final class Base  // Error: class cannot be both abstract and final
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        assertHasDiagnostic("KSWIFTK-SEMA-ABSTRACT", in: ctx)
    }

    func testError_sealedFinalConflict() throws {
        let source = """
        sealed final class Base  // Error: class cannot be both sealed and final
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        assertHasDiagnostic("KSWIFTK-SEMA-ABSTRACT", in: ctx)
    }

    func testError_missingAbstractOverride() throws {
        let source = """
        abstract class Base {
            abstract fun test()
        }
        class Derived : Base() {
            // Error: must override abstract method
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        assertHasDiagnostic("KSWIFTK-SEMA-ABSTRACT", in: ctx)
    }

    func testError_abstractPropertyWithBackingField() throws {
        let source = """
        abstract class Base {
            abstract var prop: String
                field = "error"  // Error: abstract property cannot have explicit backing field
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        assertHasDiagnostic("KSWIFTK-SEMA-ABSTRACT", in: ctx)
    }

    func testError_abstractPropertyWithDelegate() throws {
        let source = """
        abstract class Base {
            abstract val prop: String by lazy { "error" }  // Error: abstract property cannot have delegate
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        assertHasDiagnostic("KSWIFTK-SEMA-ABSTRACT", in: ctx)
    }

    func testWarning_emptyAbstractClass() throws {
        let source = """
        abstract class EmptyAbstract {
            fun someMethod() {}  // Warning: abstract class has no abstract members
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        assertHasDiagnostic("KSWIFTK-SEMA-ABSTRACT", in: ctx)
        XCTAssertEqual(ctx.diagnostics.diagnostics.first?.severity, .warning)
    }
}

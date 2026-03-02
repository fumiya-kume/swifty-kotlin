@testable import CompilerCore
import Foundation
import XCTest

/// Tests for companion object support (P5-73).
///
/// Fix 1 – TypeCheckHelpers.resolveTypeRef short-name fallback:
///   Packaged types referenced by simple name (e.g. `Foo` instead of
///   `test.Foo`) must resolve during type-checking.
///
/// Fix 2 – Parser unnamed companion object:
///   `companion object { ... }` (without a name) must not emit
///   "Expected declaration name" warning (KSWIFTK-PARSE-0002).
final class CompanionObjectTests: XCTestCase {
    // MARK: - Fix 1: Type resolution short-name fallback for packaged types

    func testPackagedClassInCompanionFunctionReturnTypeResolves() throws {
        let source = """
        package test
        class Foo
        class Bar {
            companion object {
                fun create(): Foo = Foo()
            }
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-SEMA-0025", in: ctx)
    }

    func testPackagedClassInRegularFunctionReturnTypeResolves() throws {
        let source = """
        package test
        class Foo
        fun makeFoo(): Foo = Foo()
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-SEMA-0025", in: ctx)
    }

    func testPackagedClassInFunctionParameterTypeResolves() throws {
        let source = """
        package test
        class Foo
        fun takeFoo(f: Foo): Int = 1
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-SEMA-0025", in: ctx)
    }

    func testNonPackagedTypeResolutionStillWorks() throws {
        let source = """
        class Foo
        fun makeFoo(): Foo = Foo()
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-SEMA-0025", in: ctx)
    }

    func testBuiltinTypesResolveInPackagedContext() throws {
        let source = """
        package test
        fun intFn(): Int = 1
        fun strFn(): String = "hello"
        fun boolFn(): Boolean = true
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-SEMA-0025", in: ctx)
        assertNoDiagnostic("KSWIFTK-TYPE-0001", in: ctx)
    }

    func testUnresolvedTypeStillReportsDiagnostic() throws {
        let source = """
        package test
        fun bad(): NoSuchType = 1
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertHasDiagnostic("KSWIFTK-SEMA-0025", in: ctx)
    }

    func testMultiplePackagedClassesResolveIndependently() throws {
        let source = """
        package test
        class Alpha
        class Beta
        fun makeAlpha(): Alpha = Alpha()
        fun makeBeta(): Beta = Beta()
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-SEMA-0025", in: ctx)
    }

    // MARK: - Fix 2: Parser unnamed companion object

    func testUnnamedCompanionObjectProducesNoParseWarning() throws {
        let source = """
        class Foo {
            companion object {
                fun create(): Int = 1
            }
        }
        """
        let ctx = makeContextFromSource(source)
        try runFrontend(ctx)

        assertNoDiagnostic("KSWIFTK-PARSE-0002", in: ctx)
    }

    func testNamedCompanionObjectProducesNoParseWarning() throws {
        let source = """
        class Foo {
            companion object Factory {
                fun create(): Int = 1
            }
        }
        """
        let ctx = makeContextFromSource(source)
        try runFrontend(ctx)

        assertNoDiagnostic("KSWIFTK-PARSE-0002", in: ctx)
    }

    func testNonCompanionObjectWithNameProducesNoWarning() throws {
        let source = """
        object MySingleton {
            fun value(): Int = 42
        }
        """
        let ctx = makeContextFromSource(source)
        try runFrontend(ctx)

        assertNoDiagnostic("KSWIFTK-PARSE-0002", in: ctx)
    }

    // MARK: - Combined: companion object in packaged context

    func testUnnamedCompanionInPackagedClassResolvesReturnType() throws {
        let source = """
        package test
        class Result
        class Builder {
            companion object {
                fun build(): Result = Result()
            }
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-PARSE-0002", in: ctx)
        assertNoDiagnostic("KSWIFTK-SEMA-0025", in: ctx)
    }

    func testNamedCompanionInPackagedClassResolvesReturnType() throws {
        let source = """
        package test
        class Config
        class App {
            companion object Factory {
                fun defaultConfig(): Config = Config()
            }
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-PARSE-0002", in: ctx)
        assertNoDiagnostic("KSWIFTK-SEMA-0025", in: ctx)
    }

    func testCompanionObjectWithMultipleFunctions() throws {
        let source = """
        package test
        class Item
        class Container {
            companion object {
                fun empty(): Int = 0
                fun single(): Item = Item()
            }
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-PARSE-0002", in: ctx)
        assertNoDiagnostic("KSWIFTK-SEMA-0025", in: ctx)
    }

    // MARK: - KIR emission for companion object

    func testCompanionObjectKIREmissionSucceeds() throws {
        let source = """
        class Foo {
            companion object {
                fun value(): Int = 42
            }
        }
        """
        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)

        XCTAssertFalse(ctx.diagnostics.diagnostics.contains(where: { $0.severity == .error }))
        let module = try XCTUnwrap(ctx.kir)
        XCTAssertGreaterThanOrEqual(module.functionCount, 1)
    }

    func testPackagedCompanionObjectKIREmissionSucceeds() throws {
        let source = """
        package test
        class Foo
        class Bar {
            companion object {
                fun create(): Foo = Foo()
            }
        }
        """
        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)

        XCTAssertFalse(ctx.diagnostics.diagnostics.contains(where: { $0.severity == .error }))
    }

}

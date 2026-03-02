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

    // MARK: - CLASS-001: End-to-end companion object (factory, const val, singleton)

    /// Verify `Foo.create()` companion factory resolves through sema with no errors.
    func testCompanionFactoryFunctionResolvesEndToEnd() throws {
        let source = """
        package test
        class Foo(val x: Int) {
            companion object {
                fun create(): Foo = Foo(0)
            }
        }
        fun main() {
            val f: Foo = Foo.create()
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        XCTAssertFalse(
            ctx.diagnostics.diagnostics.contains(where: { $0.severity == .error }),
            "Expected no sema errors for Foo.create(), got: \(ctx.diagnostics.diagnostics.map(\.code))"
        )
    }

    /// Verify `Foo.MAX_COUNT` const val access resolves through sema with no errors.
    func testCompanionConstValAccessResolvesEndToEnd() throws {
        let source = """
        package test
        class Foo {
            companion object {
                const val MAX_COUNT: Int = 100
            }
        }
        fun main() {
            val m: Int = Foo.MAX_COUNT
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        XCTAssertFalse(
            ctx.diagnostics.diagnostics.contains(where: { $0.severity == .error }),
            "Expected no sema errors for Foo.MAX_COUNT, got: \(ctx.diagnostics.diagnostics.map(\.code))"
        )
    }

    /// Combined: factory function + const val in the same companion, used from main.
    func testCompanionFactoryAndConstValCombinedEndToEnd() throws {
        let source = """
        package test
        class Foo(val x: Int) {
            companion object {
                const val MAX_COUNT: Int = 100
                fun create(): Foo = Foo(0)
            }
        }
        fun main() {
            val f: Foo = Foo.create()
            val m: Int = Foo.MAX_COUNT
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        XCTAssertFalse(
            ctx.diagnostics.diagnostics.contains(where: { $0.severity == .error }),
            "Expected no sema errors, got: \(ctx.diagnostics.diagnostics.map(\.code))"
        )
    }

    /// Verify companion factory + const val lowers to KIR with companion init synthesized.
    func testCompanionFactoryAndConstValKIRLowering() throws {
        let source = """
        package test
        class Foo(val x: Int) {
            companion object {
                const val MAX_COUNT: Int = 100
                fun create(): Foo = Foo(0)
            }
        }
        fun main() {
            val f: Foo = Foo.create()
            val m: Int = Foo.MAX_COUNT
        }
        """
        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)

        XCTAssertFalse(
            ctx.diagnostics.diagnostics.contains(where: { $0.severity == .error }),
            "Expected no KIR errors, got: \(ctx.diagnostics.diagnostics.map(\.code))"
        )

        let module = try XCTUnwrap(ctx.kir)
        let functionNames = module.arena.declarations.compactMap { decl -> String? in
            guard case let .function(function) = decl else { return nil }
            return ctx.interner.resolve(function.name)
        }

        // Companion initializer must be synthesized
        XCTAssertTrue(
            functionNames.contains(where: { $0.hasPrefix("__companion_init_") }),
            "Expected synthesized companion initializer, got: \(functionNames)"
        )

        // The create function must be lowered
        XCTAssertTrue(
            functionNames.contains("create"),
            "Expected companion function 'create' in KIR, got: \(functionNames)"
        )
    }

    /// Verify exactly one companion singleton init function is synthesized.
    func testCompanionSingletonInitSynthesizedExactlyOnce() throws {
        let source = """
        class Host {
            companion object {
                val counter: Int = 1
                fun get(): Int = counter
            }
        }
        fun main() {
            val v: Int = Host.get()
        }
        """
        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)

        XCTAssertFalse(
            ctx.diagnostics.diagnostics.contains(where: { $0.severity == .error }),
            "Expected no errors, got: \(ctx.diagnostics.diagnostics.map(\.code))"
        )

        let module = try XCTUnwrap(ctx.kir)
        // Verify companion init function exists
        let companionInits = module.arena.declarations.compactMap { decl -> String? in
            guard case let .function(function) = decl else { return nil }
            let name = ctx.interner.resolve(function.name)
            return name.hasPrefix("__companion_init_") ? name : nil
        }
        XCTAssertEqual(
            companionInits.count,
            1,
            "Expected exactly one companion initializer, got \(companionInits.count): \(companionInits)"
        )
    }

    /// Named companion object should resolve factory calls via `ClassName.factoryFn()`.
    func testNamedCompanionFactoryResolvesEndToEnd() throws {
        let source = """
        package test
        class Widget {
            companion object Factory {
                fun create(): Widget = Widget()
            }
        }
        fun main() {
            val w: Widget = Widget.create()
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        XCTAssertFalse(
            ctx.diagnostics.diagnostics.contains(where: { $0.severity == .error }),
            "Expected no errors for named companion factory, got: \(ctx.diagnostics.diagnostics.map(\.code))"
        )
    }

    /// Companion lowering through the full pipeline including LoweringPhase.
    func testCompanionObjectFullPipelineLowering() throws {
        let source = """
        class Foo(val x: Int) {
            companion object {
                const val DEFAULT: Int = 42
                fun of(v: Int): Foo = Foo(v)
            }
        }
        fun main() {
            val d: Int = Foo.DEFAULT
            val f: Foo = Foo.of(1)
        }
        """
        let ctx = makeContextFromSource(source)
        try runToLowering(ctx)

        XCTAssertFalse(
            ctx.diagnostics.diagnostics.contains(where: { $0.severity == .error }),
            "Expected no errors after full lowering, got: \(ctx.diagnostics.diagnostics.map(\.code))"
        )
    }

    /// Companion object with property initializer generates correct KIR body.
    func testCompanionPropertyInitializerInKIRBody() throws {
        let source = """
        class Config {
            companion object {
                val defaultTimeout: Int = 30
            }
        }
        fun main(): Int = Config.defaultTimeout
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            XCTAssertFalse(
                ctx.diagnostics.diagnostics.contains(where: { $0.severity == .error }),
                "Expected no KIR errors, got: \(ctx.diagnostics.diagnostics.map(\.code))"
            )

            let module = try XCTUnwrap(ctx.kir)
            // Find the companion init function and verify it has a copy instruction
            // (property initialization writes the initial value)
            let companionInitFn = module.arena.declarations.compactMap { decl -> KIRFunction? in
                guard case let .function(function) = decl else { return nil }
                let name = ctx.interner.resolve(function.name)
                return name.hasPrefix("__companion_init_") ? function : nil
            }.first
            let initBody = try XCTUnwrap(companionInitFn, "Expected companion init function").body
            let hasCopy = initBody.contains { instruction in
                if case .copy = instruction { return true }
                return false
            }
            XCTAssertTrue(hasCopy, "Expected copy instruction in companion init body for property initialization")
        }
    }
}

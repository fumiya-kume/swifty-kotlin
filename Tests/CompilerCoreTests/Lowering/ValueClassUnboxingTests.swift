@testable import CompilerCore
import Foundation
import XCTest

final class ValueClassUnboxingTests: XCTestCase {
    // MARK: - Value class flag propagation

    func testValueModifierSetsValueTypeFlag() throws {
        let source = """
        value class Meter(val amount: Int)
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let sema = try XCTUnwrap(ctx.sema)
        let interner = ctx.interner

        let meterSymbol = try XCTUnwrap(sema.symbols.allSymbols().first(where: { symbol in
            symbol.kind == .class && interner.resolve(symbol.name) == "Meter"
        }))
        XCTAssertTrue(meterSymbol.flags.contains(.valueType), "value class should have valueType flag")
    }

    func testValueClassRecordsUnderlyingType() throws {
        let source = """
        value class Meter(val amount: Int)
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let sema = try XCTUnwrap(ctx.sema)
        let interner = ctx.interner

        let meterSymbol = try XCTUnwrap(sema.symbols.allSymbols().first(where: { symbol in
            symbol.kind == .class && interner.resolve(symbol.name) == "Meter"
        }))
        let underlyingType = sema.symbols.valueClassUnderlyingType(for: meterSymbol.id)
        XCTAssertNotNil(underlyingType, "value class should have an underlying type recorded")

        if let underlyingType {
            let kind = sema.types.kind(of: underlyingType)
            if case .primitive(.int, .nonNull) = kind {
                // Expected
            } else {
                XCTFail("Expected underlying type to be Int, got \(kind)")
            }
        }
    }

    // MARK: - Value class unboxing lowering

    func testValueClassConstructorNotRewrittenWhenPassDisabled() throws {
        // The ValueClassUnboxingPass is currently disabled (shouldRun
        // returns false). Verify that the pass is skipped and that the
        // constructor call is preserved in the KIR — i.e. no .copy
        // rewrite has occurred.
        let source = """
        value class Meter(val amount: Int)

        fun create(): Int {
            val m = Meter(42)
            return m.amount
        }
        """
        let ctx = makeContextFromSource(source)
        try runToLowering(ctx)

        let module = try XCTUnwrap(ctx.kir)

        // The pass name should be recorded even though shouldRun returned
        // false — the lowering framework records skipped passes too.
        XCTAssertTrue(
            module.executedLowerings.contains("ValueClassUnboxing"),
            "ValueClassUnboxing pass should have been recorded"
        )

        // Inspect the lowered KIR to confirm that constructor calls are
        // still present (not rewritten to .copy instructions).
        var hasConstructorCall = false
        var hasCopyRewrite = false
        for decl in module.arena.declarations {
            guard case let .function(function) = decl else { continue }
            for instruction in function.body {
                switch instruction {
                case let .call(symbol, _, _, _, _, _, _):
                    if let symbol,
                       let sym = ctx.sema?.symbols.symbol(symbol),
                       sym.kind == .constructor
                    {
                        hasConstructorCall = true
                    }
                case .copy:
                    hasCopyRewrite = true
                default:
                    break
                }
            }
        }

        // Since the pass is disabled, the constructor call should remain
        // and no .copy rewrite should have been introduced by this pass.
        // Note: other lowering passes may legitimately introduce .copy
        // instructions, so we only assert the constructor call survives.
        XCTAssertTrue(
            hasConstructorCall,
            "Constructor call should be preserved when ValueClassUnboxingPass is disabled"
        )
    }

    // MARK: - Validation diagnostics

    func testValueClassMultipleParamsEmitsDiagnostic() throws {
        let source = """
        value class Bad(val x: Int, val y: Int)
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.contains(where: { $0.message.contains("exactly one primary constructor parameter") }),
            "Expected diagnostic about single constructor parameter for value class"
        )
    }

    func testValueClassSecondaryConstructorEmitsDiagnostic() throws {
        let source = """
        value class Bad(val x: Int) {
            constructor() : this(0)
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.contains(where: { $0.message.contains("secondary constructors") }),
            "Expected diagnostic about secondary constructors for value class"
        )
    }
}

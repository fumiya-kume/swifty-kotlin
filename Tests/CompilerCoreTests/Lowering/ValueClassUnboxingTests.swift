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

    func testValueClassConstructorRewrittenToCopy() throws {
        // The ValueClassUnboxingPass is now enabled and rewrites constructor
        // calls for value classes into .copy instructions.
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

        // The pass name should be recorded.
        XCTAssertTrue(
            module.executedLowerings.contains("ValueClassUnboxing"),
            "ValueClassUnboxing pass should have been recorded"
        )

        // After unboxing, constructor calls for value classes should be
        // eliminated (rewritten to .copy or removed entirely).
        var hasValueClassConstructorCall = false
        for decl in module.arena.declarations {
            guard case let .function(function) = decl else { continue }
            for instruction in function.body {
                switch instruction {
                case let .call(symbol, _, _, _, _, _, _):
                    if let symbol,
                       let sym = ctx.sema?.symbols.symbol(symbol),
                       sym.kind == .constructor,
                       sym.flags.contains(.valueType) || {
                           // Check if the parent class is a value class
                           guard let parentID = ctx.sema?.symbols.parentSymbol(for: symbol),
                                 let parentSym = ctx.sema?.symbols.symbol(parentID)
                           else { return false }
                           return parentSym.flags.contains(.valueType)
                       }()
                    {
                        hasValueClassConstructorCall = true
                    }
                default:
                    break
                }
            }
        }

        XCTAssertFalse(
            hasValueClassConstructorCall,
            "Value class constructor call should be rewritten by ValueClassUnboxingPass"
        )
    }

    func testValueClassPropertyAccessRewrittenToCopy() throws {
        // Property access on a value class via kk_array_get_inbounds should be
        // rewritten to a copy instruction after unboxing.
        let source = """
        value class Meter(val amount: Int)

        fun getAmount(m: Meter): Int = m.amount
        """
        let ctx = makeContextFromSource(source)
        try runToLowering(ctx)

        let module = try XCTUnwrap(ctx.kir)
        let interner = ctx.interner
        let kk_array_get_inbounds = interner.intern("kk_array_get_inbounds")

        // After unboxing, there should be no kk_array_get_inbounds calls
        // on value class receivers.
        var hasArrayGetOnValueClass = false
        for decl in module.arena.declarations {
            guard case let .function(function) = decl else { continue }
            for instruction in function.body {
                if case let .call(_, callee, arguments, _, _, _, _) = instruction,
                   callee == kk_array_get_inbounds,
                   arguments.count == 2
                {
                    // Check if the receiver argument has a value class type
                    if let receiverType = module.arena.exprType(arguments[0]),
                       case let .classType(classType) = ctx.sema?.types.kind(of: receiverType),
                       let sym = ctx.sema?.symbols.symbol(classType.classSymbol),
                       sym.flags.contains(.valueType)
                    {
                        hasArrayGetOnValueClass = true
                    }
                }
            }
        }

        XCTAssertFalse(
            hasArrayGetOnValueClass,
            "kk_array_get_inbounds on value class should be rewritten to copy"
        )
    }

    func testValueClassNoHeapAllocation() throws {
        // After unboxing, kk_object_new calls for value class instances
        // should be eliminated.
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
        let interner = ctx.interner
        let kk_object_new = interner.intern("kk_object_new")

        // Scan for kk_object_new calls whose result has a value class type
        var hasValueClassAlloc = false
        for decl in module.arena.declarations {
            guard case let .function(function) = decl else { continue }
            for instruction in function.body {
                if case let .call(_, callee, _, result, _, _, _) = instruction,
                   callee == kk_object_new,
                   let result,
                   let resultType = module.arena.exprType(result),
                   case let .classType(classType) = ctx.sema?.types.kind(of: resultType),
                   let sym = ctx.sema?.symbols.symbol(classType.classSymbol),
                   sym.flags.contains(.valueType)
                {
                    hasValueClassAlloc = true
                }
            }
        }

        XCTAssertFalse(
            hasValueClassAlloc,
            "kk_object_new for value class should be eliminated by unboxing"
        )
    }

    func testNonValueClassNotAffected() throws {
        // Regular classes should not be affected by the unboxing pass.
        let source = """
        class Box(val value: Int)

        fun create(): Int {
            val b = Box(42)
            return b.value
        }
        """
        let ctx = makeContextFromSource(source)
        try runToLowering(ctx)

        let module = try XCTUnwrap(ctx.kir)
        let interner = ctx.interner
        let kk_object_new = interner.intern("kk_object_new")

        // Regular classes should still have kk_object_new calls.
        var hasObjectNew = false
        for decl in module.arena.declarations {
            guard case let .function(function) = decl else { continue }
            for instruction in function.body {
                if case let .call(_, callee, _, _, _, _, _) = instruction,
                   callee == kk_object_new
                {
                    hasObjectNew = true
                }
            }
        }

        XCTAssertTrue(
            hasObjectNew,
            "Regular class should still use kk_object_new for allocation"
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

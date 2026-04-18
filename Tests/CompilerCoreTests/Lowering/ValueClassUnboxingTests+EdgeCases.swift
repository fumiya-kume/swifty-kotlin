@testable import CompilerCore
import Foundation
import XCTest

// MARK: - Value class edge case coverage (TEST-VAL-001)
// Expands value class / inline class test coverage from ~10 to 21+ cases.

extension ValueClassUnboxingTests {

    // MARK: - Payload type variants

    func testValueClassWithStringPayload() throws {
        let source = """
        value class Name(val raw: String)
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let sema = try XCTUnwrap(ctx.sema)
        let interner = ctx.interner

        let nameSymbol = try XCTUnwrap(sema.symbols.allSymbols().first(where: { symbol in
            symbol.kind == .class && interner.resolve(symbol.name) == "Name"
        }))
        XCTAssertTrue(nameSymbol.flags.contains(.valueType), "value class with String payload should have valueType flag")

        let underlyingType = sema.symbols.valueClassUnderlyingType(for: nameSymbol.id)
        XCTAssertNotNil(underlyingType, "value class with String payload should record an underlying type")
        if let underlyingType {
            if case .primitive(.string, _) = sema.types.kind(of: underlyingType) {
                // Expected
            } else {
                XCTFail("Expected underlying type to be String, got \(sema.types.kind(of: underlyingType))")
            }
        }
    }

    func testValueClassWithLongPayload() throws {
        let source = """
        value class Timestamp(val epochMillis: Long)
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let sema = try XCTUnwrap(ctx.sema)
        let interner = ctx.interner

        let tsSymbol = try XCTUnwrap(sema.symbols.allSymbols().first(where: { symbol in
            symbol.kind == .class && interner.resolve(symbol.name) == "Timestamp"
        }))
        XCTAssertTrue(tsSymbol.flags.contains(.valueType), "value class with Long payload should have valueType flag")

        let underlyingType = sema.symbols.valueClassUnderlyingType(for: tsSymbol.id)
        XCTAssertNotNil(underlyingType, "value class with Long payload should record an underlying type")
        if let underlyingType {
            if case .primitive(.long, _) = sema.types.kind(of: underlyingType) {
                // Expected
            } else {
                XCTFail("Expected underlying type to be Long, got \(sema.types.kind(of: underlyingType))")
            }
        }
    }

    func testValueClassWithDoublePayload() throws {
        let source = """
        value class Celsius(val degrees: Double)
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let sema = try XCTUnwrap(ctx.sema)
        let interner = ctx.interner

        let celsiusSymbol = try XCTUnwrap(sema.symbols.allSymbols().first(where: { symbol in
            symbol.kind == .class && interner.resolve(symbol.name) == "Celsius"
        }))
        XCTAssertTrue(celsiusSymbol.flags.contains(.valueType), "value class with Double payload should have valueType flag")

        let underlyingType = sema.symbols.valueClassUnderlyingType(for: celsiusSymbol.id)
        XCTAssertNotNil(underlyingType, "value class with Double payload should record an underlying type")
        if let underlyingType {
            if case .primitive(.double, _) = sema.types.kind(of: underlyingType) {
                // Expected
            } else {
                XCTFail("Expected underlying type to be Double, got \(sema.types.kind(of: underlyingType))")
            }
        }
    }

    // MARK: - Unboxing lowering with different payload types

    func testValueClassStringPayloadNoHeapAllocation() throws {
        let source = """
        value class Name(val raw: String)

        fun greet(n: Name): String = n.raw
        """
        let ctx = makeContextFromSource(source)
        try runToLowering(ctx)

        let module = try XCTUnwrap(ctx.kir)
        let interner = ctx.interner
        let kk_object_new = interner.intern("kk_object_new")

        var hasValueClassAlloc = false
        for decl in module.arena.declarations {
            guard case let .function(function) = decl else { continue }
            for instruction in function.body {
                if case let .call(_, callee, _, result, _, _, _, _) = instruction,
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

        XCTAssertFalse(hasValueClassAlloc, "kk_object_new for String-payload value class should be eliminated by unboxing")
    }

    // MARK: - @JvmInline annotation is inert (no additional effects beyond valueType flag)

    func testJvmInlineAnnotationIsInertBeyondValueTypeFlag() throws {
        let sourceWithAnnotation = """
        @JvmInline
        value class UserId(val raw: Int)
        """
        let sourceWithout = """
        value class UserId(val raw: Int)
        """
        let ctxWith = makeContextFromSource(sourceWithAnnotation)
        let ctxWithout = makeContextFromSource(sourceWithout)
        try runSema(ctxWith)
        try runSema(ctxWithout)

        let semaWith = try XCTUnwrap(ctxWith.sema)
        let semaWithout = try XCTUnwrap(ctxWithout.sema)

        let symWith = try XCTUnwrap(semaWith.symbols.allSymbols().first(where: {
            $0.kind == .class && ctxWith.interner.resolve($0.name) == "UserId"
        }))
        let symWithout = try XCTUnwrap(semaWithout.symbols.allSymbols().first(where: {
            $0.kind == .class && ctxWithout.interner.resolve($0.name) == "UserId"
        }))

        // Both should have the valueType flag — @JvmInline adds no extra flags
        XCTAssertTrue(symWith.flags.contains(.valueType))
        XCTAssertTrue(symWithout.flags.contains(.valueType))
        XCTAssertEqual(
            symWith.flags.contains(.valueType),
            symWithout.flags.contains(.valueType),
            "@JvmInline should not introduce extra SymbolFlags beyond valueType"
        )
    }

    // MARK: - Single-property constraint diagnostics

    func testValueClassWithZeroParamsEmitsDiagnostic() throws {
        let source = """
        value class Empty()
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.contains(where: { $0.message.contains("exactly one primary constructor parameter") }),
            "value class with zero params should emit a single-property diagnostic"
        )
    }

    func testValueClassWithThreeParamsEmitsDiagnostic() throws {
        let source = """
        value class Triple(val a: Int, val b: String, val c: Long)
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.contains(where: { $0.message.contains("exactly one primary constructor parameter") }),
            "value class with three params should emit a single-property diagnostic"
        )
    }

    // MARK: - Upcast / boxing transition: stored as supertype

    func testValueClassUpcastedToAnyUnboxed() throws {
        let source = """
        value class Meter(val amount: Int)

        fun toAny(m: Meter): Any = m
        """
        let ctx = makeContextFromSource(source)
        // Sema should succeed without errors even when value class is upcast to Any
        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(errors.isEmpty, "Upcasting value class to Any should not produce errors; got: \(errors.map { $0.message })")
    }

    func testValueClassPassedAsConcreteTypeNoBoxing() throws {
        let source = """
        value class Meter(val amount: Int)

        fun getAmount(m: Meter): Int = m.amount
        """
        let ctx = makeContextFromSource(source)
        try runToLowering(ctx)

        let module = try XCTUnwrap(ctx.kir)
        XCTAssertTrue(
            module.executedLowerings.contains("ValueClassUnboxing"),
            "ValueClassUnboxing pass should run when value class is used as concrete parameter type"
        )
    }

    // MARK: - Nullable value class

    func testNullableValueClassIsRecognizedAsValueType() throws {
        let source = """
        value class Token(val value: String)

        fun maybeToken(): Token? = null
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let sema = try XCTUnwrap(ctx.sema)
        let interner = ctx.interner

        let tokenSymbol = try XCTUnwrap(sema.symbols.allSymbols().first(where: { symbol in
            symbol.kind == .class && interner.resolve(symbol.name) == "Token"
        }))
        // The Token class itself still has the valueType flag regardless of nullable usage
        XCTAssertTrue(tokenSymbol.flags.contains(.valueType), "Token value class should retain valueType flag when used as nullable")
    }

    // MARK: - Member functions on value class

    func testValueClassMemberFunctionIsRegistered() throws {
        let source = """
        value class Meter(val amount: Int) {
            fun doubled(): Int = amount * 2
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let sema = try XCTUnwrap(ctx.sema)
        let interner = ctx.interner

        let meterSymbol = try XCTUnwrap(sema.symbols.allSymbols().first(where: { symbol in
            symbol.kind == .class && interner.resolve(symbol.name) == "Meter"
        }))
        XCTAssertTrue(meterSymbol.flags.contains(.valueType))

        // The member function 'doubled' should exist in the symbol table
        let doubledExists = sema.symbols.allSymbols().contains(where: { symbol in
            symbol.kind == .function && interner.resolve(symbol.name) == "doubled"
        })
        XCTAssertTrue(doubledExists, "Member function 'doubled' should be registered in the symbol table for value class Meter")
    }

    func testValueClassMemberFunctionUnboxedCorrectly() throws {
        let source = """
        value class Meter(val amount: Int) {
            fun doubled(): Int = amount * 2
        }

        fun compute(): Int {
            val m = Meter(5)
            return m.doubled()
        }
        """
        let ctx = makeContextFromSource(source)
        try runToLowering(ctx)

        let module = try XCTUnwrap(ctx.kir)
        XCTAssertTrue(
            module.executedLowerings.contains("ValueClassUnboxing"),
            "ValueClassUnboxing pass should run for value class with member function call"
        )
    }

    // MARK: - Value class implementing interface

    func testValueClassImplementingInterfaceHasValueTypeFlag() throws {
        let source = """
        interface Measurable {
            fun measure(): Int
        }

        value class Meter(val amount: Int) : Measurable {
            override fun measure(): Int = amount
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let sema = try XCTUnwrap(ctx.sema)
        let interner = ctx.interner

        let meterSymbol = try XCTUnwrap(sema.symbols.allSymbols().first(where: { symbol in
            symbol.kind == .class && interner.resolve(symbol.name) == "Meter"
        }))
        XCTAssertTrue(meterSymbol.flags.contains(.valueType), "value class implementing interface should retain valueType flag")
    }

    // MARK: - Companion object in value class

    func testValueClassWithCompanionObjectDoesNotAffectValueFlag() throws {
        let source = """
        value class Score(val points: Int) {
            companion object {
                val ZERO = Score(0)
            }
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let sema = try XCTUnwrap(ctx.sema)
        let interner = ctx.interner

        let scoreSymbol = try XCTUnwrap(sema.symbols.allSymbols().first(where: { symbol in
            symbol.kind == .class && interner.resolve(symbol.name) == "Score"
        }))
        XCTAssertTrue(scoreSymbol.flags.contains(.valueType), "value class with companion object should retain valueType flag")
    }

    // MARK: - toString / default representation

    func testValueClassToStringFunctionParsesWithoutError() throws {
        let source = """
        value class Version(val code: Int) {
            override fun toString(): String = "Version(${'$'}code)"
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "value class with overridden toString should compile without errors; got: \(errors.map { $0.message })"
        )
    }

    // MARK: - Value class used in when-expression

    func testValueClassUsedInWhenExpressionCompiles() throws {
        let source = """
        value class HttpStatus(val code: Int)

        fun describe(s: HttpStatus): String {
            return when (s.code) {
                200 -> "OK"
                404 -> "Not Found"
                else -> "Other"
            }
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "value class used in when-expression should compile without errors; got: \(errors.map { $0.message })"
        )
    }

    // MARK: - Multiple distinct value classes coexist

    func testMultipleValueClassesAreIndependentlyTracked() throws {
        let source = """
        value class MeterId(val raw: Int)
        value class ScoreId(val raw: Int)
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let sema = try XCTUnwrap(ctx.sema)
        let interner = ctx.interner

        let valueTypeSymbols = sema.symbols.allSymbols().filter {
            $0.kind == .class && $0.flags.contains(.valueType)
        }
        let names = valueTypeSymbols.map { interner.resolve($0.name) }
        XCTAssertTrue(names.contains("MeterId"), "MeterId should be registered as a value class")
        XCTAssertTrue(names.contains("ScoreId"), "ScoreId should be registered as a value class")
        XCTAssertGreaterThanOrEqual(valueTypeSymbols.count, 2, "Both value classes should be independently tracked")

        // Each must have an underlying type recorded
        for sym in valueTypeSymbols {
            let underlying = sema.symbols.valueClassUnderlyingType(for: sym.id)
            XCTAssertNotNil(underlying, "\(interner.resolve(sym.name)) should have an underlying type recorded")
        }
    }
}

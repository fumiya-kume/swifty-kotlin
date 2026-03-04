@testable import CompilerCore
import XCTest

extension OverloadResolverTests {
    func testResolveCallAllowsOmittedDefaultArguments() {
        let (resolver, types, symbols, interner, ctx) = makeEnv()

        let intType = types.make(.primitive(.int, .nonNull))
        let fn = defineSymbol(
            kind: .function,
            name: "withDefault",
            suffix: "withDefault",
            symbols: symbols,
            interner: interner
        )
        let paramA = defineSymbol(
            kind: .valueParameter,
            name: "a",
            suffix: "withDefault_a",
            symbols: symbols,
            interner: interner
        )
        let paramB = defineSymbol(
            kind: .valueParameter,
            name: "b",
            suffix: "withDefault_b",
            symbols: symbols,
            interner: interner
        )
        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: [intType, intType],
                returnType: intType,
                valueParameterSymbols: [paramA, paramB],
                valueParameterHasDefaultValues: [false, true]
            ),
            for: fn
        )

        let call = CallExpr(
            range: makeRange(start: 70, end: 81),
            calleeName: interner.intern("withDefault"),
            args: [CallArg(type: intType)]
        )
        let resolved = resolver.resolveCall(
            candidates: [fn],
            call: call,
            expectedType: nil,
            ctx: ctx
        )

        XCTAssertEqual(resolved.chosenCallee, fn)
        XCTAssertNil(resolved.diagnostic)
        XCTAssertEqual(resolved.parameterMapping, [0: 0])
    }

    func testResolveCallSupportsNamedArgumentsAndParameterMapping() {
        let (resolver, types, symbols, interner, ctx) = makeEnv()

        let intType = types.make(.primitive(.int, .nonNull))
        let boolType = types.make(.primitive(.boolean, .nonNull))
        let fn = defineSymbol(
            kind: .function,
            name: "named",
            suffix: "named",
            symbols: symbols,
            interner: interner
        )
        let paramX = defineSymbol(
            kind: .valueParameter,
            name: "x",
            suffix: "named_x",
            symbols: symbols,
            interner: interner
        )
        let paramFlag = defineSymbol(
            kind: .valueParameter,
            name: "flag",
            suffix: "named_flag",
            symbols: symbols,
            interner: interner
        )
        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: [intType, boolType],
                returnType: boolType,
                valueParameterSymbols: [paramX, paramFlag]
            ),
            for: fn
        )

        let call = CallExpr(
            range: makeRange(start: 82, end: 99),
            calleeName: interner.intern("named"),
            args: [
                CallArg(label: interner.intern("flag"), type: boolType),
                CallArg(label: interner.intern("x"), type: intType)
            ]
        )
        let resolved = resolver.resolveCall(
            candidates: [fn],
            call: call,
            expectedType: nil,
            ctx: ctx
        )

        XCTAssertEqual(resolved.chosenCallee, fn)
        XCTAssertNil(resolved.diagnostic)
        XCTAssertEqual(resolved.parameterMapping, [0: 1, 1: 0])
    }

    func testResolveCallSupportsMixedPositionalAndNamedArguments() {
        let (resolver, types, symbols, interner, ctx) = makeEnv()

        let intType = types.make(.primitive(.int, .nonNull))
        let boolType = types.make(.primitive(.boolean, .nonNull))
        let fn = defineSymbol(
            kind: .function,
            name: "mix",
            suffix: "mix",
            symbols: symbols,
            interner: interner
        )
        let paramX = defineSymbol(
            kind: .valueParameter,
            name: "x",
            suffix: "mix_x",
            symbols: symbols,
            interner: interner
        )
        let paramFlag = defineSymbol(
            kind: .valueParameter,
            name: "flag",
            suffix: "mix_flag",
            symbols: symbols,
            interner: interner
        )
        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: [intType, boolType],
                returnType: boolType,
                valueParameterSymbols: [paramX, paramFlag]
            ),
            for: fn
        )

        let call = CallExpr(
            range: makeRange(start: 95, end: 114),
            calleeName: interner.intern("mix"),
            args: [
                CallArg(type: intType),
                CallArg(label: interner.intern("flag"), type: boolType)
            ]
        )
        let resolved = resolver.resolveCall(
            candidates: [fn],
            call: call,
            expectedType: nil,
            ctx: ctx
        )

        XCTAssertEqual(resolved.chosenCallee, fn)
        XCTAssertNil(resolved.diagnostic)
        XCTAssertEqual(resolved.parameterMapping, [0: 0, 1: 1])
    }

    func testResolveCallRejectsPositionalArgumentAfterNamedArgument() {
        let (resolver, types, symbols, interner, ctx) = makeEnv()

        let intType = types.make(.primitive(.int, .nonNull))
        let boolType = types.make(.primitive(.boolean, .nonNull))
        let fn = defineSymbol(
            kind: .function,
            name: "mixBad",
            suffix: "mixBad",
            symbols: symbols,
            interner: interner
        )
        let paramX = defineSymbol(
            kind: .valueParameter,
            name: "x",
            suffix: "mixBad_x",
            symbols: symbols,
            interner: interner
        )
        let paramFlag = defineSymbol(
            kind: .valueParameter,
            name: "flag",
            suffix: "mixBad_flag",
            symbols: symbols,
            interner: interner
        )
        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: [intType, boolType],
                returnType: boolType,
                valueParameterSymbols: [paramX, paramFlag]
            ),
            for: fn
        )

        let call = CallExpr(
            range: makeRange(start: 115, end: 137),
            calleeName: interner.intern("mixBad"),
            args: [
                CallArg(label: interner.intern("flag"), type: boolType),
                CallArg(type: intType)
            ]
        )
        let resolved = resolver.resolveCall(
            candidates: [fn],
            call: call,
            expectedType: nil,
            ctx: ctx
        )

        XCTAssertNil(resolved.chosenCallee)
        XCTAssertEqual(resolved.diagnostic?.code, "KSWIFTK-SEMA-0002")
    }

    func testResolveCallSupportsTrailingVarargMapping() {
        let (resolver, types, symbols, interner, ctx) = makeEnv()

        let intType = types.make(.primitive(.int, .nonNull))
        let fn = defineSymbol(
            kind: .function,
            name: "varargFn",
            suffix: "varargFn",
            symbols: symbols,
            interner: interner
        )
        let paramHead = defineSymbol(
            kind: .valueParameter,
            name: "head",
            suffix: "vararg_head",
            symbols: symbols,
            interner: interner
        )
        let paramTail = defineSymbol(
            kind: .valueParameter,
            name: "tail",
            suffix: "vararg_tail",
            symbols: symbols,
            interner: interner
        )
        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: [intType, intType],
                returnType: intType,
                valueParameterSymbols: [paramHead, paramTail],
                valueParameterIsVararg: [false, true]
            ),
            for: fn
        )

        let call = CallExpr(
            range: makeRange(start: 100, end: 119),
            calleeName: interner.intern("varargFn"),
            args: [CallArg(type: intType), CallArg(type: intType), CallArg(type: intType)]
        )
        let resolved = resolver.resolveCall(
            candidates: [fn],
            call: call,
            expectedType: nil,
            ctx: ctx
        )

        XCTAssertEqual(resolved.chosenCallee, fn)
        XCTAssertNil(resolved.diagnostic)
        XCTAssertEqual(resolved.parameterMapping, [0: 0, 1: 1, 2: 1])
    }

    func testResolveCallSupportsNonTrailingVarargWithNamedTail() {
        let (resolver, types, symbols, interner, ctx) = makeEnv()

        let intType = types.make(.primitive(.int, .nonNull))
        let boolType = types.make(.primitive(.boolean, .nonNull))
        let fn = defineSymbol(
            kind: .function,
            name: "nonTrailingVararg",
            suffix: "nonTrailingVararg",
            symbols: symbols,
            interner: interner
        )
        let paramNums = defineSymbol(
            kind: .valueParameter,
            name: "nums",
            suffix: "nonTrailingVararg_nums",
            symbols: symbols,
            interner: interner
        )
        let paramTail = defineSymbol(
            kind: .valueParameter,
            name: "tail",
            suffix: "nonTrailingVararg_tail",
            symbols: symbols,
            interner: interner
        )
        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: [intType, boolType],
                returnType: boolType,
                valueParameterSymbols: [paramNums, paramTail],
                valueParameterIsVararg: [true, false]
            ),
            for: fn
        )

        let call = CallExpr(
            range: makeRange(start: 138, end: 170),
            calleeName: interner.intern("nonTrailingVararg"),
            args: [
                CallArg(type: intType),
                CallArg(type: intType),
                CallArg(label: interner.intern("tail"), type: boolType)
            ]
        )
        let resolved = resolver.resolveCall(
            candidates: [fn],
            call: call,
            expectedType: nil,
            ctx: ctx
        )

        XCTAssertEqual(resolved.chosenCallee, fn)
        XCTAssertNil(resolved.diagnostic)
        XCTAssertEqual(resolved.parameterMapping, [0: 0, 1: 0, 2: 1])
    }

    func testResolveCallRejectsSpreadArgumentForNonVarargParameter() {
        let (resolver, types, symbols, interner, ctx) = makeEnv()

        let intType = types.make(.primitive(.int, .nonNull))
        let fn = defineSymbol(
            kind: .function,
            name: "spreadBad",
            suffix: "spreadBad",
            symbols: symbols,
            interner: interner
        )
        let paramX = defineSymbol(
            kind: .valueParameter,
            name: "x",
            suffix: "spreadBad_x",
            symbols: symbols,
            interner: interner
        )
        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: [intType],
                returnType: intType,
                valueParameterSymbols: [paramX]
            ),
            for: fn
        )

        let call = CallExpr(
            range: makeRange(start: 171, end: 188),
            calleeName: interner.intern("spreadBad"),
            args: [CallArg(isSpread: true, type: intType)]
        )
        let resolved = resolver.resolveCall(
            candidates: [fn],
            call: call,
            expectedType: nil,
            ctx: ctx
        )

        XCTAssertNil(resolved.chosenCallee)
        XCTAssertEqual(resolved.diagnostic?.code, "KSWIFTK-SEMA-0002")
    }

    func testResolveCallAcceptsGenericWithSatisfiedUpperBound() {
        let (resolver, types, symbols, interner, ctx) = makeEnv()

        let intType = types.make(.primitive(.int, .nonNull))
        let anyType = types.anyType
        let typeParamSymbol = defineSymbol(
            kind: .typeParameter,
            name: "T",
            suffix: "bound_ok_T",
            symbols: symbols,
            interner: interner
        )
        let typeParamType = types.make(.typeParam(TypeParamType(symbol: typeParamSymbol, nullability: .nonNull)))

        let generic = defineSymbol(
            kind: .function,
            name: "bounded",
            suffix: "bound_ok",
            symbols: symbols,
            interner: interner
        )
        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: [typeParamType],
                returnType: typeParamType,
                typeParameterSymbols: [typeParamSymbol],
                typeParameterUpperBounds: [anyType]
            ),
            for: generic
        )

        let call = CallExpr(
            range: makeRange(start: 200, end: 210),
            calleeName: interner.intern("bounded"),
            args: [CallArg(type: intType)]
        )
        let resolved = resolver.resolveCall(
            candidates: [generic],
            call: call,
            expectedType: nil,
            ctx: ctx
        )

        XCTAssertEqual(resolved.chosenCallee, generic)
        XCTAssertNil(resolved.diagnostic)
    }

    func testResolveCallRejectsGenericWithViolatedUpperBound() {
        let (resolver, types, symbols, interner, ctx) = makeEnv()

        let intType = types.make(.primitive(.int, .nonNull))
        let boolType = types.make(.primitive(.boolean, .nonNull))
        let typeParamSymbol = defineSymbol(
            kind: .typeParameter,
            name: "T",
            suffix: "bound_bad_T",
            symbols: symbols,
            interner: interner
        )
        let typeParamType = types.make(.typeParam(TypeParamType(symbol: typeParamSymbol, nullability: .nonNull)))

        let generic = defineSymbol(
            kind: .function,
            name: "bounded",
            suffix: "bound_bad",
            symbols: symbols,
            interner: interner
        )
        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: [typeParamType],
                returnType: typeParamType,
                typeParameterSymbols: [typeParamSymbol],
                typeParameterUpperBounds: [boolType]
            ),
            for: generic
        )

        let call = CallExpr(
            range: makeRange(start: 211, end: 220),
            calleeName: interner.intern("bounded"),
            args: [CallArg(type: intType)]
        )
        let resolved = resolver.resolveCall(
            candidates: [generic],
            call: call,
            expectedType: nil,
            ctx: ctx
        )

        XCTAssertNil(resolved.chosenCallee)
        XCTAssertEqual(resolved.diagnostic?.code, "KSWIFTK-SEMA-0030")
    }

    // MARK: - Advanced Named Arguments Tests

    // Named arguments with 3 parameters reordered out of order.
}

@testable import CompilerCore
import XCTest

extension OverloadResolverTests {
    func testResolveCallRejectsGenericWithViolatedUpperBoundFromSymbolTable() {
        let (resolver, types, symbols, interner, ctx) = makeEnv()

        let intType = types.make(.primitive(.int, .nonNull))
        let boolType = types.make(.primitive(.boolean, .nonNull))
        let typeParamSymbol = defineSymbol(
            kind: .typeParameter,
            name: "T",
            suffix: "bound_st_T",
            symbols: symbols,
            interner: interner
        )
        let typeParamType = types.make(.typeParam(TypeParamType(symbol: typeParamSymbol, nullability: .nonNull)))

        let generic = defineSymbol(
            kind: .function,
            name: "bounded",
            suffix: "bound_st",
            symbols: symbols,
            interner: interner
        )
        symbols.setTypeParameterUpperBound(boolType, for: typeParamSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: [typeParamType],
                returnType: typeParamType,
                typeParameterSymbols: [typeParamSymbol]
            ),
            for: generic
        )

        let call = CallExpr(
            range: makeRange(start: 221, end: 230),
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

    func testResolveCallHandlesOversizedFlagsArrays() {
        let (resolver, types, symbols, interner, ctx) = makeEnv()

        let intType = types.make(.primitive(.int, .nonNull))
        let fn = defineSymbol(kind: .function, name: "overflags", suffix: "overflags", symbols: symbols, interner: interner)
        let paramA = defineSymbol(kind: .valueParameter, name: "a", suffix: "overflags_a", symbols: symbols, interner: interner)
        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: [intType],
                returnType: intType,
                valueParameterSymbols: [paramA],
                valueParameterHasDefaultValues: [false, true, false],
                valueParameterIsVararg: [false, false, true]
            ),
            for: fn
        )

        let call = CallExpr(
            range: makeRange(start: 300, end: 310),
            calleeName: interner.intern("overflags"),
            args: [CallArg(type: intType)]
        )
        let resolved = resolver.resolveCall(candidates: [fn], call: call, expectedType: nil, ctx: ctx)
        XCTAssertEqual(resolved.chosenCallee, fn)
        XCTAssertNil(resolved.diagnostic)
    }

    func testResolveCallHandlesUndersizedFlagsArrays() {
        let (resolver, types, symbols, interner, ctx) = makeEnv()

        let intType = types.make(.primitive(.int, .nonNull))
        let fn = defineSymbol(kind: .function, name: "underflags", suffix: "underflags", symbols: symbols, interner: interner)
        let paramA = defineSymbol(kind: .valueParameter, name: "a", suffix: "underflags_a", symbols: symbols, interner: interner)
        let paramB = defineSymbol(kind: .valueParameter, name: "b", suffix: "underflags_b", symbols: symbols, interner: interner)
        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: [intType, intType],
                returnType: intType,
                valueParameterSymbols: [paramA, paramB],
                valueParameterHasDefaultValues: [false]
            ),
            for: fn
        )

        let call = CallExpr(
            range: makeRange(start: 311, end: 320),
            calleeName: interner.intern("underflags"),
            args: [CallArg(type: intType), CallArg(type: intType)]
        )
        let resolved = resolver.resolveCall(candidates: [fn], call: call, expectedType: nil, ctx: ctx)
        XCTAssertEqual(resolved.chosenCallee, fn)
    }

    func testResolveCallRejectsDuplicateNamedArgument() {
        let (resolver, types, symbols, interner, ctx) = makeEnv()

        let intType = types.make(.primitive(.int, .nonNull))
        let fn = defineSymbol(kind: .function, name: "dupNamed", suffix: "dupNamed", symbols: symbols, interner: interner)
        let paramX = defineSymbol(kind: .valueParameter, name: "x", suffix: "dupNamed_x", symbols: symbols, interner: interner)
        symbols.setFunctionSignature(
            FunctionSignature(parameterTypes: [intType], returnType: intType, valueParameterSymbols: [paramX]),
            for: fn
        )

        let call = CallExpr(
            range: makeRange(start: 321, end: 330),
            calleeName: interner.intern("dupNamed"),
            args: [
                CallArg(label: interner.intern("x"), type: intType),
                CallArg(label: interner.intern("x"), type: intType),
            ]
        )
        let resolved = resolver.resolveCall(candidates: [fn], call: call, expectedType: nil, ctx: ctx)
        XCTAssertNil(resolved.chosenCallee)
    }

    func testResolveCallRejectsNamedSpreadOnNonVararg() {
        let (resolver, types, symbols, interner, ctx) = makeEnv()

        let intType = types.make(.primitive(.int, .nonNull))
        let fn = defineSymbol(kind: .function, name: "namedSpreadBad", suffix: "namedSpreadBad", symbols: symbols, interner: interner)
        let paramX = defineSymbol(kind: .valueParameter, name: "x", suffix: "namedSpreadBad_x", symbols: symbols, interner: interner)
        symbols.setFunctionSignature(
            FunctionSignature(parameterTypes: [intType], returnType: intType, valueParameterSymbols: [paramX]),
            for: fn
        )

        let call = CallExpr(
            range: makeRange(start: 331, end: 340),
            calleeName: interner.intern("namedSpreadBad"),
            args: [CallArg(label: interner.intern("x"), isSpread: true, type: intType)]
        )
        let resolved = resolver.resolveCall(candidates: [fn], call: call, expectedType: nil, ctx: ctx)
        XCTAssertNil(resolved.chosenCallee)
    }

    func testResolveCallRejectsArgsForZeroParamFunction() {
        let (resolver, types, symbols, interner, ctx) = makeEnv()

        let intType = types.make(.primitive(.int, .nonNull))
        let fn = defineSymbol(kind: .function, name: "noParams", suffix: "noParams", symbols: symbols, interner: interner)
        symbols.setFunctionSignature(
            FunctionSignature(parameterTypes: [], returnType: intType),
            for: fn
        )

        let call = CallExpr(
            range: makeRange(start: 351, end: 360),
            calleeName: interner.intern("noParams"),
            args: [CallArg(type: intType)]
        )
        let resolved = resolver.resolveCall(candidates: [fn], call: call, expectedType: nil, ctx: ctx)
        XCTAssertNil(resolved.chosenCallee)
    }

    func testResolveCallAcceptsNamedVarargArgument() {
        let (resolver, types, symbols, interner, ctx) = makeEnv()

        let intType = types.make(.primitive(.int, .nonNull))
        let fn = defineSymbol(kind: .function, name: "namedVararg", suffix: "namedVararg", symbols: symbols, interner: interner)
        let paramX = defineSymbol(kind: .valueParameter, name: "x", suffix: "namedVararg_x", symbols: symbols, interner: interner)
        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: [intType],
                returnType: intType,
                valueParameterSymbols: [paramX],
                valueParameterIsVararg: [true]
            ),
            for: fn
        )

        let call = CallExpr(
            range: makeRange(start: 371, end: 380),
            calleeName: interner.intern("namedVararg"),
            args: [
                CallArg(label: interner.intern("x"), type: intType),
                CallArg(label: interner.intern("x"), type: intType),
            ]
        )
        let resolved = resolver.resolveCall(candidates: [fn], call: call, expectedType: nil, ctx: ctx)
        XCTAssertEqual(resolved.chosenCallee, fn)
        XCTAssertEqual(resolved.parameterMapping, [0: 0, 1: 0])
    }

    func testResolveCallHandlesMissingParameterSymbols() {
        let (resolver, types, symbols, interner, ctx) = makeEnv()

        let intType = types.make(.primitive(.int, .nonNull))
        let fn = defineSymbol(kind: .function, name: "missingSyms", suffix: "missingSyms", symbols: symbols, interner: interner)
        let paramA = defineSymbol(kind: .valueParameter, name: "a", suffix: "missingSyms_a", symbols: symbols, interner: interner)
        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: [intType, intType],
                returnType: intType,
                valueParameterSymbols: [paramA]
            ),
            for: fn
        )

        let call = CallExpr(
            range: makeRange(start: 381, end: 390),
            calleeName: interner.intern("missingSyms"),
            args: [CallArg(type: intType), CallArg(type: intType)]
        )
        let resolved = resolver.resolveCall(candidates: [fn], call: call, expectedType: nil, ctx: ctx)
        XCTAssertEqual(resolved.chosenCallee, fn)
        XCTAssertEqual(resolved.parameterMapping, [0: 0, 1: 1])
    }

    func testResolveCallRejectsUnknownNamedLabel() {
        let (resolver, types, symbols, interner, ctx) = makeEnv()

        let intType = types.make(.primitive(.int, .nonNull))
        let fn = defineSymbol(kind: .function, name: "unknownLabel", suffix: "unknownLabel", symbols: symbols, interner: interner)
        let paramX = defineSymbol(kind: .valueParameter, name: "x", suffix: "unknownLabel_x", symbols: symbols, interner: interner)
        symbols.setFunctionSignature(
            FunctionSignature(parameterTypes: [intType], returnType: intType, valueParameterSymbols: [paramX]),
            for: fn
        )

        let call = CallExpr(
            range: makeRange(start: 411, end: 420),
            calleeName: interner.intern("unknownLabel"),
            args: [CallArg(label: interner.intern("z"), type: intType)]
        )
        let resolved = resolver.resolveCall(candidates: [fn], call: call, expectedType: nil, ctx: ctx)
        XCTAssertNil(resolved.chosenCallee)
    }

    func testResolveCallRejectsTooManyPositionalArgs() {
        let (resolver, types, symbols, interner, ctx) = makeEnv()

        let intType = types.make(.primitive(.int, .nonNull))
        let fn = defineSymbol(kind: .function, name: "oneParam", suffix: "oneParam", symbols: symbols, interner: interner)
        let paramX = defineSymbol(kind: .valueParameter, name: "x", suffix: "oneParam_x", symbols: symbols, interner: interner)
        symbols.setFunctionSignature(
            FunctionSignature(parameterTypes: [intType], returnType: intType, valueParameterSymbols: [paramX]),
            for: fn
        )

        let call = CallExpr(
            range: makeRange(start: 421, end: 430),
            calleeName: interner.intern("oneParam"),
            args: [CallArg(type: intType), CallArg(type: intType)]
        )
        let resolved = resolver.resolveCall(candidates: [fn], call: call, expectedType: nil, ctx: ctx)
        XCTAssertNil(resolved.chosenCallee)
    }

    func testResolveCallSkipsNamedBoundParamForPositionalArg() {
        let (resolver, types, symbols, interner, ctx) = makeEnv()

        let intType = types.make(.primitive(.int, .nonNull))
        let boolType = types.make(.primitive(.boolean, .nonNull))
        let fn = defineSymbol(kind: .function, name: "skipBound", suffix: "skipBound", symbols: symbols, interner: interner)
        let paramA = defineSymbol(kind: .valueParameter, name: "a", suffix: "skipBound_a", symbols: symbols, interner: interner)
        let paramB = defineSymbol(kind: .valueParameter, name: "b", suffix: "skipBound_b", symbols: symbols, interner: interner)
        let paramC = defineSymbol(kind: .valueParameter, name: "c", suffix: "skipBound_c", symbols: symbols, interner: interner)
        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: [intType, boolType, intType],
                returnType: intType,
                valueParameterSymbols: [paramA, paramB, paramC]
            ),
            for: fn
        )

        // Named arg binds param "b" (index 1), then positional should skip to "c" (index 2)
        // since param "a" (index 0) is at positionalCursor=0, but after named "b" binds index 1,
        // the while loop should skip any bound non-vararg params
        let call = CallExpr(
            range: makeRange(start: 431, end: 440),
            calleeName: interner.intern("skipBound"),
            args: [
                CallArg(label: interner.intern("a"), type: intType),
                CallArg(label: interner.intern("b"), type: boolType),
                CallArg(label: interner.intern("c"), type: intType),
            ]
        )
        let resolved = resolver.resolveCall(candidates: [fn], call: call, expectedType: nil, ctx: ctx)
        XCTAssertEqual(resolved.chosenCallee, fn)
    }

    func testResolveCallSkipsTypeParamWithoutSubstitution() {
        let (resolver, types, symbols, interner, ctx) = makeEnv()

        let intType = types.make(.primitive(.int, .nonNull))
        let anyType = types.anyType
        // Create two type params but only use one in param types
        let tpUsed = defineSymbol(kind: .typeParameter, name: "T", suffix: "skip_tp_T", symbols: symbols, interner: interner)
        let tpUnused = defineSymbol(kind: .typeParameter, name: "U", suffix: "skip_tp_U", symbols: symbols, interner: interner)
        let tpType = types.make(.typeParam(TypeParamType(symbol: tpUsed, nullability: .nonNull)))

        let fn = defineSymbol(kind: .function, name: "skipTP", suffix: "skipTP", symbols: symbols, interner: interner)
        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: [tpType],
                returnType: tpType,
                typeParameterSymbols: [tpUsed, tpUnused],
                typeParameterUpperBounds: [anyType, anyType]
            ),
            for: fn
        )

        let call = CallExpr(
            range: makeRange(start: 441, end: 450),
            calleeName: interner.intern("skipTP"),
            args: [CallArg(type: intType)]
        )
        let resolved = resolver.resolveCall(candidates: [fn], call: call, expectedType: nil, ctx: ctx)
        XCTAssertEqual(resolved.chosenCallee, fn)
    }

    func testResolveCallForwardsConstraintFailureDiagnostic() {
        let (resolver, types, symbols, interner, ctx) = makeEnv()

        let intType = types.make(.primitive(.int, .nonNull))
        let boolType = types.make(.primitive(.boolean, .nonNull))

        let tpSym = defineSymbol(kind: .typeParameter, name: "T", suffix: "fwd_T", symbols: symbols, interner: interner)
        let tpType = types.make(.typeParam(TypeParamType(symbol: tpSym, nullability: .nonNull)))
        let fn = defineSymbol(kind: .function, name: "fwd", suffix: "fwd", symbols: symbols, interner: interner)
        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: [tpType],
                returnType: tpType,
                typeParameterSymbols: [tpSym],
                typeParameterUpperBounds: [boolType]
            ),
            for: fn
        )

        let call = CallExpr(
            range: makeRange(start: 391, end: 400),
            calleeName: interner.intern("fwd"),
            args: [CallArg(type: intType)]
        )
        let resolved = resolver.resolveCall(candidates: [fn], call: call, expectedType: nil, ctx: ctx)
        XCTAssertNil(resolved.chosenCallee)
        XCTAssertEqual(resolved.diagnostic?.code, "KSWIFTK-SEMA-0030")
    }

    func testResolveCallNoTypeVarsButUnsatisfiedConstraint() {
        let (resolver, types, symbols, interner, ctx) = makeEnv()

        let intType = types.make(.primitive(.int, .nonNull))
        let boolType = types.make(.primitive(.boolean, .nonNull))

        let fn = defineSymbol(kind: .function, name: "strict", suffix: "strict", symbols: symbols, interner: interner)
        let paramA = defineSymbol(kind: .valueParameter, name: "a", suffix: "strict_a", symbols: symbols, interner: interner)
        symbols.setFunctionSignature(
            FunctionSignature(parameterTypes: [boolType], returnType: boolType, valueParameterSymbols: [paramA]),
            for: fn
        )

        let call = CallExpr(
            range: makeRange(start: 401, end: 410),
            calleeName: interner.intern("strict"),
            args: [CallArg(type: intType)]
        )
        let resolved = resolver.resolveCall(candidates: [fn], call: call, expectedType: nil, ctx: ctx)
        XCTAssertNil(resolved.chosenCallee)
    }

    func testResolveCallWithMultipleTypeParametersInConstraints() {
        let (resolver, types, symbols, interner, ctx) = makeEnv()

        let intType = types.make(.primitive(.int, .nonNull))
        let boolType = types.make(.primitive(.boolean, .nonNull))
        let anyType = types.anyType

        // Two type params both used in parameter types → 2+ type variables in constraints
        let tpT = defineSymbol(kind: .typeParameter, name: "T", suffix: "multi_tp_T", symbols: symbols, interner: interner)
        let tpU = defineSymbol(kind: .typeParameter, name: "U", suffix: "multi_tp_U", symbols: symbols, interner: interner)
        let tpTType = types.make(.typeParam(TypeParamType(symbol: tpT, nullability: .nonNull)))
        let tpUType = types.make(.typeParam(TypeParamType(symbol: tpU, nullability: .nonNull)))

        let fn = defineSymbol(kind: .function, name: "multiTP", suffix: "multiTP", symbols: symbols, interner: interner)
        let paramA = defineSymbol(kind: .valueParameter, name: "a", suffix: "multiTP_a", symbols: symbols, interner: interner)
        let paramB = defineSymbol(kind: .valueParameter, name: "b", suffix: "multiTP_b", symbols: symbols, interner: interner)
        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: [tpTType, tpUType],
                returnType: tpTType,
                valueParameterSymbols: [paramA, paramB],
                typeParameterSymbols: [tpT, tpU],
                typeParameterUpperBounds: [anyType, anyType]
            ),
            for: fn
        )

        let call = CallExpr(
            range: makeRange(start: 451, end: 460),
            calleeName: interner.intern("multiTP"),
            args: [CallArg(type: intType), CallArg(type: boolType)]
        )
        let resolved = resolver.resolveCall(candidates: [fn], call: call, expectedType: nil, ctx: ctx)
        XCTAssertEqual(resolved.chosenCallee, fn)
    }

    // MARK: - Advanced Named Arguments Tests

    /// Named arguments with 3 parameters reordered out of order.
    func testResolveCallNamedArgsThreeParamsReordered() {
        let (resolver, types, symbols, interner, ctx) = makeEnv()

        let intType = types.make(.primitive(.int, .nonNull))
        let boolType = types.make(.primitive(.boolean, .nonNull))
        let stringType = types.make(.primitive(.string, .nonNull))
        let fn = defineSymbol(kind: .function, name: "triple", suffix: "namedTriple", symbols: symbols, interner: interner)
        let paramA = defineSymbol(kind: .valueParameter, name: "a", suffix: "namedTriple_a", symbols: symbols, interner: interner)
        let paramB = defineSymbol(kind: .valueParameter, name: "b", suffix: "namedTriple_b", symbols: symbols, interner: interner)
        let paramC = defineSymbol(kind: .valueParameter, name: "c", suffix: "namedTriple_c", symbols: symbols, interner: interner)
        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: [intType, boolType, stringType],
                returnType: intType,
                valueParameterSymbols: [paramA, paramB, paramC]
            ),
            for: fn
        )

        // Pass args in c, a, b order
        let call = CallExpr(
            range: makeRange(start: 500, end: 520),
            calleeName: interner.intern("triple"),
            args: [
                CallArg(label: interner.intern("c"), type: stringType),
                CallArg(label: interner.intern("a"), type: intType),
                CallArg(label: interner.intern("b"), type: boolType),
            ]
        )
        let resolved = resolver.resolveCall(candidates: [fn], call: call, expectedType: nil, ctx: ctx)
        XCTAssertEqual(resolved.chosenCallee, fn)
        XCTAssertNil(resolved.diagnostic)
        XCTAssertEqual(resolved.parameterMapping, [0: 2, 1: 0, 2: 1])
    }
}

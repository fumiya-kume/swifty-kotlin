@testable import CompilerCore
import XCTest

extension OverloadResolverTests {
    func testResolveCallExtensionFunctionWithGenericParam() {
        let (resolver, types, symbols, interner, ctx) = makeEnv()

        let intType = types.make(.primitive(.int, .nonNull))
        let stringType = types.make(.primitive(.string, .nonNull))

        let tpSym = defineSymbol(kind: .typeParameter, name: "T", suffix: "extGen_T", symbols: symbols, interner: interner)
        let tpType = types.make(.typeParam(TypeParamType(symbol: tpSym, nullability: .nonNull)))

        let ext = defineSymbol(kind: .function, name: "extGeneric", suffix: "extGeneric", symbols: symbols, interner: interner)
        let paramX = defineSymbol(kind: .valueParameter, name: "x", suffix: "extGeneric_x", symbols: symbols, interner: interner)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: stringType,
                parameterTypes: [tpType],
                returnType: tpType,
                valueParameterSymbols: [paramX],
                typeParameterSymbols: [tpSym]
            ),
            for: ext
        )

        let call = CallExpr(
            range: makeRange(start: 721, end: 735),
            calleeName: interner.intern("extGeneric"),
            args: [CallArg(type: intType)]
        )
        let resolved = resolver.resolveCall(
            candidates: [ext],
            call: call,
            expectedType: intType,
            implicitReceiverType: stringType,
            ctx: ctx
        )
        XCTAssertEqual(resolved.chosenCallee, ext)
        XCTAssertNil(resolved.diagnostic)
        XCTAssertEqual(resolved.substitutedTypeArguments.count, 1)
    }

    // MARK: - Advanced Multiple Type Parameters Tests

    /// Multiple type params where one violates its bound.
    func testResolveCallMultipleTypeParamsOneViolatesBound() {
        let (resolver, types, symbols, interner, ctx) = makeEnv()

        let intType = types.make(.primitive(.int, .nonNull))
        let boolType = types.make(.primitive(.boolean, .nonNull))

        let tpT = defineSymbol(kind: .typeParameter, name: "T", suffix: "multiViol_T", symbols: symbols, interner: interner)
        let tpU = defineSymbol(kind: .typeParameter, name: "U", suffix: "multiViol_U", symbols: symbols, interner: interner)
        let tpTType = types.make(.typeParam(TypeParamType(symbol: tpT, nullability: .nonNull)))
        let tpUType = types.make(.typeParam(TypeParamType(symbol: tpU, nullability: .nonNull)))

        let fn = defineSymbol(kind: .function, name: "multiViol", suffix: "multiViol", symbols: symbols, interner: interner)
        let paramA = defineSymbol(kind: .valueParameter, name: "a", suffix: "multiViol_a", symbols: symbols, interner: interner)
        let paramB = defineSymbol(kind: .valueParameter, name: "b", suffix: "multiViol_b", symbols: symbols, interner: interner)
        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: [tpTType, tpUType],
                returnType: tpTType,
                valueParameterSymbols: [paramA, paramB],
                typeParameterSymbols: [tpT, tpU],
                typeParameterUpperBounds: [types.anyType, boolType] // U bound to Bool
            ),
            for: fn
        )

        // T=Int (satisfies Any), U=Int (violates Bool bound)
        let call = CallExpr(
            range: makeRange(start: 736, end: 750),
            calleeName: interner.intern("multiViol"),
            args: [CallArg(type: intType), CallArg(type: intType)]
        )
        let resolved = resolver.resolveCall(candidates: [fn], call: call, expectedType: nil, ctx: ctx)
        XCTAssertNil(resolved.chosenCallee)
        XCTAssertEqual(resolved.diagnostic?.code, "KSWIFTK-SEMA-0030")
    }

    /// Multiple type params with expected return type constraint.
    func testResolveCallMultipleTypeParamsWithExpectedReturnType() {
        let (resolver, types, symbols, interner, ctx) = makeEnv()

        let intType = types.make(.primitive(.int, .nonNull))
        let boolType = types.make(.primitive(.boolean, .nonNull))
        let anyType = types.anyType

        let tpT = defineSymbol(kind: .typeParameter, name: "T", suffix: "multiRet_T", symbols: symbols, interner: interner)
        let tpU = defineSymbol(kind: .typeParameter, name: "U", suffix: "multiRet_U", symbols: symbols, interner: interner)
        let tpTType = types.make(.typeParam(TypeParamType(symbol: tpT, nullability: .nonNull)))
        let tpUType = types.make(.typeParam(TypeParamType(symbol: tpU, nullability: .nonNull)))

        // fn<T, U>(a: T, b: U) -> U
        let fn = defineSymbol(kind: .function, name: "multiRet", suffix: "multiRet", symbols: symbols, interner: interner)
        let paramA = defineSymbol(kind: .valueParameter, name: "a", suffix: "multiRet_a", symbols: symbols, interner: interner)
        let paramB = defineSymbol(kind: .valueParameter, name: "b", suffix: "multiRet_b", symbols: symbols, interner: interner)
        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: [tpTType, tpUType],
                returnType: tpUType,
                valueParameterSymbols: [paramA, paramB],
                typeParameterSymbols: [tpT, tpU],
                typeParameterUpperBounds: [anyType, anyType]
            ),
            for: fn
        )

        // Call with (Int, Bool) expecting Bool return
        let call = CallExpr(
            range: makeRange(start: 751, end: 765),
            calleeName: interner.intern("multiRet"),
            args: [CallArg(type: intType), CallArg(type: boolType)]
        )
        let resolved = resolver.resolveCall(candidates: [fn], call: call, expectedType: boolType, ctx: ctx)
        XCTAssertEqual(resolved.chosenCallee, fn)
        XCTAssertNil(resolved.diagnostic)
        XCTAssertEqual(resolved.substitutedTypeArguments.count, 2)
    }

    /// Multiple type params where return type constraint conflicts with argument types.
    func testResolveCallMultipleTypeParamsReturnTypeConflict() {
        let (resolver, types, symbols, interner, ctx) = makeEnv()

        let intType = types.make(.primitive(.int, .nonNull))
        let boolType = types.make(.primitive(.boolean, .nonNull))
        let anyType = types.anyType

        let tpT = defineSymbol(kind: .typeParameter, name: "T", suffix: "multiConflict_T", symbols: symbols, interner: interner)
        let tpTType = types.make(.typeParam(TypeParamType(symbol: tpT, nullability: .nonNull)))

        // fn<T>(a: T) -> T — single type param used for both param and return
        let fn = defineSymbol(kind: .function, name: "multiConflict", suffix: "multiConflict", symbols: symbols, interner: interner)
        let paramA = defineSymbol(kind: .valueParameter, name: "a", suffix: "multiConflict_a", symbols: symbols, interner: interner)
        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: [tpTType],
                returnType: tpTType,
                valueParameterSymbols: [paramA],
                typeParameterSymbols: [tpT],
                typeParameterUpperBounds: [anyType]
            ),
            for: fn
        )

        // Pass Int arg but expect Bool return → T can't be both Int and Bool
        let call = CallExpr(
            range: makeRange(start: 766, end: 780),
            calleeName: interner.intern("multiConflict"),
            args: [CallArg(type: intType)]
        )
        let resolved = resolver.resolveCall(candidates: [fn], call: call, expectedType: boolType, ctx: ctx)
        XCTAssertNil(resolved.chosenCallee)
        XCTAssertNotNil(resolved.diagnostic)
    }

    // MARK: - Advanced Most Specific Overload Selection Tests

    /// Three candidates, one is most specific (Int < Any, String < Any).
    func testResolveCallMostSpecificFromThreeCandidates() {
        let (resolver, types, symbols, interner, ctx) = makeEnv()

        let intType = types.make(.primitive(.int, .nonNull))
        let anyType = types.anyType

        // Candidate 1: fn(Any)
        let fn1 = defineSymbol(kind: .function, name: "triple", suffix: "specTriple1", symbols: symbols, interner: interner)
        symbols.setFunctionSignature(
            FunctionSignature(parameterTypes: [anyType], returnType: anyType),
            for: fn1
        )

        // Candidate 2: fn(Int)
        let fn2 = defineSymbol(kind: .function, name: "triple", suffix: "specTriple2", symbols: symbols, interner: interner)
        symbols.setFunctionSignature(
            FunctionSignature(parameterTypes: [intType], returnType: intType),
            for: fn2
        )

        // Candidate 3: fn(Any) — duplicate of fn1
        let fn3 = defineSymbol(kind: .function, name: "triple", suffix: "specTriple3", symbols: symbols, interner: interner)
        symbols.setFunctionSignature(
            FunctionSignature(parameterTypes: [anyType], returnType: anyType),
            for: fn3
        )

        let call = CallExpr(
            range: makeRange(start: 781, end: 795),
            calleeName: interner.intern("triple"),
            args: [CallArg(type: intType)]
        )
        let resolved = resolver.resolveCall(candidates: [fn1, fn2, fn3], call: call, expectedType: nil, ctx: ctx)
        XCTAssertEqual(resolved.chosenCallee, fn2)
        XCTAssertNil(resolved.diagnostic)
    }

    /// Multi-parameter most specific selection.
    func testResolveCallMostSpecificMultipleParameters() {
        let (resolver, types, symbols, interner, ctx) = makeEnv()

        let intType = types.make(.primitive(.int, .nonNull))
        let boolType = types.make(.primitive(.boolean, .nonNull))
        let anyType = types.anyType

        // Candidate 1: fn(Int, Any) — partially specific
        let fn1 = defineSymbol(kind: .function, name: "multiSpec", suffix: "multiSpec1", symbols: symbols, interner: interner)
        symbols.setFunctionSignature(
            FunctionSignature(parameterTypes: [intType, anyType], returnType: intType),
            for: fn1
        )

        // Candidate 2: fn(Int, Bool) — more specific
        let fn2 = defineSymbol(kind: .function, name: "multiSpec", suffix: "multiSpec2", symbols: symbols, interner: interner)
        symbols.setFunctionSignature(
            FunctionSignature(parameterTypes: [intType, boolType], returnType: intType),
            for: fn2
        )

        let call = CallExpr(
            range: makeRange(start: 796, end: 810),
            calleeName: interner.intern("multiSpec"),
            args: [CallArg(type: intType), CallArg(type: boolType)]
        )
        let resolved = resolver.resolveCall(candidates: [fn1, fn2], call: call, expectedType: nil, ctx: ctx)
        XCTAssertEqual(resolved.chosenCallee, fn2)
        XCTAssertNil(resolved.diagnostic)
    }

    /// Three truly ambiguous candidates → ambiguous diagnostic.
    func testResolveCallAmbiguousAmongThreeCandidates() {
        let (resolver, types, symbols, interner, ctx) = makeEnv()

        let intType = types.make(.primitive(.int, .nonNull))

        let fn1 = defineSymbol(kind: .function, name: "amb3", suffix: "amb3_1", symbols: symbols, interner: interner)
        symbols.setFunctionSignature(
            FunctionSignature(parameterTypes: [intType], returnType: intType),
            for: fn1
        )

        let fn2 = defineSymbol(kind: .function, name: "amb3", suffix: "amb3_2", symbols: symbols, interner: interner)
        symbols.setFunctionSignature(
            FunctionSignature(parameterTypes: [intType], returnType: intType),
            for: fn2
        )

        let fn3 = defineSymbol(kind: .function, name: "amb3", suffix: "amb3_3", symbols: symbols, interner: interner)
        symbols.setFunctionSignature(
            FunctionSignature(parameterTypes: [intType], returnType: intType),
            for: fn3
        )

        let call = CallExpr(
            range: makeRange(start: 811, end: 820),
            calleeName: interner.intern("amb3"),
            args: [CallArg(type: intType)]
        )
        let resolved = resolver.resolveCall(candidates: [fn1, fn2, fn3], call: call, expectedType: nil, ctx: ctx)
        XCTAssertNil(resolved.chosenCallee)
        XCTAssertEqual(resolved.diagnostic?.code, "KSWIFTK-SEMA-0003")
    }

    /// Generic candidate instantiated to same types as concrete → ambiguous
    /// (resolver compares instantiated parameter types, not generic vs concrete).
    func testResolveCallGenericVsConcreteWithSameInstantiatedTypesIsAmbiguous() {
        let (resolver, types, symbols, interner, ctx) = makeEnv()

        let intType = types.make(.primitive(.int, .nonNull))
        let anyType = types.anyType

        // Generic candidate: fn<T>(x: T) -> T
        let tpSym = defineSymbol(kind: .typeParameter, name: "T", suffix: "concreteVsGen_T", symbols: symbols, interner: interner)
        let tpType = types.make(.typeParam(TypeParamType(symbol: tpSym, nullability: .nonNull)))
        let genericFn = defineSymbol(kind: .function, name: "concreteGen", suffix: "concreteVsGen_generic", symbols: symbols, interner: interner)
        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: [tpType],
                returnType: tpType,
                typeParameterSymbols: [tpSym],
                typeParameterUpperBounds: [anyType]
            ),
            for: genericFn
        )

        // Concrete candidate: fn(x: Int) -> Int
        let concreteFn = defineSymbol(kind: .function, name: "concreteGen", suffix: "concreteVsGen_concrete", symbols: symbols, interner: interner)
        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: [intType],
                returnType: intType
            ),
            for: concreteFn
        )

        let call = CallExpr(
            range: makeRange(start: 821, end: 835),
            calleeName: interner.intern("concreteGen"),
            args: [CallArg(type: intType)]
        )
        let resolved = resolver.resolveCall(candidates: [genericFn, concreteFn], call: call, expectedType: nil, ctx: ctx)
        // After type substitution both have [Int] → isMoreSpecific sees them as equal → ambiguous
        XCTAssertNil(resolved.chosenCallee)
        XCTAssertEqual(resolved.diagnostic?.code, "KSWIFTK-SEMA-0003")
    }

    /// Most specific selection with incompatible parameter counts yields no winner.
    func testResolveCallMostSpecificDifferentArityCandidates() {
        let (resolver, types, symbols, interner, ctx) = makeEnv()

        let intType = types.make(.primitive(.int, .nonNull))

        // Candidate 1: fn(a: Int) with default b
        let fn1 = defineSymbol(kind: .function, name: "aritySpec", suffix: "aritySpec1", symbols: symbols, interner: interner)
        let p1a = defineSymbol(kind: .valueParameter, name: "a", suffix: "aritySpec1_a", symbols: symbols, interner: interner)
        let p1b = defineSymbol(kind: .valueParameter, name: "b", suffix: "aritySpec1_b", symbols: symbols, interner: interner)
        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: [intType, intType],
                returnType: intType,
                valueParameterSymbols: [p1a, p1b],
                valueParameterHasDefaultValues: [false, true]
            ),
            for: fn1
        )

        // Candidate 2: fn(a: Int) — single param
        let fn2 = defineSymbol(kind: .function, name: "aritySpec", suffix: "aritySpec2", symbols: symbols, interner: interner)
        let p2a = defineSymbol(kind: .valueParameter, name: "a", suffix: "aritySpec2_a", symbols: symbols, interner: interner)
        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: [intType],
                returnType: intType,
                valueParameterSymbols: [p2a]
            ),
            for: fn2
        )

        // Call with 1 arg → both match, but different arity → ambiguous
        let call = CallExpr(
            range: makeRange(start: 836, end: 850),
            calleeName: interner.intern("aritySpec"),
            args: [CallArg(type: intType)]
        )
        let resolved = resolver.resolveCall(candidates: [fn1, fn2], call: call, expectedType: nil, ctx: ctx)
        // Both match, isMoreSpecific requires same count → ambiguous
        XCTAssertNil(resolved.chosenCallee)
        XCTAssertEqual(resolved.diagnostic?.code, "KSWIFTK-SEMA-0003")
    }

    // MARK: - P5-39: positional args after named args for vararg

    func testResolveCallAcceptsPositionalArgsAfterNamedArgForVarargParameter() {
        let (resolver, types, symbols, interner, ctx) = makeEnv()

        let intType = types.make(.primitive(.int, .nonNull))
        let stringType = types.make(.primitive(.string, .nonNull))
        let fn = defineSymbol(
            kind: .function,
            name: "namedThenVararg",
            suffix: "namedThenVararg",
            symbols: symbols,
            interner: interner
        )
        let paramA = defineSymbol(
            kind: .valueParameter,
            name: "a",
            suffix: "namedThenVararg_a",
            symbols: symbols,
            interner: interner
        )
        let paramB = defineSymbol(
            kind: .valueParameter,
            name: "b",
            suffix: "namedThenVararg_b",
            symbols: symbols,
            interner: interner
        )
        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: [stringType, intType],
                returnType: intType,
                valueParameterSymbols: [paramA, paramB],
                valueParameterIsVararg: [false, true]
            ),
            for: fn
        )

        // f(a = "x", 2, 3) — positional args 2,3 should bind to vararg param b
        let call = CallExpr(
            range: makeRange(start: 461, end: 480),
            calleeName: interner.intern("namedThenVararg"),
            args: [
                CallArg(label: interner.intern("a"), type: stringType),
                CallArg(type: intType),
                CallArg(type: intType)
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
        // arg 0 → param 0 (named "a"), args 1,2 → param 1 (vararg "b")
        XCTAssertEqual(resolved.parameterMapping, [0: 0, 1: 1, 2: 1])
    }

    func testResolveCallRejectsPositionalAfterNamedArgForNonVarargParameter() {
        let (resolver, types, symbols, interner, ctx) = makeEnv()

        let intType = types.make(.primitive(.int, .nonNull))
        let boolType = types.make(.primitive(.boolean, .nonNull))
        let fn = defineSymbol(
            kind: .function,
            name: "namedThenNonVararg",
            suffix: "namedThenNonVararg",
            symbols: symbols,
            interner: interner
        )
        let paramA = defineSymbol(
            kind: .valueParameter,
            name: "a",
            suffix: "namedThenNonVararg_a",
            symbols: symbols,
            interner: interner
        )
        let paramB = defineSymbol(
            kind: .valueParameter,
            name: "b",
            suffix: "namedThenNonVararg_b",
            symbols: symbols,
            interner: interner
        )
        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: [intType, boolType],
                returnType: boolType,
                valueParameterSymbols: [paramA, paramB]
                // no valueParameterIsVararg → b is NOT vararg
            ),
            for: fn
        )

        // f(a = 1, true) — positional after named for non-vararg should still be rejected
        let call = CallExpr(
            range: makeRange(start: 481, end: 500),
            calleeName: interner.intern("namedThenNonVararg"),
            args: [
                CallArg(label: interner.intern("a"), type: intType),
                CallArg(type: boolType)
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
}

@testable import CompilerCore
import XCTest

extension OverloadResolverTests {
    func testUnifiedInference_StarProjectionProducesNoConstraint() {
        let (resolver, types, symbols, interner, ctx) = makeEnv()
        let intType = types.make(.primitive(.int, .nonNull))
        let tSym = defineSymbol(kind: .typeParameter, name: "T", suffix: "star_T", symbols: symbols, interner: interner)
        let tType = types.make(.typeParam(TypeParamType(symbol: tSym)))
        let boxSym = defineSymbol(kind: .class, name: "Box", suffix: "star_Box", symbols: symbols, interner: interner)
        // Parameter: Box<*>  (star projection on supertype side)
        let boxOfT = types.make(.classType(ClassType(classSymbol: boxSym, args: [.star])))
        // Arg: Box<Int>
        let boxOfInt = types.make(.classType(ClassType(classSymbol: boxSym, args: [.invariant(intType)])))

        let fn = defineSymbol(kind: .function, name: "takeStar", suffix: "star_takeStar", symbols: symbols, interner: interner)
        let paramSym = defineSymbol(kind: .valueParameter, name: "b", suffix: "star_b", symbols: symbols, interner: interner)
        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: [boxOfT],
                returnType: tType,
                valueParameterSymbols: [paramSym],
                typeParameterSymbols: [tSym]
            ),
            for: fn
        )

        let call = CallExpr(
            range: makeRange(start: 6000, end: 6010),
            calleeName: interner.intern("takeStar"),
            args: [CallArg(type: boxOfInt)]
        )
        let resolved = resolver.resolveCall(candidates: [fn], call: call, expectedType: nil, ctx: ctx)
        // Star projection means no constraint is generated for that type arg pair.
        // The simple type constraint Box<Int> <: Box<*> still fails because they are
        // structurally different, so candidate is rejected.
        XCTAssertNil(resolved.chosenCallee)
        XCTAssertNotNil(resolved.diagnostic)
    }

    // MARK: - Coverage: incompatible variance (.out vs .in) triggers invariant fallback

    func testUnifiedInference_IncompatibleVarianceFallsBackToInvariant() {
        let (resolver, types, symbols, interner, ctx) = makeEnv()
        let intType = types.make(.primitive(.int, .nonNull))
        let tSym = defineSymbol(kind: .typeParameter, name: "T", suffix: "ivar_T", symbols: symbols, interner: interner)
        let tType = types.make(.typeParam(TypeParamType(symbol: tSym)))
        let pairSym = defineSymbol(kind: .class, name: "Pair", suffix: "ivar_Pair", symbols: symbols, interner: interner)
        // Parameter type: Pair<in T> (contravariant)
        let pairOfInT = types.make(.classType(ClassType(classSymbol: pairSym, args: [.in(tType)])))
        // Argument type: Pair<out Int> (covariant) – incompatible variance with .in
        let pairOfOutInt = types.make(.classType(ClassType(classSymbol: pairSym, args: [.out(intType)])))

        let fn = defineSymbol(kind: .function, name: "mixVar", suffix: "ivar_mixVar", symbols: symbols, interner: interner)
        let paramSym = defineSymbol(kind: .valueParameter, name: "p", suffix: "ivar_p", symbols: symbols, interner: interner)
        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: [pairOfInT],
                returnType: tType,
                valueParameterSymbols: [paramSym],
                typeParameterSymbols: [tSym]
            ),
            for: fn
        )

        let call = CallExpr(
            range: makeRange(start: 6020, end: 6030),
            calleeName: interner.intern("mixVar"),
            args: [CallArg(type: pairOfOutInt)]
        )
        let resolved = resolver.resolveCall(candidates: [fn], call: call, expectedType: nil, ctx: ctx)
        XCTAssertEqual(resolved.chosenCallee, fn)
        XCTAssertNil(resolved.diagnostic)
        // Invariant fallback means T = Int (both directions)
        XCTAssertEqual(resolved.substitutedTypeArguments[TypeVarID(rawValue: 0)], intType)
    }

    // MARK: - Coverage: nullability mismatch in class type falls through to simple constraint

    func testUnifiedInference_NullabilityMismatchClassTypeFallsThrough() {
        let (resolver, types, symbols, interner, ctx) = makeEnv()
        let intType = types.make(.primitive(.int, .nonNull))
        let tSym = defineSymbol(kind: .typeParameter, name: "T", suffix: "null_T", symbols: symbols, interner: interner)
        let tType = types.make(.typeParam(TypeParamType(symbol: tSym)))
        let listSym = defineSymbol(kind: .class, name: "List", suffix: "null_List", symbols: symbols, interner: interner)
        // Parameter: List<T>? (nullable) – allows nullable argument
        let listOfT = types.make(.classType(ClassType(classSymbol: listSym, args: [.invariant(tType)], nullability: .nullable)))
        // Argument: List<Int> (nonNull) – nullability differs but super is nullable so ok
        let listOfIntNonNull = types.make(.classType(ClassType(classSymbol: listSym, args: [.invariant(intType)], nullability: .nonNull)))

        let fn = defineSymbol(kind: .function, name: "takeList", suffix: "null_takeList", symbols: symbols, interner: interner)
        let paramSym = defineSymbol(kind: .valueParameter, name: "l", suffix: "null_l", symbols: symbols, interner: interner)
        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: [listOfT],
                returnType: tType,
                valueParameterSymbols: [paramSym],
                typeParameterSymbols: [tSym]
            ),
            for: fn
        )

        let call = CallExpr(
            range: makeRange(start: 6040, end: 6050),
            calleeName: interner.intern("takeList"),
            args: [CallArg(type: listOfIntNonNull)]
        )
        let resolved = resolver.resolveCall(candidates: [fn], call: call, expectedType: nil, ctx: ctx)
        // Nullability differs but supertype is nullable, so decomposition proceeds.
        XCTAssertEqual(resolved.chosenCallee, fn)
        XCTAssertNil(resolved.diagnostic)
        XCTAssertEqual(resolved.substitutedTypeArguments[TypeVarID(rawValue: 0)], intType)
    }

    // MARK: - Coverage: function type param count mismatch falls through

    func testUnifiedInference_FunctionTypeParamCountMismatchFallsThrough() {
        let (resolver, types, symbols, interner, ctx) = makeEnv()
        let intType = types.make(.primitive(.int, .nonNull))
        let tSym = defineSymbol(kind: .typeParameter, name: "T", suffix: "fpm_T", symbols: symbols, interner: interner)
        let tType = types.make(.typeParam(TypeParamType(symbol: tSym)))
        // Parameter type: (T, T) -> T  (2 params)
        let funcOfTT = types.make(.functionType(FunctionType(params: [tType, tType], returnType: tType)))
        // Argument type: (Int) -> Int  (1 param – mismatch)
        let funcOfInt = types.make(.functionType(FunctionType(params: [intType], returnType: intType)))

        let fn = defineSymbol(kind: .function, name: "applyFn", suffix: "fpm_applyFn", symbols: symbols, interner: interner)
        let paramSym = defineSymbol(kind: .valueParameter, name: "f", suffix: "fpm_f", symbols: symbols, interner: interner)
        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: [funcOfTT],
                returnType: tType,
                valueParameterSymbols: [paramSym],
                typeParameterSymbols: [tSym]
            ),
            for: fn
        )

        let call = CallExpr(
            range: makeRange(start: 6060, end: 6070),
            calleeName: interner.intern("applyFn"),
            args: [CallArg(type: funcOfInt)]
        )
        let resolved = resolver.resolveCall(candidates: [fn], call: call, expectedType: nil, ctx: ctx)
        // Param count mismatch means function decomposition is skipped.
        // Falls through to simple type constraint which may fail.
        XCTAssertNil(resolved.chosenCallee)
        XCTAssertNotNil(resolved.diagnostic)
    }

    // MARK: - Coverage: Case 4 backward inference with class type var on subtype side

    func testUnifiedInference_SubtypeSideClassDecomposition() {
        let (resolver, types, symbols, interner, ctx) = makeEnv()
        let intType = types.make(.primitive(.int, .nonNull))
        let tSym = defineSymbol(kind: .typeParameter, name: "T", suffix: "sub4_T", symbols: symbols, interner: interner)
        let tType = types.make(.typeParam(TypeParamType(symbol: tSym)))
        let wrapSym = defineSymbol(kind: .class, name: "Wrap", suffix: "sub4_Wrap", symbols: symbols, interner: interner)
        // Return type: Wrap<T> – type variable on subtype side when matched against expected type
        let wrapOfT = types.make(.classType(ClassType(classSymbol: wrapSym, args: [.invariant(tType)])))
        let wrapOfInt = types.make(.classType(ClassType(classSymbol: wrapSym, args: [.invariant(intType)])))

        let fn = defineSymbol(kind: .function, name: "makeWrap", suffix: "sub4_makeWrap", symbols: symbols, interner: interner)
        let paramSym = defineSymbol(kind: .valueParameter, name: "x", suffix: "sub4_x", symbols: symbols, interner: interner)
        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: [intType],
                returnType: wrapOfT,
                valueParameterSymbols: [paramSym],
                typeParameterSymbols: [tSym]
            ),
            for: fn
        )

        let call = CallExpr(
            range: makeRange(start: 6080, end: 6090),
            calleeName: interner.intern("makeWrap"),
            args: [CallArg(type: intType)]
        )
        // Expected type is Wrap<Int> – triggers Case 4 (subtype side class decomposition)
        let resolved = resolver.resolveCall(candidates: [fn], call: call, expectedType: wrapOfInt, ctx: ctx)
        XCTAssertEqual(resolved.chosenCallee, fn)
        XCTAssertNil(resolved.diagnostic)
        XCTAssertEqual(resolved.substitutedTypeArguments[TypeVarID(rawValue: 0)], intType)
    }

    // MARK: - Coverage: isSuspend mismatch in function type falls through

    func testUnifiedInference_SuspendMismatchFunctionTypeFallsThrough() {
        let (resolver, types, symbols, interner, ctx) = makeEnv()
        let intType = types.make(.primitive(.int, .nonNull))
        let tSym = defineSymbol(kind: .typeParameter, name: "T", suffix: "susp_T", symbols: symbols, interner: interner)
        let tType = types.make(.typeParam(TypeParamType(symbol: tSym)))
        // Parameter: suspend (T) -> T
        let suspendFuncOfT = types.make(.functionType(FunctionType(params: [tType], returnType: tType, isSuspend: true)))
        // Argument: (Int) -> Int  (non-suspend – mismatch)
        let nonSuspendFunc = types.make(.functionType(FunctionType(params: [intType], returnType: intType, isSuspend: false)))

        let fn = defineSymbol(kind: .function, name: "runSusp", suffix: "susp_runSusp", symbols: symbols, interner: interner)
        let paramSym = defineSymbol(kind: .valueParameter, name: "f", suffix: "susp_f", symbols: symbols, interner: interner)
        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: [suspendFuncOfT],
                returnType: tType,
                valueParameterSymbols: [paramSym],
                typeParameterSymbols: [tSym]
            ),
            for: fn
        )

        let call = CallExpr(
            range: makeRange(start: 6100, end: 6110),
            calleeName: interner.intern("runSusp"),
            args: [CallArg(type: nonSuspendFunc)]
        )
        let resolved = resolver.resolveCall(candidates: [fn], call: call, expectedType: nil, ctx: ctx)
        // isSuspend mismatch means function decomposition is skipped; falls through
        // to simple type constraint which fails.
        XCTAssertNil(resolved.chosenCallee)
        XCTAssertNotNil(resolved.diagnostic)
    }

    // MARK: - Coverage: class type arg count mismatch falls through

    func testUnifiedInference_ClassArgCountMismatchFallsThrough() {
        let (resolver, types, symbols, interner, ctx) = makeEnv()
        let intType = types.make(.primitive(.int, .nonNull))
        let tSym = defineSymbol(kind: .typeParameter, name: "T", suffix: "acm_T", symbols: symbols, interner: interner)
        let tType = types.make(.typeParam(TypeParamType(symbol: tSym)))
        let boxSym = defineSymbol(kind: .class, name: "Box", suffix: "acm_Box", symbols: symbols, interner: interner)
        // Parameter: Box<T> (1 type arg)
        let boxOfT = types.make(.classType(ClassType(classSymbol: boxSym, args: [.invariant(tType)])))
        // Argument: Box<Int, Int> (2 type args – mismatch)
        let boxOfIntInt = types.make(.classType(ClassType(classSymbol: boxSym, args: [.invariant(intType), .invariant(intType)])))

        let fn = defineSymbol(kind: .function, name: "takeBox", suffix: "acm_takeBox", symbols: symbols, interner: interner)
        let paramSym = defineSymbol(kind: .valueParameter, name: "b", suffix: "acm_b", symbols: symbols, interner: interner)
        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: [boxOfT],
                returnType: tType,
                valueParameterSymbols: [paramSym],
                typeParameterSymbols: [tSym]
            ),
            for: fn
        )

        let call = CallExpr(
            range: makeRange(start: 6120, end: 6130),
            calleeName: interner.intern("takeBox"),
            args: [CallArg(type: boxOfIntInt)]
        )
        let resolved = resolver.resolveCall(candidates: [fn], call: call, expectedType: nil, ctx: ctx)
        // Arg count mismatch → decomposition falls through to simple type constraint
        // which fails because Box<Int,Int> is not subtype of Box<T>.
        XCTAssertNil(resolved.chosenCallee)
        XCTAssertNotNil(resolved.diagnostic)
    }

    // MARK: - Coverage: different class symbols falls through

    func testUnifiedInference_DifferentClassSymbolFallsThrough() {
        let (resolver, types, symbols, interner, ctx) = makeEnv()
        let intType = types.make(.primitive(.int, .nonNull))
        let tSym = defineSymbol(kind: .typeParameter, name: "T", suffix: "dcs_T", symbols: symbols, interner: interner)
        let tType = types.make(.typeParam(TypeParamType(symbol: tSym)))
        let listSym = defineSymbol(kind: .class, name: "List", suffix: "dcs_List", symbols: symbols, interner: interner)
        let setSym = defineSymbol(kind: .class, name: "Set", suffix: "dcs_Set", symbols: symbols, interner: interner)
        // Parameter: List<T>
        let listOfT = types.make(.classType(ClassType(classSymbol: listSym, args: [.invariant(tType)])))
        // Argument: Set<Int> (different class symbol)
        let setOfInt = types.make(.classType(ClassType(classSymbol: setSym, args: [.invariant(intType)])))

        let fn = defineSymbol(kind: .function, name: "takeList", suffix: "dcs_takeList", symbols: symbols, interner: interner)
        let paramSym = defineSymbol(kind: .valueParameter, name: "l", suffix: "dcs_l", symbols: symbols, interner: interner)
        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: [listOfT],
                returnType: tType,
                valueParameterSymbols: [paramSym],
                typeParameterSymbols: [tSym]
            ),
            for: fn
        )

        let call = CallExpr(
            range: makeRange(start: 6140, end: 6150),
            calleeName: interner.intern("takeList"),
            args: [CallArg(type: setOfInt)]
        )
        let resolved = resolver.resolveCall(candidates: [fn], call: call, expectedType: nil, ctx: ctx)
        // Different class symbols → decomposition falls through to simple constraint
        // which fails because Set<Int> is not subtype of List<T>.
        XCTAssertNil(resolved.chosenCallee)
        XCTAssertNotNil(resolved.diagnostic)
    }

    // MARK: - Coverage: non-generic type on supertype side (no decomposition)

    func testUnifiedInference_NonGenericSupertypeSkipsDecomposition() {
        let (resolver, types, symbols, interner, ctx) = makeEnv()
        let intType = types.make(.primitive(.int, .nonNull))
        let stringType = types.make(.primitive(.string, .nonNull))
        let tSym = defineSymbol(kind: .typeParameter, name: "T", suffix: "ng_T", symbols: symbols, interner: interner)
        let tType = types.make(.typeParam(TypeParamType(symbol: tSym)))

        // Parameter type is plain Int (no type vars, no generic class)
        let fn = defineSymbol(kind: .function, name: "plainParam", suffix: "ng_plainParam", symbols: symbols, interner: interner)
        let paramSym = defineSymbol(kind: .valueParameter, name: "x", suffix: "ng_x", symbols: symbols, interner: interner)
        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: [intType],
                returnType: tType,
                valueParameterSymbols: [paramSym],
                typeParameterSymbols: [tSym]
            ),
            for: fn
        )

        let call = CallExpr(
            range: makeRange(start: 6160, end: 6170),
            calleeName: interner.intern("plainParam"),
            args: [CallArg(type: intType)]
        )
        // Expected type is String to exercise the default simple constraint path
        let resolved = resolver.resolveCall(candidates: [fn], call: call, expectedType: stringType, ctx: ctx)
        XCTAssertEqual(resolved.chosenCallee, fn)
    }
}

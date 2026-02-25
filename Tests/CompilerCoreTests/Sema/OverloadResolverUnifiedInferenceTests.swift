import XCTest
@testable import CompilerCore

extension OverloadResolverTests {
    // MARK: - Unified Generic Type Inference (P5-85 / P5-126)

    // P5-126: fun <T> id(x: T): T – infer T = Int from id(42)
    // (Already covered by testResolveCallInfersGenericTypeArgumentFromParameter but
    //  included here for completeness of the unified test suite.)
    func testUnifiedInference_SimpleIdentityFunction() {
        let (resolver, types, symbols, interner, ctx) = makeEnv()
        let intType = types.make(.primitive(.int, .nonNull))
        let tSym = defineSymbol(kind: .typeParameter, name: "T", suffix: "uid_T", symbols: symbols, interner: interner)
        let tType = types.make(.typeParam(TypeParamType(symbol: tSym)))
        let fn = defineSymbol(kind: .function, name: "id", suffix: "uid_id", symbols: symbols, interner: interner)
        symbols.setFunctionSignature(
            FunctionSignature(parameterTypes: [tType], returnType: tType, typeParameterSymbols: [tSym]),
            for: fn
        )

        let call = CallExpr(range: makeRange(start: 5000, end: 5010), calleeName: interner.intern("id"), args: [CallArg(type: intType)])
        let resolved = resolver.resolveCall(candidates: [fn], call: call, expectedType: intType, ctx: ctx)

        XCTAssertEqual(resolved.chosenCallee, fn)
        XCTAssertNil(resolved.diagnostic)
        XCTAssertEqual(resolved.substitutedTypeArguments[TypeVarID(rawValue: 0)], intType)
    }

    // P5-85: fun <T> listOf(vararg elements: T): List<T> – infer T = Int from listOf(1, 2, 3)
    func testUnifiedInference_VarargUniformElementType() {
        let (resolver, types, symbols, interner, ctx) = makeEnv()
        let intType = types.make(.primitive(.int, .nonNull))
        let tSym = defineSymbol(kind: .typeParameter, name: "T", suffix: "uva_T", symbols: symbols, interner: interner)
        let tType = types.make(.typeParam(TypeParamType(symbol: tSym)))
        let listClassSym = defineSymbol(kind: .class, name: "List", suffix: "uva_List", symbols: symbols, interner: interner)
        let listOfT = types.make(.classType(ClassType(classSymbol: listClassSym, args: [.invariant(tType)])))
        let fn = defineSymbol(kind: .function, name: "listOf", suffix: "uva_listOf", symbols: symbols, interner: interner)
        let paramSym = defineSymbol(kind: .valueParameter, name: "elements", suffix: "uva_elements", symbols: symbols, interner: interner)
        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: [tType],
                returnType: listOfT,
                valueParameterSymbols: [paramSym],
                valueParameterIsVararg: [true],
                typeParameterSymbols: [tSym]
            ),
            for: fn
        )

        // listOf(1, 2, 3)
        let call = CallExpr(
            range: makeRange(start: 5020, end: 5030),
            calleeName: interner.intern("listOf"),
            args: [CallArg(type: intType), CallArg(type: intType), CallArg(type: intType)]
        )
        let resolved = resolver.resolveCall(candidates: [fn], call: call, expectedType: nil, ctx: ctx)

        XCTAssertEqual(resolved.chosenCallee, fn)
        XCTAssertNil(resolved.diagnostic)
        XCTAssertEqual(resolved.substitutedTypeArguments[TypeVarID(rawValue: 0)], intType)
    }

    // P5-85: listOf(1, "a") – mixed types → T = Any via LUB
    func testUnifiedInference_VarargMixedElementTypeLUB() {
        let (resolver, types, symbols, interner, ctx) = makeEnv()
        let intType = types.make(.primitive(.int, .nonNull))
        let stringType = types.make(.primitive(.string, .nonNull))
        let tSym = defineSymbol(kind: .typeParameter, name: "T", suffix: "uvx_T", symbols: symbols, interner: interner)
        let tType = types.make(.typeParam(TypeParamType(symbol: tSym)))
        let listClassSym = defineSymbol(kind: .class, name: "List", suffix: "uvx_List", symbols: symbols, interner: interner)
        let listOfT = types.make(.classType(ClassType(classSymbol: listClassSym, args: [.invariant(tType)])))
        let fn = defineSymbol(kind: .function, name: "listOf", suffix: "uvx_listOf", symbols: symbols, interner: interner)
        let paramSym = defineSymbol(kind: .valueParameter, name: "elements", suffix: "uvx_elements", symbols: symbols, interner: interner)
        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: [tType],
                returnType: listOfT,
                valueParameterSymbols: [paramSym],
                valueParameterIsVararg: [true],
                typeParameterSymbols: [tSym]
            ),
            for: fn
        )

        // listOf(1, "a") → T = Any? (LUB of Int, String)
        let call = CallExpr(
            range: makeRange(start: 5040, end: 5050),
            calleeName: interner.intern("listOf"),
            args: [CallArg(type: intType), CallArg(type: stringType)]
        )
        let resolved = resolver.resolveCall(candidates: [fn], call: call, expectedType: nil, ctx: ctx)

        XCTAssertEqual(resolved.chosenCallee, fn)
        XCTAssertNil(resolved.diagnostic)
        // LUB(Int, String) = Any? (nullableAnyType) because the current
        // LUB implementation returns nullableAnyType when all types satisfy
        // isSubtype($0, nullableAnyType).
        XCTAssertEqual(resolved.substitutedTypeArguments[TypeVarID(rawValue: 0)], types.nullableAnyType)
    }

    // P5-85: listOf<Int>(1, 2) – explicit type argument overrides inference
    func testUnifiedInference_ExplicitTypeArgWithVararg() {
        let (resolver, types, symbols, interner, ctx) = makeEnv()
        let intType = types.make(.primitive(.int, .nonNull))
        let tSym = defineSymbol(kind: .typeParameter, name: "T", suffix: "uex_T", symbols: symbols, interner: interner)
        let tType = types.make(.typeParam(TypeParamType(symbol: tSym)))
        let listClassSym = defineSymbol(kind: .class, name: "List", suffix: "uex_List", symbols: symbols, interner: interner)
        let listOfT = types.make(.classType(ClassType(classSymbol: listClassSym, args: [.invariant(tType)])))
        let fn = defineSymbol(kind: .function, name: "listOf", suffix: "uex_listOf", symbols: symbols, interner: interner)
        let paramSym = defineSymbol(kind: .valueParameter, name: "elements", suffix: "uex_elements", symbols: symbols, interner: interner)
        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: [tType],
                returnType: listOfT,
                valueParameterSymbols: [paramSym],
                valueParameterIsVararg: [true],
                typeParameterSymbols: [tSym]
            ),
            for: fn
        )

        // listOf<Int>(1, 2) – explicit type arg Int consistent with elements
        let call = CallExpr(
            range: makeRange(start: 5060, end: 5070),
            calleeName: interner.intern("listOf"),
            args: [CallArg(type: intType), CallArg(type: intType)],
            explicitTypeArgs: [intType]
        )
        let resolved = resolver.resolveCall(candidates: [fn], call: call, expectedType: nil, ctx: ctx)

        XCTAssertEqual(resolved.chosenCallee, fn)
        XCTAssertNil(resolved.diagnostic)
        XCTAssertEqual(resolved.substitutedTypeArguments[TypeVarID(rawValue: 0)], intType)
    }

    // P5-126: fun <T> unwrap(list: List<T>): T – infer T = Int from List<Int> argument
    func testUnifiedInference_InferTypeArgFromNestedClassTypeParameter() {
        let (resolver, types, symbols, interner, ctx) = makeEnv()
        let intType = types.make(.primitive(.int, .nonNull))
        let tSym = defineSymbol(kind: .typeParameter, name: "T", suffix: "unw_T", symbols: symbols, interner: interner)
        let tType = types.make(.typeParam(TypeParamType(symbol: tSym)))
        let listClassSym = defineSymbol(kind: .class, name: "List", suffix: "unw_List", symbols: symbols, interner: interner)
        let listOfT = types.make(.classType(ClassType(classSymbol: listClassSym, args: [.invariant(tType)])))
        let listOfInt = types.make(.classType(ClassType(classSymbol: listClassSym, args: [.invariant(intType)])))

        let fn = defineSymbol(kind: .function, name: "unwrap", suffix: "unw_unwrap", symbols: symbols, interner: interner)
        symbols.setFunctionSignature(
            FunctionSignature(parameterTypes: [listOfT], returnType: tType, typeParameterSymbols: [tSym]),
            for: fn
        )

        // unwrap(listOf(1, 2)) where arg type is List<Int>
        let call = CallExpr(
            range: makeRange(start: 5080, end: 5090),
            calleeName: interner.intern("unwrap"),
            args: [CallArg(type: listOfInt)]
        )
        let resolved = resolver.resolveCall(candidates: [fn], call: call, expectedType: intType, ctx: ctx)

        XCTAssertEqual(resolved.chosenCallee, fn)
        XCTAssertNil(resolved.diagnostic)
        XCTAssertEqual(resolved.substitutedTypeArguments[TypeVarID(rawValue: 0)], intType)
    }

    // P5-126: fun <T> wrap(x: T): List<T> – expected type List<Int> backward inference
    func testUnifiedInference_BackwardInferenceFromExpectedType() {
        let (resolver, types, symbols, interner, ctx) = makeEnv()
        let intType = types.make(.primitive(.int, .nonNull))
        let tSym = defineSymbol(kind: .typeParameter, name: "T", suffix: "bck_T", symbols: symbols, interner: interner)
        let tType = types.make(.typeParam(TypeParamType(symbol: tSym)))
        let listClassSym = defineSymbol(kind: .class, name: "List", suffix: "bck_List", symbols: symbols, interner: interner)
        let listOfT = types.make(.classType(ClassType(classSymbol: listClassSym, args: [.invariant(tType)])))
        let listOfInt = types.make(.classType(ClassType(classSymbol: listClassSym, args: [.invariant(intType)])))

        let fn = defineSymbol(kind: .function, name: "wrap", suffix: "bck_wrap", symbols: symbols, interner: interner)
        symbols.setFunctionSignature(
            FunctionSignature(parameterTypes: [tType], returnType: listOfT, typeParameterSymbols: [tSym]),
            for: fn
        )

        // val x: List<Int> = wrap(42)
        let call = CallExpr(
            range: makeRange(start: 5100, end: 5110),
            calleeName: interner.intern("wrap"),
            args: [CallArg(type: intType)]
        )
        let resolved = resolver.resolveCall(candidates: [fn], call: call, expectedType: listOfInt, ctx: ctx)

        XCTAssertEqual(resolved.chosenCallee, fn)
        XCTAssertNil(resolved.diagnostic)
        XCTAssertEqual(resolved.substitutedTypeArguments[TypeVarID(rawValue: 0)], intType)
    }

    // P5-126: fun <K, V> mapOf(k: K, v: V): Map<K, V> – multiple type params
    func testUnifiedInference_MultipleTypeParamsFromNestedClassType() {
        let (resolver, types, symbols, interner, ctx) = makeEnv()
        let stringType = types.make(.primitive(.string, .nonNull))
        let intType = types.make(.primitive(.int, .nonNull))
        let kSym = defineSymbol(kind: .typeParameter, name: "K", suffix: "mtp_K", symbols: symbols, interner: interner)
        let vSym = defineSymbol(kind: .typeParameter, name: "V", suffix: "mtp_V", symbols: symbols, interner: interner)
        let kType = types.make(.typeParam(TypeParamType(symbol: kSym)))
        let vType = types.make(.typeParam(TypeParamType(symbol: vSym)))
        let mapClassSym = defineSymbol(kind: .class, name: "Map", suffix: "mtp_Map", symbols: symbols, interner: interner)
        let mapKV = types.make(.classType(ClassType(classSymbol: mapClassSym, args: [.invariant(kType), .invariant(vType)])))

        let fn = defineSymbol(kind: .function, name: "mapOf", suffix: "mtp_mapOf", symbols: symbols, interner: interner)
        symbols.setFunctionSignature(
            FunctionSignature(parameterTypes: [kType, vType], returnType: mapKV, typeParameterSymbols: [kSym, vSym]),
            for: fn
        )

        // mapOf("key", 42) → K = String, V = Int
        let call = CallExpr(
            range: makeRange(start: 5120, end: 5130),
            calleeName: interner.intern("mapOf"),
            args: [CallArg(type: stringType), CallArg(type: intType)]
        )
        let resolved = resolver.resolveCall(candidates: [fn], call: call, expectedType: nil, ctx: ctx)

        XCTAssertEqual(resolved.chosenCallee, fn)
        XCTAssertNil(resolved.diagnostic)
        XCTAssertEqual(resolved.substitutedTypeArguments.count, 2)
        XCTAssertEqual(resolved.substitutedTypeArguments[TypeVarID(rawValue: 0)], stringType)
        XCTAssertEqual(resolved.substitutedTypeArguments[TypeVarID(rawValue: 1)], intType)
    }

    // P5-126: backward inference from expected Map<String, Int> for return type Map<K, V>
    func testUnifiedInference_BackwardInferenceMultipleTypeParamsFromExpectedType() {
        let (resolver, types, symbols, interner, ctx) = makeEnv()
        let stringType = types.make(.primitive(.string, .nonNull))
        let intType = types.make(.primitive(.int, .nonNull))
        let kSym = defineSymbol(kind: .typeParameter, name: "K", suffix: "bmt_K", symbols: symbols, interner: interner)
        let vSym = defineSymbol(kind: .typeParameter, name: "V", suffix: "bmt_V", symbols: symbols, interner: interner)
        let kType = types.make(.typeParam(TypeParamType(symbol: kSym)))
        let vType = types.make(.typeParam(TypeParamType(symbol: vSym)))
        let mapClassSym = defineSymbol(kind: .class, name: "Map", suffix: "bmt_Map", symbols: symbols, interner: interner)
        let mapKV = types.make(.classType(ClassType(classSymbol: mapClassSym, args: [.invariant(kType), .invariant(vType)])))
        let mapStringInt = types.make(.classType(ClassType(classSymbol: mapClassSym, args: [.invariant(stringType), .invariant(intType)])))

        let fn = defineSymbol(kind: .function, name: "emptyMap", suffix: "bmt_emptyMap", symbols: symbols, interner: interner)
        symbols.setFunctionSignature(
            FunctionSignature(parameterTypes: [], returnType: mapKV, typeParameterSymbols: [kSym, vSym]),
            for: fn
        )

        // val m: Map<String, Int> = emptyMap()
        let call = CallExpr(
            range: makeRange(start: 5140, end: 5150),
            calleeName: interner.intern("emptyMap"),
            args: []
        )
        let resolved = resolver.resolveCall(candidates: [fn], call: call, expectedType: mapStringInt, ctx: ctx)

        XCTAssertEqual(resolved.chosenCallee, fn)
        XCTAssertNil(resolved.diagnostic)
        XCTAssertEqual(resolved.substitutedTypeArguments[TypeVarID(rawValue: 0)], stringType)
        XCTAssertEqual(resolved.substitutedTypeArguments[TypeVarID(rawValue: 1)], intType)
    }

    // P5-126: Inference failure when no constraints exist → KSWIFTK-SEMA-INFER diagnostic
    func testUnifiedInference_FailureEmitsInferDiagnostic() {
        let (resolver, types, symbols, interner, ctx) = makeEnv()
        let tSym = defineSymbol(kind: .typeParameter, name: "T", suffix: "inf_T", symbols: symbols, interner: interner)
        let tType = types.make(.typeParam(TypeParamType(symbol: tSym)))
        let listClassSym = defineSymbol(kind: .class, name: "List", suffix: "inf_List", symbols: symbols, interner: interner)
        let listOfT = types.make(.classType(ClassType(classSymbol: listClassSym, args: [.invariant(tType)])))

        let fn = defineSymbol(kind: .function, name: "emptyList", suffix: "inf_emptyList", symbols: symbols, interner: interner)
        symbols.setFunctionSignature(
            FunctionSignature(parameterTypes: [], returnType: listOfT, typeParameterSymbols: [tSym]),
            for: fn
        )

        // emptyList() with no expected type → cannot infer T
        let call = CallExpr(
            range: makeRange(start: 5160, end: 5170),
            calleeName: interner.intern("emptyList"),
            args: []
        )
        let resolved = resolver.resolveCall(candidates: [fn], call: call, expectedType: nil, ctx: ctx)

        XCTAssertNil(resolved.chosenCallee)
        XCTAssertEqual(resolved.diagnostic?.code, "KSWIFTK-SEMA-INFER")
    }

    // P5-126: fun <T> transform(list: List<T>, f: (T) -> T): List<T>
    // Infer T = Int from List<Int> argument, with function type param.
    func testUnifiedInference_FunctionTypeParameterDecomposition() {
        let (resolver, types, symbols, interner, ctx) = makeEnv()
        let intType = types.make(.primitive(.int, .nonNull))
        let tSym = defineSymbol(kind: .typeParameter, name: "T", suffix: "ftp_T", symbols: symbols, interner: interner)
        let tType = types.make(.typeParam(TypeParamType(symbol: tSym)))
        let listClassSym = defineSymbol(kind: .class, name: "List", suffix: "ftp_List", symbols: symbols, interner: interner)
        let listOfT = types.make(.classType(ClassType(classSymbol: listClassSym, args: [.invariant(tType)])))
        let listOfInt = types.make(.classType(ClassType(classSymbol: listClassSym, args: [.invariant(intType)])))
        let tToT = types.make(.functionType(FunctionType(params: [tType], returnType: tType)))
        let intToInt = types.make(.functionType(FunctionType(params: [intType], returnType: intType)))

        let fn = defineSymbol(kind: .function, name: "transform", suffix: "ftp_transform", symbols: symbols, interner: interner)
        symbols.setFunctionSignature(
            FunctionSignature(parameterTypes: [listOfT, tToT], returnType: listOfT, typeParameterSymbols: [tSym]),
            for: fn
        )

        // transform(listOf(1), { it + 1 }) where args are List<Int> and (Int) -> Int
        let call = CallExpr(
            range: makeRange(start: 5180, end: 5190),
            calleeName: interner.intern("transform"),
            args: [CallArg(type: listOfInt), CallArg(type: intToInt)]
        )
        let resolved = resolver.resolveCall(candidates: [fn], call: call, expectedType: nil, ctx: ctx)

        XCTAssertEqual(resolved.chosenCallee, fn)
        XCTAssertNil(resolved.diagnostic)
        XCTAssertEqual(resolved.substitutedTypeArguments[TypeVarID(rawValue: 0)], intType)
    }

    // P5-126: Covariant (out T) decomposition – List<out T> parameter
    func testUnifiedInference_CovariantTypeArgDecomposition() {
        let (resolver, types, symbols, interner, ctx) = makeEnv()
        let intType = types.make(.primitive(.int, .nonNull))
        let tSym = defineSymbol(kind: .typeParameter, name: "T", suffix: "cov_T", symbols: symbols, interner: interner)
        let tType = types.make(.typeParam(TypeParamType(symbol: tSym)))
        let producerSym = defineSymbol(kind: .class, name: "Producer", suffix: "cov_Producer", symbols: symbols, interner: interner)
        let producerOfT = types.make(.classType(ClassType(classSymbol: producerSym, args: [.out(tType)])))
        let producerOfInt = types.make(.classType(ClassType(classSymbol: producerSym, args: [.out(intType)])))

        let fn = defineSymbol(kind: .function, name: "consume", suffix: "cov_consume", symbols: symbols, interner: interner)
        symbols.setFunctionSignature(
            FunctionSignature(parameterTypes: [producerOfT], returnType: tType, typeParameterSymbols: [tSym]),
            for: fn
        )

        let call = CallExpr(
            range: makeRange(start: 5200, end: 5210),
            calleeName: interner.intern("consume"),
            args: [CallArg(type: producerOfInt)]
        )
        let resolved = resolver.resolveCall(candidates: [fn], call: call, expectedType: nil, ctx: ctx)

        XCTAssertEqual(resolved.chosenCallee, fn)
        XCTAssertNil(resolved.diagnostic)
        XCTAssertEqual(resolved.substitutedTypeArguments[TypeVarID(rawValue: 0)], intType)
    }

    // P5-126: Contravariant (in T) decomposition – Consumer<in T> parameter
    func testUnifiedInference_ContravariantTypeArgDecomposition() {
        let (resolver, types, symbols, interner, ctx) = makeEnv()
        let intType = types.make(.primitive(.int, .nonNull))
        let tSym = defineSymbol(kind: .typeParameter, name: "T", suffix: "con_T", symbols: symbols, interner: interner)
        let tType = types.make(.typeParam(TypeParamType(symbol: tSym)))
        let consumerSym = defineSymbol(kind: .class, name: "Consumer", suffix: "con_Consumer", symbols: symbols, interner: interner)
        let consumerOfT = types.make(.classType(ClassType(classSymbol: consumerSym, args: [.in(tType)])))
        let consumerOfInt = types.make(.classType(ClassType(classSymbol: consumerSym, args: [.in(intType)])))

        let fn = defineSymbol(kind: .function, name: "provide", suffix: "con_provide", symbols: symbols, interner: interner)
        symbols.setFunctionSignature(
            FunctionSignature(parameterTypes: [consumerOfT], returnType: tType, typeParameterSymbols: [tSym]),
            for: fn
        )

        let call = CallExpr(
            range: makeRange(start: 5220, end: 5230),
            calleeName: interner.intern("provide"),
            args: [CallArg(type: consumerOfInt)]
        )
        let resolved = resolver.resolveCall(candidates: [fn], call: call, expectedType: nil, ctx: ctx)

        XCTAssertEqual(resolved.chosenCallee, fn)
        XCTAssertNil(resolved.diagnostic)
        XCTAssertEqual(resolved.substitutedTypeArguments[TypeVarID(rawValue: 0)], intType)
    }

    // MARK: - Coverage: star projection in type args produces no constraint

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

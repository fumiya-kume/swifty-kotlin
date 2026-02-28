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

}

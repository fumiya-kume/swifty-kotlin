@testable import CompilerCore
import XCTest

extension OverloadResolverTests {
    /// Named arguments select the correct overload from multiple candidates.
    func testResolveCallNamedArgsSelectCorrectOverload() {
        let (resolver, types, symbols, interner, ctx) = makeEnv()

        let intType = types.make(.primitive(.int, .nonNull))
        let boolType = types.make(.primitive(.boolean, .nonNull))

        // Candidate 1: fn(x: Int, y: Bool)
        let fn1 = defineSymbol(kind: .function, name: "overloaded", suffix: "namedOvl1", symbols: symbols, interner: interner)
        let p1x = defineSymbol(kind: .valueParameter, name: "x", suffix: "namedOvl1_x", symbols: symbols, interner: interner)
        let p1y = defineSymbol(kind: .valueParameter, name: "y", suffix: "namedOvl1_y", symbols: symbols, interner: interner)
        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: [intType, boolType],
                returnType: intType,
                valueParameterSymbols: [p1x, p1y]
            ),
            for: fn1
        )

        // Candidate 2: fn(a: Int, b: Bool) — different parameter names
        let fn2 = defineSymbol(kind: .function, name: "overloaded", suffix: "namedOvl2", symbols: symbols, interner: interner)
        let p2a = defineSymbol(kind: .valueParameter, name: "a", suffix: "namedOvl2_a", symbols: symbols, interner: interner)
        let p2b = defineSymbol(kind: .valueParameter, name: "b", suffix: "namedOvl2_b", symbols: symbols, interner: interner)
        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: [intType, boolType],
                returnType: intType,
                valueParameterSymbols: [p2a, p2b]
            ),
            for: fn2
        )

        // Call with named args x, y → should match fn1
        let call = CallExpr(
            range: makeRange(start: 521, end: 540),
            calleeName: interner.intern("overloaded"),
            args: [
                CallArg(label: interner.intern("x"), type: intType),
                CallArg(label: interner.intern("y"), type: boolType),
            ]
        )
        let resolved = resolver.resolveCall(candidates: [fn1, fn2], call: call, expectedType: nil, ctx: ctx)
        XCTAssertEqual(resolved.chosenCallee, fn1)
        XCTAssertNil(resolved.diagnostic)
    }

    /// Named arguments combined with default argument omission.
    func testResolveCallNamedArgsWithDefaultArgsCombined() {
        let (resolver, types, symbols, interner, ctx) = makeEnv()

        let intType = types.make(.primitive(.int, .nonNull))
        let boolType = types.make(.primitive(.boolean, .nonNull))
        let stringType = types.make(.primitive(.string, .nonNull))

        // fn(a: Int, b: Bool = true, c: String)
        let fn = defineSymbol(kind: .function, name: "namedDef", suffix: "namedDef", symbols: symbols, interner: interner)
        let paramA = defineSymbol(kind: .valueParameter, name: "a", suffix: "namedDef_a", symbols: symbols, interner: interner)
        let paramB = defineSymbol(kind: .valueParameter, name: "b", suffix: "namedDef_b", symbols: symbols, interner: interner)
        let paramC = defineSymbol(kind: .valueParameter, name: "c", suffix: "namedDef_c", symbols: symbols, interner: interner)
        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: [intType, boolType, stringType],
                returnType: intType,
                valueParameterSymbols: [paramA, paramB, paramC],
                valueParameterHasDefaultValues: [false, true, false]
            ),
            for: fn
        )

        // Call with named c and a only, omitting default b
        let call = CallExpr(
            range: makeRange(start: 541, end: 560),
            calleeName: interner.intern("namedDef"),
            args: [
                CallArg(label: interner.intern("c"), type: stringType),
                CallArg(label: interner.intern("a"), type: intType),
            ]
        )
        let resolved = resolver.resolveCall(candidates: [fn], call: call, expectedType: nil, ctx: ctx)
        XCTAssertEqual(resolved.chosenCallee, fn)
        XCTAssertNil(resolved.diagnostic)
        XCTAssertEqual(resolved.parameterMapping, [0: 2, 1: 0])
    }

    // MARK: - Advanced Vararg Tests

    /// Vararg parameter receives zero elements when only non-vararg params provided.
    func testResolveCallVarargReceivesZeroElements() {
        let (resolver, types, symbols, interner, ctx) = makeEnv()

        let intType = types.make(.primitive(.int, .nonNull))
        let boolType = types.make(.primitive(.boolean, .nonNull))

        // fn(head: Int, tail: vararg Int)
        let fn = defineSymbol(kind: .function, name: "zeroVararg", suffix: "zeroVararg", symbols: symbols, interner: interner)
        let paramHead = defineSymbol(kind: .valueParameter, name: "head", suffix: "zeroVararg_head", symbols: symbols, interner: interner)
        let paramTail = defineSymbol(kind: .valueParameter, name: "tail", suffix: "zeroVararg_tail", symbols: symbols, interner: interner)
        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: [intType, intType],
                returnType: boolType,
                valueParameterSymbols: [paramHead, paramTail],
                valueParameterIsVararg: [false, true]
            ),
            for: fn
        )

        // Only pass one arg for the non-vararg head, zero for tail
        let call = CallExpr(
            range: makeRange(start: 561, end: 575),
            calleeName: interner.intern("zeroVararg"),
            args: [CallArg(type: intType)]
        )
        let resolved = resolver.resolveCall(candidates: [fn], call: call, expectedType: nil, ctx: ctx)
        XCTAssertEqual(resolved.chosenCallee, fn)
        XCTAssertNil(resolved.diagnostic)
        XCTAssertEqual(resolved.parameterMapping, [0: 0])
    }

    /// Vararg-only function accepting multiple elements.
    func testResolveCallVarargOnlyFunctionMultipleElements() {
        let (resolver, types, symbols, interner, ctx) = makeEnv()

        let intType = types.make(.primitive(.int, .nonNull))

        // fn(nums: vararg Int)
        let fn = defineSymbol(kind: .function, name: "varargOnly", suffix: "varargOnly", symbols: symbols, interner: interner)
        let paramNums = defineSymbol(kind: .valueParameter, name: "nums", suffix: "varargOnly_nums", symbols: symbols, interner: interner)
        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: [intType],
                returnType: intType,
                valueParameterSymbols: [paramNums],
                valueParameterIsVararg: [true]
            ),
            for: fn
        )

        let call = CallExpr(
            range: makeRange(start: 576, end: 590),
            calleeName: interner.intern("varargOnly"),
            args: [CallArg(type: intType), CallArg(type: intType), CallArg(type: intType), CallArg(type: intType)]
        )
        let resolved = resolver.resolveCall(candidates: [fn], call: call, expectedType: nil, ctx: ctx)
        XCTAssertEqual(resolved.chosenCallee, fn)
        XCTAssertNil(resolved.diagnostic)
        XCTAssertEqual(resolved.parameterMapping, [0: 0, 1: 0, 2: 0, 3: 0])
    }

    /// Spread argument on a vararg parameter should be accepted.
    func testResolveCallSpreadArgumentOnVarargParameter() {
        let (resolver, types, symbols, interner, ctx) = makeEnv()

        let intType = types.make(.primitive(.int, .nonNull))

        let fn = defineSymbol(kind: .function, name: "spreadVararg", suffix: "spreadVararg", symbols: symbols, interner: interner)
        let paramX = defineSymbol(kind: .valueParameter, name: "x", suffix: "spreadVararg_x", symbols: symbols, interner: interner)
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
            range: makeRange(start: 591, end: 605),
            calleeName: interner.intern("spreadVararg"),
            args: [CallArg(isSpread: true, type: intType)]
        )
        let resolved = resolver.resolveCall(candidates: [fn], call: call, expectedType: nil, ctx: ctx)
        XCTAssertEqual(resolved.chosenCallee, fn)
        XCTAssertNil(resolved.diagnostic)
    }

    /// Vararg with wrong element type is rejected.
    func testResolveCallVarargWithTypeMismatch() {
        let (resolver, types, symbols, interner, ctx) = makeEnv()

        let intType = types.make(.primitive(.int, .nonNull))
        let boolType = types.make(.primitive(.boolean, .nonNull))

        let fn = defineSymbol(kind: .function, name: "varargTyped", suffix: "varargTyped", symbols: symbols, interner: interner)
        let paramX = defineSymbol(kind: .valueParameter, name: "x", suffix: "varargTyped_x", symbols: symbols, interner: interner)
        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: [boolType],
                returnType: boolType,
                valueParameterSymbols: [paramX],
                valueParameterIsVararg: [true]
            ),
            for: fn
        )

        // Pass Int to a Bool vararg
        let call = CallExpr(
            range: makeRange(start: 606, end: 620),
            calleeName: interner.intern("varargTyped"),
            args: [CallArg(type: intType)]
        )
        let resolved = resolver.resolveCall(candidates: [fn], call: call, expectedType: nil, ctx: ctx)
        XCTAssertNil(resolved.chosenCallee)
    }

    // MARK: - Advanced Default Arguments Tests

    /// All parameters have defaults; calling with zero args should succeed.
    func testResolveCallAllDefaultsOmitted() {
        let (resolver, types, symbols, interner, ctx) = makeEnv()

        let intType = types.make(.primitive(.int, .nonNull))
        let boolType = types.make(.primitive(.boolean, .nonNull))

        let fn = defineSymbol(kind: .function, name: "allDefaults", suffix: "allDefaults", symbols: symbols, interner: interner)
        let paramA = defineSymbol(kind: .valueParameter, name: "a", suffix: "allDefaults_a", symbols: symbols, interner: interner)
        let paramB = defineSymbol(kind: .valueParameter, name: "b", suffix: "allDefaults_b", symbols: symbols, interner: interner)
        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: [intType, boolType],
                returnType: intType,
                valueParameterSymbols: [paramA, paramB],
                valueParameterHasDefaultValues: [true, true]
            ),
            for: fn
        )

        let call = CallExpr(
            range: makeRange(start: 621, end: 630),
            calleeName: interner.intern("allDefaults"),
            args: []
        )
        let resolved = resolver.resolveCall(candidates: [fn], call: call, expectedType: nil, ctx: ctx)
        XCTAssertEqual(resolved.chosenCallee, fn)
        XCTAssertNil(resolved.diagnostic)
        XCTAssertEqual(resolved.parameterMapping, [:])
    }

    /// Three params: first required, middle default, last required. Provide first and last via named args.
    func testResolveCallDefaultArgMiddleOmittedWithNamedArgs() {
        let (resolver, types, symbols, interner, ctx) = makeEnv()

        let intType = types.make(.primitive(.int, .nonNull))
        let boolType = types.make(.primitive(.boolean, .nonNull))
        let stringType = types.make(.primitive(.string, .nonNull))

        // fn(first: Int, mid: Bool = false, last: String)
        let fn = defineSymbol(kind: .function, name: "midDefault", suffix: "midDefault", symbols: symbols, interner: interner)
        let paramFirst = defineSymbol(kind: .valueParameter, name: "first", suffix: "midDefault_first", symbols: symbols, interner: interner)
        let paramMid = defineSymbol(kind: .valueParameter, name: "mid", suffix: "midDefault_mid", symbols: symbols, interner: interner)
        let paramLast = defineSymbol(kind: .valueParameter, name: "last", suffix: "midDefault_last", symbols: symbols, interner: interner)
        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: [intType, boolType, stringType],
                returnType: intType,
                valueParameterSymbols: [paramFirst, paramMid, paramLast],
                valueParameterHasDefaultValues: [false, true, false]
            ),
            for: fn
        )

        // Provide first and last via named args, skipping mid
        let call = CallExpr(
            range: makeRange(start: 631, end: 650),
            calleeName: interner.intern("midDefault"),
            args: [
                CallArg(label: interner.intern("first"), type: intType),
                CallArg(label: interner.intern("last"), type: stringType),
            ]
        )
        let resolved = resolver.resolveCall(candidates: [fn], call: call, expectedType: nil, ctx: ctx)
        XCTAssertEqual(resolved.chosenCallee, fn)
        XCTAssertNil(resolved.diagnostic)
        XCTAssertEqual(resolved.parameterMapping, [0: 0, 1: 2])
    }

    /// Default args help select between overloads: one candidate matches with defaults, other doesn't.
    func testResolveCallDefaultArgsSelectOverload() {
        let (resolver, types, symbols, interner, ctx) = makeEnv()

        let intType = types.make(.primitive(.int, .nonNull))
        let boolType = types.make(.primitive(.boolean, .nonNull))

        // Candidate 1: fn(a: Int, b: Bool) — no defaults, requires both args
        let fn1 = defineSymbol(kind: .function, name: "defOvl", suffix: "defOvl1", symbols: symbols, interner: interner)
        let p1a = defineSymbol(kind: .valueParameter, name: "a", suffix: "defOvl1_a", symbols: symbols, interner: interner)
        let p1b = defineSymbol(kind: .valueParameter, name: "b", suffix: "defOvl1_b", symbols: symbols, interner: interner)
        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: [intType, boolType],
                returnType: intType,
                valueParameterSymbols: [p1a, p1b]
            ),
            for: fn1
        )

        // Candidate 2: fn(a: Int) — single param
        let fn2 = defineSymbol(kind: .function, name: "defOvl", suffix: "defOvl2", symbols: symbols, interner: interner)
        let p2a = defineSymbol(kind: .valueParameter, name: "a", suffix: "defOvl2_a", symbols: symbols, interner: interner)
        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: [intType],
                returnType: intType,
                valueParameterSymbols: [p2a]
            ),
            for: fn2
        )

        // Call with 1 arg → fn1 rejected (missing b, no default), fn2 matches
        let call = CallExpr(
            range: makeRange(start: 651, end: 665),
            calleeName: interner.intern("defOvl"),
            args: [CallArg(type: intType)]
        )
        let resolved = resolver.resolveCall(candidates: [fn1, fn2], call: call, expectedType: nil, ctx: ctx)
        XCTAssertEqual(resolved.chosenCallee, fn2)
        XCTAssertNil(resolved.diagnostic)
    }

    /// When a required param is missing (no default), call should fail.
    func testResolveCallRejectsWhenRequiredParamNotProvided() {
        let (resolver, types, symbols, interner, ctx) = makeEnv()

        let intType = types.make(.primitive(.int, .nonNull))
        let boolType = types.make(.primitive(.boolean, .nonNull))

        // fn(a: Int, b: Bool) — both required
        let fn = defineSymbol(kind: .function, name: "reqBoth", suffix: "reqBoth", symbols: symbols, interner: interner)
        let paramA = defineSymbol(kind: .valueParameter, name: "a", suffix: "reqBoth_a", symbols: symbols, interner: interner)
        let paramB = defineSymbol(kind: .valueParameter, name: "b", suffix: "reqBoth_b", symbols: symbols, interner: interner)
        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: [intType, boolType],
                returnType: intType,
                valueParameterSymbols: [paramA, paramB]
            ),
            for: fn
        )

        let call = CallExpr(
            range: makeRange(start: 666, end: 675),
            calleeName: interner.intern("reqBoth"),
            args: [CallArg(type: intType)]
        )
        let resolved = resolver.resolveCall(candidates: [fn], call: call, expectedType: nil, ctx: ctx)
        XCTAssertNil(resolved.chosenCallee)
    }

    // MARK: - Advanced Receiver Type (Extension Function) Tests

    /// Extension function with wrong receiver type is rejected.
    func testResolveCallRejectsExtensionWithReceiverTypeMismatch() {
        let (resolver, types, symbols, interner, ctx) = makeEnv()

        let intType = types.make(.primitive(.int, .nonNull))
        let stringType = types.make(.primitive(.string, .nonNull))
        let boolType = types.make(.primitive(.boolean, .nonNull))

        // Extension on String
        let ext = defineSymbol(kind: .function, name: "extMismatch", suffix: "extMismatch", symbols: symbols, interner: interner)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: stringType,
                parameterTypes: [],
                returnType: intType
            ),
            for: ext
        )

        // Call with Bool receiver (not String)
        let call = CallExpr(
            range: makeRange(start: 676, end: 690),
            calleeName: interner.intern("extMismatch"),
            args: []
        )
        let resolved = resolver.resolveCall(
            candidates: [ext],
            call: call,
            expectedType: nil,
            implicitReceiverType: boolType,
            ctx: ctx
        )
        XCTAssertNil(resolved.chosenCallee)
    }

    /// Multiple extension candidates with different receiver types — correct one selected.
    func testResolveCallSelectsCorrectExtensionByReceiverType() {
        let (resolver, types, symbols, interner, ctx) = makeEnv()

        let intType = types.make(.primitive(.int, .nonNull))
        let stringType = types.make(.primitive(.string, .nonNull))
        let boolType = types.make(.primitive(.boolean, .nonNull))

        // Extension on String
        let extString = defineSymbol(kind: .function, name: "extSel", suffix: "extSelString", symbols: symbols, interner: interner)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: stringType,
                parameterTypes: [],
                returnType: intType
            ),
            for: extString
        )

        // Extension on Bool
        let extBool = defineSymbol(kind: .function, name: "extSel", suffix: "extSelBool", symbols: symbols, interner: interner)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: boolType,
                parameterTypes: [],
                returnType: intType
            ),
            for: extBool
        )

        // Call with String receiver → should select extString
        let call = CallExpr(
            range: makeRange(start: 691, end: 705),
            calleeName: interner.intern("extSel"),
            args: []
        )
        let resolved = resolver.resolveCall(
            candidates: [extString, extBool],
            call: call,
            expectedType: nil,
            implicitReceiverType: stringType,
            ctx: ctx
        )
        XCTAssertEqual(resolved.chosenCallee, extString)
        XCTAssertNil(resolved.diagnostic)
    }

    /// When both non-null and nullable receiver extensions are viable,
    /// the non-null receiver extension should be preferred.
    func testResolveCallPrefersNonNullReceiverExtensionOverNullable() {
        let (resolver, types, symbols, interner, ctx) = makeEnv()

        let intType = types.make(.primitive(.int, .nonNull))
        let stringType = types.make(.primitive(.string, .nonNull))
        let nullableStringType = types.make(.primitive(.string, .nullable))

        let nonNullExt = defineSymbol(kind: .function, name: "tag", suffix: "tagNonNull", symbols: symbols, interner: interner)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: stringType,
                parameterTypes: [],
                returnType: intType
            ),
            for: nonNullExt
        )

        let nullableExt = defineSymbol(kind: .function, name: "tag", suffix: "tagNullable", symbols: symbols, interner: interner)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: nullableStringType,
                parameterTypes: [],
                returnType: intType
            ),
            for: nullableExt
        )

        let call = CallExpr(
            range: makeRange(start: 706, end: 715),
            calleeName: interner.intern("tag"),
            args: []
        )
        let resolved = resolver.resolveCall(
            candidates: [nullableExt, nonNullExt],
            call: call,
            expectedType: nil,
            implicitReceiverType: stringType,
            ctx: ctx
        )

        XCTAssertEqual(resolved.chosenCallee, nonNullExt)
        XCTAssertNil(resolved.diagnostic)
    }

    /// Extension function with parameters and receiver type.
    func testResolveCallExtensionFunctionWithParameters() {
        let (resolver, types, symbols, interner, ctx) = makeEnv()

        let intType = types.make(.primitive(.int, .nonNull))
        let stringType = types.make(.primitive(.string, .nonNull))

        let ext = defineSymbol(kind: .function, name: "extWithParams", suffix: "extWithParams", symbols: symbols, interner: interner)
        let paramX = defineSymbol(kind: .valueParameter, name: "x", suffix: "extWithParams_x", symbols: symbols, interner: interner)
        let paramY = defineSymbol(kind: .valueParameter, name: "y", suffix: "extWithParams_y", symbols: symbols, interner: interner)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: stringType,
                parameterTypes: [intType, intType],
                returnType: intType,
                valueParameterSymbols: [paramX, paramY]
            ),
            for: ext
        )

        let call = CallExpr(
            range: makeRange(start: 706, end: 720),
            calleeName: interner.intern("extWithParams"),
            args: [CallArg(type: intType), CallArg(type: intType)]
        )
        let resolved = resolver.resolveCall(
            candidates: [ext],
            call: call,
            expectedType: nil,
            implicitReceiverType: stringType,
            ctx: ctx
        )
        XCTAssertEqual(resolved.chosenCallee, ext)
        XCTAssertNil(resolved.diagnostic)
        XCTAssertEqual(resolved.parameterMapping, [0: 0, 1: 1])
    }

    // Extension function with receiver + generic type param.

    // MARK: - Advanced Multiple Type Parameters Tests

    // Multiple type params where one violates its bound.

    // Multiple type params with expected return type constraint.

    // Multiple type params where return type constraint conflicts with argument types.

    // MARK: - Advanced Most Specific Overload Selection Tests

    // Three candidates, one is most specific (Int < Any, String < Any).

    // Multi-parameter most specific selection.

    // Three truly ambiguous candidates → ambiguous diagnostic.

    // Generic candidate instantiated to same types as concrete → ambiguous
    // (resolver compares instantiated parameter types, not generic vs concrete).

    // Most specific selection with incompatible parameter counts yields no winner.
}

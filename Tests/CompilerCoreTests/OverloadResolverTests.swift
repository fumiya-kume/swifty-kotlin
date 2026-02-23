import XCTest
@testable import CompilerCore

final class OverloadResolverTests: XCTestCase {
    private func makeEnv() -> (resolver: OverloadResolver, types: TypeSystem, symbols: SymbolTable, interner: StringInterner, ctx: SemaModule) {
        let setup = makeSemaModule()
        return (OverloadResolver(), setup.types, setup.symbols, setup.interner, setup.ctx)
    }

    func testResolveCallReturnsNoViableDiagnosticAfterAllCandidateFilters() {
        let (resolver, types, symbols, interner, ctx) = makeEnv()
        let intType = types.make(.primitive(.int, .nonNull))
        let boolType = types.make(.primitive(.boolean, .nonNull))
        let call = CallExpr(
            range: makeRange(start: 10, end: 20),
            calleeName: interner.intern("foo"),
            args: [CallArg(type: intType)]
        )

        var candidates: [SymbolID] = [SymbolID(rawValue: 999)]

        let notCallable = defineSymbol(
            kind: .property,
            name: "foo",
            suffix: "property",
            symbols: symbols,
            interner: interner
        )
        candidates.append(notCallable)

        let noSignature = defineSymbol(
            kind: .function,
            name: "foo",
            suffix: "noSignature",
            symbols: symbols,
            interner: interner
        )
        candidates.append(noSignature)

        let wrongArity = defineSymbol(
            kind: .function,
            name: "foo",
            suffix: "wrongArity",
            symbols: symbols,
            interner: interner
        )
        symbols.setFunctionSignature(
            FunctionSignature(parameterTypes: [intType, intType], returnType: intType),
            for: wrongArity
        )
        candidates.append(wrongArity)

        let typeMismatch = defineSymbol(
            kind: .function,
            name: "foo",
            suffix: "typeMismatch",
            symbols: symbols,
            interner: interner
        )
        symbols.setFunctionSignature(
            FunctionSignature(parameterTypes: [boolType], returnType: intType),
            for: typeMismatch
        )
        candidates.append(typeMismatch)

        let expectedTypeMismatch = defineSymbol(
            kind: .function,
            name: "foo",
            suffix: "expectedMismatch",
            symbols: symbols,
            interner: interner
        )
        symbols.setFunctionSignature(
            FunctionSignature(parameterTypes: [intType], returnType: intType),
            for: expectedTypeMismatch
        )
        candidates.append(expectedTypeMismatch)

        let resolved = resolver.resolveCall(
            candidates: candidates,
            call: call,
            expectedType: boolType,
            ctx: ctx
        )

        XCTAssertNil(resolved.chosenCallee)
        XCTAssertEqual(resolved.substitutedTypeArguments, [:])
        XCTAssertEqual(resolved.parameterMapping, [:])
        XCTAssertEqual(resolved.diagnostic?.code, "KSWIFTK-SEMA-0002")
    }

    func testResolveCallReturnsAmbiguousDiagnosticForMultipleViableCandidates() {
        let (resolver, types, symbols, interner, ctx) = makeEnv()

        let intType = types.make(.primitive(.int, .nonNull))
        let call = CallExpr(
            range: makeRange(start: 30, end: 35),
            calleeName: interner.intern("foo"),
            args: [CallArg(type: intType)]
        )

        let first = defineSymbol(
            kind: .function,
            name: "foo",
            suffix: "first",
            symbols: symbols,
            interner: interner
        )
        symbols.setFunctionSignature(
            FunctionSignature(parameterTypes: [intType], returnType: intType),
            for: first
        )

        let second = defineSymbol(
            kind: .function,
            name: "foo",
            suffix: "second",
            symbols: symbols,
            interner: interner
        )
        symbols.setFunctionSignature(
            FunctionSignature(parameterTypes: [intType], returnType: intType),
            for: second
        )

        let resolved = resolver.resolveCall(
            candidates: [first, second],
            call: call,
            expectedType: nil,
            ctx: ctx
        )

        XCTAssertNil(resolved.chosenCallee)
        XCTAssertEqual(resolved.diagnostic?.code, "KSWIFTK-SEMA-0003")
    }

    func testResolveCallReturnsChosenCandidateAndIdentityMapping() {
        let (resolver, types, symbols, interner, ctx) = makeEnv()

        let intType = types.make(.primitive(.int, .nonNull))
        let boolType = types.make(.primitive(.boolean, .nonNull))

        let constructor = defineSymbol(
            kind: .constructor,
            name: "Ctor",
            suffix: "ctor",
            symbols: symbols,
            interner: interner
        )
        symbols.setFunctionSignature(
            FunctionSignature(parameterTypes: [intType, boolType], returnType: boolType),
            for: constructor
        )

        let call = CallExpr(
            range: makeRange(start: 40, end: 48),
            calleeName: interner.intern("Ctor"),
            args: [CallArg(type: intType), CallArg(type: boolType)]
        )

        let resolved = resolver.resolveCall(
            candidates: [constructor],
            call: call,
            expectedType: boolType,
            ctx: ctx
        )

        XCTAssertEqual(resolved.chosenCallee, constructor)
        XCTAssertNil(resolved.diagnostic)
        XCTAssertEqual(resolved.parameterMapping, [0: 0, 1: 1])
        XCTAssertEqual(resolved.substitutedTypeArguments, [:])
    }

    func testResolveCallPrefersMostSpecificCandidate() {
        let (resolver, types, symbols, interner, ctx) = makeEnv()

        let intType = types.make(.primitive(.int, .nonNull))
        let anyType = types.anyType

        let genericLike = defineSymbol(
            kind: .function,
            name: "foo",
            suffix: "any",
            symbols: symbols,
            interner: interner
        )
        symbols.setFunctionSignature(
            FunctionSignature(parameterTypes: [anyType], returnType: anyType),
            for: genericLike
        )

        let intSpecific = defineSymbol(
            kind: .function,
            name: "foo",
            suffix: "int",
            symbols: symbols,
            interner: interner
        )
        symbols.setFunctionSignature(
            FunctionSignature(parameterTypes: [intType], returnType: intType),
            for: intSpecific
        )

        let call = CallExpr(
            range: makeRange(start: 50, end: 55),
            calleeName: interner.intern("foo"),
            args: [CallArg(type: intType)]
        )

        let resolved = resolver.resolveCall(
            candidates: [genericLike, intSpecific],
            call: call,
            expectedType: nil,
            ctx: ctx
        )

        XCTAssertEqual(resolved.chosenCallee, intSpecific)
        XCTAssertNil(resolved.diagnostic)
    }

    func testResolveCallInfersGenericTypeArgumentFromParameter() {
        let (resolver, types, symbols, interner, ctx) = makeEnv()

        let intType = types.make(.primitive(.int, .nonNull))
        let typeParamSymbol = defineSymbol(
            kind: .typeParameter,
            name: "T",
            suffix: "typeParam",
            symbols: symbols,
            interner: interner
        )
        let typeParamType = types.make(.typeParam(TypeParamType(symbol: typeParamSymbol, nullability: .nonNull)))

        let generic = defineSymbol(
            kind: .function,
            name: "id",
            suffix: "generic",
            symbols: symbols,
            interner: interner
        )
        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: [typeParamType],
                returnType: typeParamType,
                typeParameterSymbols: [typeParamSymbol]
            ),
            for: generic
        )

        let call = CallExpr(
            range: makeRange(start: 60, end: 63),
            calleeName: interner.intern("id"),
            args: [CallArg(type: intType)]
        )
        let resolved = resolver.resolveCall(
            candidates: [generic],
            call: call,
            expectedType: intType,
            ctx: ctx
        )

        XCTAssertEqual(resolved.chosenCallee, generic)
        XCTAssertNil(resolved.diagnostic)
        XCTAssertEqual(resolved.substitutedTypeArguments.count, 1)
        XCTAssertEqual(resolved.substitutedTypeArguments[TypeVarID(rawValue: 0)], intType)
    }

    func testResolveCallReturnsConstraintDiagnosticForGenericMismatch() {
        let (resolver, types, symbols, interner, ctx) = makeEnv()

        let intType = types.make(.primitive(.int, .nonNull))
        let boolType = types.make(.primitive(.boolean, .nonNull))
        let typeParamSymbol = defineSymbol(
            kind: .typeParameter,
            name: "T",
            suffix: "constraint_typeParam",
            symbols: symbols,
            interner: interner
        )
        let typeParamType = types.make(.typeParam(TypeParamType(symbol: typeParamSymbol, nullability: .nonNull)))

        let generic = defineSymbol(
            kind: .function,
            name: "id",
            suffix: "constraint_generic",
            symbols: symbols,
            interner: interner
        )
        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: [typeParamType],
                returnType: typeParamType,
                typeParameterSymbols: [typeParamSymbol]
            ),
            for: generic
        )

        let call = CallExpr(
            range: makeRange(start: 64, end: 69),
            calleeName: interner.intern("id"),
            args: [CallArg(type: intType)]
        )
        let resolved = resolver.resolveCall(
            candidates: [generic],
            call: call,
            expectedType: boolType,
            ctx: ctx
        )

        XCTAssertNil(resolved.chosenCallee)
        XCTAssertEqual(resolved.diagnostic?.code, "KSWIFTK-TYPE-0001")
    }

    func testResolveCallSkipsExtensionCandidateWithoutReceiver() {
        let (resolver, types, symbols, interner, ctx) = makeEnv()

        let intType = types.make(.primitive(.int, .nonNull))
        let stringType = types.make(.primitive(.string, .nonNull))

        let ext = defineSymbol(
            kind: .function,
            name: "ext",
            suffix: "extension",
            symbols: symbols,
            interner: interner
        )
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: stringType,
                parameterTypes: [],
                returnType: intType
            ),
            for: ext
        )

        let call = CallExpr(
            range: makeRange(start: 64, end: 68),
            calleeName: interner.intern("ext"),
            args: []
        )
        let resolved = resolver.resolveCall(
            candidates: [ext],
            call: call,
            expectedType: nil,
            ctx: ctx
        )

        XCTAssertNil(resolved.chosenCallee)
        XCTAssertEqual(resolved.diagnostic?.code, "KSWIFTK-SEMA-0002")
    }

    func testResolveCallAcceptsExtensionCandidateWithImplicitReceiver() {
        let (resolver, types, symbols, interner, ctx) = makeEnv()

        let intType = types.make(.primitive(.int, .nonNull))
        let stringType = types.make(.primitive(.string, .nonNull))

        let ext = defineSymbol(
            kind: .function,
            name: "ext",
            suffix: "extension_with_receiver",
            symbols: symbols,
            interner: interner
        )
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: stringType,
                parameterTypes: [],
                returnType: intType
            ),
            for: ext
        )

        let call = CallExpr(
            range: makeRange(start: 68, end: 72),
            calleeName: interner.intern("ext"),
            args: []
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
    }

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
                CallArg(label: interner.intern("x"), type: intType)
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
                CallArg(label: interner.intern("x"), type: intType)
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
                CallArg(label: interner.intern("c"), type: intType)
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
                CallArg(label: interner.intern("b"), type: boolType)
            ]
        )
        let resolved = resolver.resolveCall(candidates: [fn], call: call, expectedType: nil, ctx: ctx)
        XCTAssertEqual(resolved.chosenCallee, fn)
        XCTAssertNil(resolved.diagnostic)
        XCTAssertEqual(resolved.parameterMapping, [0: 2, 1: 0, 2: 1])
    }

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
                CallArg(label: interner.intern("y"), type: boolType)
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
                CallArg(label: interner.intern("a"), type: intType)
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
                CallArg(label: interner.intern("last"), type: stringType)
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

    /// Extension function with receiver + generic type param.
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
                typeParameterUpperBounds: [types.anyType, boolType]  // U bound to Bool
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

        // listOf(1, "a") → T = Any (LUB of Int, String)
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

    private func defineSymbol(
        kind: SymbolKind,
        name: String,
        suffix: String,
        symbols: SymbolTable,
        interner: StringInterner
    ) -> SymbolID {
        symbols.define(
            kind: kind,
            name: interner.intern(name),
            fqName: [interner.intern("test"), interner.intern(suffix)],
            declSite: nil,
            visibility: .public,
            flags: []
        )
    }
}

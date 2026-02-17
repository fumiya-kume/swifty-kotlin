import XCTest
@testable import CompilerCore

final class OverloadResolverTests: XCTestCase {
    private var setup: (ctx: SemaModule, symbols: SymbolTable, types: TypeSystem, interner: StringInterner)!
    private var resolver: OverloadResolver!
    private var types: TypeSystem!
    private var symbols: SymbolTable!
    private var interner: StringInterner!

    override func setUp() {
        super.setUp()
        setup = makeSemaModule()
        resolver = OverloadResolver()
        types = setup.types
        symbols = setup.symbols
        interner = setup.interner
    }

    func testResolveCallReturnsNoViableDiagnosticAfterAllCandidateFilters() {
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
            ctx: setup.ctx
        )

        XCTAssertNil(resolved.chosenCallee)
        XCTAssertEqual(resolved.substitutedTypeArguments, [:])
        XCTAssertEqual(resolved.parameterMapping, [:])
        XCTAssertEqual(resolved.diagnostic?.code, "KSWIFTK-SEMA-0002")
    }

    func testResolveCallReturnsAmbiguousDiagnosticForMultipleViableCandidates() {

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
            ctx: setup.ctx
        )

        XCTAssertNil(resolved.chosenCallee)
        XCTAssertEqual(resolved.diagnostic?.code, "KSWIFTK-SEMA-0003")
    }

    func testResolveCallReturnsChosenCandidateAndIdentityMapping() {

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
            ctx: setup.ctx
        )

        XCTAssertEqual(resolved.chosenCallee, constructor)
        XCTAssertNil(resolved.diagnostic)
        XCTAssertEqual(resolved.parameterMapping, [0: 0, 1: 1])
        XCTAssertEqual(resolved.substitutedTypeArguments, [:])
    }

    func testResolveCallPrefersMostSpecificCandidate() {

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
            ctx: setup.ctx
        )

        XCTAssertEqual(resolved.chosenCallee, intSpecific)
        XCTAssertNil(resolved.diagnostic)
    }

    func testResolveCallInfersGenericTypeArgumentFromParameter() {

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
            ctx: setup.ctx
        )

        XCTAssertEqual(resolved.chosenCallee, generic)
        XCTAssertNil(resolved.diagnostic)
        XCTAssertEqual(resolved.substitutedTypeArguments.count, 1)
        XCTAssertEqual(resolved.substitutedTypeArguments[TypeVarID(rawValue: 0)], intType)
    }

    func testResolveCallReturnsConstraintDiagnosticForGenericMismatch() {

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
            ctx: setup.ctx
        )

        XCTAssertNil(resolved.chosenCallee)
        XCTAssertEqual(resolved.diagnostic?.code, "KSWIFTK-TYPE-0001")
    }

    func testResolveCallSkipsExtensionCandidateWithoutReceiver() {

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
            ctx: setup.ctx
        )

        XCTAssertNil(resolved.chosenCallee)
        XCTAssertEqual(resolved.diagnostic?.code, "KSWIFTK-SEMA-0002")
    }

    func testResolveCallAcceptsExtensionCandidateWithImplicitReceiver() {

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
            ctx: setup.ctx
        )

        XCTAssertEqual(resolved.chosenCallee, ext)
        XCTAssertNil(resolved.diagnostic)
    }

    func testResolveCallAllowsOmittedDefaultArguments() {

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
            ctx: setup.ctx
        )

        XCTAssertEqual(resolved.chosenCallee, fn)
        XCTAssertNil(resolved.diagnostic)
        XCTAssertEqual(resolved.parameterMapping, [0: 0])
    }

    func testResolveCallSupportsNamedArgumentsAndParameterMapping() {

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
            ctx: setup.ctx
        )

        XCTAssertEqual(resolved.chosenCallee, fn)
        XCTAssertNil(resolved.diagnostic)
        XCTAssertEqual(resolved.parameterMapping, [0: 1, 1: 0])
    }

    func testResolveCallSupportsMixedPositionalAndNamedArguments() {

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
            ctx: setup.ctx
        )

        XCTAssertEqual(resolved.chosenCallee, fn)
        XCTAssertNil(resolved.diagnostic)
        XCTAssertEqual(resolved.parameterMapping, [0: 0, 1: 1])
    }

    func testResolveCallRejectsPositionalArgumentAfterNamedArgument() {

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
            ctx: setup.ctx
        )

        XCTAssertNil(resolved.chosenCallee)
        XCTAssertEqual(resolved.diagnostic?.code, "KSWIFTK-SEMA-0002")
    }

    func testResolveCallSupportsTrailingVarargMapping() {

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
            ctx: setup.ctx
        )

        XCTAssertEqual(resolved.chosenCallee, fn)
        XCTAssertNil(resolved.diagnostic)
        XCTAssertEqual(resolved.parameterMapping, [0: 0, 1: 1, 2: 1])
    }

    func testResolveCallSupportsNonTrailingVarargWithNamedTail() {

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
            ctx: setup.ctx
        )

        XCTAssertEqual(resolved.chosenCallee, fn)
        XCTAssertNil(resolved.diagnostic)
        XCTAssertEqual(resolved.parameterMapping, [0: 0, 1: 0, 2: 1])
    }

    func testResolveCallRejectsSpreadArgumentForNonVarargParameter() {

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
            ctx: setup.ctx
        )

        XCTAssertNil(resolved.chosenCallee)
        XCTAssertEqual(resolved.diagnostic?.code, "KSWIFTK-SEMA-0002")
    }

    func testResolveCallAcceptsGenericWithSatisfiedUpperBound() {

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
            ctx: setup.ctx
        )

        XCTAssertEqual(resolved.chosenCallee, generic)
        XCTAssertNil(resolved.diagnostic)
    }

    func testResolveCallRejectsGenericWithViolatedUpperBound() {

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
            ctx: setup.ctx
        )

        XCTAssertNil(resolved.chosenCallee)
        XCTAssertEqual(resolved.diagnostic?.code, "KSWIFTK-SEMA-0030")
    }

    func testResolveCallRejectsGenericWithViolatedUpperBoundFromSymbolTable() {

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
            ctx: setup.ctx
        )

        XCTAssertNil(resolved.chosenCallee)
        XCTAssertEqual(resolved.diagnostic?.code, "KSWIFTK-SEMA-0030")
    }

    func testResolveCallHandlesOversizedFlagsArrays() {

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
        let resolved = resolver.resolveCall(candidates: [fn], call: call, expectedType: nil, ctx: setup.ctx)
        XCTAssertEqual(resolved.chosenCallee, fn)
        XCTAssertNil(resolved.diagnostic)
    }

    func testResolveCallHandlesUndersizedFlagsArrays() {

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
        let resolved = resolver.resolveCall(candidates: [fn], call: call, expectedType: nil, ctx: setup.ctx)
        XCTAssertEqual(resolved.chosenCallee, fn)
    }

    func testResolveCallRejectsDuplicateNamedArgument() {

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
        let resolved = resolver.resolveCall(candidates: [fn], call: call, expectedType: nil, ctx: setup.ctx)
        XCTAssertNil(resolved.chosenCallee)
    }

    func testResolveCallRejectsNamedSpreadOnNonVararg() {

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
        let resolved = resolver.resolveCall(candidates: [fn], call: call, expectedType: nil, ctx: setup.ctx)
        XCTAssertNil(resolved.chosenCallee)
    }

    func testResolveCallRejectsArgsForZeroParamFunction() {

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
        let resolved = resolver.resolveCall(candidates: [fn], call: call, expectedType: nil, ctx: setup.ctx)
        XCTAssertNil(resolved.chosenCallee)
    }

    func testResolveCallAcceptsNamedVarargArgument() {

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
        let resolved = resolver.resolveCall(candidates: [fn], call: call, expectedType: nil, ctx: setup.ctx)
        XCTAssertEqual(resolved.chosenCallee, fn)
        XCTAssertEqual(resolved.parameterMapping, [0: 0, 1: 0])
    }

    func testResolveCallHandlesMissingParameterSymbols() {

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
        let resolved = resolver.resolveCall(candidates: [fn], call: call, expectedType: nil, ctx: setup.ctx)
        XCTAssertEqual(resolved.chosenCallee, fn)
        XCTAssertEqual(resolved.parameterMapping, [0: 0, 1: 1])
    }

    func testResolveCallRejectsUnknownNamedLabel() {

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
        let resolved = resolver.resolveCall(candidates: [fn], call: call, expectedType: nil, ctx: setup.ctx)
        XCTAssertNil(resolved.chosenCallee)
    }

    func testResolveCallRejectsTooManyPositionalArgs() {

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
        let resolved = resolver.resolveCall(candidates: [fn], call: call, expectedType: nil, ctx: setup.ctx)
        XCTAssertNil(resolved.chosenCallee)
    }

    func testResolveCallSkipsNamedBoundParamForPositionalArg() {

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
        let resolved = resolver.resolveCall(candidates: [fn], call: call, expectedType: nil, ctx: setup.ctx)
        XCTAssertEqual(resolved.chosenCallee, fn)
    }

    func testResolveCallSkipsTypeParamWithoutSubstitution() {

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
        let resolved = resolver.resolveCall(candidates: [fn], call: call, expectedType: nil, ctx: setup.ctx)
        XCTAssertEqual(resolved.chosenCallee, fn)
    }

    func testResolveCallForwardsConstraintFailureDiagnostic() {

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
        let resolved = resolver.resolveCall(candidates: [fn], call: call, expectedType: nil, ctx: setup.ctx)
        XCTAssertNil(resolved.chosenCallee)
        XCTAssertEqual(resolved.diagnostic?.code, "KSWIFTK-SEMA-0030")
    }

    func testResolveCallNoTypeVarsButUnsatisfiedConstraint() {

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
        let resolved = resolver.resolveCall(candidates: [fn], call: call, expectedType: nil, ctx: setup.ctx)
        XCTAssertNil(resolved.chosenCallee)
    }

    func testResolveCallWithMultipleTypeParametersInConstraints() {

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
        let resolved = resolver.resolveCall(candidates: [fn], call: call, expectedType: nil, ctx: setup.ctx)
        XCTAssertEqual(resolved.chosenCallee, fn)
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

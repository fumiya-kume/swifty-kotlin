import XCTest
@testable import CompilerCore

final class OverloadResolverTests: XCTestCase {
    func testResolveCallReturnsNoViableDiagnosticAfterAllCandidateFilters() {
        let setup = makeSemaModule()
        let resolver = OverloadResolver()
        let types = setup.types
        let symbols = setup.symbols
        let interner = setup.interner

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
        let setup = makeSemaModule()
        let resolver = OverloadResolver()
        let types = setup.types
        let symbols = setup.symbols
        let interner = setup.interner

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
        let setup = makeSemaModule()
        let resolver = OverloadResolver()
        let types = setup.types
        let symbols = setup.symbols
        let interner = setup.interner

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
        let setup = makeSemaModule()
        let resolver = OverloadResolver()
        let types = setup.types
        let symbols = setup.symbols
        let interner = setup.interner

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
        let setup = makeSemaModule()
        let resolver = OverloadResolver()
        let types = setup.types
        let symbols = setup.symbols
        let interner = setup.interner

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

    func testResolveCallSkipsExtensionCandidateWithoutReceiver() {
        let setup = makeSemaModule()
        let resolver = OverloadResolver()
        let types = setup.types
        let symbols = setup.symbols
        let interner = setup.interner

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
        let setup = makeSemaModule()
        let resolver = OverloadResolver()
        let types = setup.types
        let symbols = setup.symbols
        let interner = setup.interner

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
        let setup = makeSemaModule()
        let resolver = OverloadResolver()
        let types = setup.types
        let symbols = setup.symbols
        let interner = setup.interner

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
        let setup = makeSemaModule()
        let resolver = OverloadResolver()
        let types = setup.types
        let symbols = setup.symbols
        let interner = setup.interner

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
        let setup = makeSemaModule()
        let resolver = OverloadResolver()
        let types = setup.types
        let symbols = setup.symbols
        let interner = setup.interner

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
        let setup = makeSemaModule()
        let resolver = OverloadResolver()
        let types = setup.types
        let symbols = setup.symbols
        let interner = setup.interner

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
        let setup = makeSemaModule()
        let resolver = OverloadResolver()
        let types = setup.types
        let symbols = setup.symbols
        let interner = setup.interner

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
        let setup = makeSemaModule()
        let resolver = OverloadResolver()
        let types = setup.types
        let symbols = setup.symbols
        let interner = setup.interner

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
        let setup = makeSemaModule()
        let resolver = OverloadResolver()
        let types = setup.types
        let symbols = setup.symbols
        let interner = setup.interner

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

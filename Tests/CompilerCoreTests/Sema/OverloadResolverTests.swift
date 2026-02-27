import XCTest
@testable import CompilerCore

final class OverloadResolverTests: XCTestCase {
    func makeEnv() -> (resolver: OverloadResolver, types: TypeSystem, symbols: SymbolTable, interner: StringInterner, ctx: SemaModule) {
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

    func defineSymbol(
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

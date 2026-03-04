@testable import CompilerCore
import XCTest

final class TypeCheckHelpersCoverageTests: XCTestCase {
    func testEmitVisibilityErrorAndBindErrorType() throws {
        let fixture = makeHelpersFixture()
        let helpers = TypeCheckHelpers()

        let privateSymbolID = fixture.symbols.define(
            kind: .function,
            name: fixture.interner.intern("privateFn"),
            fqName: [fixture.interner.intern("privateFn")],
            declSite: makeRange(),
            visibility: .private
        )
        let protectedSymbolID = fixture.symbols.define(
            kind: .function,
            name: fixture.interner.intern("protectedFn"),
            fqName: [fixture.interner.intern("protectedFn")],
            declSite: makeRange(),
            visibility: .protected
        )

        let privateSymbol = fixture.symbols.symbol(privateSymbolID)
        let protectedSymbol = fixture.symbols.symbol(protectedSymbolID)

        try helpers.emitVisibilityError(
            for: XCTUnwrap(privateSymbol),
            name: "privateFn",
            range: makeRange(),
            diagnostics: fixture.diagnostics
        )
        try helpers.emitVisibilityError(
            for: XCTUnwrap(protectedSymbol),
            name: "protectedFn",
            range: makeRange(),
            diagnostics: fixture.diagnostics
        )

        XCTAssertTrue(fixture.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0040" })
        XCTAssertTrue(fixture.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0041" })

        let exprID = ExprID(rawValue: 123)
        let result = helpers.bindAndReturnErrorType(exprID, sema: fixture.sema)
        XCTAssertEqual(result, fixture.types.errorType)
        XCTAssertEqual(fixture.bindings.exprType(for: exprID), fixture.types.errorType)
    }

    func testStableLocalSymbolIterableAndBuiltinReturnTypes() {
        let fixture = makeHelpersFixture()
        let helpers = TypeCheckHelpers()

        let stableLocal = fixture.symbols.define(
            kind: .local,
            name: fixture.interner.intern("stable"),
            fqName: [fixture.interner.intern("stable")],
            declSite: nil,
            visibility: .private
        )
        let mutableLocal = fixture.symbols.define(
            kind: .local,
            name: fixture.interner.intern("mutable"),
            fqName: [fixture.interner.intern("mutable")],
            declSite: nil,
            visibility: .private,
            flags: [.mutable]
        )
        let fnSymbol = fixture.symbols.define(
            kind: .function,
            name: fixture.interner.intern("f"),
            fqName: [fixture.interner.intern("f")],
            declSite: nil,
            visibility: .public
        )

        XCTAssertTrue(helpers.isStableLocalSymbol(stableLocal, sema: fixture.sema))
        XCTAssertFalse(helpers.isStableLocalSymbol(mutableLocal, sema: fixture.sema))
        XCTAssertFalse(helpers.isStableLocalSymbol(fnSymbol, sema: fixture.sema))
        XCTAssertFalse(helpers.isStableLocalSymbol(SymbolID(rawValue: 999), sema: fixture.sema))

        let intArraySymbol = fixture.symbols.define(
            kind: .class,
            name: fixture.interner.intern("IntArray"),
            fqName: [fixture.interner.intern("IntArray")],
            declSite: nil,
            visibility: .public
        )
        let intArrayType = fixture.types.make(
            .classType(ClassType(classSymbol: intArraySymbol, args: [], nullability: .nonNull))
        )

        XCTAssertEqual(
            helpers.arrayElementType(for: intArrayType, sema: fixture.sema, interner: fixture.interner),
            fixture.types.intType
        )
        XCTAssertNil(
            helpers.arrayElementType(for: fixture.types.intType, sema: fixture.sema, interner: fixture.interner)
        )

        XCTAssertEqual(
            helpers.iterableElementType(for: fixture.types.intType, isRangeExpr: true, sema: fixture.sema, interner: fixture.interner),
            fixture.types.intType
        )
        XCTAssertEqual(
            helpers.iterableElementType(for: intArrayType, isRangeExpr: false, sema: fixture.sema, interner: fixture.interner),
            fixture.types.intType
        )

        XCTAssertEqual(
            helpers.kxMiniCoroutineBuiltinReturnType(
                calleeName: fixture.interner.intern("runBlocking"),
                argumentCount: 1,
                sema: fixture.sema,
                interner: fixture.interner
            ),
            fixture.types.anyType
        )
        XCTAssertEqual(
            helpers.kxMiniCoroutineBuiltinReturnType(
                calleeName: fixture.interner.intern("launch"),
                argumentCount: 1,
                sema: fixture.sema,
                interner: fixture.interner
            ),
            fixture.types.unitType
        )
        XCTAssertEqual(
            helpers.kxMiniCoroutineBuiltinReturnType(
                calleeName: fixture.interner.intern("kk_array_get"),
                argumentCount: 2,
                sema: fixture.sema,
                interner: fixture.interner
            ),
            fixture.types.anyType
        )
        XCTAssertNil(
            helpers.kxMiniCoroutineBuiltinReturnType(
                calleeName: fixture.interner.intern("unknown"),
                argumentCount: 1,
                sema: fixture.sema,
                interner: fixture.interner
            )
        )
        XCTAssertNil(
            helpers.kxMiniCoroutineBuiltinReturnType(
                calleeName: nil,
                argumentCount: 1,
                sema: fixture.sema,
                interner: fixture.interner
            )
        )
    }

    func testResolveBuiltinAndTypeRefVariants() {
        let fixture = makeHelpersFixture()
        let helpers = TypeCheckHelpers()

        XCTAssertEqual(helpers.resolveBuiltinTypeName("Int", types: fixture.types), fixture.types.intType)
        XCTAssertEqual(helpers.resolveBuiltinTypeName("Any", nullability: .nullable, types: fixture.types), fixture.types.nullableAnyType)
        XCTAssertEqual(helpers.resolveBuiltinTypeName("Nothing", nullability: .nullable, types: fixture.types), fixture.types.nullableNothingType)
        XCTAssertNil(helpers.resolveBuiltinTypeName("Unknown", types: fixture.types))

        let intRef = fixture.astArena.appendTypeRef(
            .named(path: [fixture.interner.intern("Int")], args: [], nullable: false)
        )
        let nullableIntRef = fixture.astArena.appendTypeRef(
            .named(path: [fixture.interner.intern("Int")], args: [], nullable: true)
        )
        let fnRef = fixture.astArena.appendTypeRef(
            .functionType(params: [intRef], returnType: nullableIntRef, isSuspend: true, nullable: false)
        )
        let intersectionRef = fixture.astArena.appendTypeRef(.intersection(parts: [intRef, nullableIntRef]))

        XCTAssertEqual(
            helpers.resolveTypeRef(intRef, ast: fixture.ast, sema: fixture.sema, interner: fixture.interner),
            fixture.types.intType
        )

        let resolvedFn = helpers.resolveTypeRef(fnRef, ast: fixture.ast, sema: fixture.sema, interner: fixture.interner)
        if case let .functionType(ft) = fixture.types.kind(of: resolvedFn) {
            XCTAssertEqual(ft.params, [fixture.types.intType])
            XCTAssertEqual(ft.returnType, fixture.types.make(.primitive(.int, .nullable)))
            XCTAssertTrue(ft.isSuspend)
        } else {
            XCTFail("Expected functionType")
        }

        let resolvedIntersection = helpers.resolveTypeRef(
            intersectionRef,
            ast: fixture.ast,
            sema: fixture.sema,
            interner: fixture.interner
        )
        if case let .intersection(parts) = fixture.types.kind(of: resolvedIntersection) {
            XCTAssertEqual(parts.count, 2)
        } else {
            XCTFail("Expected intersection")
        }

        let unresolvedRef = fixture.astArena.appendTypeRef(
            .named(path: [fixture.interner.intern("MissingType")], args: [], nullable: false)
        )
        let unresolved = helpers.resolveTypeRef(
            unresolvedRef,
            ast: fixture.ast,
            sema: fixture.sema,
            interner: fixture.interner,
            diagnostics: fixture.diagnostics
        )
        XCTAssertEqual(unresolved, fixture.types.errorType)
        XCTAssertTrue(fixture.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0025" })

        XCTAssertEqual(
            helpers.resolveTypeRef(TypeRefID(rawValue: 9999), ast: fixture.ast, sema: fixture.sema, interner: fixture.interner),
            fixture.types.errorType
        )
    }

    func testTypeAliasExpansionAndSubstitutionPaths() {
        let fixture = makeHelpersFixture()
        let helpers = TypeCheckHelpers()

        let tParam = fixture.symbols.define(
            kind: .typeParameter,
            name: fixture.interner.intern("T"),
            fqName: [fixture.interner.intern("Alias"), fixture.interner.intern("T")],
            declSite: nil,
            visibility: .private
        )
        let aliasSymbol = fixture.symbols.define(
            kind: .typeAlias,
            name: fixture.interner.intern("Alias"),
            fqName: [fixture.interner.intern("pkg"), fixture.interner.intern("Alias")],
            declSite: nil,
            visibility: .public
        )
        let typeParamType = fixture.types.make(.typeParam(TypeParamType(symbol: tParam, nullability: .nonNull)))
        fixture.symbols.setTypeAliasUnderlyingType(typeParamType, for: aliasSymbol)
        fixture.symbols.setTypeAliasTypeParameters([tParam], for: aliasSymbol)

        let expanded = helpers.expandTypeAlias(
            aliasSymbol,
            typeArgs: [.invariant(fixture.types.intType)],
            sema: fixture.sema,
            visited: [],
            depth: 0,
            diagnostics: fixture.diagnostics
        )
        XCTAssertEqual(expanded, fixture.types.intType)

        let aliasRef = fixture.astArena.appendTypeRef(
            .named(
                path: [fixture.interner.intern("Alias")],
                args: [.invariant(fixture.astArena.appendTypeRef(.named(path: [fixture.interner.intern("Int")], args: [], nullable: false)))],
                nullable: false
            )
        )
        let resolvedAlias = helpers.resolveTypeRef(
            aliasRef,
            ast: fixture.ast,
            sema: fixture.sema,
            interner: fixture.interner,
            diagnostics: fixture.diagnostics
        )
        XCTAssertEqual(resolvedAlias, fixture.types.intType)

        let aliasA = fixture.symbols.define(
            kind: .typeAlias,
            name: fixture.interner.intern("A"),
            fqName: [fixture.interner.intern("A")],
            declSite: nil,
            visibility: .public
        )
        let aliasB = fixture.symbols.define(
            kind: .typeAlias,
            name: fixture.interner.intern("B"),
            fqName: [fixture.interner.intern("B")],
            declSite: nil,
            visibility: .public
        )
        fixture.symbols.setTypeAliasUnderlyingType(
            fixture.types.make(.classType(ClassType(classSymbol: aliasB, args: [], nullability: .nonNull))),
            for: aliasA
        )
        fixture.symbols.setTypeAliasUnderlyingType(
            fixture.types.make(.classType(ClassType(classSymbol: aliasA, args: [], nullability: .nonNull))),
            for: aliasB
        )

        let cyclic = helpers.expandTypeAlias(
            aliasA,
            typeArgs: [],
            sema: fixture.sema,
            visited: [],
            depth: 0,
            diagnostics: fixture.diagnostics
        )
        XCTAssertNil(cyclic)
        XCTAssertTrue(fixture.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-ALIAS-CYCLE" })

        let overDepth = helpers.expandTypeAlias(
            aliasA,
            typeArgs: [],
            sema: fixture.sema,
            visited: [],
            depth: 32,
            diagnostics: fixture.diagnostics
        )
        XCTAssertNil(overDepth)
        XCTAssertTrue(fixture.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-ALIAS-DEPTH" })

        _ = helpers.expandTypeAlias(
            aliasSymbol,
            typeArgs: [],
            sema: fixture.sema,
            visited: [],
            depth: 0,
            diagnostics: fixture.diagnostics
        )
        XCTAssertTrue(fixture.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0062" })

        let substituted = helpers.applyAliasSubstitution(
            typeParamType,
            argSubstitution: [tParam: .invariant(fixture.types.stringType)],
            sema: fixture.sema
        )
        XCTAssertEqual(substituted, fixture.types.stringType)
    }

    func testPart2HelpersForNullabilitySmartCastAndCallableSelection() {
        let fixture = makeHelpersFixture()
        let helpers = TypeCheckHelpers()
        let range = makeRange()

        let tp = fixture.symbols.define(
            kind: .typeParameter,
            name: fixture.interner.intern("U"),
            fqName: [fixture.interner.intern("U")],
            declSite: nil,
            visibility: .private
        )
        let tpType = fixture.types.make(.typeParam(TypeParamType(symbol: tp, nullability: .nullable)))

        let substitutedInvariant = helpers.substituteAliasArg(
            .invariant(tpType),
            argSubstitution: [tp: .invariant(fixture.types.intType)],
            sema: fixture.sema
        )
        if case let .invariant(inner) = substitutedInvariant {
            XCTAssertEqual(fixture.types.kind(of: inner), .primitive(.int, .nullable))
        } else {
            XCTFail("Expected invariant")
        }

        let substitutedOut = helpers.substituteAliasArg(
            .out(tpType),
            argSubstitution: [tp: .star],
            sema: fixture.sema
        )
        XCTAssertEqual(substitutedOut, .star)

        let substitutedIn = helpers.substituteAliasArg(
            .in(tpType),
            argSubstitution: [tp: .in(fixture.types.stringType)],
            sema: fixture.sema
        )
        if case let .in(inner) = substitutedIn {
            XCTAssertEqual(fixture.types.kind(of: inner), .primitive(.string, .nullable))
        } else {
            XCTFail("Expected in")
        }

        XCTAssertEqual(
            helpers.applyNullabilityForTypeCheck(fixture.types.intType, types: fixture.types),
            fixture.types.make(.primitive(.int, .nullable))
        )
        XCTAssertEqual(
            helpers.applyNullabilityForTypeCheck(fixture.types.errorType, types: fixture.types),
            fixture.types.nullableAnyType
        )

        XCTAssertEqual(helpers.typeArgInnerTypeForCheck(.star), TypeID.invalid)
        XCTAssertEqual(helpers.typeArgInnerTypeForCheck(.out(fixture.types.intType)), fixture.types.intType)

        let explicitTypeArgRef = fixture.astArena.appendTypeRef(
            .named(path: [fixture.interner.intern("Int")], args: [], nullable: false)
        )
        XCTAssertEqual(
            helpers.resolveExplicitTypeArgs([], ast: fixture.ast, sema: fixture.sema, interner: fixture.interner),
            []
        )
        XCTAssertEqual(
            helpers.resolveExplicitTypeArgs([explicitTypeArgRef], ast: fixture.ast, sema: fixture.sema, interner: fixture.interner),
            [fixture.types.intType]
        )

        XCTAssertTrue(helpers.isTerminatingExpr(.returnExpr(value: nil, range: range)))
        XCTAssertTrue(helpers.isTerminatingExpr(.throwExpr(value: fixture.astArena.appendExpr(.intLiteral(1, range)), range: range)))
        XCTAssertFalse(helpers.isTerminatingExpr(.intLiteral(1, range)))

        XCTAssertEqual(helpers.compoundAssignToBinaryOp(.plusAssign), .add)
        XCTAssertEqual(helpers.compoundAssignToBinaryOp(.modAssign), .modulo)

        let boolCondition = fixture.astArena.appendExpr(.boolLiteral(true, range))
        let smartCastFromBool = helpers.smartCastTypeForWhenSubjectCase(
            conditionID: boolCondition,
            subjectType: fixture.types.booleanType,
            ast: fixture.ast,
            sema: fixture.sema,
            interner: fixture.interner
        )
        XCTAssertEqual(smartCastFromBool, fixture.types.booleanType)

        let enumSymbol = fixture.symbols.define(
            kind: .enumClass,
            name: fixture.interner.intern("Color"),
            fqName: [fixture.interner.intern("Color")],
            declSite: nil,
            visibility: .public
        )
        let enumEntry = fixture.symbols.define(
            kind: .field,
            name: fixture.interner.intern("RED"),
            fqName: [fixture.interner.intern("Color"), fixture.interner.intern("RED")],
            declSite: nil,
            visibility: .public
        )
        let enumRefExpr = fixture.astArena.appendExpr(.nameRef(fixture.interner.intern("RED"), range))
        fixture.bindings.bindIdentifier(enumRefExpr, symbol: enumEntry)
        let enumSubjectType = fixture.types.make(.classType(ClassType(classSymbol: enumSymbol, args: [], nullability: .nonNull)))
        let enumSmartCast = helpers.smartCastTypeForWhenSubjectCase(
            conditionID: enumRefExpr,
            subjectType: enumSubjectType,
            ast: fixture.ast,
            sema: fixture.sema,
            interner: fixture.interner
        )
        XCTAssertNotNil(enumSmartCast)

        let base = fixture.symbols.define(
            kind: .class,
            name: fixture.interner.intern("Base"),
            fqName: [fixture.interner.intern("Base")],
            declSite: nil,
            visibility: .public
        )
        let child = fixture.symbols.define(
            kind: .class,
            name: fixture.interner.intern("Child"),
            fqName: [fixture.interner.intern("Child")],
            declSite: nil,
            visibility: .public
        )
        fixture.symbols.setDirectSupertypes([base], for: child)

        let childRefExpr = fixture.astArena.appendExpr(.nameRef(fixture.interner.intern("Child"), range))
        fixture.bindings.bindIdentifier(childRefExpr, symbol: child)

        let nominalSmartCast = helpers.smartCastTypeForWhenSubjectCase(
            conditionID: childRefExpr,
            subjectType: fixture.types.make(.classType(ClassType(classSymbol: base, args: [], nullability: .nonNull))),
            ast: fixture.ast,
            sema: fixture.sema,
            interner: fixture.interner
        )
        XCTAssertEqual(
            nominalSmartCast,
            fixture.types.make(.classType(ClassType(classSymbol: child, args: [], nullability: .nonNull)))
        )

        let owner = fixture.symbols.define(
            kind: .class,
            name: fixture.interner.intern("Owner"),
            fqName: [fixture.interner.intern("Owner")],
            declSite: nil,
            visibility: .public
        )
        let receiverType = fixture.types.make(.classType(ClassType(classSymbol: owner, args: [], nullability: .nonNull)))

        let memberFn = fixture.symbols.define(
            kind: .function,
            name: fixture.interner.intern("m"),
            fqName: [fixture.interner.intern("Owner"), fixture.interner.intern("m")],
            declSite: nil,
            visibility: .public
        )
        fixture.symbols.setParentSymbol(owner, for: memberFn)
        fixture.symbols.setFunctionSignature(
            FunctionSignature(receiverType: receiverType, parameterTypes: [], returnType: fixture.types.unitType),
            for: memberFn
        )

        let candidates = helpers.collectMemberFunctionCandidates(
            named: fixture.interner.intern("m"),
            receiverType: receiverType,
            sema: fixture.sema
        )
        XCTAssertEqual(candidates, [memberFn])

        let propertySymbol = fixture.symbols.define(
            kind: .property,
            name: fixture.interner.intern("p"),
            fqName: [fixture.interner.intern("Owner"), fixture.interner.intern("p")],
            declSite: nil,
            visibility: .public
        )
        fixture.symbols.setPropertyType(fixture.types.intType, for: propertySymbol)

        let propertyLookup = helpers.lookupMemberProperty(
            named: fixture.interner.intern("p"),
            receiverType: receiverType,
            sema: fixture.sema
        )
        XCTAssertEqual(propertyLookup?.symbol, propertySymbol)

        XCTAssertTrue(helpers.isNominalSubtype(child, of: base, symbols: fixture.symbols))
        XCTAssertFalse(helpers.isNominalSubtype(base, of: child, symbols: fixture.symbols))

        let calleeExpr = ExprID(rawValue: 700)
        fixture.bindings.bindCallableTarget(calleeExpr, target: .symbol(memberFn))
        XCTAssertEqual(helpers.callableTargetForCalleeExpr(calleeExpr, sema: fixture.sema), .symbol(memberFn))

        let calleeExpr2 = ExprID(rawValue: 701)
        fixture.bindings.bindIdentifier(calleeExpr2, symbol: propertySymbol)
        XCTAssertEqual(helpers.callableTargetForCalleeExpr(calleeExpr2, sema: fixture.sema), .localValue(propertySymbol))

        let callableType = helpers.callableFunctionType(
            for: FunctionSignature(receiverType: receiverType, parameterTypes: [fixture.types.intType], returnType: fixture.types.unitType),
            bindReceiver: false,
            sema: fixture.sema
        )
        if case let .functionType(ft) = fixture.types.kind(of: callableType) {
            XCTAssertEqual(ft.params.count, 2)
        } else {
            XCTFail("Expected function type")
        }

        let chooserA = fixture.symbols.define(
            kind: .function,
            name: fixture.interner.intern("choose"),
            fqName: [fixture.interner.intern("chooseA")],
            declSite: nil,
            visibility: .public
        )
        fixture.symbols.setFunctionSignature(
            FunctionSignature(parameterTypes: [fixture.types.anyType], returnType: fixture.types.anyType),
            for: chooserA
        )
        let chooserB = fixture.symbols.define(
            kind: .function,
            name: fixture.interner.intern("choose"),
            fqName: [fixture.interner.intern("chooseB")],
            declSite: nil,
            visibility: .public
        )
        fixture.symbols.setFunctionSignature(
            FunctionSignature(parameterTypes: [fixture.types.intType], returnType: fixture.types.intType),
            for: chooserB
        )

        let expectedFnType = fixture.types.make(
            .functionType(FunctionType(params: [fixture.types.intType], returnType: fixture.types.intType, isSuspend: false, nullability: .nonNull))
        )
        let chosen = helpers.chooseCallableReferenceTarget(
            from: [chooserA, chooserB],
            expectedType: expectedFnType,
            bindReceiver: true,
            sema: fixture.sema
        )
        XCTAssertEqual(chosen, chooserB)

        let defaultChosen = helpers.chooseCallableReferenceTarget(
            from: [chooserB, chooserA],
            expectedType: fixture.types.intType,
            bindReceiver: true,
            sema: fixture.sema
        )
        XCTAssertEqual(defaultChosen, [chooserA, chooserB].sorted(by: { $0.rawValue < $1.rawValue }).first)
    }
}

private struct HelpersFixture {
    let interner: StringInterner
    let diagnostics: DiagnosticEngine
    let symbols: SymbolTable
    let types: TypeSystem
    let bindings: BindingTable
    let sema: SemaModule
    let astArena: ASTArena
    let ast: ASTModule
}

private func makeHelpersFixture() -> HelpersFixture {
    let interner = StringInterner()
    let diagnostics = DiagnosticEngine()
    let symbols = SymbolTable()
    let types = TypeSystem()
    let bindings = BindingTable()
    let sema = SemaModule(
        symbols: symbols,
        types: types,
        bindings: bindings,
        diagnostics: diagnostics
    )

    let astArena = ASTArena()
    let ast = ASTModule(
        files: [
            ASTFile(
                fileID: FileID(rawValue: 0),
                packageFQName: [interner.intern("pkg")],
                imports: [],
                topLevelDecls: [],
                scriptBody: []
            ),
        ],
        arena: astArena,
        declarationCount: 0,
        tokenCount: 0
    )

    return HelpersFixture(
        interner: interner,
        diagnostics: diagnostics,
        symbols: symbols,
        types: types,
        bindings: bindings,
        sema: sema,
        astArena: astArena,
        ast: ast
    )
}

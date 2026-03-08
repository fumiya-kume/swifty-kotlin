@testable import CompilerCore
import XCTest

extension TypeCheckHelpersCoverageTests {
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

    func testSubstituteAliasArgAndNullabilityHelpers() {
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
    }

    func testSmartCastAndMemberCallableSelection() {
        let fixture = makeHelpersFixture()
        let helpers = TypeCheckHelpers()
        let range = makeRange()

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

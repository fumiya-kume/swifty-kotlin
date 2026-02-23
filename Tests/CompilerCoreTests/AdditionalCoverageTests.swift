import XCTest
@testable import CompilerCore

// MARK: - SymbolTable Missing Accessor Tests

final class SymbolTableAdditionalTests: XCTestCase {

    func testLookupByShortNameReturnsMatchingSymbols() {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let name = interner.intern("foo")
        let id1 = symbols.define(
            kind: .function,
            name: name,
            fqName: [interner.intern("pkg"), name],
            declSite: nil,
            visibility: .public
        )
        let id2 = symbols.define(
            kind: .function,
            name: name,
            fqName: [interner.intern("other"), name],
            declSite: nil,
            visibility: .public
        )
        let results = symbols.lookupByShortName(name)
        XCTAssertTrue(results.contains(id1))
        XCTAssertTrue(results.contains(id2))
        XCTAssertEqual(results.count, 2)
    }

    func testLookupByShortNameReturnsEmptyForUnknown() {
        let interner = StringInterner()
        let symbols = SymbolTable()
        XCTAssertEqual(symbols.lookupByShortName(interner.intern("missing")), [])
    }

    func testSetAndGetSupertypeTypeArgs() {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let types = TypeSystem()
        let parent = symbols.define(
            kind: .class,
            name: interner.intern("Parent"),
            fqName: [interner.intern("Parent")],
            declSite: nil,
            visibility: .public
        )
        let child = symbols.define(
            kind: .class,
            name: interner.intern("Child"),
            fqName: [interner.intern("Child")],
            declSite: nil,
            visibility: .public
        )
        let intType = types.make(.primitive(.int, .nonNull))
        let args: [TypeArg] = [.invariant(intType), .out(types.anyType)]
        symbols.setSupertypeTypeArgs(args, for: child, supertype: parent)
        let retrieved = symbols.supertypeTypeArgs(for: child, supertype: parent)
        XCTAssertEqual(retrieved, args)
    }

    func testSupertypeTypeArgsReturnsEmptyForUnset() {
        let symbols = SymbolTable()
        let result = symbols.supertypeTypeArgs(
            for: SymbolID(rawValue: 0),
            supertype: SymbolID(rawValue: 1)
        )
        XCTAssertEqual(result, [])
    }

    func testSetAndGetBackingFieldSymbol() {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let prop = symbols.define(
            kind: .property,
            name: interner.intern("value"),
            fqName: [interner.intern("value")],
            declSite: nil,
            visibility: .public
        )
        let backingField = symbols.define(
            kind: .backingField,
            name: interner.intern("value$backing"),
            fqName: [interner.intern("value$backing")],
            declSite: nil,
            visibility: .private
        )
        symbols.setBackingFieldSymbol(backingField, for: prop)
        XCTAssertEqual(symbols.backingFieldSymbol(for: prop), backingField)
    }

    func testBackingFieldSymbolReturnsNilForUnset() {
        let symbols = SymbolTable()
        XCTAssertNil(symbols.backingFieldSymbol(for: SymbolID(rawValue: 0)))
    }
}

// MARK: - BindingTable Read-Side Accessor Tests

final class BindingTableAdditionalTests: XCTestCase {

    func testExprTypeForMethod() {
        let bindings = BindingTable()
        let types = TypeSystem()
        let expr = ExprID(rawValue: 10)
        let intType = types.make(.primitive(.int, .nonNull))
        bindings.bindExprType(expr, type: intType)
        XCTAssertEqual(bindings.exprType(for: expr), intType)
    }

    func testExprTypeForReturnsNilWhenUnbound() {
        let bindings = BindingTable()
        XCTAssertNil(bindings.exprType(for: ExprID(rawValue: 99)))
    }

    func testIdentifierSymbolForMethod() {
        let bindings = BindingTable()
        let expr = ExprID(rawValue: 5)
        let sym = SymbolID(rawValue: 42)
        bindings.bindIdentifier(expr, symbol: sym)
        XCTAssertEqual(bindings.identifierSymbol(for: expr), sym)
    }

    func testIdentifierSymbolForReturnsNilWhenUnbound() {
        let bindings = BindingTable()
        XCTAssertNil(bindings.identifierSymbol(for: ExprID(rawValue: 99)))
    }

    func testCallBindingForMethod() {
        let bindings = BindingTable()
        let expr = ExprID(rawValue: 3)
        let binding = CallBinding(
            chosenCallee: SymbolID(rawValue: 7),
            substitutedTypeArguments: [],
            parameterMapping: [0: 1, 1: 0]
        )
        bindings.bindCall(expr, binding: binding)
        let retrieved = bindings.callBinding(for: expr)
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.chosenCallee, SymbolID(rawValue: 7))
        XCTAssertEqual(retrieved?.parameterMapping, [0: 1, 1: 0])
    }

    func testCallBindingForReturnsNilWhenUnbound() {
        let bindings = BindingTable()
        XCTAssertNil(bindings.callBinding(for: ExprID(rawValue: 99)))
    }

    func testDeclSymbolForMethod() {
        let bindings = BindingTable()
        let decl = DeclID(rawValue: 2)
        let sym = SymbolID(rawValue: 15)
        bindings.bindDecl(decl, symbol: sym)
        XCTAssertEqual(bindings.declSymbol(for: decl), sym)
    }

    func testDeclSymbolForReturnsNilWhenUnbound() {
        let bindings = BindingTable()
        XCTAssertNil(bindings.declSymbol(for: DeclID(rawValue: 99)))
    }

    func testIsSuperCallExprMethod() {
        let bindings = BindingTable()
        let expr = ExprID(rawValue: 20)
        XCTAssertFalse(bindings.isSuperCallExpr(expr))
        bindings.markSuperCall(expr)
        XCTAssertTrue(bindings.isSuperCallExpr(expr))
    }

    func testIsSuperCallExprReturnsFalseForUnmarked() {
        let bindings = BindingTable()
        XCTAssertFalse(bindings.isSuperCallExpr(ExprID(rawValue: 999)))
    }
}

// MARK: - TypeSystem Nominal Supertype TypeArgs Tests

final class TypeSystemAdditionalTests: XCTestCase {

    func testSetAndGetNominalSupertypeTypeArgs() {
        let ts = TypeSystem()
        let child = SymbolID(rawValue: 0)
        let parent = SymbolID(rawValue: 1)
        let intType = ts.make(.primitive(.int, .nonNull))
        let args: [TypeArg] = [.invariant(intType), .out(ts.anyType)]
        ts.setNominalSupertypeTypeArgs(args, for: child, supertype: parent)
        let retrieved = ts.nominalSupertypeTypeArgs(for: child, supertype: parent)
        XCTAssertEqual(retrieved, args)
    }

    func testNominalSupertypeTypeArgsReturnsEmptyForUnset() {
        let ts = TypeSystem()
        let result = ts.nominalSupertypeTypeArgs(
            for: SymbolID(rawValue: 0),
            supertype: SymbolID(rawValue: 1)
        )
        XCTAssertEqual(result, [])
    }
}

// MARK: - ASTArena Edge Case Tests

final class ASTArenaAdditionalTests: XCTestCase {

    func testDeclReturnsNilForNegativeID() {
        let arena = ASTArena()
        XCTAssertNil(arena.decl(DeclID(rawValue: -1)))
    }

    func testDeclReturnsNilForOutOfRangeID() {
        let arena = ASTArena()
        XCTAssertNil(arena.decl(DeclID(rawValue: 999)))
    }

    func testTypeRefReturnsNilForNegativeID() {
        let arena = ASTArena()
        XCTAssertNil(arena.typeRef(TypeRefID(rawValue: -1)))
    }

    func testTypeRefReturnsNilForOutOfRangeID() {
        let arena = ASTArena()
        XCTAssertNil(arena.typeRef(TypeRefID(rawValue: 999)))
    }

}

// Note: testASTModuleConvenienceInit and testASTModuleSortedFiles were removed
// as they duplicate testASTModuleFullAndCompactInitializers and
// testSortedFilesReturnsByFileID in ASTModelsTests.swift.

// MARK: - DataFlowAnalyzer Struct Init Edge Cases

final class DataFlowStructTests: XCTestCase {

    func testDataFlowStateDefaultInit() {
        let state = DataFlowState()
        XCTAssertTrue(state.variables.isEmpty)
    }

    func testVariableFlowStateEquality() {
        let types = TypeSystem()
        let intType = types.make(.primitive(.int, .nonNull))
        let a = VariableFlowState(
            possibleTypes: [intType],
            nullability: .nonNull,
            isStable: true
        )
        let b = VariableFlowState(
            possibleTypes: [intType],
            nullability: .nonNull,
            isStable: true
        )
        let c = VariableFlowState(
            possibleTypes: [intType],
            nullability: .nullable,
            isStable: true
        )
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    func testWhenBranchSummaryAutoDerivation() {
        // When hasTrueCase/hasFalseCase are not explicitly provided,
        // they should be derived from coveredSymbols containing
        // InternedString(rawValue: 1) and InternedString(rawValue: 2).
        // WARNING: These sentinel values are coupled to DataFlowAnalysis.swift:38-39.
        // If the implementation changes these magic constants, this test must be
        // updated in sync.
        let trueSymbol = InternedString(rawValue: 1)
        let falseSymbol = InternedString(rawValue: 2)

        let summaryBoth = WhenBranchSummary(
            coveredSymbols: [trueSymbol, falseSymbol],
            hasElse: false
        )
        XCTAssertTrue(summaryBoth.hasTrueCase)
        XCTAssertTrue(summaryBoth.hasFalseCase)

        let summaryTrueOnly = WhenBranchSummary(
            coveredSymbols: [trueSymbol],
            hasElse: false
        )
        XCTAssertTrue(summaryTrueOnly.hasTrueCase)
        XCTAssertFalse(summaryTrueOnly.hasFalseCase)

        let summaryNone = WhenBranchSummary(
            coveredSymbols: [],
            hasElse: false
        )
        XCTAssertFalse(summaryNone.hasTrueCase)
        XCTAssertFalse(summaryNone.hasFalseCase)

        // Explicit override should take precedence
        let summaryExplicit = WhenBranchSummary(
            coveredSymbols: [],
            hasElse: false,
            hasTrueCase: true,
            hasFalseCase: true
        )
        XCTAssertTrue(summaryExplicit.hasTrueCase)
        XCTAssertTrue(summaryExplicit.hasFalseCase)
    }
}

// MARK: - DiagnosticEngine.hasError Tests

final class DiagnosticEngineAdditionalTests: XCTestCase {

    func testHasErrorReturnsFalseWhenEmpty() {
        let engine = DiagnosticEngine()
        XCTAssertFalse(engine.hasError)
    }

    func testHasErrorReturnsFalseWithOnlyWarnings() {
        let engine = DiagnosticEngine()
        engine.warning("W001", "some warning", range: nil)
        engine.note("N001", "some note", range: nil)
        engine.info("I001", "some info", range: nil)
        XCTAssertFalse(engine.hasError)
    }

    func testHasErrorReturnsTrueWithError() {
        let engine = DiagnosticEngine()
        engine.warning("W001", "some warning", range: nil)
        engine.error("E001", "some error", range: nil)
        XCTAssertTrue(engine.hasError)
    }
}

// Note: Scope subclass tests (FileScope, BlockScope, ImportScope) were removed
// as BaseScope behavior is already thoroughly tested in SymbolTableTests.swift.
// PackageScope and FunctionScope are empty final classes with no unique logic.
// The 3-level scope chain delegation test was also removed since
// testBaseScopeLookupDelegatesToParent in SymbolTableTests.swift covers this.

// MARK: - CallableValueCallBinding and CatchClauseBinding Init Tests

final class BindingModelAdditionalTests: XCTestCase {

    func testCallableValueCallBindingInit() {
        let types = TypeSystem()
        let fnType = types.make(.functionType(FunctionType(
            params: [types.make(.primitive(.int, .nonNull))],
            returnType: types.unitType
        )))
        let binding = CallableValueCallBinding(
            target: .symbol(SymbolID(rawValue: 5)),
            functionType: fnType,
            parameterMapping: [0: 0]
        )
        XCTAssertEqual(binding.target, .symbol(SymbolID(rawValue: 5)))
        XCTAssertEqual(binding.functionType, fnType)
        XCTAssertEqual(binding.parameterMapping, [0: 0])
    }

    func testCallableValueCallBindingNilTarget() {
        let types = TypeSystem()
        let binding = CallableValueCallBinding(
            target: nil,
            functionType: types.unitType,
            parameterMapping: [:]
        )
        XCTAssertNil(binding.target)
    }

    func testCatchClauseBindingDefaultParameterSymbol() {
        let types = TypeSystem()
        let binding = CatchClauseBinding(parameterType: types.anyType)
        XCTAssertEqual(binding.parameterSymbol, .invalid)
        XCTAssertEqual(binding.parameterType, types.anyType)
    }

    func testCatchClauseBindingWithExplicitSymbol() {
        let types = TypeSystem()
        let sym = SymbolID(rawValue: 42)
        let binding = CatchClauseBinding(parameterSymbol: sym, parameterType: types.anyType)
        XCTAssertEqual(binding.parameterSymbol, sym)
    }

    func testCallableTargetEquality() {
        let sym1 = SymbolID(rawValue: 1)
        let sym2 = SymbolID(rawValue: 2)
        XCTAssertEqual(CallableTarget.symbol(sym1), CallableTarget.symbol(sym1))
        XCTAssertNotEqual(CallableTarget.symbol(sym1), CallableTarget.symbol(sym2))
        XCTAssertEqual(CallableTarget.localValue(sym1), CallableTarget.localValue(sym1))
        XCTAssertNotEqual(CallableTarget.symbol(sym1), CallableTarget.localValue(sym1))
    }
}

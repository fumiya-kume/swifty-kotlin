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

    func testASTModuleConvenienceInit() {
        let module = ASTModule(declarationCount: 5, tokenCount: 20)
        XCTAssertEqual(module.declarationCount, 5)
        XCTAssertEqual(module.tokenCount, 20)
        XCTAssertTrue(module.files.isEmpty)
    }

    func testASTModuleSortedFiles() {
        let arena = ASTArena()
        let interner = StringInterner()
        let file0 = ASTFile(
            fileID: FileID(rawValue: 2),
            packageFQName: [interner.intern("b")],
            imports: [],
            topLevelDecls: [],
            scriptBody: []
        )
        let file1 = ASTFile(
            fileID: FileID(rawValue: 0),
            packageFQName: [interner.intern("a")],
            imports: [],
            topLevelDecls: [],
            scriptBody: []
        )
        let module = ASTModule(
            files: [file0, file1],
            arena: arena,
            declarationCount: 0,
            tokenCount: 0
        )
        let sorted = module.sortedFiles
        XCTAssertEqual(sorted[0].fileID.rawValue, 0)
        XCTAssertEqual(sorted[1].fileID.rawValue, 2)
    }
}

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
        // InternedString(rawValue: 1) and InternedString(rawValue: 2)
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

// MARK: - Scope Subclass Tests

final class ScopeSubclassTests: XCTestCase {

    func testFileScopeInheritsBaseScopeBehavior() {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let scope = FileScope(parent: nil, symbols: symbols)
        let id = symbols.define(
            kind: .function,
            name: interner.intern("f"),
            fqName: [interner.intern("f")],
            declSite: nil,
            visibility: .public
        )
        scope.insert(id)
        XCTAssertEqual(scope.lookup(interner.intern("f")), [id])
        XCTAssertEqual(scope.lookup(interner.intern("missing")), [])
        XCTAssertNil(scope.parent)
    }

    func testPackageScopeInheritsBaseScopeBehavior() {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let scope = PackageScope(parent: nil, symbols: symbols)
        let id = symbols.define(
            kind: .class,
            name: interner.intern("MyClass"),
            fqName: [interner.intern("MyClass")],
            declSite: nil,
            visibility: .public
        )
        scope.insert(id)
        XCTAssertEqual(scope.lookup(interner.intern("MyClass")), [id])
    }

    func testImportScopeInheritsBaseScopeBehavior() {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let scope = ImportScope(parent: nil, symbols: symbols)
        let id = symbols.define(
            kind: .function,
            name: interner.intern("imported"),
            fqName: [interner.intern("imported")],
            declSite: nil,
            visibility: .public
        )
        scope.insert(id)
        XCTAssertEqual(scope.lookup(interner.intern("imported")), [id])
    }

    func testFunctionScopeInheritsBaseScopeBehavior() {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let scope = FunctionScope(parent: nil, symbols: symbols)
        let id = symbols.define(
            kind: .local,
            name: interner.intern("x"),
            fqName: [interner.intern("x")],
            declSite: nil,
            visibility: .internal
        )
        scope.insert(id)
        XCTAssertEqual(scope.lookup(interner.intern("x")), [id])
    }

    func testBlockScopeInheritsBaseScopeBehavior() {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let scope = BlockScope(parent: nil, symbols: symbols)
        let id = symbols.define(
            kind: .local,
            name: interner.intern("y"),
            fqName: [interner.intern("y")],
            declSite: nil,
            visibility: .internal
        )
        scope.insert(id)
        XCTAssertEqual(scope.lookup(interner.intern("y")), [id])
    }

    func testScopeChainDelegation() {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let parentScope = PackageScope(parent: nil, symbols: symbols)
        let childScope = FileScope(parent: parentScope, symbols: symbols)
        let grandChildScope = FunctionScope(parent: childScope, symbols: symbols)

        let id = symbols.define(
            kind: .class,
            name: interner.intern("Top"),
            fqName: [interner.intern("Top")],
            declSite: nil,
            visibility: .public
        )
        parentScope.insert(id)

        // grandchild should find symbol through parent chain
        XCTAssertEqual(grandChildScope.lookup(interner.intern("Top")), [id])
        XCTAssertNotNil(grandChildScope.parent)
    }
}

// MARK: - NominalLayout Inferred Size Logic Tests

final class NominalLayoutAdditionalTests: XCTestCase {

    func testNominalLayoutInfersFieldCountAndInstanceSize() {
        let field0 = SymbolID(rawValue: 10)
        let field1 = SymbolID(rawValue: 11)
        let field2 = SymbolID(rawValue: 12)
        let layout = NominalLayout(
            objectHeaderWords: 2,
            instanceFieldCount: 0,
            instanceSizeWords: 0,
            fieldOffsets: [field0: 2, field1: 3, field2: 4],
            vtableSlots: [:],
            itableSlots: [:],
            superClass: nil
        )
        // instanceFieldCount should be inferred from fieldOffsets.count (3)
        XCTAssertEqual(layout.instanceFieldCount, 3)
        // instanceSizeWords should be max(max(0, max_offset+1), headerWords + fieldCount)
        // max_offset+1 = 5, headerWords + fieldCount = 2+3 = 5
        XCTAssertEqual(layout.instanceSizeWords, 5)
    }

    func testNominalLayoutInfersVtableAndItableSize() {
        let fn0 = SymbolID(rawValue: 20)
        let fn1 = SymbolID(rawValue: 21)
        let iface0 = SymbolID(rawValue: 30)
        let layout = NominalLayout(
            objectHeaderWords: 2,
            instanceFieldCount: 0,
            instanceSizeWords: 2,
            vtableSlots: [fn0: 0, fn1: 1],
            itableSlots: [iface0: 0],
            superClass: nil
        )
        // vtableSize = max(0, max(0, max_slot+1)) = 2
        XCTAssertEqual(layout.vtableSize, 2)
        // itableSize = max(0, max(0, max_slot+1)) = 1
        XCTAssertEqual(layout.itableSize, 1)
    }

    func testNominalLayoutExplicitSizeTakesPrecedenceWhenLarger() {
        let layout = NominalLayout(
            objectHeaderWords: 2,
            instanceFieldCount: 1,
            instanceSizeWords: 10,
            fieldOffsets: [SymbolID(rawValue: 0): 2],
            vtableSlots: [:],
            itableSlots: [:],
            vtableSize: 5,
            itableSize: 3,
            superClass: SymbolID(rawValue: 99)
        )
        XCTAssertEqual(layout.instanceSizeWords, 10)
        XCTAssertEqual(layout.vtableSize, 5)
        XCTAssertEqual(layout.itableSize, 3)
        XCTAssertEqual(layout.superClass, SymbolID(rawValue: 99))
    }

    func testNominalLayoutEmptyFieldOffsetsAndSlots() {
        let layout = NominalLayout(
            objectHeaderWords: 2,
            instanceFieldCount: 0,
            instanceSizeWords: 2,
            vtableSlots: [:],
            itableSlots: [:],
            superClass: nil
        )
        XCTAssertEqual(layout.instanceFieldCount, 0)
        XCTAssertEqual(layout.instanceSizeWords, 2)
        XCTAssertEqual(layout.vtableSize, 0)
        XCTAssertEqual(layout.itableSize, 0)
        XCTAssertNil(layout.superClass)
    }
}

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

// MARK: - NominalLayoutHint Tests

final class NominalLayoutHintTests: XCTestCase {

    func testNominalLayoutHintAllNilFields() {
        let hint = NominalLayoutHint(
            declaredFieldCount: nil,
            declaredInstanceSizeWords: nil,
            declaredVtableSize: nil,
            declaredItableSize: nil
        )
        XCTAssertNil(hint.declaredFieldCount)
        XCTAssertNil(hint.declaredInstanceSizeWords)
        XCTAssertNil(hint.declaredVtableSize)
        XCTAssertNil(hint.declaredItableSize)
    }

    func testNominalLayoutHintEquality() {
        let a = NominalLayoutHint(
            declaredFieldCount: 2,
            declaredInstanceSizeWords: 4,
            declaredVtableSize: 3,
            declaredItableSize: 1
        )
        let b = NominalLayoutHint(
            declaredFieldCount: 2,
            declaredInstanceSizeWords: 4,
            declaredVtableSize: 3,
            declaredItableSize: 1
        )
        let c = NominalLayoutHint(
            declaredFieldCount: 5,
            declaredInstanceSizeWords: nil,
            declaredVtableSize: nil,
            declaredItableSize: nil
        )
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }
}

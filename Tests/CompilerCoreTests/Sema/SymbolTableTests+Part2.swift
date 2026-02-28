import XCTest
@testable import CompilerCore


extension SymbolTableTests {
    func testParentSymbolReturnsNilForUnset() {
        let symbols = SymbolTable()
        XCTAssertNil(symbols.parentSymbol(for: SymbolID(rawValue: 0)))
    }

    // MARK: - Type Parameter Upper Bound

    func testSetAndGetTypeParameterUpperBound() {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let types = TypeSystem()
        let id = symbols.define(kind: .typeParameter, name: interner.intern("T"), fqName: [interner.intern("T")], declSite: nil, visibility: .public)
        symbols.setTypeParameterUpperBound(types.anyType, for: id)
        XCTAssertEqual(symbols.typeParameterUpperBound(for: id), types.anyType)
    }

    func testTypeParameterUpperBoundReturnsNilForUnset() {
        let symbols = SymbolTable()
        XCTAssertNil(symbols.typeParameterUpperBound(for: SymbolID(rawValue: 0)))
    }

    // MARK: - Source File ID

    func testSetAndGetSourceFileID() {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let id = symbols.define(kind: .class, name: interner.intern("C"), fqName: [interner.intern("C")], declSite: nil, visibility: .public)
        let fileID = FileID(rawValue: 42)
        symbols.setSourceFileID(fileID, for: id)
        XCTAssertEqual(symbols.sourceFileID(for: id), fileID)
    }

    func testSourceFileIDReturnsNilForUnset() {
        let symbols = SymbolTable()
        XCTAssertNil(symbols.sourceFileID(for: SymbolID(rawValue: 0)))
    }
}

// MARK: - BindingTable Tests

final class BindingTableTests: XCTestCase {

    func testBindExprType() {
        let bindings = BindingTable()
        let types = TypeSystem()
        let expr = ExprID(rawValue: 0)
        let intType = types.make(.primitive(.int, .nonNull))
        bindings.bindExprType(expr, type: intType)
        XCTAssertEqual(bindings.exprTypes[expr], intType)
    }

    func testBindIdentifier() {
        let bindings = BindingTable()
        let expr = ExprID(rawValue: 0)
        let sym = SymbolID(rawValue: 5)
        bindings.bindIdentifier(expr, symbol: sym)
        XCTAssertEqual(bindings.identifierSymbols[expr], sym)
    }

    func testBindCall() {
        let bindings = BindingTable()
        let expr = ExprID(rawValue: 0)
        let binding = CallBinding(
            chosenCallee: SymbolID(rawValue: 1),
            substitutedTypeArguments: [],
            parameterMapping: [0: 0]
        )
        bindings.bindCall(expr, binding: binding)
        XCTAssertNotNil(bindings.callBindings[expr])
        XCTAssertEqual(bindings.callBindings[expr]!.chosenCallee, SymbolID(rawValue: 1))
    }

    func testBindDecl() {
        let bindings = BindingTable()
        let decl = DeclID(rawValue: 0)
        let sym = SymbolID(rawValue: 3)
        bindings.bindDecl(decl, symbol: sym)
        XCTAssertEqual(bindings.declSymbols[decl], sym)
    }

    func testMarkSuperCall() {
        let bindings = BindingTable()
        let expr = ExprID(rawValue: 7)
        bindings.markSuperCall(expr)
        XCTAssertTrue(bindings.superCallExprs.contains(expr))
    }

    func testMarkSuperCallIdempotent() {
        let bindings = BindingTable()
        let expr = ExprID(rawValue: 7)
        bindings.markSuperCall(expr)
        bindings.markSuperCall(expr)
        XCTAssertEqual(bindings.superCallExprs.count, 1)
    }

    func testMultipleBindings() {
        let bindings = BindingTable()
        let types = TypeSystem()
        let intType = types.make(.primitive(.int, .nonNull))
        let stringType = types.make(.primitive(.string, .nonNull))

        bindings.bindExprType(ExprID(rawValue: 0), type: intType)
        bindings.bindExprType(ExprID(rawValue: 1), type: stringType)

        XCTAssertEqual(bindings.exprTypes.count, 2)
        XCTAssertEqual(bindings.exprTypes[ExprID(rawValue: 0)], intType)
        XCTAssertEqual(bindings.exprTypes[ExprID(rawValue: 1)], stringType)
    }
}

// MARK: - Scope Tests

final class ScopeTests: XCTestCase {

    func testBaseScopeLookupReturnsLocalSymbol() {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let scope = FileScope(parent: nil, symbols: symbols)

        let name = interner.intern("x")
        let id = symbols.define(kind: .local, name: name, fqName: [name], declSite: nil, visibility: .internal)
        scope.insert(id)

        let result = scope.lookup(name)
        XCTAssertEqual(result, [id])
    }

    func testBaseScopeLookupDelegatesToParent() {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let parent = FileScope(parent: nil, symbols: symbols)
        let child = BlockScope(parent: parent, symbols: symbols)

        let name = interner.intern("x")
        let id = symbols.define(kind: .local, name: name, fqName: [name], declSite: nil, visibility: .internal)
        parent.insert(id)

        let result = child.lookup(name)
        XCTAssertEqual(result, [id])
    }

    func testBaseScopeLocalShadowsParent() {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let parent = FileScope(parent: nil, symbols: symbols)
        let child = BlockScope(parent: parent, symbols: symbols)

        let name = interner.intern("x")
        let parentID = symbols.define(kind: .local, name: name, fqName: [interner.intern("outer"), name], declSite: nil, visibility: .internal)
        let childID = symbols.define(kind: .local, name: name, fqName: [interner.intern("inner"), name], declSite: nil, visibility: .internal)
        parent.insert(parentID)
        child.insert(childID)

        let result = child.lookup(name)
        XCTAssertEqual(result, [childID])
    }

    func testBaseScopeLookupReturnsEmptyForUnknown() {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let scope = FileScope(parent: nil, symbols: symbols)
        XCTAssertEqual(scope.lookup(interner.intern("unknown")), [])
    }

    func testInsertWithAlias() {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let scope = ImportScope(parent: nil, symbols: symbols)

        let originalName = interner.intern("Original")
        let alias = interner.intern("Alias")
        let id = symbols.define(kind: .class, name: originalName, fqName: [originalName], declSite: nil, visibility: .public)
        scope.insertWithAlias(id, asName: alias)

        XCTAssertEqual(scope.lookup(alias), [id])
        XCTAssertEqual(scope.lookup(originalName), [])
    }

    func testInsertDeduplicates() {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let scope = FileScope(parent: nil, symbols: symbols)

        let name = interner.intern("x")
        let id = symbols.define(kind: .local, name: name, fqName: [name], declSite: nil, visibility: .internal)
        scope.insert(id)
        scope.insert(id)

        XCTAssertEqual(scope.lookup(name), [id])
    }

    func testClassMemberScopeReceiverType() {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let types = TypeSystem()
        let ownerSym = symbols.define(kind: .class, name: interner.intern("C"), fqName: [interner.intern("C")], declSite: nil, visibility: .public)
        let thisType = types.make(.classType(ClassType(classSymbol: ownerSym)))

        let scope = ClassMemberScope(parent: nil, symbols: symbols, ownerSymbol: ownerSym, thisType: thisType)
        XCTAssertEqual(scope.receiverType, thisType)
        XCTAssertEqual(scope.owner, ownerSym)
    }

    func testClassMemberScopeNilReceiverType() {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let ownerSym = symbols.define(kind: .object, name: interner.intern("O"), fqName: [interner.intern("O")], declSite: nil, visibility: .public)
        let scope = ClassMemberScope(parent: nil, symbols: symbols, ownerSymbol: ownerSym, thisType: nil)
        XCTAssertNil(scope.receiverType)
    }

    func testInsertWithInvalidIDIsNoOp() {
        let symbols = SymbolTable()
        let scope = FileScope(parent: nil, symbols: symbols)
        scope.insert(SymbolID.invalid)
        // Should not crash
    }
}

// MARK: - SemaModule Tests

final class SemaModuleTests: XCTestCase {

    func testSemaModuleInit() {
        let (sema, symbols, types, _) = makeSemaModule()
        XCTAssertTrue(sema.symbols === symbols)
        XCTAssertTrue(sema.types === types)
        XCTAssertTrue(sema.bindings.exprTypes.isEmpty)
        XCTAssertTrue(sema.diagnostics.diagnostics.isEmpty)
    }

    func testSemaModuleImportedInlineFunctionsDefault() {
        let (sema, _, _, _) = makeSemaModule()
        XCTAssertTrue(sema.importedInlineFunctions.isEmpty)
    }
}

// MARK: - FunctionSignature Tests

final class FunctionSignatureTests: XCTestCase {

    func testFunctionSignatureDefaults() {
        let types = TypeSystem()
        let intType = types.make(.primitive(.int, .nonNull))
        let sig = FunctionSignature(parameterTypes: [intType], returnType: intType)
        XCTAssertNil(sig.receiverType)
        XCTAssertFalse(sig.isSuspend)
        XCTAssertTrue(sig.valueParameterSymbols.isEmpty)
        XCTAssertTrue(sig.valueParameterHasDefaultValues.isEmpty)
        XCTAssertTrue(sig.valueParameterIsVararg.isEmpty)
        XCTAssertTrue(sig.typeParameterSymbols.isEmpty)
        XCTAssertTrue(sig.reifiedTypeParameterIndices.isEmpty)
        XCTAssertTrue(sig.typeParameterUpperBounds.isEmpty)
    }

    func testFunctionSignatureFullInit() {
        let types = TypeSystem()
        let intType = types.make(.primitive(.int, .nonNull))
        let sig = FunctionSignature(
            receiverType: intType,
            parameterTypes: [intType],
            returnType: intType,
            isSuspend: true,
            valueParameterSymbols: [SymbolID(rawValue: 0)],
            valueParameterHasDefaultValues: [true],
            valueParameterIsVararg: [false],
            typeParameterSymbols: [SymbolID(rawValue: 1)],
            reifiedTypeParameterIndices: [0],
            typeParameterUpperBounds: [intType]
        )
        XCTAssertEqual(sig.receiverType, intType)
        XCTAssertTrue(sig.isSuspend)
        XCTAssertEqual(sig.valueParameterSymbols.count, 1)
        XCTAssertEqual(sig.valueParameterHasDefaultValues, [true])
        XCTAssertEqual(sig.valueParameterIsVararg, [false])
        XCTAssertEqual(sig.typeParameterSymbols.count, 1)
        XCTAssertEqual(sig.reifiedTypeParameterIndices, [0])
        XCTAssertEqual(sig.typeParameterUpperBounds, [intType])
    }
}

// MARK: - CallBinding Tests

final class CallBindingTests: XCTestCase {

    func testCallBindingInit() {
        let types = TypeSystem()
        let intType = types.make(.primitive(.int, .nonNull))
        let binding = CallBinding(
            chosenCallee: SymbolID(rawValue: 0),
            substitutedTypeArguments: [intType],
            parameterMapping: [0: 0, 1: 1]
        )
        XCTAssertEqual(binding.chosenCallee, SymbolID(rawValue: 0))
        XCTAssertEqual(binding.substitutedTypeArguments, [intType])
        XCTAssertEqual(binding.parameterMapping, [0: 0, 1: 1])
    }
}

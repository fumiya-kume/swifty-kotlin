import XCTest
@testable import CompilerCore

final class SymbolTableTests: XCTestCase {

    // MARK: - Define & Symbol

    func testDefineReturnsUniqueIDs() {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let id1 = symbols.define(
            kind: .function,
            name: interner.intern("a"),
            fqName: [interner.intern("a")],
            declSite: nil,
            visibility: .public
        )
        let id2 = symbols.define(
            kind: .class,
            name: interner.intern("B"),
            fqName: [interner.intern("B")],
            declSite: nil,
            visibility: .internal
        )
        XCTAssertNotEqual(id1, id2)
        XCTAssertEqual(symbols.count, 2)
    }

    func testSymbolReturnsNilForInvalidID() {
        let symbols = SymbolTable()
        XCTAssertNil(symbols.symbol(SymbolID.invalid))
        XCTAssertNil(symbols.symbol(SymbolID(rawValue: 999)))
    }

    func testSymbolPreservesFields() {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let range = makeRange(start: 0, end: 5)
        let id = symbols.define(
            kind: .property,
            name: interner.intern("x"),
            fqName: [interner.intern("pkg"), interner.intern("x")],
            declSite: range,
            visibility: .private,
            flags: .mutable
        )
        let sym = symbols.symbol(id)!
        XCTAssertEqual(sym.kind, .property)
        XCTAssertEqual(sym.name, interner.intern("x"))
        XCTAssertEqual(sym.fqName, [interner.intern("pkg"), interner.intern("x")])
        XCTAssertEqual(sym.declSite, range)
        XCTAssertEqual(sym.visibility, .private)
        XCTAssertTrue(sym.flags.contains(.mutable))
    }

    // MARK: - Count & allSymbols

    func testCountReflectsSymbolCount() {
        let interner = StringInterner()
        let symbols = SymbolTable()
        XCTAssertEqual(symbols.count, 0)
        _ = symbols.define(kind: .local, name: interner.intern("x"), fqName: [interner.intern("x")], declSite: nil, visibility: .internal)
        XCTAssertEqual(symbols.count, 1)
    }

    func testAllSymbolsReturnsAll() {
        let interner = StringInterner()
        let symbols = SymbolTable()
        _ = symbols.define(kind: .local, name: interner.intern("a"), fqName: [interner.intern("a")], declSite: nil, visibility: .internal)
        _ = symbols.define(kind: .function, name: interner.intern("b"), fqName: [interner.intern("b")], declSite: nil, visibility: .public)
        let all = symbols.allSymbols()
        XCTAssertEqual(all.count, 2)
    }

    // MARK: - Lookup by FQ Name

    func testLookupByFQName() {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let fqName = [interner.intern("com"), interner.intern("example"), interner.intern("Foo")]
        let id = symbols.define(kind: .class, name: interner.intern("Foo"), fqName: fqName, declSite: nil, visibility: .public)
        XCTAssertEqual(symbols.lookup(fqName: fqName), id)
    }

    func testLookupByFQNameReturnsNilForUnknown() {
        let interner = StringInterner()
        let symbols = SymbolTable()
        XCTAssertNil(symbols.lookup(fqName: [interner.intern("unknown")]))
    }

    func testLookupAllByFQName() {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let fqName = [interner.intern("fn")]
        let id1 = symbols.define(kind: .function, name: interner.intern("fn"), fqName: fqName, declSite: nil, visibility: .public)
        let id2 = symbols.define(kind: .function, name: interner.intern("fn"), fqName: fqName, declSite: nil, visibility: .public)
        let all = symbols.lookupAll(fqName: fqName)
        XCTAssertEqual(all.count, 2)
        XCTAssertTrue(all.contains(id1))
        XCTAssertTrue(all.contains(id2))
    }

    func testLookupAllReturnsEmptyForUnknown() {
        let interner = StringInterner()
        let symbols = SymbolTable()
        XCTAssertEqual(symbols.lookupAll(fqName: [interner.intern("nope")]), [])
    }

    // MARK: - Overloading

    func testFunctionsCanCoexistAsOverloads() {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let fqName = [interner.intern("fn")]
        let id1 = symbols.define(kind: .function, name: interner.intern("fn"), fqName: fqName, declSite: nil, visibility: .public)
        let id2 = symbols.define(kind: .function, name: interner.intern("fn"), fqName: fqName, declSite: nil, visibility: .public)
        XCTAssertNotEqual(id1, id2)
    }

    func testConstructorsCanCoexistAsOverloads() {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let fqName = [interner.intern("init")]
        let id1 = symbols.define(kind: .constructor, name: interner.intern("init"), fqName: fqName, declSite: nil, visibility: .public)
        let id2 = symbols.define(kind: .constructor, name: interner.intern("init"), fqName: fqName, declSite: nil, visibility: .public)
        XCTAssertNotEqual(id1, id2)
    }

    func testNonOverloadableKindsReturnExistingID() {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let fqName = [interner.intern("MyClass")]
        let id1 = symbols.define(kind: .class, name: interner.intern("MyClass"), fqName: fqName, declSite: nil, visibility: .public)
        let id2 = symbols.define(kind: .class, name: interner.intern("MyClass"), fqName: fqName, declSite: nil, visibility: .public)
        XCTAssertEqual(id1, id2)
        XCTAssertEqual(symbols.count, 1)
    }

    func testMixedOverloadAndNonOverloadReturnsExisting() {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let fqName = [interner.intern("x")]
        let id1 = symbols.define(kind: .class, name: interner.intern("x"), fqName: fqName, declSite: nil, visibility: .public)
        let id2 = symbols.define(kind: .function, name: interner.intern("x"), fqName: fqName, declSite: nil, visibility: .public)
        XCTAssertEqual(id1, id2)
    }

    // MARK: - Function Signatures

    func testSetAndGetFunctionSignature() {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let types = TypeSystem()
        let id = symbols.define(kind: .function, name: interner.intern("f"), fqName: [interner.intern("f")], declSite: nil, visibility: .public)
        let intType = types.make(.primitive(.int, .nonNull))
        let sig = FunctionSignature(parameterTypes: [intType], returnType: intType)
        symbols.setFunctionSignature(sig, for: id)
        let retrieved = symbols.functionSignature(for: id)!
        XCTAssertEqual(retrieved.parameterTypes, [intType])
        XCTAssertEqual(retrieved.returnType, intType)
    }

    func testFunctionSignatureReturnsNilForUnset() {
        let symbols = SymbolTable()
        XCTAssertNil(symbols.functionSignature(for: SymbolID(rawValue: 0)))
    }

    // MARK: - Property Types

    func testSetAndGetPropertyType() {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let types = TypeSystem()
        let id = symbols.define(kind: .property, name: interner.intern("p"), fqName: [interner.intern("p")], declSite: nil, visibility: .public)
        let intType = types.make(.primitive(.int, .nonNull))
        symbols.setPropertyType(intType, for: id)
        XCTAssertEqual(symbols.propertyType(for: id), intType)
    }

    func testPropertyTypeReturnsNilForUnset() {
        let symbols = SymbolTable()
        XCTAssertNil(symbols.propertyType(for: SymbolID(rawValue: 0)))
    }

    // MARK: - Direct Supertypes / Subtypes

    func testSetAndGetDirectSupertypes() {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let parent = symbols.define(kind: .class, name: interner.intern("Parent"), fqName: [interner.intern("Parent")], declSite: nil, visibility: .public)
        let child = symbols.define(kind: .class, name: interner.intern("Child"), fqName: [interner.intern("Child")], declSite: nil, visibility: .public)
        symbols.setDirectSupertypes([parent], for: child)
        XCTAssertEqual(symbols.directSupertypes(for: child), [parent])
    }

    func testDirectSupertypesReturnsEmptyForUnset() {
        let symbols = SymbolTable()
        XCTAssertEqual(symbols.directSupertypes(for: SymbolID(rawValue: 99)), [])
    }

    func testDirectSubtypes() {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let parent = symbols.define(kind: .class, name: interner.intern("P"), fqName: [interner.intern("P")], declSite: nil, visibility: .public)
        let child1 = symbols.define(kind: .class, name: interner.intern("C1"), fqName: [interner.intern("C1")], declSite: nil, visibility: .public)
        let child2 = symbols.define(kind: .class, name: interner.intern("C2"), fqName: [interner.intern("C2")], declSite: nil, visibility: .public)
        symbols.setDirectSupertypes([parent], for: child1)
        symbols.setDirectSupertypes([parent], for: child2)
        let subtypes = symbols.directSubtypes(of: parent)
        XCTAssertEqual(subtypes.count, 2)
        XCTAssertTrue(subtypes.contains(child1))
        XCTAssertTrue(subtypes.contains(child2))
    }

    func testDirectSubtypesReturnsEmptyWhenNone() {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let id = symbols.define(kind: .class, name: interner.intern("A"), fqName: [interner.intern("A")], declSite: nil, visibility: .public)
        XCTAssertEqual(symbols.directSubtypes(of: id), [])
    }

    // MARK: - NominalLayout / Hint

    func testSetAndGetNominalLayout() {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let id = symbols.define(kind: .class, name: interner.intern("C"), fqName: [interner.intern("C")], declSite: nil, visibility: .public)
        let layout = NominalLayout(
            objectHeaderWords: 2,
            instanceFieldCount: 1,
            instanceSizeWords: 3,
            vtableSlots: [:],
            itableSlots: [:],
            superClass: nil
        )
        symbols.setNominalLayout(layout, for: id)
        XCTAssertEqual(symbols.nominalLayout(for: id), layout)
    }

    func testNominalLayoutReturnsNilForUnset() {
        let symbols = SymbolTable()
        XCTAssertNil(symbols.nominalLayout(for: SymbolID(rawValue: 0)))
    }

    func testSetAndGetNominalLayoutHint() {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let id = symbols.define(kind: .class, name: interner.intern("C"), fqName: [interner.intern("C")], declSite: nil, visibility: .public)
        let hint = NominalLayoutHint(
            declaredFieldCount: 3,
            declaredInstanceSizeWords: nil,
            declaredVtableSize: 5,
            declaredItableSize: nil
        )
        symbols.setNominalLayoutHint(hint, for: id)
        XCTAssertEqual(symbols.nominalLayoutHint(for: id), hint)
    }

    // MARK: - External Link Name

    func testSetAndGetExternalLinkName() {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let id = symbols.define(kind: .function, name: interner.intern("f"), fqName: [interner.intern("f")], declSite: nil, visibility: .public)
        symbols.setExternalLinkName("_custom_link_name", for: id)
        XCTAssertEqual(symbols.externalLinkName(for: id), "_custom_link_name")
    }

    func testExternalLinkNameReturnsNilForUnset() {
        let symbols = SymbolTable()
        XCTAssertNil(symbols.externalLinkName(for: SymbolID(rawValue: 0)))
    }

    // MARK: - TypeAlias Underlying Type

    func testSetAndGetTypeAliasUnderlyingType() {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let types = TypeSystem()
        let id = symbols.define(kind: .typeAlias, name: interner.intern("MyInt"), fqName: [interner.intern("MyInt")], declSite: nil, visibility: .public)
        let intType = types.make(.primitive(.int, .nonNull))
        symbols.setTypeAliasUnderlyingType(intType, for: id)
        XCTAssertEqual(symbols.typeAliasUnderlyingType(for: id), intType)
    }

    func testTypeAliasUnderlyingTypeReturnsNilForUnset() {
        let symbols = SymbolTable()
        XCTAssertNil(symbols.typeAliasUnderlyingType(for: SymbolID(rawValue: 0)))
    }

    // MARK: - Parent Symbol

    func testSetAndGetParentSymbol() {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let parent = symbols.define(kind: .class, name: interner.intern("P"), fqName: [interner.intern("P")], declSite: nil, visibility: .public)
        let child = symbols.define(kind: .function, name: interner.intern("f"), fqName: [interner.intern("P"), interner.intern("f")], declSite: nil, visibility: .public)
        symbols.setParentSymbol(parent, for: child)
        XCTAssertEqual(symbols.parentSymbol(for: child), parent)
    }

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

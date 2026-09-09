@testable import CompilerCore
import Testing

@Suite
struct SymbolTableTests {
    // MARK: - Define & Symbol

    @Test
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
        #expect(id1 != id2)
        #expect(symbols.count == 2)
    }

    @Test
    func testSymbolReturnsNilForInvalidID() {
        let symbols = SymbolTable()
        #expect(symbols.symbol(SymbolID.invalid) == nil)
        #expect(symbols.symbol(SymbolID(rawValue: 999)) == nil)
    }

    @Test
    func testSymbolPreservesFields() throws {
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
        let sym = try #require(symbols.symbol(id))
        #expect(sym.kind == .property)
        #expect(sym.name == interner.intern("x"))
        #expect(sym.fqName == [interner.intern("pkg"), interner.intern("x")])
        #expect(sym.declSite == range)
        #expect(sym.visibility == .private)
        #expect(sym.flags.contains(.mutable))
    }

    // MARK: - Count & allSymbols

    @Test
    func testCountReflectsSymbolCount() {
        let interner = StringInterner()
        let symbols = SymbolTable()
        #expect(symbols.count == 0)
        _ = symbols.define(kind: .local, name: interner.intern("x"), fqName: [interner.intern("x")], declSite: nil, visibility: .internal)
        #expect(symbols.count == 1)
    }

    @Test
    func testAllSymbolsReturnsAll() {
        let interner = StringInterner()
        let symbols = SymbolTable()
        _ = symbols.define(kind: .local, name: interner.intern("a"), fqName: [interner.intern("a")], declSite: nil, visibility: .internal)
        _ = symbols.define(kind: .function, name: interner.intern("b"), fqName: [interner.intern("b")], declSite: nil, visibility: .public)
        let all = symbols.allSymbols()
        #expect(all.count == 2)
    }

    // MARK: - Lookup by FQ Name

    @Test
    func testLookupByFQName() {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let fqName = [interner.intern("com"), interner.intern("example"), interner.intern("Foo")]
        let id = symbols.define(kind: .class, name: interner.intern("Foo"), fqName: fqName, declSite: nil, visibility: .public)
        #expect(symbols.lookup(fqName: fqName) == id)
    }

    @Test
    func testLookupByFQNameReturnsNilForUnknown() {
        let interner = StringInterner()
        let symbols = SymbolTable()
        #expect(symbols.lookup(fqName: [interner.intern("unknown")]) == nil)
    }

    @Test
    func testLookupAllByFQName() {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let fqName = [interner.intern("fn")]
        let id1 = symbols.define(kind: .function, name: interner.intern("fn"), fqName: fqName, declSite: nil, visibility: .public)
        let id2 = symbols.define(kind: .function, name: interner.intern("fn"), fqName: fqName, declSite: nil, visibility: .public)
        let all = symbols.lookupAll(fqName: fqName)
        #expect(all.count == 2)
        #expect(all.contains(id1))
        #expect(all.contains(id2))
    }

    @Test
    func testLookupAllReturnsEmptyForUnknown() {
        let interner = StringInterner()
        let symbols = SymbolTable()
        #expect(symbols.lookupAll(fqName: [interner.intern("nope")]) == [])
    }

    // MARK: - Overloading

    @Test
    func testFunctionsCanCoexistAsOverloads() {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let fqName = [interner.intern("fn")]
        let id1 = symbols.define(kind: .function, name: interner.intern("fn"), fqName: fqName, declSite: nil, visibility: .public)
        let id2 = symbols.define(kind: .function, name: interner.intern("fn"), fqName: fqName, declSite: nil, visibility: .public)
        #expect(id1 != id2)
        #expect(symbols.lookupAll(fqName: fqName) == [id1, id2])
        #expect(symbols.lookup(fqName: fqName) == id1)
    }

    @Test
    func testConstructorsCanCoexistAsOverloads() {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let fqName = [interner.intern("init")]
        let id1 = symbols.define(kind: .constructor, name: interner.intern("init"), fqName: fqName, declSite: nil, visibility: .public)
        let id2 = symbols.define(kind: .constructor, name: interner.intern("init"), fqName: fqName, declSite: nil, visibility: .public)
        #expect(id1 != id2)
    }

    @Test
    func testNonOverloadableKindsReturnExistingID() {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let fqName = [interner.intern("MyClass")]
        let id1 = symbols.define(kind: .class, name: interner.intern("MyClass"), fqName: fqName, declSite: nil, visibility: .public)
        let id2 = symbols.define(kind: .class, name: interner.intern("MyClass"), fqName: fqName, declSite: nil, visibility: .public)
        #expect(id1 == id2)
        #expect(symbols.count == 1)
    }

    @Test
    func testFunctionCanCoexistWithNominalTypeUsingSameName() {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let fqName = [interner.intern("x")]
        let id1 = symbols.define(kind: .class, name: interner.intern("x"), fqName: fqName, declSite: nil, visibility: .public)
        let id2 = symbols.define(kind: .function, name: interner.intern("x"), fqName: fqName, declSite: nil, visibility: .public)
        #expect(id1 != id2)
        #expect(symbols.count == 2)
    }

    @Test
    func testPropertyCanCoexistWithFactoryValueParameterUsingSameFQName() throws {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let fqName = [interner.intern("AtomicIntArray"), interner.intern("size")]
        let parameterID = symbols.define(
            kind: .valueParameter,
            name: interner.intern("size"),
            fqName: fqName,
            declSite: nil,
            visibility: .private
        )
        let propertyID = symbols.define(
            kind: .property,
            name: interner.intern("size"),
            fqName: fqName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )

        #expect(parameterID != propertyID)
        #expect(symbols.count == 2)
        #expect(symbols.lookupAll(fqName: fqName) == [parameterID, propertyID])
        #expect(try #require(symbols.symbol(parameterID)).kind == .valueParameter)
        #expect(try #require(symbols.symbol(propertyID)).kind == .property)
    }

    @Test
    func testFactoryValueParameterCanCoexistWithPropertyUsingSameFQNameInReverseOrder() throws {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let fqName = [interner.intern("AtomicIntArray"), interner.intern("size")]
        let propertyID = symbols.define(
            kind: .property,
            name: interner.intern("size"),
            fqName: fqName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        let parameterID = symbols.define(
            kind: .valueParameter,
            name: interner.intern("size"),
            fqName: fqName,
            declSite: nil,
            visibility: .private
        )

        #expect(parameterID != propertyID)
        #expect(symbols.count == 2)
        #expect(symbols.lookupAll(fqName: fqName) == [propertyID, parameterID])
        #expect(try #require(symbols.symbol(propertyID)).kind == .property)
        #expect(try #require(symbols.symbol(parameterID)).kind == .valueParameter)
    }

    @Test
    func testFunctionCanCoexistWithPropertyUsingSameNameInReverseDeclarationOrder() {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let fqName = [interner.intern("port")]
        let propertyID = symbols.define(
            kind: .property,
            name: interner.intern("port"),
            fqName: fqName,
            declSite: nil,
            visibility: .public
        )
        let functionID = symbols.define(
            kind: .function,
            name: interner.intern("port"),
            fqName: fqName,
            declSite: nil,
            visibility: .public
        )

        #expect(propertyID != functionID)
        #expect(symbols.count == 2)
        #expect(symbols.lookupAll(fqName: fqName) == [propertyID, functionID])
    }

    @Test
    func testExpectAnnotationClassCanCoexistWithActualTypeAlias() throws {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let fqName = [
            interner.intern("kotlin"),
            interner.intern("concurrent"),
            interner.intern("Volatile")
        ]

        let expectID = symbols.define(
            kind: .annotationClass,
            name: interner.intern("Volatile"),
            fqName: fqName,
            declSite: nil,
            visibility: .public,
            flags: [.expectDeclaration]
        )
        let actualID = symbols.define(
            kind: .typeAlias,
            name: interner.intern("Volatile"),
            fqName: fqName,
            declSite: nil,
            visibility: .public,
            flags: [.actualDeclaration]
        )

        #expect(expectID != actualID)
        #expect(symbols.count == 2)
        #expect(symbols.lookupAll(fqName: fqName).count == 2)
        #expect(try #require(symbols.symbol(expectID)).kind == .annotationClass)
        #expect(try #require(symbols.symbol(actualID)).kind == .typeAlias)
    }

    @Test
    func testActualTypeAliasCanCoexistWithExpectAnnotationClassInReverseOrder() throws {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let fqName = [
            interner.intern("kotlin"),
            interner.intern("concurrent"),
            interner.intern("Volatile")
        ]

        let actualID = symbols.define(
            kind: .typeAlias,
            name: interner.intern("Volatile"),
            fqName: fqName,
            declSite: nil,
            visibility: .public,
            flags: [.actualDeclaration]
        )
        let expectID = symbols.define(
            kind: .annotationClass,
            name: interner.intern("Volatile"),
            fqName: fqName,
            declSite: nil,
            visibility: .public,
            flags: [.expectDeclaration]
        )

        #expect(expectID != actualID)
        #expect(symbols.count == 2)
        #expect(symbols.lookupAll(fqName: fqName).count == 2)
        #expect(try #require(symbols.symbol(expectID)).kind == .annotationClass)
        #expect(try #require(symbols.symbol(actualID)).kind == .typeAlias)
    }

    // MARK: - Function Signatures

    @Test
    func testSetAndGetFunctionSignature() throws {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let types = TypeSystem()
        let id = symbols.define(kind: .function, name: interner.intern("f"), fqName: [interner.intern("f")], declSite: nil, visibility: .public)
        let intType = types.make(.primitive(.int, .nonNull))
        let sig = FunctionSignature(parameterTypes: [intType], returnType: intType)
        symbols.setFunctionSignature(sig, for: id)
        let retrieved = try #require(symbols.functionSignature(for: id))
        #expect(retrieved.parameterTypes == [intType])
        #expect(retrieved.returnType == intType)
    }

    @Test
    func testFunctionSignatureReturnsNilForUnset() {
        let symbols = SymbolTable()
        #expect(symbols.functionSignature(for: SymbolID(rawValue: 0)) == nil)
    }

    // MARK: - Property Types

    @Test
    func testSetAndGetPropertyType() {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let types = TypeSystem()
        let id = symbols.define(kind: .property, name: interner.intern("p"), fqName: [interner.intern("p")], declSite: nil, visibility: .public)
        let intType = types.make(.primitive(.int, .nonNull))
        symbols.setPropertyType(intType, for: id)
        #expect(symbols.propertyType(for: id) == intType)
    }

    @Test
    func testPropertyTypeReturnsNilForUnset() {
        let symbols = SymbolTable()
        #expect(symbols.propertyType(for: SymbolID(rawValue: 0)) == nil)
    }

    // MARK: - Direct Supertypes / Subtypes

    @Test
    func testSetAndGetDirectSupertypes() {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let parent = symbols.define(kind: .class, name: interner.intern("Parent"), fqName: [interner.intern("Parent")], declSite: nil, visibility: .public)
        let child = symbols.define(kind: .class, name: interner.intern("Child"), fqName: [interner.intern("Child")], declSite: nil, visibility: .public)
        symbols.setDirectSupertypes([parent], for: child)
        #expect(symbols.directSupertypes(for: child) == [parent])
    }

    @Test
    func testDirectSupertypesReturnsEmptyForUnset() {
        let symbols = SymbolTable()
        #expect(symbols.directSupertypes(for: SymbolID(rawValue: 99)) == [])
    }

    @Test
    func testDirectSubtypes() {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let parent = symbols.define(kind: .class, name: interner.intern("P"), fqName: [interner.intern("P")], declSite: nil, visibility: .public)
        let child1 = symbols.define(kind: .class, name: interner.intern("C1"), fqName: [interner.intern("C1")], declSite: nil, visibility: .public)
        let child2 = symbols.define(kind: .class, name: interner.intern("C2"), fqName: [interner.intern("C2")], declSite: nil, visibility: .public)
        symbols.setDirectSupertypes([parent], for: child1)
        symbols.setDirectSupertypes([parent], for: child2)
        let subtypes = symbols.directSubtypes(of: parent)
        #expect(subtypes.count == 2)
        #expect(subtypes.contains(child1))
        #expect(subtypes.contains(child2))
    }

    @Test
    func testDirectSubtypesReturnsEmptyWhenNone() {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let id = symbols.define(kind: .class, name: interner.intern("A"), fqName: [interner.intern("A")], declSite: nil, visibility: .public)
        #expect(symbols.directSubtypes(of: id) == [])
    }

    // MARK: - NominalLayout / Hint

    @Test
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
        #expect(symbols.nominalLayout(for: id) == layout)
    }

    @Test
    func testNominalLayoutReturnsNilForUnset() {
        let symbols = SymbolTable()
        #expect(symbols.nominalLayout(for: SymbolID(rawValue: 0)) == nil)
    }

    @Test
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
        #expect(symbols.nominalLayoutHint(for: id) == hint)
    }

    // MARK: - External Link Name

    @Test
    func testSetAndGetExternalLinkName() {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let id = symbols.define(kind: .function, name: interner.intern("f"), fqName: [interner.intern("f")], declSite: nil, visibility: .public)
        symbols.setExternalLinkName("_custom_link_name", for: id)
        #expect(symbols.externalLinkName(for: id) == "_custom_link_name")
    }

    @Test
    func testExternalLinkNameReturnsNilForUnset() {
        let symbols = SymbolTable()
        #expect(symbols.externalLinkName(for: SymbolID(rawValue: 0)) == nil)
    }

    // MARK: - TypeAlias Underlying Type

    @Test
    func testSetAndGetTypeAliasUnderlyingType() {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let types = TypeSystem()
        let id = symbols.define(kind: .typeAlias, name: interner.intern("MyInt"), fqName: [interner.intern("MyInt")], declSite: nil, visibility: .public)
        let intType = types.make(.primitive(.int, .nonNull))
        symbols.setTypeAliasUnderlyingType(intType, for: id)
        #expect(symbols.typeAliasUnderlyingType(for: id) == intType)
    }

    @Test
    func testTypeAliasUnderlyingTypeReturnsNilForUnset() {
        let symbols = SymbolTable()
        #expect(symbols.typeAliasUnderlyingType(for: SymbolID(rawValue: 0)) == nil)
    }

    // MARK: - Parent Symbol

    @Test
    func testSetAndGetParentSymbol() {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let parent = symbols.define(kind: .class, name: interner.intern("P"), fqName: [interner.intern("P")], declSite: nil, visibility: .public)
        let child = symbols.define(kind: .function, name: interner.intern("f"), fqName: [interner.intern("P"), interner.intern("f")], declSite: nil, visibility: .public)
        symbols.setParentSymbol(parent, for: child)
        #expect(symbols.parentSymbol(for: child) == parent)
    }
}

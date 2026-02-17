import XCTest
@testable import CompilerCore

final class ASTModelsTests: XCTestCase {
    func testIDInitializersSupportDefaultAndExplicitValues() {
        XCTAssertEqual(ASTNodeID(), .invalid)
        XCTAssertEqual(ExprID(), .invalid)
        XCTAssertEqual(TypeRefID(), .invalid)

        XCTAssertEqual(ASTNodeID(rawValue: 10).rawValue, 10)
        XCTAssertEqual(ExprID(rawValue: 11).rawValue, 11)
        XCTAssertEqual(TypeRefID(rawValue: 12).rawValue, 12)
    }

    func testFunDeclInitializerAppliesDefaults() {
        let interner = StringInterner()
        let name = interner.intern("run")
        let decl = FunDecl(
            range: makeRange(start: 1, end: 5),
            name: name,
            modifiers: [.public]
        )

        XCTAssertEqual(decl.name, name)
        XCTAssertTrue(decl.typeParams.isEmpty)
        XCTAssertNil(decl.receiverType)
        XCTAssertTrue(decl.valueParams.isEmpty)
        XCTAssertNil(decl.returnType)
        XCTAssertEqual(decl.body, .unit)
        XCTAssertFalse(decl.isSuspend)
        XCTAssertFalse(decl.isInline)
    }

    func testModifiersOptionSetComposition() {
        let modifiers: Modifiers = [.public, .inline, .operator, .tailrec]

        XCTAssertTrue(modifiers.contains(.public))
        XCTAssertTrue(modifiers.contains(.inline))
        XCTAssertTrue(modifiers.contains(.operator))
        XCTAssertTrue(modifiers.contains(.tailrec))
        XCTAssertFalse(modifiers.contains(.private))
    }

    func testASTArenaAppendLookupAndDeclarationSnapshot() {
        let interner = StringInterner()
        let name = interner.intern("C")
        let classDecl = ClassDecl(
            range: makeRange(start: 0, end: 2),
            name: name,
            modifiers: [.public],
            typeParams: [],
            primaryConstructorParams: []
        )

        let arena = ASTArena()
        let classID = arena.appendDecl(.classDecl(classDecl))
        let propertyDecl = PropertyDecl(
            range: makeRange(start: 3, end: 5),
            name: interner.intern("p"),
            modifiers: [.private],
            type: TypeRefID(rawValue: 1)
        )
        let propertyID = arena.appendDecl(.propertyDecl(propertyDecl))

        XCTAssertEqual(classID.rawValue, 0)
        XCTAssertEqual(propertyID.rawValue, 1)
        XCTAssertNotNil(arena.decl(classID))
        XCTAssertNotNil(arena.decl(propertyID))
        XCTAssertNil(arena.decl(DeclID(rawValue: -1)))
        XCTAssertNil(arena.decl(DeclID(rawValue: 999)))
        XCTAssertEqual(arena.declarations().count, 2)

        let typeRefID = arena.appendTypeRef(.named(path: [interner.intern("Int")], args: [], nullable: false))
        XCTAssertEqual(typeRefID.rawValue, 0)
        XCTAssertNotNil(arena.typeRef(typeRefID))
        XCTAssertNil(arena.typeRef(TypeRefID(rawValue: 999)))
    }

    func testModelStructsAndModuleInitializers() {
        let interner = StringInterner()
        let range = makeRange(start: 5, end: 9)
        let typeRef = TypeRefID(rawValue: 4)
        let name = interner.intern("Name")

        let objectDecl = ObjectDecl(range: range, name: name, modifiers: [.public])
        XCTAssertEqual(objectDecl.name, name)

        let typeAliasDecl = TypeAliasDecl(range: range, name: interner.intern("Alias"), modifiers: [.internal])
        XCTAssertEqual(typeAliasDecl.modifiers, [.internal])

        let enumEntryDecl = EnumEntryDecl(range: range, name: interner.intern("Entry"))
        XCTAssertEqual(enumEntryDecl.range, range)

        let importDecl = ImportDecl(range: range, path: [interner.intern("kotlin"), interner.intern("collections")], alias: nil)
        XCTAssertEqual(importDecl.path.count, 2)
        XCTAssertNil(importDecl.alias)

        let aliasedImport = ImportDecl(range: range, path: [interner.intern("kotlin"), interner.intern("collections"), interner.intern("List")], alias: interner.intern("KList"))
        XCTAssertEqual(aliasedImport.alias, interner.intern("KList"))
        XCTAssertEqual(aliasedImport.path.count, 3)

        let typeParam = TypeParamDecl(name: interner.intern("T"))
        XCTAssertEqual(typeParam.name, interner.intern("T"))

        let valueParam = ValueParamDecl(name: interner.intern("value"), type: typeRef)
        XCTAssertEqual(valueParam.type, typeRef)

        let file = ASTFile(
            fileID: FileID(rawValue: 1),
            packageFQName: [interner.intern("pkg")],
            imports: [importDecl],
            topLevelDecls: [DeclID(rawValue: 0)]
        )
        XCTAssertEqual(file.fileID, FileID(rawValue: 1))

        let fullArena = ASTArena()
        let fullModule = ASTModule(files: [file], arena: fullArena, declarationCount: 7, tokenCount: 13)
        XCTAssertEqual(fullModule.files.count, 1)
        XCTAssertEqual(fullModule.declarationCount, 7)
        XCTAssertEqual(fullModule.tokenCount, 13)

        let compactModule = ASTModule(declarationCount: 2, tokenCount: 3)
        XCTAssertTrue(compactModule.files.isEmpty)
        XCTAssertEqual(compactModule.declarationCount, 2)
        XCTAssertEqual(compactModule.tokenCount, 3)
    }

    func testConstructorDeclAndDelegationCallInitializers() {
        let interner = StringInterner()
        let range = makeRange(start: 10, end: 50)
        let typeRef = TypeRefID(rawValue: 0)

        let delegationThis = ConstructorDelegationCall(
            kind: .this,
            args: [CallArgument(label: nil, expr: ExprID(rawValue: 0))],
            range: range
        )
        XCTAssertEqual(delegationThis.kind, .this)
        XCTAssertEqual(delegationThis.args.count, 1)
        XCTAssertEqual(delegationThis.range, range)

        let delegationSuper = ConstructorDelegationCall(
            kind: .super_,
            args: [],
            range: range
        )
        XCTAssertEqual(delegationSuper.kind, .super_)
        XCTAssertTrue(delegationSuper.args.isEmpty)
        XCTAssertNotEqual(delegationThis, delegationSuper)

        let ctorDefault = ConstructorDecl(range: range)
        XCTAssertEqual(ctorDefault.range, range)
        XCTAssertEqual(ctorDefault.modifiers, [])
        XCTAssertTrue(ctorDefault.valueParams.isEmpty)
        XCTAssertNil(ctorDefault.delegationCall)
        XCTAssertEqual(ctorDefault.body, .unit)

        let param = ValueParamDecl(name: interner.intern("x"), type: typeRef)
        let ctorFull = ConstructorDecl(
            range: range,
            modifiers: [.public],
            valueParams: [param],
            delegationCall: delegationThis,
            body: .block([ExprID(rawValue: 1)], range)
        )
        XCTAssertEqual(ctorFull.modifiers, [.public])
        XCTAssertEqual(ctorFull.valueParams.count, 1)
        XCTAssertNotNil(ctorFull.delegationCall)
        if case .block(let exprs, _) = ctorFull.body {
            XCTAssertEqual(exprs.count, 1)
        } else {
            XCTFail("Expected .block body")
        }

        let classDeclWithCtor = ClassDecl(
            range: range,
            name: interner.intern("Foo"),
            modifiers: [],
            typeParams: [],
            primaryConstructorParams: [],
            secondaryConstructors: [ctorFull]
        )
        XCTAssertEqual(classDeclWithCtor.secondaryConstructors.count, 1)
        XCTAssertTrue(classDeclWithCtor.initBlocks.isEmpty)
    }
}

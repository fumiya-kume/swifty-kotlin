import XCTest
@testable import CompilerCore

final class ASTModelsTests: XCTestCase {
    func testIDInitializersSupportDefaultAndExplicitValues() {
        XCTAssertEqual(ASTNodeID().rawValue, invalidID)
        XCTAssertEqual(ExprID().rawValue, invalidID)
        XCTAssertEqual(TypeRefID().rawValue, invalidID)

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
            modifiers: [.publicModifier]
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
        let modifiers: Modifiers = [.publicModifier, .inline, .operator, .tailrec]

        XCTAssertTrue(modifiers.contains(.publicModifier))
        XCTAssertTrue(modifiers.contains(.inline))
        XCTAssertTrue(modifiers.contains(.operator))
        XCTAssertTrue(modifiers.contains(.tailrec))
        XCTAssertFalse(modifiers.contains(.privateModifier))
    }

    func testASTArenaAppendLookupAndDeclarationSnapshot() {
        let interner = StringInterner()
        let name = interner.intern("C")
        let classDecl = ClassDecl(
            range: makeRange(start: 0, end: 2),
            name: name,
            modifiers: [.publicModifier],
            typeParams: [],
            primaryConstructorParams: []
        )

        let arena = ASTArena()
        let classID = arena.appendDecl(.classDecl(classDecl))
        let propertyDecl = PropertyDecl(
            range: makeRange(start: 3, end: 5),
            name: interner.intern("p"),
            modifiers: [.privateModifier],
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
    }

    func testModelStructsAndModuleInitializers() {
        let interner = StringInterner()
        let range = makeRange(start: 5, end: 9)
        let typeRef = TypeRefID(rawValue: 4)
        let name = interner.intern("Name")

        let objectDecl = ObjectDecl(range: range, name: name, modifiers: [.publicModifier])
        XCTAssertEqual(objectDecl.name, name)

        let typeAliasDecl = TypeAliasDecl(range: range, name: interner.intern("Alias"), modifiers: [.internalModifier])
        XCTAssertEqual(typeAliasDecl.modifiers, [.internalModifier])

        let enumEntryDecl = EnumEntryDecl(range: range, name: interner.intern("Entry"))
        XCTAssertEqual(enumEntryDecl.range, range)

        let importDecl = ImportDecl(range: range, path: [interner.intern("kotlin"), interner.intern("collections")])
        XCTAssertEqual(importDecl.path.count, 2)

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
}

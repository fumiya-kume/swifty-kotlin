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

    func testDeclModelStructInitializers() {
        let interner = StringInterner()
        let range = makeRange(start: 5, end: 9)
        let typeRef = TypeRefID(rawValue: 4)

        let objectDecl = ObjectDecl(range: range, name: interner.intern("Name"), modifiers: [.public])
        XCTAssertEqual(objectDecl.name, interner.intern("Name"))

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
    }

    func testASTFileInitializer() {
        let interner = StringInterner()
        let range = makeRange(start: 5, end: 9)
        let importDecl = ImportDecl(range: range, path: [interner.intern("kotlin"), interner.intern("collections")], alias: nil)

        let file = ASTFile(
            fileID: FileID(rawValue: 1),
            packageFQName: [interner.intern("pkg")],
            imports: [importDecl],
            topLevelDecls: [DeclID(rawValue: 0)],
            scriptBody: []
        )
        XCTAssertEqual(file.fileID, FileID(rawValue: 1))
        XCTAssertEqual(file.packageFQName.count, 1)
        XCTAssertEqual(file.imports.count, 1)
        XCTAssertEqual(file.topLevelDecls.count, 1)
    }

    func testASTModuleFullAndCompactInitializers() {
        let interner = StringInterner()
        let file = ASTFile(
            fileID: FileID(rawValue: 0),
            packageFQName: [interner.intern("pkg")],
            imports: [],
            topLevelDecls: [],
            scriptBody: []
        )

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

    func testExprRangeReturnsRangeForAllExprCases() {
        let interner = StringInterner()
        let arena = ASTArena()
        let r = makeRange(start: 0, end: 10)
        let dummyExprID = arena.appendExpr(.intLiteral(42, r))
        let dummyTypeRefID = arena.appendTypeRef(.named(path: [interner.intern("Int")], args: [], nullable: false))
        let name = interner.intern("x")

        let cases: [Expr] = [
            .intLiteral(1, r),
            .longLiteral(1, r),
            .floatLiteral(1.0, r),
            .doubleLiteral(1.0, r),
            .charLiteral(65, r),
            .boolLiteral(true, r),
            .stringLiteral(name, r),
            .nameRef(name, r),
            .forExpr(loopVariable: name, iterable: dummyExprID, body: dummyExprID, range: r),
            .whileExpr(condition: dummyExprID, body: dummyExprID, range: r),
            .doWhileExpr(body: dummyExprID, condition: dummyExprID, range: r),
            .breakExpr(range: r),
            .continueExpr(range: r),
            .localDecl(name: name, isMutable: false, typeAnnotation: nil, initializer: dummyExprID, range: r),
            .localAssign(name: name, value: dummyExprID, range: r),
            .arrayAssign(array: dummyExprID, index: dummyExprID, value: dummyExprID, range: r),
            .call(callee: dummyExprID, typeArgs: [], args: [], range: r),
            .memberCall(receiver: dummyExprID, callee: name, typeArgs: [], args: [], range: r),
            .arrayAccess(array: dummyExprID, index: dummyExprID, range: r),
            .binary(op: .add, lhs: dummyExprID, rhs: dummyExprID, range: r),
            .whenExpr(subject: dummyExprID, branches: [], elseExpr: nil, range: r),
            .returnExpr(value: nil, range: r),
            .ifExpr(condition: dummyExprID, thenExpr: dummyExprID, elseExpr: nil, range: r),
            .tryExpr(body: dummyExprID, catchClauses: [], finallyExpr: nil, range: r),
            .unaryExpr(op: .not, operand: dummyExprID, range: r),
            .isCheck(expr: dummyExprID, type: dummyTypeRefID, negated: false, range: r),
            .asCast(expr: dummyExprID, type: dummyTypeRefID, isSafe: true, range: r),
            .nullAssert(expr: dummyExprID, range: r),
            .safeMemberCall(receiver: dummyExprID, callee: name, typeArgs: [], args: [], range: r),
            .compoundAssign(op: .plusAssign, name: name, value: dummyExprID, range: r),
            .throwExpr(value: dummyExprID, range: r),
            .localFunDecl(name: name, valueParams: [], returnType: nil, body: .unit, range: r),
        ]

        for (index, exprCase) in cases.enumerated() {
            let id = arena.appendExpr(exprCase)
            XCTAssertEqual(arena.exprRange(id), r, "Expr case at index \(index) failed")
        }
    }

    func testExprRangeReturnsNilForInvalidID() {
        let arena = ASTArena()
        XCTAssertNil(arena.exprRange(ExprID(rawValue: -1)))
        XCTAssertNil(arena.exprRange(ExprID(rawValue: 999)))
    }

    func testSortedFilesReturnsByFileID() {
        let arena = ASTArena()
        let file0 = ASTFile(fileID: FileID(rawValue: 2), packageFQName: [], imports: [], topLevelDecls: [], scriptBody: [])
        let file1 = ASTFile(fileID: FileID(rawValue: 0), packageFQName: [], imports: [], topLevelDecls: [], scriptBody: [])
        let file2 = ASTFile(fileID: FileID(rawValue: 1), packageFQName: [], imports: [], topLevelDecls: [], scriptBody: [])
        let module = ASTModule(files: [file0, file1, file2], arena: arena, declarationCount: 0, tokenCount: 0)
        let sorted = module.sortedFiles
        XCTAssertEqual(sorted[0].fileID, FileID(rawValue: 0))
        XCTAssertEqual(sorted[1].fileID, FileID(rawValue: 1))
        XCTAssertEqual(sorted[2].fileID, FileID(rawValue: 2))
    }

    func testTypeRefFunctionTypeLookup() {
        let arena = ASTArena()
        let paramTypeRef = arena.appendTypeRef(.named(path: [], args: [], nullable: false))
        let returnTypeRef = arena.appendTypeRef(.named(path: [], args: [], nullable: false))
        let funcTypeID = arena.appendTypeRef(.functionType(params: [paramTypeRef], returnType: returnTypeRef, isSuspend: true, nullable: false))
        if case .functionType(let params, let ret, let suspend, let nullable) = arena.typeRef(funcTypeID) {
            XCTAssertEqual(params.count, 1)
            XCTAssertEqual(ret, returnTypeRef)
            XCTAssertTrue(suspend)
            XCTAssertFalse(nullable)
        } else {
            XCTFail("Expected .functionType")
        }
    }

    func testTypeArgRefCases() {
        let typeRef = TypeRefID(rawValue: 0)
        let invariant = TypeArgRef.invariant(typeRef)
        let outArg = TypeArgRef.out(typeRef)
        let inArg = TypeArgRef.in(typeRef)
        let star = TypeArgRef.star
        XCTAssertNotEqual(invariant, star)
        XCTAssertNotEqual(outArg, inArg)
    }

    func testPropertyAccessorDeclSetterWithExprBody() {
        let interner = StringInterner()
        let r = makeRange(start: 0, end: 5)
        let exprID = ExprID(rawValue: 0)
        let name = interner.intern("x")

        let setter = PropertyAccessorDecl(range: r, kind: .setter, parameterName: name, body: .expr(exprID, r))
        XCTAssertEqual(setter.kind, .setter)
        XCTAssertEqual(setter.parameterName, name)
        if case .expr(let e, _) = setter.body {
            XCTAssertEqual(e, exprID)
        } else {
            XCTFail("Expected .expr body")
        }
    }

    func testPropertyDeclWithAllFields() {
        let interner = StringInterner()
        let r = makeRange(start: 0, end: 5)
        let typeRef = TypeRefID(rawValue: 0)
        let exprID = ExprID(rawValue: 0)
        let name = interner.intern("x")

        let getter = PropertyAccessorDecl(range: r, kind: .getter)
        let setter = PropertyAccessorDecl(range: r, kind: .setter, parameterName: name, body: .expr(exprID, r))
        let propDecl = PropertyDecl(
            range: r, name: name, modifiers: [.public], type: typeRef,
            isVar: true, initializer: exprID, getter: getter, setter: setter, delegateExpression: exprID
        )
        XCTAssertTrue(propDecl.isVar)
        XCTAssertEqual(propDecl.getter?.kind, .getter)
        XCTAssertEqual(propDecl.setter?.kind, .setter)
        XCTAssertEqual(propDecl.delegateExpression, exprID)
    }

    func testValueParamDeclWithDefaultAndVararg() {
        let interner = StringInterner()
        let typeRef = TypeRefID(rawValue: 0)
        let exprID = ExprID(rawValue: 0)
        let name = interner.intern("x")

        let param = ValueParamDecl(name: name, type: typeRef, hasDefaultValue: true, isVararg: true, defaultValue: exprID)
        XCTAssertTrue(param.hasDefaultValue)
        XCTAssertTrue(param.isVararg)
        XCTAssertEqual(param.defaultValue, exprID)
    }

    func testTypeParamDeclWithVarianceAndBound() {
        let interner = StringInterner()
        let typeRef = TypeRefID(rawValue: 0)
        let name = interner.intern("x")

        let typeParam = TypeParamDecl(name: name, variance: .out, isReified: true, upperBound: typeRef)
        XCTAssertEqual(typeParam.variance, .out)
        XCTAssertTrue(typeParam.isReified)
        XCTAssertEqual(typeParam.upperBound, typeRef)
    }

    func testFunDeclWithAllExplicitFields() {
        let interner = StringInterner()
        let r = makeRange(start: 0, end: 5)
        let typeRef = TypeRefID(rawValue: 0)
        let exprID = ExprID(rawValue: 0)
        let name = interner.intern("x")

        let typeParam = TypeParamDecl(name: name, variance: .out, isReified: true, upperBound: typeRef)
        let param = ValueParamDecl(name: name, type: typeRef, hasDefaultValue: true, isVararg: true, defaultValue: exprID)
        let funDecl = FunDecl(
            range: r, name: name, modifiers: [.suspend, .inline],
            typeParams: [typeParam], receiverType: typeRef, valueParams: [param],
            returnType: typeRef, body: .block([exprID], r), isSuspend: true, isInline: true
        )
        XCTAssertTrue(funDecl.isSuspend)
        XCTAssertTrue(funDecl.isInline)
        XCTAssertEqual(funDecl.receiverType, typeRef)
        XCTAssertEqual(funDecl.returnType, typeRef)
        XCTAssertEqual(funDecl.typeParams.count, 1)
    }

    func testInterfaceDeclWithTypeParamsAndSuperTypes() {
        let interner = StringInterner()
        let r = makeRange(start: 0, end: 5)
        let typeRef = TypeRefID(rawValue: 0)
        let name = interner.intern("x")

        let typeParam = TypeParamDecl(name: name, variance: .out, isReified: true, upperBound: typeRef)
        let alias = TypeAliasDecl(range: r, name: name, modifiers: [], typeParams: [typeParam], underlyingType: typeRef)
        XCTAssertEqual(alias.underlyingType, typeRef)
        let iface = InterfaceDecl(
            range: r, name: name, modifiers: [],
            typeParams: [typeParam], superTypes: [typeRef], nestedTypeAliases: [alias]
        )
        XCTAssertEqual(iface.typeParams.count, 1)
        XCTAssertEqual(iface.superTypes.count, 1)
        XCTAssertEqual(iface.nestedTypeAliases.count, 1)
    }

    func testWhenBranchCallArgumentAndCatchClauseInit() {
        let interner = StringInterner()
        let r = makeRange(start: 0, end: 5)
        let exprID = ExprID(rawValue: 0)
        let name = interner.intern("x")

        let branch = WhenBranch(condition: exprID, body: exprID, range: r)
        XCTAssertEqual(branch.condition, exprID)
        let callArg = CallArgument(label: name, isSpread: true, expr: exprID)
        XCTAssertEqual(callArg.label, name)
        XCTAssertTrue(callArg.isSpread)
        let catchClause = CatchClause(paramName: name, paramTypeName: name, body: exprID, range: r)
        XCTAssertEqual(catchClause.paramName, name)
        XCTAssertEqual(catchClause.paramTypeName, name)
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

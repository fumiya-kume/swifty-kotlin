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
            .breakExpr(label: nil, range: r),
            .continueExpr(label: nil, range: r),
            .localDecl(name: name, isMutable: false, typeAnnotation: nil, initializer: dummyExprID, range: r),
            .localAssign(name: name, value: dummyExprID, range: r),
            .indexedAssign(receiver: dummyExprID, indices: [dummyExprID], value: dummyExprID, range: r),
            .call(callee: dummyExprID, typeArgs: [], args: [], range: r),
            .memberCall(receiver: dummyExprID, callee: name, typeArgs: [], args: [], range: r),
            .indexedAccess(receiver: dummyExprID, indices: [dummyExprID], range: r),
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
            .lambdaLiteral(params: [name], body: dummyExprID, range: r),
            .objectLiteral(superTypes: [dummyTypeRefID], range: r),
            .callableRef(receiver: dummyExprID, member: name, range: r),
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

    // MARK: - All Decl variants

    func testDeclVariantClassDecl() {
        let interner = StringInterner()
        let r = makeRange(start: 0, end: 5)
        let classDecl = ClassDecl(range: r, name: interner.intern("MyClass"), modifiers: [.public], typeParams: [], primaryConstructorParams: [])
        let decl = Decl.classDecl(classDecl)
        if case .classDecl(let d) = decl {
            XCTAssertEqual(d.name, interner.intern("MyClass"))
        } else {
            XCTFail("Expected .classDecl")
        }
    }

    func testDeclVariantInterfaceDecl() {
        let interner = StringInterner()
        let r = makeRange(start: 0, end: 5)
        let ifaceDecl = InterfaceDecl(range: r, name: interner.intern("MyInterface"), modifiers: [.abstract])
        let decl = Decl.interfaceDecl(ifaceDecl)
        if case .interfaceDecl(let d) = decl {
            XCTAssertEqual(d.name, interner.intern("MyInterface"))
            XCTAssertEqual(d.modifiers, [.abstract])
        } else {
            XCTFail("Expected .interfaceDecl")
        }
    }

    func testDeclVariantFunDecl() {
        let interner = StringInterner()
        let r = makeRange(start: 0, end: 5)
        let funDecl = FunDecl(range: r, name: interner.intern("doStuff"), modifiers: [.suspend])
        let decl = Decl.funDecl(funDecl)
        if case .funDecl(let d) = decl {
            XCTAssertEqual(d.name, interner.intern("doStuff"))
            XCTAssertTrue(d.modifiers.contains(.suspend))
        } else {
            XCTFail("Expected .funDecl")
        }
    }

    func testDeclVariantPropertyDecl() {
        let interner = StringInterner()
        let r = makeRange(start: 0, end: 5)
        let propDecl = PropertyDecl(range: r, name: interner.intern("count"), modifiers: [.private], type: TypeRefID(rawValue: 0))
        let decl = Decl.propertyDecl(propDecl)
        if case .propertyDecl(let d) = decl {
            XCTAssertEqual(d.name, interner.intern("count"))
            XCTAssertTrue(d.modifiers.contains(.private))
        } else {
            XCTFail("Expected .propertyDecl")
        }
    }

    func testDeclVariantTypeAliasDecl() {
        let interner = StringInterner()
        let r = makeRange(start: 0, end: 5)
        let alias = TypeAliasDecl(range: r, name: interner.intern("StringList"), modifiers: [.internal])
        let decl = Decl.typeAliasDecl(alias)
        if case .typeAliasDecl(let d) = decl {
            XCTAssertEqual(d.name, interner.intern("StringList"))
            XCTAssertEqual(d.modifiers, [.internal])
        } else {
            XCTFail("Expected .typeAliasDecl")
        }
    }

    func testDeclVariantObjectDecl() {
        let interner = StringInterner()
        let r = makeRange(start: 0, end: 5)
        let objDecl = ObjectDecl(range: r, name: interner.intern("Companion"), modifiers: [.public])
        let decl = Decl.objectDecl(objDecl)
        if case .objectDecl(let d) = decl {
            XCTAssertEqual(d.name, interner.intern("Companion"))
        } else {
            XCTFail("Expected .objectDecl")
        }
    }

    func testDeclVariantEnumEntryDecl() {
        let interner = StringInterner()
        let r = makeRange(start: 0, end: 5)
        let entry = EnumEntryDecl(range: r, name: interner.intern("RED"))
        let decl = Decl.enumEntryDecl(entry)
        if case .enumEntryDecl(let d) = decl {
            XCTAssertEqual(d.name, interner.intern("RED"))
        } else {
            XCTFail("Expected .enumEntryDecl")
        }
    }

    func testAllDeclVariantsInArena() {
        let interner = StringInterner()
        let r = makeRange(start: 0, end: 5)
        let arena = ASTArena()

        let classID = arena.appendDecl(.classDecl(ClassDecl(range: r, name: interner.intern("C"), modifiers: [], typeParams: [], primaryConstructorParams: [])))
        let ifaceID = arena.appendDecl(.interfaceDecl(InterfaceDecl(range: r, name: interner.intern("I"), modifiers: [])))
        let funID = arena.appendDecl(.funDecl(FunDecl(range: r, name: interner.intern("f"), modifiers: [])))
        let propID = arena.appendDecl(.propertyDecl(PropertyDecl(range: r, name: interner.intern("p"), modifiers: [], type: nil)))
        let aliasID = arena.appendDecl(.typeAliasDecl(TypeAliasDecl(range: r, name: interner.intern("A"), modifiers: [])))
        let objID = arena.appendDecl(.objectDecl(ObjectDecl(range: r, name: interner.intern("O"), modifiers: [])))
        let enumID = arena.appendDecl(.enumEntryDecl(EnumEntryDecl(range: r, name: interner.intern("E"))))

        XCTAssertEqual(arena.declarations().count, 7)

        if case .classDecl = arena.decl(classID) {} else { XCTFail("Expected classDecl") }
        if case .interfaceDecl = arena.decl(ifaceID) {} else { XCTFail("Expected interfaceDecl") }
        if case .funDecl = arena.decl(funID) {} else { XCTFail("Expected funDecl") }
        if case .propertyDecl = arena.decl(propID) {} else { XCTFail("Expected propertyDecl") }
        if case .typeAliasDecl = arena.decl(aliasID) {} else { XCTFail("Expected typeAliasDecl") }
        if case .objectDecl = arena.decl(objID) {} else { XCTFail("Expected objectDecl") }
        if case .enumEntryDecl = arena.decl(enumID) {} else { XCTFail("Expected enumEntryDecl") }
    }

    // MARK: - Visibility enum all cases

    func testVisibilityAllCases() {
        XCTAssertEqual(Visibility.public.rawValue, 0)
        XCTAssertEqual(Visibility.private.rawValue, 1)
        XCTAssertEqual(Visibility.internal.rawValue, 2)
        XCTAssertEqual(Visibility.protected.rawValue, 3)
    }

    func testVisibilityInitFromRawValue() {
        XCTAssertEqual(Visibility(rawValue: 0), .public)
        XCTAssertEqual(Visibility(rawValue: 1), .private)
        XCTAssertEqual(Visibility(rawValue: 2), .internal)
        XCTAssertEqual(Visibility(rawValue: 3), .protected)
        XCTAssertNil(Visibility(rawValue: 4))
        XCTAssertNil(Visibility(rawValue: -1))
    }

    // MARK: - Modifiers all flags and combinations

    func testModifiersAllIndividualFlags() {
        let allFlags: [(Modifiers, Int32)] = [
            (.public, 1 << 0),
            (.internal, 1 << 1),
            (.private, 1 << 2),
            (.protected, 1 << 3),
            (.final, 1 << 4),
            (.open, 1 << 5),
            (.abstract, 1 << 6),
            (.sealed, 1 << 7),
            (.data, 1 << 8),
            (.annotationClass, 1 << 9),
            (.inline, 1 << 10),
            (.suspend, 1 << 11),
            (.tailrec, 1 << 12),
            (.operator, 1 << 13),
            (.infix, 1 << 14),
            (.crossinline, 1 << 15),
            (.noinline, 1 << 16),
            (.vararg, 1 << 17),
            (.external, 1 << 18),
            (.expect, 1 << 19),
            (.actual, 1 << 20),
            (.value, 1 << 21),
            (.enumModifier, 1 << 22),
        ]
        for (flag, expected) in allFlags {
            XCTAssertEqual(flag.rawValue, expected, "Flag with rawValue \(flag.rawValue) expected \(expected)")
        }
    }

    func testModifiersEmptySet() {
        let empty: Modifiers = []
        XCTAssertTrue(empty.isEmpty)
        XCTAssertEqual(empty.rawValue, 0)
        XCTAssertFalse(empty.contains(.public))
    }

    func testModifiersCombinationAccessModifiers() {
        let combo: Modifiers = [.public, .final, .data]
        XCTAssertTrue(combo.contains(.public))
        XCTAssertTrue(combo.contains(.final))
        XCTAssertTrue(combo.contains(.data))
        XCTAssertFalse(combo.contains(.private))
        XCTAssertFalse(combo.contains(.abstract))
    }

    func testModifiersCombinationFunctionModifiers() {
        let combo: Modifiers = [.suspend, .inline, .tailrec, .operator, .infix]
        XCTAssertTrue(combo.contains(.suspend))
        XCTAssertTrue(combo.contains(.inline))
        XCTAssertTrue(combo.contains(.tailrec))
        XCTAssertTrue(combo.contains(.operator))
        XCTAssertTrue(combo.contains(.infix))
        XCTAssertFalse(combo.contains(.crossinline))
    }

    func testModifiersCombinationParameterModifiers() {
        let combo: Modifiers = [.crossinline, .noinline, .vararg]
        XCTAssertTrue(combo.contains(.crossinline))
        XCTAssertTrue(combo.contains(.noinline))
        XCTAssertTrue(combo.contains(.vararg))
        XCTAssertFalse(combo.contains(.suspend))
    }

    func testModifiersCombinationPlatformModifiers() {
        let combo: Modifiers = [.external, .expect, .actual]
        XCTAssertTrue(combo.contains(.external))
        XCTAssertTrue(combo.contains(.expect))
        XCTAssertTrue(combo.contains(.actual))
        XCTAssertFalse(combo.contains(.value))
    }

    func testModifiersCombinationClassModifiers() {
        let combo: Modifiers = [.abstract, .sealed, .open, .value, .enumModifier, .annotationClass]
        XCTAssertTrue(combo.contains(.abstract))
        XCTAssertTrue(combo.contains(.sealed))
        XCTAssertTrue(combo.contains(.open))
        XCTAssertTrue(combo.contains(.value))
        XCTAssertTrue(combo.contains(.enumModifier))
        XCTAssertTrue(combo.contains(.annotationClass))
        XCTAssertFalse(combo.contains(.final))
    }

    func testModifiersUnionAndIntersection() {
        let a: Modifiers = [.public, .final]
        let b: Modifiers = [.final, .data]
        let union = a.union(b)
        XCTAssertTrue(union.contains(.public))
        XCTAssertTrue(union.contains(.final))
        XCTAssertTrue(union.contains(.data))
        let intersection = a.intersection(b)
        XCTAssertTrue(intersection.contains(.final))
        XCTAssertFalse(intersection.contains(.public))
        XCTAssertFalse(intersection.contains(.data))
    }

    func testModifiersSymmetricDifference() {
        let a: Modifiers = [.public, .final]
        let b: Modifiers = [.final, .open]
        let diff = a.symmetricDifference(b)
        XCTAssertTrue(diff.contains(.public))
        XCTAssertTrue(diff.contains(.open))
        XCTAssertFalse(diff.contains(.final))
    }

    // MARK: - TypeRef variants

    func testTypeRefNamedVariant() {
        let interner = StringInterner()
        let arena = ASTArena()
        let id = arena.appendTypeRef(.named(path: [interner.intern("kotlin"), interner.intern("String")], args: [], nullable: false))
        if case .named(let path, let args, let nullable) = arena.typeRef(id) {
            XCTAssertEqual(path.count, 2)
            XCTAssertTrue(args.isEmpty)
            XCTAssertFalse(nullable)
        } else {
            XCTFail("Expected .named")
        }
    }

    func testTypeRefNamedNullableVariant() {
        let interner = StringInterner()
        let arena = ASTArena()
        let id = arena.appendTypeRef(.named(path: [interner.intern("Int")], args: [], nullable: true))
        if case .named(_, _, let nullable) = arena.typeRef(id) {
            XCTAssertTrue(nullable)
        } else {
            XCTFail("Expected .named")
        }
    }

    func testTypeRefNamedWithTypeArgs() {
        let interner = StringInterner()
        let arena = ASTArena()
        let innerID = arena.appendTypeRef(.named(path: [interner.intern("String")], args: [], nullable: false))
        let id = arena.appendTypeRef(.named(
            path: [interner.intern("List")],
            args: [.invariant(innerID)],
            nullable: false
        ))
        if case .named(let path, let args, _) = arena.typeRef(id) {
            XCTAssertEqual(path.count, 1)
            XCTAssertEqual(args.count, 1)
        } else {
            XCTFail("Expected .named")
        }
    }

    func testTypeRefFunctionTypeVariant() {
        let arena = ASTArena()
        let paramID = arena.appendTypeRef(.named(path: [], args: [], nullable: false))
        let returnID = arena.appendTypeRef(.named(path: [], args: [], nullable: false))
        let id = arena.appendTypeRef(.functionType(params: [paramID], returnType: returnID, isSuspend: false, nullable: false))
        if case .functionType(let params, let ret, let isSuspend, let nullable) = arena.typeRef(id) {
            XCTAssertEqual(params.count, 1)
            XCTAssertEqual(ret, returnID)
            XCTAssertFalse(isSuspend)
            XCTAssertFalse(nullable)
        } else {
            XCTFail("Expected .functionType")
        }
    }

    func testTypeRefFunctionTypeSuspendNullable() {
        let arena = ASTArena()
        let returnID = arena.appendTypeRef(.named(path: [], args: [], nullable: false))
        let id = arena.appendTypeRef(.functionType(params: [], returnType: returnID, isSuspend: true, nullable: true))
        if case .functionType(let params, _, let isSuspend, let nullable) = arena.typeRef(id) {
            XCTAssertTrue(params.isEmpty)
            XCTAssertTrue(isSuspend)
            XCTAssertTrue(nullable)
        } else {
            XCTFail("Expected .functionType")
        }
    }

    func testTypeRefEquality() {
        let interner = StringInterner()
        let a = TypeRef.named(path: [interner.intern("Int")], args: [], nullable: false)
        let b = TypeRef.named(path: [interner.intern("Int")], args: [], nullable: false)
        let c = TypeRef.named(path: [interner.intern("Int")], args: [], nullable: true)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    func testTypeArgRefAllVariants() {
        let typeRef = TypeRefID(rawValue: 5)
        let invariant = TypeArgRef.invariant(typeRef)
        let outArg = TypeArgRef.out(typeRef)
        let inArg = TypeArgRef.in(typeRef)
        let star = TypeArgRef.star

        // Each variant is distinct
        XCTAssertNotEqual(invariant, outArg)
        XCTAssertNotEqual(invariant, inArg)
        XCTAssertNotEqual(invariant, star)
        XCTAssertNotEqual(outArg, inArg)
        XCTAssertNotEqual(outArg, star)
        XCTAssertNotEqual(inArg, star)

        // Same variant with same value is equal
        XCTAssertEqual(TypeArgRef.invariant(typeRef), invariant)
        XCTAssertEqual(TypeArgRef.out(typeRef), outArg)
        XCTAssertEqual(TypeArgRef.in(typeRef), inArg)
        XCTAssertEqual(TypeArgRef.star, star)
    }

    // MARK: - Expr variants

    func testExprIntLiteral() {
        let r = makeRange(start: 0, end: 3)
        let expr = Expr.intLiteral(42, r)
        if case .intLiteral(let val, let range) = expr {
            XCTAssertEqual(val, 42)
            XCTAssertEqual(range, r)
        } else {
            XCTFail("Expected .intLiteral")
        }
    }

    func testExprLongLiteral() {
        let r = makeRange(start: 0, end: 3)
        let expr = Expr.longLiteral(Int64.max, r)
        if case .longLiteral(let val, _) = expr {
            XCTAssertEqual(val, Int64.max)
        } else {
            XCTFail("Expected .longLiteral")
        }
    }

    func testExprFloatAndDoubleLiteral() {
        let r = makeRange(start: 0, end: 3)
        let floatExpr = Expr.floatLiteral(3.14, r)
        if case .floatLiteral(let val, _) = floatExpr {
            XCTAssertEqual(val, 3.14)
        } else {
            XCTFail("Expected .floatLiteral")
        }
        let doubleExpr = Expr.doubleLiteral(2.718, r)
        if case .doubleLiteral(let val, _) = doubleExpr {
            XCTAssertEqual(val, 2.718)
        } else {
            XCTFail("Expected .doubleLiteral")
        }
    }

    func testExprCharLiteral() {
        let r = makeRange(start: 0, end: 3)
        let expr = Expr.charLiteral(65, r)
        if case .charLiteral(let val, _) = expr {
            XCTAssertEqual(val, 65)
        } else {
            XCTFail("Expected .charLiteral")
        }
    }

    func testExprBoolLiteral() {
        let r = makeRange(start: 0, end: 3)
        let trueExpr = Expr.boolLiteral(true, r)
        let falseExpr = Expr.boolLiteral(false, r)
        if case .boolLiteral(let val, _) = trueExpr {
            XCTAssertTrue(val)
        } else {
            XCTFail("Expected .boolLiteral")
        }
        if case .boolLiteral(let val, _) = falseExpr {
            XCTAssertFalse(val)
        } else {
            XCTFail("Expected .boolLiteral")
        }
    }

    func testExprStringLiteralAndTemplate() {
        let interner = StringInterner()
        let r = makeRange(start: 0, end: 3)
        let strExpr = Expr.stringLiteral(interner.intern("hello"), r)
        if case .stringLiteral(let val, _) = strExpr {
            XCTAssertEqual(val, interner.intern("hello"))
        } else {
            XCTFail("Expected .stringLiteral")
        }

        let arena = ASTArena()
        let innerExprID = arena.appendExpr(.intLiteral(1, r))
        let templateExpr = Expr.stringTemplate(
            parts: [.literal(interner.intern("x=")), .expression(innerExprID)],
            range: r
        )
        if case .stringTemplate(let parts, _) = templateExpr {
            XCTAssertEqual(parts.count, 2)
        } else {
            XCTFail("Expected .stringTemplate")
        }
    }

    func testExprNameRef() {
        let interner = StringInterner()
        let r = makeRange(start: 0, end: 3)
        let expr = Expr.nameRef(interner.intern("myVar"), r)
        if case .nameRef(let name, _) = expr {
            XCTAssertEqual(name, interner.intern("myVar"))
        } else {
            XCTFail("Expected .nameRef")
        }
    }

    func testExprControlFlow() {
        let r = makeRange(start: 0, end: 10)
        let arena = ASTArena()
        let interner = StringInterner()
        let bodyID = arena.appendExpr(.intLiteral(1, r))
        let condID = arena.appendExpr(.boolLiteral(true, r))
        let loopVar = interner.intern("i")

        let forExpr = Expr.forExpr(loopVariable: loopVar, iterable: bodyID, body: bodyID, range: r)
        if case .forExpr(let lv, _, _, _) = forExpr {
            XCTAssertEqual(lv, loopVar)
        } else { XCTFail("Expected .forExpr") }

        let whileExpr = Expr.whileExpr(condition: condID, body: bodyID, range: r)
        if case .whileExpr(let c, let b, _) = whileExpr {
            XCTAssertEqual(c, condID)
            XCTAssertEqual(b, bodyID)
        } else { XCTFail("Expected .whileExpr") }

        let doWhileExpr = Expr.doWhileExpr(body: bodyID, condition: condID, range: r)
        if case .doWhileExpr(let b, let c, _) = doWhileExpr {
            XCTAssertEqual(b, bodyID)
            XCTAssertEqual(c, condID)
        } else { XCTFail("Expected .doWhileExpr") }

        let breakExpr = Expr.breakExpr(label: nil, range: r)
        if case .breakExpr(_, let range) = breakExpr {
            XCTAssertEqual(range, r)
        } else { XCTFail("Expected .breakExpr") }

        let continueExpr = Expr.continueExpr(label: nil, range: r)
        if case .continueExpr(_, let range) = continueExpr {
            XCTAssertEqual(range, r)
        } else { XCTFail("Expected .continueExpr") }
    }

    func testExprLocalDeclAndAssign() {
        let interner = StringInterner()
        let r = makeRange(start: 0, end: 10)
        let arena = ASTArena()
        let initID = arena.appendExpr(.intLiteral(5, r))
        let name = interner.intern("x")
        let typeRefID = arena.appendTypeRef(.named(path: [interner.intern("Int")], args: [], nullable: false))

        let localDecl = Expr.localDecl(name: name, isMutable: true, typeAnnotation: typeRefID, initializer: initID, range: r)
        if case .localDecl(let n, let mut, let ta, let init_, _) = localDecl {
            XCTAssertEqual(n, name)
            XCTAssertTrue(mut)
            XCTAssertEqual(ta, typeRefID)
            XCTAssertEqual(init_, initID)
        } else { XCTFail("Expected .localDecl") }

        let localAssign = Expr.localAssign(name: name, value: initID, range: r)
        if case .localAssign(let n, let v, _) = localAssign {
            XCTAssertEqual(n, name)
            XCTAssertEqual(v, initID)
        } else { XCTFail("Expected .localAssign") }

        let arrExprID = arena.appendExpr(.intLiteral(0, r))
        let idxExprID = arena.appendExpr(.intLiteral(1, r))
        let indexedAssign = Expr.indexedAssign(receiver: arrExprID, indices: [idxExprID], value: initID, range: r)
        if case .indexedAssign(let a, let indices, let v, _) = indexedAssign {
            XCTAssertEqual(a, arrExprID)
            XCTAssertEqual(indices, [idxExprID])
            XCTAssertEqual(v, initID)
        } else { XCTFail("Expected .indexedAssign") }
    }

    func testExprCallAndMemberCall() {
        let interner = StringInterner()
        let r = makeRange(start: 0, end: 10)
        let arena = ASTArena()
        let calleeID = arena.appendExpr(.nameRef(interner.intern("foo"), r))
        let argExprID = arena.appendExpr(.intLiteral(1, r))
        let typeRefID = arena.appendTypeRef(.named(path: [interner.intern("Int")], args: [], nullable: false))
        let arg = CallArgument(label: interner.intern("x"), isSpread: false, expr: argExprID)

        let callExpr = Expr.call(callee: calleeID, typeArgs: [typeRefID], args: [arg], range: r)
        if case .call(let c, let ta, let args, _) = callExpr {
            XCTAssertEqual(c, calleeID)
            XCTAssertEqual(ta.count, 1)
            XCTAssertEqual(args.count, 1)
            XCTAssertEqual(args[0].label, interner.intern("x"))
        } else { XCTFail("Expected .call") }

        let receiverID = arena.appendExpr(.nameRef(interner.intern("obj"), r))
        let memberCall = Expr.memberCall(receiver: receiverID, callee: interner.intern("bar"), typeArgs: [], args: [arg], range: r)
        if case .memberCall(let recv, let callee, _, let args, _) = memberCall {
            XCTAssertEqual(recv, receiverID)
            XCTAssertEqual(callee, interner.intern("bar"))
            XCTAssertEqual(args.count, 1)
        } else { XCTFail("Expected .memberCall") }

        let safeMemberCall = Expr.safeMemberCall(receiver: receiverID, callee: interner.intern("baz"), typeArgs: [], args: [], range: r)
        if case .safeMemberCall(let recv, let callee, _, _, _) = safeMemberCall {
            XCTAssertEqual(recv, receiverID)
            XCTAssertEqual(callee, interner.intern("baz"))
        } else { XCTFail("Expected .safeMemberCall") }
    }

    func testExprIndexedAccess() {
        let r = makeRange(start: 0, end: 5)
        let arena = ASTArena()
        let arrID = arena.appendExpr(.intLiteral(0, r))
        let idxID = arena.appendExpr(.intLiteral(1, r))
        let expr = Expr.indexedAccess(receiver: arrID, indices: [idxID], range: r)
        if case .indexedAccess(let a, let indices, _) = expr {
            XCTAssertEqual(a, arrID)
            XCTAssertEqual(indices, [idxID])
        } else { XCTFail("Expected .indexedAccess") }
    }

    func testExprBinaryAllOps() {
        let r = makeRange(start: 0, end: 5)
        let arena = ASTArena()
        let lhs = arena.appendExpr(.intLiteral(1, r))
        let rhs = arena.appendExpr(.intLiteral(2, r))
        let ops: [BinaryOp] = [
            .add, .subtract, .multiply, .divide, .modulo,
            .equal, .notEqual, .lessThan, .lessOrEqual,
            .greaterThan, .greaterOrEqual, .logicalAnd,
            .logicalOr, .elvis, .rangeTo,
        ]
        for op in ops {
            let expr = Expr.binary(op: op, lhs: lhs, rhs: rhs, range: r)
            if case .binary(let o, _, _, _) = expr {
                XCTAssertEqual(o, op)
            } else { XCTFail("Expected .binary for op \(op)") }
        }
    }

    func testExprUnaryAllOps() {
        let r = makeRange(start: 0, end: 5)
        let arena = ASTArena()
        let operand = arena.appendExpr(.intLiteral(1, r))
        let ops: [UnaryOp] = [.not, .unaryPlus, .unaryMinus]
        for op in ops {
            let expr = Expr.unaryExpr(op: op, operand: operand, range: r)
            if case .unaryExpr(let o, _, _) = expr {
                XCTAssertEqual(o, op)
            } else { XCTFail("Expected .unaryExpr for op \(op)") }
        }
    }

    func testExprCompoundAssignAllOps() {
        let interner = StringInterner()
        let r = makeRange(start: 0, end: 5)
        let arena = ASTArena()
        let valID = arena.appendExpr(.intLiteral(1, r))
        let name = interner.intern("x")
        let ops: [CompoundAssignOp] = [.plusAssign, .minusAssign, .timesAssign, .divAssign, .modAssign]
        for op in ops {
            let expr = Expr.compoundAssign(op: op, name: name, value: valID, range: r)
            if case .compoundAssign(let o, _, _, _) = expr {
                XCTAssertEqual(o, op)
            } else { XCTFail("Expected .compoundAssign for op \(op)") }
        }
    }

    func testExprWhenExpr() {
        let r = makeRange(start: 0, end: 10)
        let arena = ASTArena()
        let subjectID = arena.appendExpr(.intLiteral(1, r))
        let bodyID = arena.appendExpr(.intLiteral(2, r))
        let condID = arena.appendExpr(.boolLiteral(true, r))
        let elseID = arena.appendExpr(.intLiteral(3, r))
        let branch = WhenBranch(condition: condID, body: bodyID, range: r)
        let expr = Expr.whenExpr(subject: subjectID, branches: [branch], elseExpr: elseID, range: r)
        if case .whenExpr(let s, let bs, let e, _) = expr {
            XCTAssertEqual(s, subjectID)
            XCTAssertEqual(bs.count, 1)
            XCTAssertEqual(e, elseID)
        } else { XCTFail("Expected .whenExpr") }
    }

    func testExprReturnAndThrow() {
        let r = makeRange(start: 0, end: 5)
        let arena = ASTArena()
        let valID = arena.appendExpr(.intLiteral(1, r))

        let returnWithValue = Expr.returnExpr(value: valID, range: r)
        if case .returnExpr(let v, _) = returnWithValue {
            XCTAssertEqual(v, valID)
        } else { XCTFail("Expected .returnExpr") }

        let returnVoid = Expr.returnExpr(value: nil, range: r)
        if case .returnExpr(let v, _) = returnVoid {
            XCTAssertNil(v)
        } else { XCTFail("Expected .returnExpr") }

        let throwExpr = Expr.throwExpr(value: valID, range: r)
        if case .throwExpr(let v, _) = throwExpr {
            XCTAssertEqual(v, valID)
        } else { XCTFail("Expected .throwExpr") }
    }

    func testExprIfExpr() {
        let r = makeRange(start: 0, end: 10)
        let arena = ASTArena()
        let condID = arena.appendExpr(.boolLiteral(true, r))
        let thenID = arena.appendExpr(.intLiteral(1, r))
        let elseID = arena.appendExpr(.intLiteral(2, r))

        let withElse = Expr.ifExpr(condition: condID, thenExpr: thenID, elseExpr: elseID, range: r)
        if case .ifExpr(let c, let t, let e, _) = withElse {
            XCTAssertEqual(c, condID)
            XCTAssertEqual(t, thenID)
            XCTAssertEqual(e, elseID)
        } else { XCTFail("Expected .ifExpr") }

        let withoutElse = Expr.ifExpr(condition: condID, thenExpr: thenID, elseExpr: nil, range: r)
        if case .ifExpr(_, _, let e, _) = withoutElse {
            XCTAssertNil(e)
        } else { XCTFail("Expected .ifExpr") }
    }

    func testExprTryExpr() {
        let interner = StringInterner()
        let r = makeRange(start: 0, end: 10)
        let arena = ASTArena()
        let bodyID = arena.appendExpr(.intLiteral(1, r))
        let catchBodyID = arena.appendExpr(.intLiteral(2, r))
        let finallyID = arena.appendExpr(.intLiteral(3, r))
        let catchClause = CatchClause(paramName: interner.intern("e"), paramTypeName: interner.intern("Exception"), body: catchBodyID, range: r)

        let tryExpr = Expr.tryExpr(body: bodyID, catchClauses: [catchClause], finallyExpr: finallyID, range: r)
        if case .tryExpr(let b, let cc, let f, _) = tryExpr {
            XCTAssertEqual(b, bodyID)
            XCTAssertEqual(cc.count, 1)
            XCTAssertEqual(f, finallyID)
        } else { XCTFail("Expected .tryExpr") }
    }

    func testExprIsCheckAndAsCast() {
        let r = makeRange(start: 0, end: 5)
        let arena = ASTArena()
        let exprID = arena.appendExpr(.intLiteral(1, r))
        let typeRefID = arena.appendTypeRef(.named(path: [], args: [], nullable: false))

        let isCheck = Expr.isCheck(expr: exprID, type: typeRefID, negated: false, range: r)
        if case .isCheck(_, _, let neg, _) = isCheck {
            XCTAssertFalse(neg)
        } else { XCTFail("Expected .isCheck") }

        let isNotCheck = Expr.isCheck(expr: exprID, type: typeRefID, negated: true, range: r)
        if case .isCheck(_, _, let neg, _) = isNotCheck {
            XCTAssertTrue(neg)
        } else { XCTFail("Expected .isCheck negated") }

        let safeCast = Expr.asCast(expr: exprID, type: typeRefID, isSafe: true, range: r)
        if case .asCast(_, _, let safe, _) = safeCast {
            XCTAssertTrue(safe)
        } else { XCTFail("Expected .asCast safe") }

        let unsafeCast = Expr.asCast(expr: exprID, type: typeRefID, isSafe: false, range: r)
        if case .asCast(_, _, let safe, _) = unsafeCast {
            XCTAssertFalse(safe)
        } else { XCTFail("Expected .asCast unsafe") }
    }

    func testExprNullAssert() {
        let r = makeRange(start: 0, end: 5)
        let arena = ASTArena()
        let exprID = arena.appendExpr(.intLiteral(1, r))
        let nullAssert = Expr.nullAssert(expr: exprID, range: r)
        if case .nullAssert(let e, _) = nullAssert {
            XCTAssertEqual(e, exprID)
        } else { XCTFail("Expected .nullAssert") }
    }

    func testExprLambdaLiteral() {
        let interner = StringInterner()
        let r = makeRange(start: 0, end: 10)
        let arena = ASTArena()
        let bodyID = arena.appendExpr(.intLiteral(1, r))
        let params = [interner.intern("x"), interner.intern("y")]
        let lambda = Expr.lambdaLiteral(params: params, body: bodyID, range: r)
        if case .lambdaLiteral(let p, let b, _) = lambda {
            XCTAssertEqual(p.count, 2)
            XCTAssertEqual(b, bodyID)
        } else { XCTFail("Expected .lambdaLiteral") }
    }

    func testExprObjectLiteral() {
        let r = makeRange(start: 0, end: 5)
        let arena = ASTArena()
        let typeRefID = arena.appendTypeRef(.named(path: [], args: [], nullable: false))
        let obj = Expr.objectLiteral(superTypes: [typeRefID], range: r)
        if case .objectLiteral(let st, _) = obj {
            XCTAssertEqual(st.count, 1)
        } else { XCTFail("Expected .objectLiteral") }
    }

    func testExprCallableRef() {
        let interner = StringInterner()
        let r = makeRange(start: 0, end: 5)
        let arena = ASTArena()
        let receiverID = arena.appendExpr(.nameRef(interner.intern("MyClass"), r))
        let ref = Expr.callableRef(receiver: receiverID, member: interner.intern("method"), range: r)
        if case .callableRef(let recv, let member, _) = ref {
            XCTAssertEqual(recv, receiverID)
            XCTAssertEqual(member, interner.intern("method"))
        } else { XCTFail("Expected .callableRef") }

        let refNoReceiver = Expr.callableRef(receiver: nil, member: interner.intern("topFun"), range: r)
        if case .callableRef(let recv, _, _) = refNoReceiver {
            XCTAssertNil(recv)
        } else { XCTFail("Expected .callableRef without receiver") }
    }

    func testExprLocalFunDecl() {
        let interner = StringInterner()
        let r = makeRange(start: 0, end: 10)
        let arena = ASTArena()
        let bodyID = arena.appendExpr(.intLiteral(1, r))
        let param = ValueParamDecl(name: interner.intern("a"), type: TypeRefID(rawValue: 0))
        let typeRefID = arena.appendTypeRef(.named(path: [interner.intern("Int")], args: [], nullable: false))
        let localFun = Expr.localFunDecl(name: interner.intern("helper"), valueParams: [param], returnType: typeRefID, body: .expr(bodyID, r), range: r)
        if case .localFunDecl(let name, let params, let ret, let body, _) = localFun {
            XCTAssertEqual(name, interner.intern("helper"))
            XCTAssertEqual(params.count, 1)
            XCTAssertEqual(ret, typeRefID)
            if case .expr(let e, _) = body {
                XCTAssertEqual(e, bodyID)
            } else { XCTFail("Expected .expr body") }
        } else { XCTFail("Expected .localFunDecl") }
    }

    func testExprBlockExpr() {
        let r = makeRange(start: 0, end: 10)
        let arena = ASTArena()
        let stmt1 = arena.appendExpr(.intLiteral(1, r))
        let stmt2 = arena.appendExpr(.intLiteral(2, r))
        let trailing = arena.appendExpr(.intLiteral(3, r))
        let block = Expr.blockExpr(statements: [stmt1, stmt2], trailingExpr: trailing, range: r)
        if case .blockExpr(let stmts, let trail, _) = block {
            XCTAssertEqual(stmts.count, 2)
            XCTAssertEqual(trail, trailing)
        } else { XCTFail("Expected .blockExpr") }

        let blockNoTrail = Expr.blockExpr(statements: [stmt1], trailingExpr: nil, range: r)
        if case .blockExpr(_, let trail, _) = blockNoTrail {
            XCTAssertNil(trail)
        } else { XCTFail("Expected .blockExpr without trailing") }
    }

    func testExprSuperRefAndThisRef() {
        let interner = StringInterner()
        let r = makeRange(start: 0, end: 5)
        let superRef = Expr.superRef(r)
        if case .superRef(let range) = superRef {
            XCTAssertEqual(range, r)
        } else { XCTFail("Expected .superRef") }

        let thisRef = Expr.thisRef(label: nil, r)
        if case .thisRef(let label, _) = thisRef {
            XCTAssertNil(label)
        } else { XCTFail("Expected .thisRef") }

        let thisRefLabeled = Expr.thisRef(label: interner.intern("Outer"), r)
        if case .thisRef(let label, _) = thisRefLabeled {
            XCTAssertEqual(label, interner.intern("Outer"))
        } else { XCTFail("Expected .thisRef with label") }
    }

    // MARK: - ASTArena expr() method

    func testASTArenaExprLookup() {
        let r = makeRange(start: 0, end: 5)
        let arena = ASTArena()
        let id0 = arena.appendExpr(.intLiteral(42, r))
        let id1 = arena.appendExpr(.boolLiteral(true, r))

        if case .intLiteral(let val, _) = arena.expr(id0) {
            XCTAssertEqual(val, 42)
        } else {
            XCTFail("Expected .intLiteral from arena.expr()")
        }

        if case .boolLiteral(let val, _) = arena.expr(id1) {
            XCTAssertTrue(val)
        } else {
            XCTFail("Expected .boolLiteral from arena.expr()")
        }
    }

    func testASTArenaExprReturnsNilForInvalidID() {
        let arena = ASTArena()
        XCTAssertNil(arena.expr(ExprID(rawValue: -1)))
        XCTAssertNil(arena.expr(ExprID(rawValue: 0)))
        XCTAssertNil(arena.expr(ExprID(rawValue: 999)))
    }

    func testASTArenaExprSequentialIDs() {
        let r = makeRange(start: 0, end: 5)
        let arena = ASTArena()
        let id0 = arena.appendExpr(.intLiteral(1, r))
        let id1 = arena.appendExpr(.intLiteral(2, r))
        let id2 = arena.appendExpr(.intLiteral(3, r))
        XCTAssertEqual(id0.rawValue, 0)
        XCTAssertEqual(id1.rawValue, 1)
        XCTAssertEqual(id2.rawValue, 2)
    }

    func testASTArenaExprWithMultipleTypes() {
        let interner = StringInterner()
        let r = makeRange(start: 0, end: 10)
        let arena = ASTArena()
        let intID = arena.appendExpr(.intLiteral(1, r))
        let boolID = arena.appendExpr(.boolLiteral(false, r))
        let strID = arena.appendExpr(.stringLiteral(interner.intern("test"), r))
        let breakID = arena.appendExpr(.breakExpr(label: nil, range: r))

        if case .intLiteral = arena.expr(intID) {} else { XCTFail("Expected .intLiteral") }
        if case .boolLiteral = arena.expr(boolID) {} else { XCTFail("Expected .boolLiteral") }
        if case .stringLiteral = arena.expr(strID) {} else { XCTFail("Expected .stringLiteral") }
        if case .breakExpr = arena.expr(breakID) {} else { XCTFail("Expected .breakExpr") }
    }
}

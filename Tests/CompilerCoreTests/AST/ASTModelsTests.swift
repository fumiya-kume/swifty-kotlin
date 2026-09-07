#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct ASTModelsTests {
    @Test
    func testIDInitializersSupportDefaultAndExplicitValues() {
        #expect(ASTNodeID() == .invalid)
        #expect(ExprID() == .invalid)
        #expect(TypeRefID() == .invalid)

        #expect(ASTNodeID(rawValue: 10).rawValue == 10)
        #expect(ExprID(rawValue: 11).rawValue == 11)
        #expect(TypeRefID(rawValue: 12).rawValue == 12)
    }

    @Test
    func testFunDeclInitializerAppliesDefaults() {
        let interner = StringInterner()
        let name = interner.intern("run")
        let decl = FunDecl(
            range: makeRange(start: 1, end: 5),
            name: name,
            modifiers: [.public]
        )

        #expect(decl.name == name)
        #expect(decl.typeParams.isEmpty)
        #expect(decl.receiverType == nil)
        #expect(decl.valueParams.isEmpty)
        #expect(decl.returnType == nil)
        #expect(decl.body == .unit)
        #expect(!(decl.isSuspend))
        #expect(!(decl.isInline))
    }

    @Test
    func testModifiersOptionSetComposition() {
        let modifiers: Modifiers = [.public, .inline, .operator, .tailrec]

        #expect(modifiers.contains(.public))
        #expect(modifiers.contains(.inline))
        #expect(modifiers.contains(.operator))
        #expect(modifiers.contains(.tailrec))
        #expect(!(modifiers.contains(.private)))
    }

    @Test
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

        #expect(classID.rawValue == 0)
        #expect(propertyID.rawValue == 1)
        #expect(arena.decl(classID) != nil)
        #expect(arena.decl(propertyID) != nil)
        #expect(arena.decl(DeclID(rawValue: -1)) == nil)
        #expect(arena.decl(DeclID(rawValue: 999)) == nil)
        #expect(arena.declarations().count == 2)

        let typeRefID = arena.appendTypeRef(.named(path: [interner.intern("Int")], args: [], nullable: false))
        #expect(typeRefID.rawValue == 0)
        #expect(arena.typeRef(typeRefID) != nil)
        #expect(arena.typeRef(TypeRefID(rawValue: 999)) == nil)
    }

    @Test
    func testDeclModelStructInitializers() {
        let interner = StringInterner()
        let range = makeRange(start: 5, end: 9)
        let typeRef = TypeRefID(rawValue: 4)

        let objectDecl = ObjectDecl(range: range, name: interner.intern("Name"), modifiers: [.public])
        #expect(objectDecl.name == interner.intern("Name"))

        let typeAliasDecl = TypeAliasDecl(range: range, name: interner.intern("Alias"), modifiers: [.internal])
        #expect(typeAliasDecl.modifiers == [.internal])

        let enumEntryDecl = EnumEntryDecl(range: range, name: interner.intern("Entry"))
        #expect(enumEntryDecl.range == range)

        let importDecl = ImportDecl(
            range: range,
            path: [interner.intern("kotlin"), interner.intern("collections")],
            alias: nil
        )
        #expect(importDecl.path.count == 2)
        #expect(importDecl.alias == nil)

        let aliasedImport = ImportDecl(
            range: range,
            path: [interner.intern("kotlin"), interner.intern("collections"), interner.intern("List")],
            alias: interner.intern("KList")
        )
        #expect(aliasedImport.alias == interner.intern("KList"))
        #expect(aliasedImport.path.count == 3)

        let typeParam = TypeParamDecl(name: interner.intern("T"), upperBounds: [])
        #expect(typeParam.name == interner.intern("T"))

        let valueParam = ValueParamDecl(name: interner.intern("value"), type: typeRef)
        #expect(valueParam.type == typeRef)
    }

    @Test
    func testASTFileInitializer() {
        let interner = StringInterner()
        let range = makeRange(start: 5, end: 9)
        let importDecl = ImportDecl(
            range: range,
            path: [interner.intern("kotlin"), interner.intern("collections")],
            alias: nil
        )

        let file = ASTFile(
            fileID: FileID(rawValue: 1),
            packageFQName: [interner.intern("pkg")],
            imports: [importDecl],
            topLevelDecls: [DeclID(rawValue: 0)],
            scriptBody: []
        )
        #expect(file.fileID == FileID(rawValue: 1))
        #expect(file.packageFQName.count == 1)
        #expect(file.imports.count == 1)
        #expect(file.topLevelDecls.count == 1)
    }

    @Test
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
        #expect(fullModule.files.count == 1)
        #expect(fullModule.declarationCount == 7)
        #expect(fullModule.tokenCount == 13)

        let compactModule = ASTModule(declarationCount: 2, tokenCount: 3)
        #expect(compactModule.files.isEmpty)
        #expect(compactModule.declarationCount == 2)
        #expect(compactModule.tokenCount == 3)
    }

    @Test
    func testExprRangeReturnsRangeForAllExprCases() {
        let interner = StringInterner()
        let arena = ASTArena()
        let range = makeRange(start: 0, end: 10)
        let dummyExprID = arena.appendExpr(.intLiteral(42, range))
        let dummyTypeRefID = arena.appendTypeRef(.named(path: [interner.intern("Int")], args: [], nullable: false))
        let name = interner.intern("x")

        let cases: [Expr] = [
            .intLiteral(1, range),
            .longLiteral(1, range),
            .floatLiteral(1.0, range),
            .doubleLiteral(1.0, range),
            .charLiteral(65, range),
            .boolLiteral(true, range),
            .stringLiteral(name, range),
            .nameRef(name, range),
            .forExpr(
                loopVariable: name,
                iterable: dummyExprID,
                body: dummyExprID,
                range: range
            ),
            .whileExpr(
                condition: dummyExprID,
                body: dummyExprID,
                range: range
            ),
            .doWhileExpr(
                body: dummyExprID,
                condition: dummyExprID,
                range: range
            ),
            .breakExpr(label: nil, range: range),
            .continueExpr(label: nil, range: range),
            .localDecl(
                name: name,
                isMutable: false,
                typeAnnotation: nil,
                initializer: dummyExprID,
                range: range
            ),
            .localAssign(name: name, value: dummyExprID, range: range),
            .indexedAssign(
                receiver: dummyExprID,
                indices: [dummyExprID],
                value: dummyExprID,
                range: range
            ),
            .call(callee: dummyExprID, typeArgs: [], args: [], range: range),
            .memberCall(
                receiver: dummyExprID,
                callee: name,
                typeArgs: [],
                args: [],
                range: range
            ),
            .indexedAccess(
                receiver: dummyExprID,
                indices: [dummyExprID],
                range: range
            ),
            .binary(
                op: .add,
                lhs: dummyExprID,
                rhs: dummyExprID,
                range: range
            ),
            .whenExpr(
                subject: dummyExprID,
                branches: [],
                elseExpr: nil,
                range: range
            ),
            .returnExpr(value: nil, range: range),
            .ifExpr(
                condition: dummyExprID,
                thenExpr: dummyExprID,
                elseExpr: nil,
                range: range
            ),
            .tryExpr(
                body: dummyExprID,
                catchClauses: [],
                finallyExpr: nil,
                range: range
            ),
            .unaryExpr(
                op: .not,
                operand: dummyExprID,
                range: range
            ),
            .isCheck(
                expr: dummyExprID,
                type: dummyTypeRefID,
                negated: false,
                range: range
            ),
            .asCast(
                expr: dummyExprID,
                type: dummyTypeRefID,
                isSafe: true,
                range: range
            ),
            .nullAssert(expr: dummyExprID, range: range),
            .safeMemberCall(
                receiver: dummyExprID,
                callee: name,
                typeArgs: [],
                args: [],
                range: range
            ),
            .compoundAssign(
                op: .plusAssign,
                name: name,
                value: dummyExprID,
                range: range
            ),
            .throwExpr(value: dummyExprID, range: range),
            .lambdaLiteral(
                params: [name],
                body: dummyExprID,
                range: range
            ),
            .objectLiteral(
                superTypes: [dummyTypeRefID],
                decl: nil,
                range: range
            ),
            .callableRef(
                receiver: dummyExprID,
                member: name,
                range: range
            ),
            .localFunDecl(
                name: name,
                valueParams: [],
                returnType: nil,
                body: .unit,
                isSuspend: false,
                range: range
            ),
        ]

        for (index, exprCase) in cases.enumerated() {
            let id = arena.appendExpr(exprCase)
            #expect(arena.exprRange(id) == range, "Expr case at index \(index) failed")
        }
    }

    @Test
    func testExprRangeReturnsNilForInvalidID() {
        let arena = ASTArena()
        #expect(arena.exprRange(ExprID(rawValue: -1)) == nil)
        #expect(arena.exprRange(ExprID(rawValue: 999)) == nil)
    }

    @Test
    func testSortedFilesReturnsByFileID() {
        let arena = ASTArena()
        let file0 = ASTFile(fileID: FileID(rawValue: 2), packageFQName: [], imports: [], topLevelDecls: [], scriptBody: [])
        let file1 = ASTFile(fileID: FileID(rawValue: 0), packageFQName: [], imports: [], topLevelDecls: [], scriptBody: [])
        let file2 = ASTFile(fileID: FileID(rawValue: 1), packageFQName: [], imports: [], topLevelDecls: [], scriptBody: [])
        let module = ASTModule(files: [file0, file1, file2], arena: arena, declarationCount: 0, tokenCount: 0)
        let sorted = module.sortedFiles
        #expect(sorted[0].fileID == FileID(rawValue: 0))
        #expect(sorted[1].fileID == FileID(rawValue: 1))
        #expect(sorted[2].fileID == FileID(rawValue: 2))
    }

    @Test
    func testTypeRefFunctionTypeLookup() {
        let arena = ASTArena()
        let paramTypeRef = arena.appendTypeRef(.named(path: [], args: [], nullable: false))
        let returnTypeRef = arena.appendTypeRef(.named(path: [], args: [], nullable: false))
        let funcTypeID = arena.appendTypeRef(.functionType(contextReceivers: [], receiver: nil, params: [paramTypeRef], returnType: returnTypeRef, isSuspend: true, nullable: false))
        if case let .functionType(contextReceivers, _, params, ret, suspend, nullable) = arena.typeRef(funcTypeID) {
            #expect(contextReceivers.isEmpty)
            #expect(params.count == 1)
            #expect(ret == returnTypeRef)
            #expect(suspend)
            #expect(!(nullable))
        } else {
            Issue.record("Expected .functionType")
        }
    }

    @Test
    func testTypeArgRefCases() {
        let typeRef = TypeRefID(rawValue: 0)
        let invariant = TypeArgRef.invariant(typeRef)
        let outArg = TypeArgRef.out(typeRef)
        let inArg = TypeArgRef.in(typeRef)
        let star = TypeArgRef.star
        #expect(invariant != star)
        #expect(outArg != inArg)
    }

    @Test
    func testPropertyAccessorDeclSetterWithExprBody() {
        let interner = StringInterner()
        let range = makeRange(start: 0, end: 5)
        let exprID = ExprID(rawValue: 0)
        let name = interner.intern("x")

        let setter = PropertyAccessorDecl(range: range, kind: .setter, parameterName: name, body: .expr(exprID, range))
        #expect(setter.kind == .setter)
        #expect(setter.parameterName == name)
        if case let .expr(expr, _) = setter.body {
            #expect(expr == exprID)
        } else {
            Issue.record("Expected .expr body")
        }
    }

    @Test
    func testPropertyDeclWithAllFields() {
        let interner = StringInterner()
        let range = makeRange(start: 0, end: 5)
        let typeRef = TypeRefID(rawValue: 0)
        let exprID = ExprID(rawValue: 0)
        let name = interner.intern("x")

        let getter = PropertyAccessorDecl(range: range, kind: .getter)
        let setter = PropertyAccessorDecl(range: range, kind: .setter, parameterName: name, body: .expr(exprID, range))
        let propDecl = PropertyDecl(
            range: range, name: name, modifiers: [.public], type: typeRef,
            isVar: true, initializer: exprID, getter: getter, setter: setter, delegateExpression: exprID
        )
        #expect(propDecl.isVar)
        #expect(propDecl.getter?.kind == .getter)
        #expect(propDecl.setter?.kind == .setter)
        #expect(propDecl.delegateExpression == exprID)
    }

    @Test
    func testValueParamDeclWithDefaultAndVararg() {
        let interner = StringInterner()
        let typeRef = TypeRefID(rawValue: 0)
        let exprID = ExprID(rawValue: 0)
        let name = interner.intern("x")

        let param = ValueParamDecl(name: name, type: typeRef, hasDefaultValue: true, isVararg: true, defaultValue: exprID)
        #expect(param.hasDefaultValue)
        #expect(param.isVararg)
        #expect(param.defaultValue == exprID)
    }

    @Test
    func testTypeParamDeclWithVarianceAndBound() {
        let interner = StringInterner()
        let typeRef = TypeRefID(rawValue: 0)
        let name = interner.intern("x")

        let typeParam = TypeParamDecl(name: name, variance: .out, isReified: true, upperBounds: [typeRef])
        #expect(typeParam.variance == .out)
        #expect(typeParam.isReified)
        #expect(typeParam.upperBounds.first == typeRef)
    }

    @Test
    func testFunDeclWithAllExplicitFields() {
        let interner = StringInterner()
        let range = makeRange(start: 0, end: 5)
        let typeRef = TypeRefID(rawValue: 0)
        let exprID = ExprID(rawValue: 0)
        let name = interner.intern("x")

        let typeParam = TypeParamDecl(name: name, variance: .out, isReified: true, upperBounds: [typeRef])
        let param = ValueParamDecl(name: name, type: typeRef, hasDefaultValue: true, isVararg: true, defaultValue: exprID)
        let funDecl = FunDecl(
            range: range, name: name, modifiers: [.suspend, .inline],
            typeParams: [typeParam], receiverType: typeRef, valueParams: [param],
            returnType: typeRef, body: .block([exprID], range), isSuspend: true, isInline: true
        )
        #expect(funDecl.isSuspend)
        #expect(funDecl.isInline)
        #expect(funDecl.receiverType == typeRef)
        #expect(funDecl.returnType == typeRef)
        #expect(funDecl.typeParams.count == 1)
    }

    @Test
    func testInterfaceDeclWithTypeParamsAndSuperTypes() {
        let interner = StringInterner()
        let range = makeRange(start: 0, end: 5)
        let typeRef = TypeRefID(rawValue: 0)
        let name = interner.intern("x")

        let typeParam = TypeParamDecl(name: name, variance: .out, isReified: true, upperBounds: [typeRef])
        let alias = TypeAliasDecl(range: range, name: name, modifiers: [], typeParams: [typeParam], underlyingType: typeRef)
        #expect(alias.underlyingType == typeRef)
        let iface = InterfaceDecl(
            range: range, name: name, modifiers: [],
            typeParams: [typeParam], superTypes: [typeRef], nestedTypeAliases: [alias]
        )
        #expect(iface.typeParams.count == 1)
        #expect(iface.superTypes.count == 1)
        #expect(iface.nestedTypeAliases.count == 1)
    }

    @Test
    func testWhenBranchCallArgumentAndCatchClauseInit() {
        let interner = StringInterner()
        let range = makeRange(start: 0, end: 5)
        let exprID = ExprID(rawValue: 0)
        let name = interner.intern("x")

        let branch = WhenBranch(conditions: [exprID], body: exprID, range: range)
        #expect(branch.conditions.first == exprID)
        let callArg = CallArgument(label: name, isSpread: true, expr: exprID)
        #expect(callArg.label == name)
        #expect(callArg.isSpread)
        let catchClause = CatchClause(paramName: name, paramTypeName: name, body: exprID, range: range)
        #expect(catchClause.paramName == name)
        #expect(catchClause.paramTypeName == name)
    }

    // MARK: - Expr variants

    // MARK: - ASTArena expr() method
}
#endif

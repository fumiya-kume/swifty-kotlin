// MARK: - Builder DSL Helpers (STDLIB-002)

extension CallTypeChecker {
    private enum BuilderDSLArgumentShape {
        case unary([TypeID])
        case keyed([(key: TypeID, value: TypeID)])
    }

    func builderDSLKind(for name: InternedString, interner: StringInterner) -> BuilderDSLKind? {
        let knownNames = KnownCompilerNames(interner: interner)
        switch name {
        case knownNames.buildString:
            return .buildString
        case knownNames.buildList:
            return .buildList
        case knownNames.buildMap:
            return .buildMap
        case knownNames.buildSet:
            return .buildSet
        default:
            return nil
        }
    }

    func shouldUseBuilderDSLSpecialHandling(
        calleeName: InternedString,
        ctx: TypeInferenceContext,
        locals: LocalBindings
    ) -> Bool {
        if locals[calleeName] != nil {
            return false
        }
        // Use builder DSL handling when no user-defined (non-synthetic) symbol is in scope.
        // Synthetic stubs (e.g. kotlin.collections.buildList) are allowed.
        if ctx.cachedScopeLookup(calleeName).contains(where: { candidate in
            guard let sym = ctx.cachedSymbol(candidate) else { return false }
            return !sym.flags.contains(.synthetic)
        }) {
            return false
        }
        return true
    }

    func isValidBuilderLambdaArgument(_ argumentExprID: ExprID, ast: ASTModule) -> Bool {
        guard let argumentExpr = ast.arena.expr(argumentExprID),
              case let .lambdaLiteral(params, _, _, _) = argumentExpr
        else {
            return false
        }
        return params.isEmpty
    }

    func builderDSLReceiverType(
        kind: BuilderDSLKind,
        lambdaExprID: ExprID,
        expectedType: TypeID?,
        ctx: TypeInferenceContext,
        locals: LocalBindings,
        sema: SemaModule,
        interner: StringInterner
    ) -> TypeID {
        switch kind {
        case .buildString:
            return ensureSyntheticStringBuilderType(sema: sema, interner: interner)
        case .buildList:
            let elementType = builderDSLListElementType(
                lambdaExprID: lambdaExprID,
                expectedType: expectedType,
                ctx: ctx,
                locals: locals,
                sema: sema,
                interner: interner
            )
            let mutableListFQName: [InternedString] = [
                interner.intern("kotlin"),
                interner.intern("collections"),
                interner.intern("MutableList"),
            ]
            guard let mutableListSymbol = sema.symbols.lookup(fqName: mutableListFQName) else {
                return sema.types.anyType
            }
            return sema.types.make(.classType(ClassType(
                classSymbol: mutableListSymbol,
                args: [.invariant(elementType)],
                nullability: .nonNull
            )))
        case .buildMap:
            let (keyType, valueType) = builderDSLMapElementTypes(
                lambdaExprID: lambdaExprID,
                expectedType: expectedType,
                ctx: ctx,
                locals: locals,
                sema: sema,
                interner: interner
            )
            let mutableMapFQName: [InternedString] = [
                interner.intern("kotlin"),
                interner.intern("collections"),
                interner.intern("MutableMap"),
            ]
            guard let mutableMapSymbol = sema.symbols.lookup(fqName: mutableMapFQName) else {
                return sema.types.anyType
            }
            return sema.types.make(.classType(ClassType(
                classSymbol: mutableMapSymbol,
                args: [.invariant(keyType), .invariant(valueType)],
                nullability: .nonNull
            )))
        case .buildSet:
            let elementType = builderDSLSetElementType(lambdaExprID: lambdaExprID, expectedType: expectedType, ctx: ctx, locals: locals, sema: sema, interner: interner)
            let mutableSetFQName: [InternedString] = [interner.intern("kotlin"), interner.intern("collections"), interner.intern("MutableSet")]
            guard let mutableSetSymbol = sema.symbols.lookup(fqName: mutableSetFQName) else { return sema.types.anyType }
            return sema.types.make(.classType(ClassType(classSymbol: mutableSetSymbol, args: [.invariant(elementType)], nullability: .nonNull)))
        }
    }

    private func builderDSLListElementType(
        lambdaExprID: ExprID,
        expectedType: TypeID?,
        ctx: TypeInferenceContext,
        locals: LocalBindings,
        sema: SemaModule,
        interner: StringInterner
    ) -> TypeID {
        if let expectedElementType = builderDSLExpectedListElementType(
            expectedType,
            sema: sema,
            interner: interner
        ) {
            return expectedElementType
        }
        guard case let .unary(argumentTypes) = builderDSLArgumentShape(
            kind: .buildList,
            lambdaExprID: lambdaExprID,
            ctx: ctx,
            locals: locals,
            sema: sema,
            interner: interner
        ),
            !argumentTypes.isEmpty
        else {
            return sema.types.anyType
        }
        return sema.types.lub(argumentTypes)
    }

    private func builderDSLMapElementTypes(
        lambdaExprID: ExprID,
        expectedType: TypeID?,
        ctx: TypeInferenceContext,
        locals: LocalBindings,
        sema: SemaModule,
        interner: StringInterner
    ) -> (TypeID, TypeID) {
        if let expectedTypes = builderDSLExpectedMapElementTypes(
            expectedType,
            sema: sema,
            interner: interner
        ) {
            return expectedTypes
        }
        guard case let .keyed(argumentPairs) = builderDSLArgumentShape(
            kind: .buildMap,
            lambdaExprID: lambdaExprID,
            ctx: ctx,
            locals: locals,
            sema: sema,
            interner: interner
        ),
            !argumentPairs.isEmpty
        else {
            return (sema.types.anyType, sema.types.anyType)
        }
        let keyTypes = argumentPairs.map(\.key)
        let valueTypes = argumentPairs.map(\.value)
        return (sema.types.lub(keyTypes), sema.types.lub(valueTypes))
    }

    private func builderDSLExpectedListElementType(
        _ expectedType: TypeID?,
        sema: SemaModule,
        interner: StringInterner
    ) -> TypeID? {
        let knownNames = KnownCompilerNames(interner: interner)
        guard let expectedType else {
            return nil
        }
        guard case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(expectedType)),
              let symbol = sema.symbols.symbol(classType.classSymbol),
              symbol.fqName == knownNames.kotlinCollectionsListFQName
              || symbol.fqName == knownNames.kotlinCollectionsMutableListFQName,
              let firstArg = classType.args.first
        else {
            return nil
        }
        switch firstArg {
        case let .invariant(type), let .out(type), let .in(type):
            return type
        case .star:
            return sema.types.anyType
        }
    }

    private func builderDSLExpectedMapElementTypes(
        _ expectedType: TypeID?,
        sema: SemaModule,
        interner: StringInterner
    ) -> (TypeID, TypeID)? {
        let knownNames = KnownCompilerNames(interner: interner)
        guard let expectedType else {
            return nil
        }
        guard case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(expectedType)),
              let symbol = sema.symbols.symbol(classType.classSymbol),
              symbol.fqName == knownNames.kotlinCollectionsMapFQName
              || symbol.fqName == knownNames.kotlinCollectionsMutableMapFQName,
              classType.args.count >= 2
        else {
            return nil
        }

        let keyType: TypeID = switch classType.args[0] {
        case let .invariant(type), let .out(type), let .in(type):
            type
        case .star:
            sema.types.anyType
        }
        let valueType: TypeID = switch classType.args[1] {
        case let .invariant(type), let .out(type), let .in(type):
            type
        case .star:
            sema.types.anyType
        }
        return (keyType, valueType)
    }

    private func builderDSLArgumentShape(
        kind: BuilderDSLKind,
        lambdaExprID: ExprID,
        ctx: TypeInferenceContext,
        locals: LocalBindings,
        sema: SemaModule,
        interner: StringInterner
    ) -> BuilderDSLArgumentShape {
        guard case let .lambdaLiteral(_, bodyExprID, _, _) = ctx.ast.arena.expr(lambdaExprID) else {
            return kind == .buildMap ? .keyed([]) : .unary([])
        }
        var unaryArgumentExprs: [ExprID] = []
        var keyedArgumentExprs: [(ExprID, ExprID)] = []
        collectBuilderDSLArgumentExprs(
            in: bodyExprID,
            kind: kind,
            ast: ctx.ast,
            interner: interner,
            unary: &unaryArgumentExprs,
            keyed: &keyedArgumentExprs
        )

        var previewLocals = locals
        switch kind {
        case .buildString:
            return .unary([])
        case .buildList, .buildSet:
            let argumentTypes = unaryArgumentExprs.compactMap { exprID -> TypeID? in
                let inferredType = driver.inferExpr(exprID, ctx: ctx, locals: &previewLocals)
                return inferredType == sema.types.errorType ? nil : inferredType
            }
            return .unary(argumentTypes)
        case .buildMap:
            let pairs = keyedArgumentExprs.compactMap { keyExprID, valueExprID -> (TypeID, TypeID)? in
                let keyType = driver.inferExpr(keyExprID, ctx: ctx, locals: &previewLocals)
                let valueType = driver.inferExpr(valueExprID, ctx: ctx, locals: &previewLocals)
                guard keyType != sema.types.errorType, valueType != sema.types.errorType else {
                    return nil
                }
                return (keyType, valueType)
            }
            return .keyed(pairs)
        }
    }

    // swiftlint:disable:next cyclomatic_complexity
    private func collectBuilderDSLArgumentExprs(
        in exprID: ExprID,
        kind: BuilderDSLKind,
        ast: ASTModule,
        interner: StringInterner,
        unary: inout [ExprID],
        keyed: inout [(ExprID, ExprID)]
    ) {
        guard let expr = ast.arena.expr(exprID) else {
            return
        }

        switch expr {
        case let .call(callee, _, args, _):
            if case let .nameRef(name, _) = ast.arena.expr(callee),
               isMatchingBuilderDSLFunctionName(interner.resolve(name), kind: kind)
            {
                if (kind == .buildList || kind == .buildSet), let first = args.first {
                    unary.append(first.expr)
                } else if kind == .buildMap, args.count >= 2 {
                    keyed.append((args[0].expr, args[1].expr))
                }
            }
            collectBuilderDSLArgumentExprs(in: callee, kind: kind, ast: ast, interner: interner, unary: &unary, keyed: &keyed)
            for argument in args {
                collectBuilderDSLArgumentExprs(in: argument.expr, kind: kind, ast: ast, interner: interner, unary: &unary, keyed: &keyed)
            }
        case let .memberCall(receiver, callee, _, args, _):
            if isMatchingBuilderDSLFunctionName(interner.resolve(callee), kind: kind),
               case .thisRef = ast.arena.expr(receiver)
            {
                if (kind == .buildList || kind == .buildSet), let first = args.first {
                    unary.append(first.expr)
                } else if kind == .buildMap, args.count >= 2 {
                    keyed.append((args[0].expr, args[1].expr))
                }
            }
            collectBuilderDSLArgumentExprs(in: receiver, kind: kind, ast: ast, interner: interner, unary: &unary, keyed: &keyed)
            for argument in args {
                collectBuilderDSLArgumentExprs(in: argument.expr, kind: kind, ast: ast, interner: interner, unary: &unary, keyed: &keyed)
            }
        case let .safeMemberCall(receiver, _, _, args, _):
            collectBuilderDSLArgumentExprs(in: receiver, kind: kind, ast: ast, interner: interner, unary: &unary, keyed: &keyed)
            for argument in args {
                collectBuilderDSLArgumentExprs(in: argument.expr, kind: kind, ast: ast, interner: interner, unary: &unary, keyed: &keyed)
            }
        case let .blockExpr(statements, trailingExpr, _):
            for statement in statements {
                collectBuilderDSLArgumentExprs(in: statement, kind: kind, ast: ast, interner: interner, unary: &unary, keyed: &keyed)
            }
            if let trailingExpr {
                collectBuilderDSLArgumentExprs(in: trailingExpr, kind: kind, ast: ast, interner: interner, unary: &unary, keyed: &keyed)
            }
        case let .ifExpr(condition, thenExpr, elseExpr, _):
            collectBuilderDSLArgumentExprs(in: condition, kind: kind, ast: ast, interner: interner, unary: &unary, keyed: &keyed)
            collectBuilderDSLArgumentExprs(in: thenExpr, kind: kind, ast: ast, interner: interner, unary: &unary, keyed: &keyed)
            if let elseExpr {
                collectBuilderDSLArgumentExprs(in: elseExpr, kind: kind, ast: ast, interner: interner, unary: &unary, keyed: &keyed)
            }
        case let .whenExpr(subject, branches, elseExpr, _):
            if let subject {
                collectBuilderDSLArgumentExprs(in: subject, kind: kind, ast: ast, interner: interner, unary: &unary, keyed: &keyed)
            }
            for branch in branches {
                for condition in branch.conditions {
                    collectBuilderDSLArgumentExprs(in: condition, kind: kind, ast: ast, interner: interner, unary: &unary, keyed: &keyed)
                }
                collectBuilderDSLArgumentExprs(in: branch.body, kind: kind, ast: ast, interner: interner, unary: &unary, keyed: &keyed)
            }
            if let elseExpr {
                collectBuilderDSLArgumentExprs(in: elseExpr, kind: kind, ast: ast, interner: interner, unary: &unary, keyed: &keyed)
            }
        case let .tryExpr(body, catchClauses, finallyExpr, _):
            collectBuilderDSLArgumentExprs(in: body, kind: kind, ast: ast, interner: interner, unary: &unary, keyed: &keyed)
            for catchClause in catchClauses {
                collectBuilderDSLArgumentExprs(in: catchClause.body, kind: kind, ast: ast, interner: interner, unary: &unary, keyed: &keyed)
            }
            if let finallyExpr {
                collectBuilderDSLArgumentExprs(in: finallyExpr, kind: kind, ast: ast, interner: interner, unary: &unary, keyed: &keyed)
            }
        case let .binary(_, lhs, rhs, _),
             let .inExpr(lhs, rhs, _),
             let .notInExpr(lhs, rhs, _):
            collectBuilderDSLArgumentExprs(in: lhs, kind: kind, ast: ast, interner: interner, unary: &unary, keyed: &keyed)
            collectBuilderDSLArgumentExprs(in: rhs, kind: kind, ast: ast, interner: interner, unary: &unary, keyed: &keyed)
        case let .unaryExpr(_, operand, _),
             let .nullAssert(operand, _),
             let .throwExpr(operand, _),
             let .returnExpr(operand?, _, _):
            collectBuilderDSLArgumentExprs(in: operand, kind: kind, ast: ast, interner: interner, unary: &unary, keyed: &keyed)
        case let .localDecl(_, _, _, initializer, _, _):
            if let initializer {
                collectBuilderDSLArgumentExprs(in: initializer, kind: kind, ast: ast, interner: interner, unary: &unary, keyed: &keyed)
            }
        case let .localAssign(_, value, _),
             let .memberAssign(_, _, value, _):
            collectBuilderDSLArgumentExprs(in: value, kind: kind, ast: ast, interner: interner, unary: &unary, keyed: &keyed)
        default:
            break
        }
    }

    private func isMatchingBuilderDSLFunctionName(_ name: String, kind: BuilderDSLKind) -> Bool {
        switch kind {
        case .buildString:
            name == "append"
        case .buildList, .buildSet:
            name == "add"
        case .buildMap:
            name == "put"
        }
    }

    /// Returns `Map<K, V>` for `buildMap` where K, V are extracted from `MutableMap<K, V>` receiver type.
    func builderDSLBuildMapReturnType(
        receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> TypeID {
        let mutableMapFQName: [InternedString] = [
            interner.intern("kotlin"),
            interner.intern("collections"),
            interner.intern("MutableMap"),
        ]
        let mapFQName: [InternedString] = [
            interner.intern("kotlin"),
            interner.intern("collections"),
            interner.intern("Map"),
        ]
        guard let mutableMapSymbol = sema.symbols.lookup(fqName: mutableMapFQName),
              let mapSymbol = sema.symbols.lookup(fqName: mapFQName)
        else {
            return sema.types.anyType
        }
        let (keyType, valueType): (TypeID, TypeID) = if case let .classType(ct) = sema.types.kind(of: receiverType),
                                                        ct.classSymbol == mutableMapSymbol,
                                                        ct.args.count >= 2,
                                                        case let .invariant(k) = ct.args[0],
                                                        case let .invariant(v) = ct.args[1]
        {
            (k, v)
        } else {
            (sema.types.anyType, sema.types.anyType)
        }
        return sema.types.make(.classType(ClassType(
            classSymbol: mapSymbol,
            args: [.out(keyType), .out(valueType)],
            nullability: .nonNull
        )))
    }

    /// Returns `List<E>` for `buildList` where E is extracted from `MutableList<E>` receiver type.
    func builderDSLBuildListReturnType(
        receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> TypeID {
        let mutableListFQName: [InternedString] = [
            interner.intern("kotlin"),
            interner.intern("collections"),
            interner.intern("MutableList"),
        ]
        let listFQName: [InternedString] = [
            interner.intern("kotlin"),
            interner.intern("collections"),
            interner.intern("List"),
        ]
        guard let mutableListSymbol = sema.symbols.lookup(fqName: mutableListFQName),
              let listSymbol = sema.symbols.lookup(fqName: listFQName)
        else {
            return sema.types.anyType
        }
        let elementType: TypeID = if case let .classType(ct) = sema.types.kind(of: receiverType),
                                     ct.classSymbol == mutableListSymbol,
                                     let firstArg = ct.args.first,
                                     case let .invariant(elemType) = firstArg
        {
            elemType
        } else {
            sema.types.anyType
        }
        return sema.types.make(.classType(ClassType(
            classSymbol: listSymbol,
            args: [.out(elementType)],
            nullability: .nonNull
        )))
    }

    /// Returns `Set<E>` for `buildSet` where E is extracted from `MutableSet<E>` receiver type.
    func builderDSLBuildSetReturnType(receiverType: TypeID, sema: SemaModule, interner: StringInterner) -> TypeID {
        let mutableSetFQName: [InternedString] = [interner.intern("kotlin"), interner.intern("collections"), interner.intern("MutableSet")]
        let setFQName: [InternedString] = [interner.intern("kotlin"), interner.intern("collections"), interner.intern("Set")]
        guard let mutableSetSymbol = sema.symbols.lookup(fqName: mutableSetFQName),
              let setSymbol = sema.symbols.lookup(fqName: setFQName) else { return sema.types.anyType }
        let elementType: TypeID = if case let .classType(ct) = sema.types.kind(of: receiverType),
                                     ct.classSymbol == mutableSetSymbol, let firstArg = ct.args.first,
                                     case let .invariant(elemType) = firstArg { elemType } else { sema.types.anyType }
        return sema.types.make(.classType(ClassType(classSymbol: setSymbol, args: [.out(elementType)], nullability: .nonNull)))
    }

    private func builderDSLSetElementType(lambdaExprID: ExprID, expectedType: TypeID?, ctx: TypeInferenceContext, locals: LocalBindings, sema: SemaModule, interner: StringInterner) -> TypeID {
        if let expectedElementType = builderDSLExpectedSetElementType(expectedType, sema: sema, interner: interner) { return expectedElementType }
        guard case let .unary(argumentTypes) = builderDSLArgumentShape(kind: .buildSet, lambdaExprID: lambdaExprID, ctx: ctx, locals: locals, sema: sema, interner: interner), !argumentTypes.isEmpty else { return sema.types.anyType }
        return sema.types.lub(argumentTypes)
    }

    private func builderDSLExpectedSetElementType(_ expectedType: TypeID?, sema: SemaModule, interner: StringInterner) -> TypeID? {
        let knownNames = KnownCompilerNames(interner: interner)
        guard let expectedType else { return nil }
        guard case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(expectedType)),
              let symbol = sema.symbols.symbol(classType.classSymbol),
              symbol.fqName == knownNames.kotlinCollectionsSetFQName || symbol.fqName == knownNames.kotlinCollectionsMutableSetFQName,
              let firstArg = classType.args.first else { return nil }
        switch firstArg {
        case let .invariant(type), let .out(type), let .in(type): return type
        case .star: return sema.types.anyType
        }
    }

    func ensureSyntheticStringBuilderType(
        sema: SemaModule,
        interner: StringInterner
    ) -> TypeID {
        let symbols = sema.symbols
        let kotlinPkg: [InternedString] = [interner.intern("kotlin")]
        let kotlinTextPkg: [InternedString] = kotlinPkg + [interner.intern("text")]
        _ = ensureSyntheticPackage(fqName: kotlinPkg, symbols: symbols)
        _ = ensureSyntheticPackage(fqName: kotlinTextPkg, symbols: symbols)

        let stringBuilderName = interner.intern("StringBuilder")
        let stringBuilderFQName = kotlinTextPkg + [stringBuilderName]
        let stringBuilderSymbol: SymbolID = if let existing = symbols.lookup(fqName: stringBuilderFQName) {
            existing
        } else {
            symbols.define(
                kind: .class,
                name: stringBuilderName,
                fqName: stringBuilderFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }
        return sema.types.make(.classType(ClassType(
            classSymbol: stringBuilderSymbol,
            args: [],
            nullability: .nonNull
        )))
    }

    func ensureSyntheticPackage(
        fqName: [InternedString],
        symbols: SymbolTable
    ) -> SymbolID {
        if let existing = symbols.lookup(fqName: fqName) {
            return existing
        }
        guard let name = fqName.last else {
            return .invalid
        }
        return symbols.define(
            kind: .package,
            name: name,
            fqName: fqName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
    }
}

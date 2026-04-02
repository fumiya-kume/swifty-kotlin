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
        case knownNames.buildSet:
            return .buildSet
        case knownNames.buildMap:
            return .buildMap
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

    /// Validates that the expression is a lambda literal with at most `maxParams` explicit parameters.
    /// Unlike `isValidBuilderLambdaArgument` (which requires zero params for builder DSL blocks),
    /// this variant is used for lambdas like `DeepRecursiveFunction`'s block which accepts an
    /// explicit parameter (e.g. `{ n -> callRecursive(n - 1) }`).
    func isValidLambdaArgument(_ argumentExprID: ExprID, ast: ASTModule, maxParams: Int) -> Bool {
        guard let argumentExpr = ast.arena.expr(argumentExprID),
              case let .lambdaLiteral(params, _, _, _) = argumentExpr
        else {
            return false
        }
        return params.count <= maxParams
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
        case .buildSet:
            let elementType = builderDSLSetElementType(
                lambdaExprID: lambdaExprID,
                expectedType: expectedType,
                ctx: ctx,
                locals: locals,
                sema: sema,
                interner: interner
            )
            let mutableSetFQName: [InternedString] = [
                interner.intern("kotlin"),
                interner.intern("collections"),
                interner.intern("MutableSet"),
            ]
            guard let mutableSetSymbol = sema.symbols.lookup(fqName: mutableSetFQName) else {
                return sema.types.anyType
            }
            return sema.types.make(.classType(ClassType(
                classSymbol: mutableSetSymbol,
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

    private func builderDSLSetElementType(
        lambdaExprID: ExprID,
        expectedType: TypeID?,
        ctx: TypeInferenceContext,
        locals: LocalBindings,
        sema: SemaModule,
        interner: StringInterner
    ) -> TypeID {
        if let expectedElementType = builderDSLExpectedSetElementType(
            expectedType,
            sema: sema,
            interner: interner
        ) {
            return expectedElementType
        }
        guard case let .unary(argumentTypes) = builderDSLArgumentShape(
            kind: .buildSet,
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

    private func builderDSLExpectedSetElementType(
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
              symbol.fqName == knownNames.kotlinCollectionsSetFQName
              || symbol.fqName == knownNames.kotlinCollectionsMutableSetFQName,
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
                if let guardExpr = branch.guard_ {
                    collectBuilderDSLArgumentExprs(in: guardExpr, kind: kind, ast: ast, interner: interner, unary: &unary, keyed: &keyed)
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
            name == "append" || name == "appendLine" || name == "appendRange"
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

    /// Returns `Set<E>` for `buildSet` where E is extracted from `MutableSet<E>` receiver type.
    func builderDSLBuildSetReturnType(
        receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> TypeID {
        let mutableSetFQName: [InternedString] = [
            interner.intern("kotlin"),
            interner.intern("collections"),
            interner.intern("MutableSet"),
        ]
        let setFQName: [InternedString] = [
            interner.intern("kotlin"),
            interner.intern("collections"),
            interner.intern("Set"),
        ]
        guard let mutableSetSymbol = sema.symbols.lookup(fqName: mutableSetFQName),
              let setSymbol = sema.symbols.lookup(fqName: setFQName)
        else {
            return sema.types.anyType
        }
        let elementType: TypeID = if case let .classType(ct) = sema.types.kind(of: receiverType),
                                     ct.classSymbol == mutableSetSymbol,
                                     let firstArg = ct.args.first,
                                     case let .invariant(elemType) = firstArg
        {
            elemType
        } else {
            sema.types.anyType
        }
        return sema.types.make(.classType(ClassType(
            classSymbol: setSymbol,
            args: [.out(elementType)],
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

    func sequenceBuilderReturnType(
        lambdaExprID: ExprID,
        expectedType: TypeID?,
        ctx: TypeInferenceContext,
        locals: LocalBindings,
        sema: SemaModule,
        interner: StringInterner
    ) -> TypeID {
        let elementType = sequenceBuilderElementType(
            lambdaExprID: lambdaExprID,
            expectedType: expectedType,
            ctx: ctx,
            locals: locals,
            sema: sema,
            interner: interner
        )
        let sequenceFQName: [InternedString] = [
            interner.intern("kotlin"),
            interner.intern("sequences"),
            interner.intern("Sequence"),
        ]
        guard let sequenceSymbol = sema.symbols.lookup(fqName: sequenceFQName) else {
            return sema.types.anyType
        }
        return sema.types.make(.classType(ClassType(
            classSymbol: sequenceSymbol,
            args: [.out(elementType)],
            nullability: .nonNull
        )))
    }

    func sequenceBuilderReceiverType(
        sequenceType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> TypeID {
        let scopeFQName: [InternedString] = [
            interner.intern("kotlin"),
            interner.intern("sequences"),
            interner.intern("SequenceScope"),
        ]
        guard let scopeSymbol = sema.symbols.lookup(fqName: scopeFQName) else {
            return sema.types.anyType
        }
        let elementType: TypeID
        if case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(sequenceType)),
           let firstArg = classType.args.first
        {
            switch firstArg {
            case let .invariant(type), let .out(type), let .in(type):
                elementType = type
            case .star:
                elementType = sema.types.anyType
            }
        } else {
            elementType = sema.types.anyType
        }
        return sema.types.make(.classType(ClassType(
            classSymbol: scopeSymbol,
            args: [.invariant(elementType)],
            nullability: .nonNull
        )))
    }

    func iteratorBuilderReturnType(
        lambdaExprID: ExprID,
        expectedType: TypeID?,
        ctx: TypeInferenceContext,
        locals: LocalBindings,
        sema: SemaModule,
        interner: StringInterner
    ) -> TypeID {
        let elementType = sequenceBuilderElementType(
            lambdaExprID: lambdaExprID,
            expectedType: expectedType,
            ctx: ctx,
            locals: locals,
            sema: sema,
            interner: interner
        )
        let iteratorFQName: [InternedString] = [
            interner.intern("kotlin"),
            interner.intern("collections"),
            interner.intern("Iterator"),
        ]
        guard let iteratorSymbol = sema.symbols.lookup(fqName: iteratorFQName) else {
            return sema.types.anyType
        }
        return sema.types.make(.classType(ClassType(
            classSymbol: iteratorSymbol,
            args: [.out(elementType)],
            nullability: .nonNull
        )))
    }

    func sequenceBuilderLambdaType(
        receiverType: TypeID,
        sema: SemaModule
    ) -> TypeID {
        sema.types.make(.functionType(FunctionType(
            receiver: receiverType,
            params: [],
            returnType: sema.types.unitType,
            isSuspend: true
        )))
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

    private func sequenceBuilderElementType(
        lambdaExprID: ExprID,
        expectedType: TypeID?,
        ctx: TypeInferenceContext,
        locals: LocalBindings,
        sema: SemaModule,
        interner: StringInterner
    ) -> TypeID {
        if let expectedElementType = sequenceBuilderExpectedElementType(
            expectedType,
            sema: sema,
            interner: interner
        ) {
            return expectedElementType
        }
        guard case let .lambdaLiteral(_, bodyExprID, _, _) = ctx.ast.arena.expr(lambdaExprID) else {
            return sema.types.anyType
        }
        var yieldedExprs: [ExprID] = []
        var yieldedCollectionExprs: [ExprID] = []
        collectSequenceBuilderYieldExprs(
            in: bodyExprID,
            ast: ctx.ast,
            interner: interner,
            yielded: &yieldedExprs,
            yieldedCollections: &yieldedCollectionExprs
        )
        // Pre-infer yield argument types when they are not yet in the binding table.
        // This breaks the chicken-and-egg: the lambda body hasn't been fully type-checked
        // yet, so we run a lightweight inference pass on each yield argument before
        // using them to determine the element type T for SequenceScope<T>.
        // We use a snapshot/truncate pattern on the diagnostic engine so that
        // speculative errors (e.g. unresolved loop variables) are discarded.
        var previewLocals = locals
        let diagnosticEngine = ctx.semaCtx.diagnostics
        var elementTypes: [TypeID] = []
        for exprID in yieldedExprs {
            if let cached = sema.bindings.exprType(for: exprID),
               cached != sema.types.errorType {
                elementTypes.append(cached)
                continue
            }
            let snapshot = diagnosticEngine.count
            let inferredType = driver.inferExpr(exprID, ctx: ctx, locals: &previewLocals)
            if inferredType == sema.types.errorType {
                diagnosticEngine.truncate(to: snapshot)
                continue
            }
            // Discard any spurious diagnostics emitted during speculative inference
            // (e.g. "unresolved reference" for loop variables not yet in scope).
            diagnosticEngine.truncate(to: snapshot)
            elementTypes.append(inferredType)
        }
        for exprID in yieldedCollectionExprs {
            let inferredType: TypeID
            if let cached = sema.bindings.exprType(for: exprID),
               cached != sema.types.errorType {
                inferredType = cached
            } else {
                let snapshot = diagnosticEngine.count
                let preInferred = driver.inferExpr(exprID, ctx: ctx, locals: &previewLocals)
                diagnosticEngine.truncate(to: snapshot)
                guard preInferred != sema.types.errorType else {
                    continue
                }
                inferredType = preInferred
            }
            if let elementType = sequenceBuilderCollectionElementType(
                inferredType,
                sema: sema,
                interner: interner
            ) {
                elementTypes.append(elementType)
            }
        }
        guard !elementTypes.isEmpty else {
            return sema.types.anyType
        }
        return sema.types.lub(elementTypes)
    }

    private func sequenceBuilderExpectedElementType(
        _ expectedType: TypeID?,
        sema: SemaModule,
        interner: StringInterner
    ) -> TypeID? {
        guard let expectedType,
              case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(expectedType)),
              let symbol = sema.symbols.symbol(classType.classSymbol)
        else {
            return nil
        }
        let sequenceFQName: [InternedString] = [
            interner.intern("kotlin"),
            interner.intern("sequences"),
            interner.intern("Sequence"),
        ]
        let iteratorFQName: [InternedString] = [
            interner.intern("kotlin"),
            interner.intern("collections"),
            interner.intern("Iterator"),
        ]
        guard symbol.fqName == sequenceFQName || symbol.fqName == iteratorFQName,
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

    private func sequenceBuilderCollectionElementType(
        _ collectionType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> TypeID? {
        let nonNullType = sema.types.makeNonNullable(collectionType)
        if case let .classType(classType) = sema.types.kind(of: nonNullType),
           let symbol = sema.symbols.symbol(classType.classSymbol),
           let simpleName = symbol.fqName.last
        {
            let resolved = interner.resolve(simpleName)
            switch resolved {
            case "List", "MutableList", "Set", "MutableSet", "Collection", "Iterable", "Sequence", "Array":
                guard let firstArg = classType.args.first else {
                    return sema.types.anyType
                }
                switch firstArg {
                case let .invariant(type), let .out(type), let .in(type):
                    return type
                case .star:
                    return sema.types.anyType
                }
            default:
                break
            }
        }
        return nil
    }

    private func collectSequenceBuilderYieldExprs(
        in exprID: ExprID,
        ast: ASTModule,
        interner: StringInterner,
        yielded: inout [ExprID],
        yieldedCollections: inout [ExprID]
    ) {
        guard let expr = ast.arena.expr(exprID) else {
            return
        }
        switch expr {
        case let .call(callee, _, args, _):
            if case let .nameRef(name, _) = ast.arena.expr(callee) {
                let resolved = interner.resolve(name)
                if resolved == "yield", let first = args.first {
                    yielded.append(first.expr)
                } else if resolved == "yieldAll", let first = args.first {
                    yieldedCollections.append(first.expr)
                }
            }
            collectSequenceBuilderYieldExprs(
                in: callee,
                ast: ast,
                interner: interner,
                yielded: &yielded,
                yieldedCollections: &yieldedCollections
            )
            for argument in args {
                collectSequenceBuilderYieldExprs(
                    in: argument.expr,
                    ast: ast,
                    interner: interner,
                    yielded: &yielded,
                    yieldedCollections: &yieldedCollections
                )
            }
        case let .memberCall(receiver, callee, _, args, _):
            let resolved = interner.resolve(callee)
            if case .thisRef = ast.arena.expr(receiver) {
                if resolved == "yield", let first = args.first {
                    yielded.append(first.expr)
                } else if resolved == "yieldAll", let first = args.first {
                    yieldedCollections.append(first.expr)
                }
            }
            collectSequenceBuilderYieldExprs(
                in: receiver,
                ast: ast,
                interner: interner,
                yielded: &yielded,
                yieldedCollections: &yieldedCollections
            )
            for argument in args {
                collectSequenceBuilderYieldExprs(
                    in: argument.expr,
                    ast: ast,
                    interner: interner,
                    yielded: &yielded,
                    yieldedCollections: &yieldedCollections
                )
            }
        case let .blockExpr(statements, trailingExpr, _):
            for statementExprID in statements {
                collectSequenceBuilderYieldExprs(
                    in: statementExprID,
                    ast: ast,
                    interner: interner,
                    yielded: &yielded,
                    yieldedCollections: &yieldedCollections
                )
            }
            if let trailingExpr {
                collectSequenceBuilderYieldExprs(
                    in: trailingExpr,
                    ast: ast,
                    interner: interner,
                    yielded: &yielded,
                    yieldedCollections: &yieldedCollections
                )
            }
        case let .ifExpr(condition, thenExpr, elseExpr, _):
            collectSequenceBuilderYieldExprs(
                in: condition,
                ast: ast,
                interner: interner,
                yielded: &yielded,
                yieldedCollections: &yieldedCollections
            )
            collectSequenceBuilderYieldExprs(
                in: thenExpr,
                ast: ast,
                interner: interner,
                yielded: &yielded,
                yieldedCollections: &yieldedCollections
            )
            if let elseExpr {
                collectSequenceBuilderYieldExprs(
                    in: elseExpr,
                    ast: ast,
                    interner: interner,
                    yielded: &yielded,
                    yieldedCollections: &yieldedCollections
                )
            }
        case let .forExpr(_, iterableExpr, bodyExpr, _, _),
            let .forDestructuringExpr(_, iterableExpr, bodyExpr, _):
            collectSequenceBuilderYieldExprs(
                in: iterableExpr,
                ast: ast,
                interner: interner,
                yielded: &yielded,
                yieldedCollections: &yieldedCollections
            )
            collectSequenceBuilderYieldExprs(
                in: bodyExpr,
                ast: ast,
                interner: interner,
                yielded: &yielded,
                yieldedCollections: &yieldedCollections
            )
        default:
            break
        }
    }
}

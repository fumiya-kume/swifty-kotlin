// swiftlint:disable file_length
import Foundation

// Handles call expression type inference (function calls, member calls, safe member calls).
// Derived from TypeCheckSemaPhase+InferCallsAndBinary.swift.
// File splitting is still in progress for this legacy entry point.

extension CallTypeChecker {
    private func tryBuiltinFlowMemberCall(
        _ id: ExprID,
        calleeName: InternedString,
        receiverElementType: TypeID,
        args: [CallArgument],
        safeCall: Bool,
        ast: ASTModule,
        sema: SemaModule,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) -> TypeID? {
        let memberName = ctx.interner.resolve(calleeName)
        let flowMembers: Set = ["map", "filter", "take", "collect"]
        guard flowMembers.contains(memberName) else {
            return nil
        }

        switch memberName {
        case "take":
            guard args.count == 1 else {
                return nil
            }
            _ = driver.inferExpr(
                args[0].expr,
                ctx: ctx,
                locals: &locals,
                expectedType: sema.types.intType
            )
            sema.bindings.markFlowExpr(id)
            sema.bindings.bindFlowElementType(receiverElementType, forExpr: id)
            let resultType = safeCall ? sema.types.makeNullable(sema.types.anyType) : sema.types.anyType
            sema.bindings.bindExprType(id, type: resultType)
            return resultType

        case "map", "filter", "collect":
            guard args.count == 1 else {
                return nil
            }
            let expectsLambdaTypeConstraint = switch ast.arena.expr(args[0].expr) {
            case .callableRef:
                false
            default:
                true
            }
            let lambdaReturnType: TypeID = switch memberName {
            case "filter":
                sema.types.booleanType
            case "collect":
                sema.types.unitType
            default:
                sema.types.anyType
            }
            let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                params: [receiverElementType],
                returnType: lambdaReturnType,
                isSuspend: memberName == "collect",
                nullability: .nonNull
            )))
            if expectsLambdaTypeConstraint {
                _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
            } else {
                _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals)
            }

            if memberName == "map" || memberName == "filter" {
                sema.bindings.markFlowExpr(id)
                let resultElementType: TypeID = if memberName == "map",
                                                   case let .lambdaLiteral(_, bodyExpr, _, _) = ast.arena.expr(args[0].expr),
                                                   let mappedType = sema.bindings.exprType(for: bodyExpr)
                {
                    mappedType
                } else {
                    receiverElementType
                }
                sema.bindings.bindFlowElementType(resultElementType, forExpr: id)
            }

            let resultType: TypeID = memberName == "collect" ? sema.types.unitType : sema.types.anyType
            let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
            sema.bindings.bindExprType(id, type: finalType)
            return finalType

        default:
            return nil
        }
    }

    private func isCoroutineHandleReceiverType(
        _ receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        guard case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(receiverType)),
              let symbol = sema.symbols.symbol(classType.classSymbol)
        else {
            return false
        }
        let shortName = interner.resolve(symbol.name)
        if shortName == "Job" || shortName == "Deferred" {
            return true
        }
        let fqName = symbol.fqName.map(interner.resolve)
        return fqName == ["kotlinx", "coroutines", "Job"]
            || fqName == ["kotlinx", "coroutines", "Deferred"]
    }

    private func isChannelReceiverType(
        _ receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        guard case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(receiverType)),
              let symbol = sema.symbols.symbol(classType.classSymbol)
        else {
            return false
        }
        let shortName = interner.resolve(symbol.name)
        if shortName != "Channel" {
            return false
        }
        let fqName = symbol.fqName.map(interner.resolve)
        return fqName == ["kotlinx", "coroutines", "channels", "Channel"]
    }

    // swiftlint:disable cyclomatic_complexity function_body_length
    /// This legacy inference path still owns many special cases while the split-out helpers
    /// are being migrated.
    func inferMemberCallImpl(
        _ id: ExprID,
        receiverID: ExprID,
        calleeName: InternedString,
        args: [CallArgument],
        range: SourceRange,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings,
        expectedType: TypeID?,
        explicitTypeArgs: [TypeID],
        safeCall: Bool
    ) -> TypeID {
        let ast = ctx.ast
        let sema = ctx.sema
        let interner = ctx.interner
        // swiftlint:enable cyclomatic_complexity function_body_length

        if args.isEmpty,
           case .callableRef = ast.arena.expr(receiverID),
           interner.resolve(calleeName) == "isInitialized"
        {
            _ = driver.inferExpr(receiverID, ctx: ctx, locals: &locals)
            if let propertySymbol = sema.bindings.identifierSymbol(for: receiverID),
               let propertyInfo = sema.symbols.symbol(propertySymbol),
               propertyInfo.kind == .property,
               propertyInfo.flags.contains(.lateinitProperty)
            {
                let boolType = sema.types.make(.primitive(.boolean, .nonNull))
                sema.bindings.bindExprType(id, type: boolType)
                return boolType
            }

            ctx.semaCtx.diagnostics.error(
                "KSWIFTK-SEMA-LATEINIT",
                "'isInitialized' is only available on lateinit property references.",
                range: range
            )
            return driver.helpers.bindAndReturnErrorType(id, sema: sema)
        }

        // ── T::class.simpleName / T::class.qualifiedName ──────────────
        // Detect member access on a class-reference expression (callableRef
        // with member "class").  The result type is nullable String.
        // We eagerly infer the receiver so classRefTargetType gets bound,
        // then verify it was actually set (guards against `x::class` where
        // x is a local variable rather than a type name).
        if case let .callableRef(_, refMember, _) = ast.arena.expr(receiverID),
           interner.resolve(refMember) == "class"
        {
            _ = driver.inferExpr(receiverID, ctx: ctx, locals: &locals)
            if sema.bindings.classRefTargetType(for: receiverID) != nil {
                let callee = interner.resolve(calleeName)
                if callee == "simpleName" || callee == "qualifiedName" {
                    _ = args.map { driver.inferExpr($0.expr, ctx: ctx, locals: &locals) }
                    let nullableStringType = sema.types.makeNullable(
                        sema.types.make(.primitive(.string, .nonNull))
                    )
                    sema.bindings.bindExprType(id, type: nullableStringType)
                    return nullableStringType
                }
            }
        }

        let receiverType = driver.inferExpr(receiverID, ctx: ctx, locals: &locals)

        if args.isEmpty,
           case let .nameRef(receiverName, _) = ast.arena.expr(receiverID),
           locals[receiverName] == nil,
           let ownerSymbol = ctx.cachedScopeLookup(receiverName).first(where: { candidate in
               guard let symbol = sema.symbols.symbol(candidate) else {
                   return false
               }
               switch symbol.kind {
               case .class, .interface, .enumClass:
                   return true
               default:
                   return false
               }
           }),
           let staticMember = resolveClassNameMemberValue(
               ownerNominalSymbol: ownerSymbol,
               memberName: calleeName,
               sema: sema
           )
        {
            if let memberSymbol = sema.symbols.symbol(staticMember.symbol),
               !ctx.visibilityChecker.isAccessible(
                   memberSymbol,
                   fromFile: ctx.currentFileID,
                   enclosingClass: ctx.enclosingClassSymbol
               )
            {
                driver.helpers.emitVisibilityError(
                    for: memberSymbol,
                    name: interner.resolve(calleeName),
                    range: range,
                    diagnostics: ctx.semaCtx.diagnostics
                )
                return driver.helpers.bindAndReturnErrorType(id, sema: sema)
            }
            sema.bindings.bindIdentifier(id, symbol: staticMember.symbol)
            sema.bindings.bindExprType(id, type: staticMember.type)
            return staticMember.type
        }

        // --- Scope functions: let, run, apply, also (STDLIB-004) ---
        // Must intercept BEFORE eager arg inference so the lambda argument
        // is inferred with the correct expected type (it vs. receiver this).
        // Skip interception when the receiver type defines a real member
        // with the same name (user-defined members take precedence).
        if args.count == 1 {
            let calleeStr = interner.resolve(calleeName)
            let scopeKind: ScopeFunctionKind? = switch calleeStr {
            case "let": .scopeLet
            case "run": .scopeRun
            case "apply": .scopeApply
            case "also": .scopeAlso
            default: nil
            }
            let hasUserDefinedMember = if scopeKind != nil {
                !driver.helpers.collectMemberFunctionCandidates(
                    named: calleeName,
                    receiverType: receiverType,
                    sema: sema
                ).isEmpty
            } else {
                false
            }
            if let scopeKind, !hasUserDefinedMember {
                let nonNullReceiverType = safeCall
                    ? sema.types.makeNonNullable(receiverType)
                    : receiverType

                switch scopeKind {
                case .scopeLet:
                    // let: lambda receives `it` parameter typed as T, returns R
                    let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                        params: [nonNullReceiverType],
                        returnType: expectedType ?? sema.types.anyType
                    )))
                    let lambdaType = driver.inferExpr(
                        args[0].expr, ctx: ctx, locals: &locals,
                        expectedType: lambdaExpectedType
                    )
                    let returnType: TypeID = if case let .functionType(fnType) = sema.types.kind(of: lambdaType) {
                        fnType.returnType
                    } else {
                        sema.bindings.exprTypes[args[0].expr].flatMap { typeID in
                            if case let .functionType(fnType) = sema.types.kind(of: typeID) {
                                return fnType.returnType
                            }
                            return nil
                        } ?? sema.types.anyType
                    }
                    let finalType = safeCall ? sema.types.makeNullable(returnType) : returnType
                    sema.bindings.markScopeFunctionExpr(id, kind: scopeKind)
                    sema.bindings.bindExprType(id, type: finalType)
                    return finalType

                case .scopeRun:
                    // run: lambda has receiver T as `this`, returns R
                    let receiverCtx = ctx.with(implicitReceiverType: nonNullReceiverType)
                    let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                        receiver: nonNullReceiverType,
                        params: [],
                        returnType: expectedType ?? sema.types.anyType
                    )))
                    let lambdaType = driver.inferExpr(
                        args[0].expr, ctx: receiverCtx, locals: &locals,
                        expectedType: lambdaExpectedType
                    )
                    let returnType: TypeID = if case let .functionType(fnType) = sema.types.kind(of: lambdaType) {
                        fnType.returnType
                    } else {
                        sema.bindings.exprTypes[args[0].expr].flatMap { typeID in
                            if case let .functionType(fnType) = sema.types.kind(of: typeID) {
                                return fnType.returnType
                            }
                            return nil
                        } ?? sema.types.anyType
                    }
                    let finalType = safeCall ? sema.types.makeNullable(returnType) : returnType
                    sema.bindings.markScopeFunctionExpr(id, kind: scopeKind)
                    sema.bindings.bindExprType(id, type: finalType)
                    return finalType

                case .scopeApply:
                    // apply: lambda has receiver T as `this`, returns T (receiver itself)
                    let receiverCtx = ctx.with(implicitReceiverType: nonNullReceiverType)
                    let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                        receiver: nonNullReceiverType,
                        params: [],
                        returnType: sema.types.unitType
                    )))
                    _ = driver.inferExpr(
                        args[0].expr, ctx: receiverCtx, locals: &locals,
                        expectedType: lambdaExpectedType
                    )
                    let finalType = safeCall
                        ? sema.types.makeNullable(nonNullReceiverType)
                        : nonNullReceiverType
                    sema.bindings.markScopeFunctionExpr(id, kind: scopeKind)
                    sema.bindings.bindExprType(id, type: finalType)
                    return finalType

                case .scopeAlso:
                    // also: lambda receives `it` parameter typed as T, returns T
                    let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                        params: [nonNullReceiverType],
                        returnType: sema.types.unitType
                    )))
                    _ = driver.inferExpr(
                        args[0].expr, ctx: ctx, locals: &locals,
                        expectedType: lambdaExpectedType
                    )
                    let finalType = safeCall
                        ? sema.types.makeNullable(nonNullReceiverType)
                        : nonNullReceiverType
                    sema.bindings.markScopeFunctionExpr(id, kind: scopeKind)
                    sema.bindings.bindExprType(id, type: finalType)
                    return finalType

                case .scopeWith:
                    break // with is handled in inferCallExpr (top-level function)
                }
            }
        }

        // Defer inference of lambda arguments for collection HOFs so that the
        // contextual function type (and thus implicit `it`) is available.
        let collectionHOFNames: Set = [
            "map", "filter", "mapNotNull", "forEach", "flatMap", "any", "none", "all",
            "fold", "reduce", "groupBy", "sortedBy", "count", "first", "last", "find",
            "associateBy", "associateWith", "associate", "forEachIndexed", "mapIndexed",
            "sumOf", "maxOrNull", "minOrNull",
        ]
        let flowHOFNames: Set = ["map", "filter", "collect"]
        let mapOnlyCollectionHOFNames: Set = ["mapValues", "mapKeys"]
        let isFlowReceiver = if sema.bindings.isFlowExpr(receiverID) {
            true
        } else if case .nameRef = ast.arena.expr(receiverID),
                  let receiverSymbol = sema.bindings.identifierSymbol(for: receiverID),
                  sema.bindings.isFlowSymbol(receiverSymbol)
        {
            true
        } else {
            false
        }
        let flowElementType: TypeID = if let elementType = sema.bindings.flowElementType(forExpr: receiverID) {
            elementType
        } else if case .nameRef = ast.arena.expr(receiverID),
                  let receiverSymbol = sema.bindings.identifierSymbol(for: receiverID),
                  let elementType = sema.bindings.flowElementType(forSymbol: receiverSymbol)
        {
            elementType
        } else {
            sema.types.anyType
        }
        let isFlowHOF = isFlowReceiver && flowHOFNames.contains(interner.resolve(calleeName))
        let isCollectionReceiver = sema.bindings.isCollectionExpr(receiverID)
            || isCollectionLikeType(receiverType, sema: sema, interner: interner)
        let isMapReceiver = isMapLikeCollectionType(receiverType, sema: sema, interner: interner)
        let activeCollectionHOFNames = collectionHOFNames.union(isMapReceiver ? mapOnlyCollectionHOFNames : [])
        let isCollectionHOF = activeCollectionHOFNames.contains(interner.resolve(calleeName))
            && isCollectionReceiver

        // --- Collection higher-order functions (STDLIB-005) ---
        if isCollectionHOF {
            let calleeStr = interner.resolve(calleeName)
            let collectionElementType = getCollectionElementType(receiverType, sema: sema, interner: interner)

            let resultType: TypeID
            switch calleeStr {
            case "map", "filter", "mapNotNull", "forEach", "flatMap", "any", "none", "all",
                 "count", "first", "last", "find", "associateBy", "associateWith", "associate",
                 "mapValues", "mapKeys":
                // any(), none(), count(), first(), last() can be called with no args
                if args.isEmpty {
                    switch calleeStr {
                    case "any", "none": resultType = sema.types.booleanType
                    case "count": resultType = sema.types.intType
                    case "first", "last": resultType = sema.types.makeNullable(collectionElementType)
                    default: resultType = sema.types.anyType
                    }
                } else {
                    let lambdaReturnType: TypeID = switch calleeStr {
                    case "filter", "any", "none", "all": sema.types.booleanType
                    case "forEach": sema.types.unitType
                    case "count": sema.types.booleanType
                    case "mapNotNull": sema.types.nullableAnyType
                    default: sema.types.anyType
                    }
                    let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                        params: [collectionElementType],
                        returnType: lambdaReturnType
                    )))
                    if let lambdaExpr = ast.arena.expr(args[0].expr), case .lambdaLiteral = lambdaExpr {
                        sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
                    }
                    _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)

                    switch calleeStr {
                    case "map":
                        let bodyType: TypeID = if case let .lambdaLiteral(_, bodyExpr, _, _) = ast.arena.expr(args[0].expr) {
                            sema.bindings.exprType(for: bodyExpr) ?? sema.types.anyType
                        } else if case let .functionType(fnType) = sema.types.kind(of: sema.bindings.exprType(for: args[0].expr) ?? sema.types.anyType) {
                            fnType.returnType
                        } else {
                            sema.types.anyType
                        }
                        resultType = sema.types.make(.classType(ClassType(
                            classSymbol: sema.symbols.lookupByShortName(interner.intern("List")).first!,
                            args: [.invariant(bodyType)],
                            nullability: .nonNull
                        )))
                    case "filter": resultType = receiverType
                    case "forEach": resultType = sema.types.unitType
                    case "flatMap":
                        resultType = sema.types.make(.classType(ClassType(
                            classSymbol: sema.symbols.lookupByShortName(interner.intern("List")).first!,
                            args: [.invariant(sema.types.anyType)],
                            nullability: .nonNull
                        )))
                    case "any", "none", "all": resultType = sema.types.booleanType
                    case "count": resultType = sema.types.intType
                    case "first", "last", "find": resultType = sema.types.makeNullable(collectionElementType)
                    case "associateBy", "associateWith", "associate":
                        resultType = sema.types.make(.classType(ClassType(
                            classSymbol: sema.symbols.lookupByShortName(interner.intern("Map")).first!,
                            args: [.invariant(sema.types.anyType), .invariant(sema.types.anyType)],
                            nullability: .nonNull
                        )))
                    case "mapValues" where isMapReceiver:
                        let bodyType: TypeID = if case let .lambdaLiteral(_, bodyExpr, _, _) = ast.arena.expr(args[0].expr) {
                            sema.bindings.exprType(for: bodyExpr) ?? sema.types.anyType
                        } else if case let .functionType(fnType) = sema.types.kind(of: sema.bindings.exprType(for: args[0].expr) ?? sema.types.anyType) {
                            fnType.returnType
                        } else {
                            sema.types.anyType
                        }
                        let keyType: TypeID = if case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(receiverType)),
                                                 classType.args.count >= 2
                        {
                            switch classType.args[0] {
                            case let .invariant(id), let .out(id), let .in(id): id
                            case .star: sema.types.anyType
                            }
                        } else {
                            sema.types.anyType
                        }
                        resultType = sema.types.make(.classType(ClassType(
                            classSymbol: sema.symbols.lookupByShortName(interner.intern("Map")).first!,
                            args: [.invariant(keyType), .invariant(bodyType)],
                            nullability: .nonNull
                        )))
                    case "mapKeys" where isMapReceiver:
                        let bodyType: TypeID = if case let .lambdaLiteral(_, bodyExpr, _, _) = ast.arena.expr(args[0].expr) {
                            sema.bindings.exprType(for: bodyExpr) ?? sema.types.anyType
                        } else if case let .functionType(fnType) = sema.types.kind(of: sema.bindings.exprType(for: args[0].expr) ?? sema.types.anyType) {
                            fnType.returnType
                        } else {
                            sema.types.anyType
                        }
                        let valueType: TypeID = if case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(receiverType)),
                                                   classType.args.count >= 2
                        {
                            switch classType.args[1] {
                            case let .invariant(id), let .out(id), let .in(id): id
                            case .star: sema.types.anyType
                            }
                        } else {
                            sema.types.anyType
                        }
                        resultType = sema.types.make(.classType(ClassType(
                            classSymbol: sema.symbols.lookupByShortName(interner.intern("Map")).first!,
                            args: [.invariant(bodyType), .invariant(valueType)],
                            nullability: .nonNull
                        )))
                    case "mapNotNull":
                        let bodyType: TypeID = if case let .lambdaLiteral(_, bodyExpr, _, _) = ast.arena.expr(args[0].expr) {
                            sema.types.makeNonNullable(sema.bindings.exprType(for: bodyExpr) ?? sema.types.anyType)
                        } else if case let .functionType(fnType) = sema.types.kind(of: sema.bindings.exprType(for: args[0].expr) ?? sema.types.anyType) {
                            sema.types.makeNonNullable(fnType.returnType)
                        } else {
                            sema.types.anyType
                        }
                        resultType = sema.types.make(.classType(ClassType(
                            classSymbol: sema.symbols.lookupByShortName(interner.intern("List")).first!,
                            args: [.invariant(bodyType)],
                            nullability: .nonNull
                        )))
                    default: resultType = sema.types.anyType
                    }
                }

            case "fold":
                guard args.count == 2 else {
                    sema.bindings.bindExprType(id, type: sema.types.anyType)
                    return sema.types.anyType
                }
                let initialType = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals)
                let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                    params: [initialType, collectionElementType],
                    returnType: initialType
                )))
                if let lambdaExpr = ast.arena.expr(args[1].expr), case .lambdaLiteral = lambdaExpr {
                    sema.bindings.markCollectionHOFLambdaExpr(args[1].expr)
                }
                _ = driver.inferExpr(args[1].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
                resultType = initialType

            case "reduce":
                guard args.count == 1 else {
                    sema.bindings.bindExprType(id, type: sema.types.anyType)
                    return sema.types.anyType
                }
                let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                    params: [collectionElementType, collectionElementType],
                    returnType: collectionElementType
                )))
                if let lambdaExpr = ast.arena.expr(args[0].expr), case .lambdaLiteral = lambdaExpr {
                    sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
                }
                _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
                resultType = collectionElementType

            case "groupBy":
                let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                    params: [collectionElementType],
                    returnType: sema.types.anyType
                )))
                if let lambdaExpr = ast.arena.expr(args[0].expr), case .lambdaLiteral = lambdaExpr {
                    sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
                }
                _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
                let keyType: TypeID = if case let .lambdaLiteral(_, bodyExpr, _, _) = ast.arena.expr(args[0].expr) {
                    sema.bindings.exprType(for: bodyExpr) ?? sema.types.anyType
                } else if case let .functionType(fnType) = sema.types.kind(of: sema.bindings.exprType(for: args[0].expr) ?? sema.types.anyType) {
                    fnType.returnType
                } else {
                    sema.types.anyType
                }
                let listType = sema.types.make(.classType(ClassType(
                    classSymbol: sema.symbols.lookupByShortName(interner.intern("List")).first!,
                    args: [.invariant(collectionElementType)],
                    nullability: .nonNull
                )))
                resultType = sema.types.make(.classType(ClassType(
                    classSymbol: sema.symbols.lookupByShortName(interner.intern("Map")).first!,
                    args: [.invariant(keyType), .invariant(listType)],
                    nullability: .nonNull
                )))

            case "sortedBy":
                let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                    params: [collectionElementType],
                    returnType: sema.types.anyType
                )))
                if let lambdaExpr = ast.arena.expr(args[0].expr), case .lambdaLiteral = lambdaExpr {
                    sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
                }
                _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
                resultType = receiverType

            case "forEachIndexed", "mapIndexed":
                guard args.count == 1 else {
                    sema.bindings.bindExprType(id, type: sema.types.anyType)
                    return sema.types.anyType
                }
                let lambdaReturnType = calleeStr == "forEachIndexed" ? sema.types.unitType : sema.types.anyType
                let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                    params: [sema.types.intType, collectionElementType],
                    returnType: lambdaReturnType
                )))
                if let lambdaExpr = ast.arena.expr(args[0].expr), case .lambdaLiteral = lambdaExpr {
                    sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
                }
                _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
                if calleeStr == "forEachIndexed" {
                    resultType = sema.types.unitType
                } else {
                    resultType = sema.types.make(.classType(ClassType(
                        classSymbol: sema.symbols.lookupByShortName(interner.intern("List")).first!,
                        args: [.invariant(sema.types.anyType)],
                        nullability: .nonNull
                    )))
                }

            case "sumOf":
                guard args.count == 1 else {
                    sema.bindings.bindExprType(id, type: sema.types.anyType)
                    return sema.types.anyType
                }
                let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                    params: [collectionElementType],
                    returnType: sema.types.intType
                )))
                if let lambdaExpr = ast.arena.expr(args[0].expr), case .lambdaLiteral = lambdaExpr {
                    sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
                }
                _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
                resultType = sema.types.intType

            case "maxOrNull", "minOrNull":
                guard args.isEmpty else {
                    sema.bindings.bindExprType(id, type: sema.types.anyType)
                    return sema.types.anyType
                }
                if let comparableSymbol = sema.types.comparableInterfaceSymbol {
                    let comparableElementType = sema.types.make(.classType(ClassType(
                        classSymbol: comparableSymbol,
                        args: [.invariant(collectionElementType)],
                        nullability: .nonNull
                    )))
                    if !sema.types.isSubtype(collectionElementType, comparableElementType) {
                        ctx.semaCtx.diagnostics.error(
                            "KSWIFTK-SEMA-BOUND",
                            "Type argument does not satisfy upper bound constraint.",
                            range: ast.arena.exprRange(id)
                        )
                        let failedType = safeCall ? sema.types.nullableAnyType : sema.types.anyType
                        sema.bindings.bindExprType(id, type: failedType)
                        return failedType
                    }
                }
                resultType = sema.types.makeNullable(collectionElementType)

            default:
                resultType = sema.types.anyType
            }

            let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
            sema.bindings.bindExprType(id, type: finalType)
            return finalType
        }

        if isFlowHOF,
           let lambdaArg = args.first?.expr,
           let lambdaExpr = ast.arena.expr(lambdaArg),
           case .lambdaLiteral = lambdaExpr
        {
            sema.bindings.markCollectionHOFLambdaExpr(lambdaArg)
        }

        if isFlowReceiver,
           let builtinFlowType = tryBuiltinFlowMemberCall(
               id,
               calleeName: calleeName,
               receiverElementType: flowElementType,
               args: args,
               safeCall: safeCall,
               ast: ast,
               sema: sema,
               ctx: ctx,
               locals: &locals
           )
        {
            return builtinFlowType
        }

        // Infer argument types for the normal resolution path (scope functions and
        // collection HOFs infer their lambda args with expected type above and return).
        let argTypes = args.map { arg in
            driver.inferExpr(arg.expr, ctx: ctx, locals: &locals)
        }

        let hasLeadingLocaleArgument = interner.resolve(calleeName) == "format"
            && argTypes.first.map { isJavaUtilLocaleType($0, sema: sema, interner: interner) } == true
        let lookupReceiverType = safeCall ? sema.types.makeNonNullable(receiverType) : receiverType
        // Primitive member function: Int/Long/UInt/ULong.inv() → same type (P5-103, TYPE-005)
        if interner.resolve(calleeName) == "inv",
           args.isEmpty
        {
            let intType = sema.types.make(.primitive(.int, .nonNull))
            let longType = sema.types.make(.primitive(.long, .nonNull))
            let uintType = sema.types.make(.primitive(.uint, .nonNull))
            let ulongType = sema.types.make(.primitive(.ulong, .nonNull))
            if lookupReceiverType == intType || lookupReceiverType == longType || lookupReceiverType == uintType || lookupReceiverType == ulongType {
                let resultType = lookupReceiverType
                let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
                sema.bindings.bindExprType(id, type: finalType)
                return finalType
            }
        }

        // Primitive infix member functions: Int/Long/UInt/ULong.and|or|xor|shl|shr|ushr (EXPR-003, TYPE-005)
        if args.count == 1 {
            let intType = sema.types.make(.primitive(.int, .nonNull))
            let longType = sema.types.make(.primitive(.long, .nonNull))
            let uintType = sema.types.make(.primitive(.uint, .nonNull))
            let ulongType = sema.types.make(.primitive(.ulong, .nonNull))
            let receiverForCheck = safeCall
                ? sema.types.makeNonNullable(lookupReceiverType)
                : lookupReceiverType
            let rhsType = sema.types.makeNonNullable(argTypes[0])
            let isPrimitiveReceiver = receiverForCheck == intType || receiverForCheck == longType || receiverForCheck == uintType || receiverForCheck == ulongType
            let isIntegerRhs = rhsType == intType || rhsType == longType || rhsType == uintType || rhsType == ulongType
            switch interner.resolve(calleeName) {
            case "and", "or", "xor":
                if isPrimitiveReceiver,
                   isIntegerRhs
                {
                    let resultType: TypeID = (receiverForCheck == longType || rhsType == longType) ? longType
                        : (receiverForCheck == ulongType || rhsType == ulongType) ? ulongType
                        : (receiverForCheck == uintType || rhsType == uintType) ? uintType
                        : intType
                    let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
                    sema.bindings.bindExprType(id, type: finalType)
                    return finalType
                }
            case "shl", "shr", "ushr":
                if isPrimitiveReceiver,
                   rhsType == intType
                {
                    // shift amount must be Int; receiver can be Int/Long/UInt/ULong
                    let finalType = safeCall ? sema.types.makeNullable(receiverForCheck) : receiverForCheck
                    sema.bindings.bindExprType(id, type: finalType)
                    return finalType
                }
            default:
                break
            }
        }

        // Stdlib infix function: Any.to(Any) → Pair<LHS, RHS> (FUNC-002)
        if interner.resolve(calleeName) == "to",
           args.count == 1
        {
            let rhsType = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals)
            let resultType = makeSyntheticPairType(
                symbols: sema.symbols,
                types: sema.types,
                interner: interner,
                firstType: receiverType,
                secondType: rhsType
            )
            let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
            sema.bindings.bindExprType(id, type: finalType)
            return finalType
        }

        // Primitive member function: Int/Long.toString() / toString(radix: Int) → String (EXPR-003)
        if interner.resolve(calleeName) == "toString",
           args.count <= 1
        {
            let intType = sema.types.make(.primitive(.int, .nonNull))
            let longType = sema.types.make(.primitive(.long, .nonNull))
            let stringType = sema.types.make(.primitive(.string, .nonNull))
            let receiverForCheck = safeCall
                ? sema.types.makeNonNullable(lookupReceiverType)
                : lookupReceiverType
            if receiverForCheck == intType || receiverForCheck == longType {
                if args.isEmpty || argTypes[0] == intType {
                    let finalType = safeCall ? sema.types.makeNullable(stringType) : stringType
                    sema.bindings.bindExprType(id, type: finalType)
                    return finalType
                }
            }
        }

        // Primitive conversion: toInt(), toUInt(), toLong(), toULong(),
        // toFloat(), toByte(), toShort() (TYPE-005)
        if args.isEmpty {
            let intType = sema.types.make(.primitive(.int, .nonNull))
            let longType = sema.types.make(.primitive(.long, .nonNull))
            let uintType = sema.types.make(.primitive(.uint, .nonNull))
            let ulongType = sema.types.make(.primitive(.ulong, .nonNull))
            let floatType = sema.types.make(.primitive(.float, .nonNull))
            let receiverForCheck = safeCall
                ? sema.types.makeNonNullable(lookupReceiverType)
                : lookupReceiverType
            let calleeStr = interner.resolve(calleeName)
            let (targetType, matches): (TypeID, Bool) = switch calleeStr {
            case "toInt": (intType, receiverForCheck == uintType || receiverForCheck == ulongType || receiverForCheck == intType || receiverForCheck == longType)
            case "toUInt": (uintType, receiverForCheck == intType || receiverForCheck == longType || receiverForCheck == uintType || receiverForCheck == ulongType)
            case "toLong": (longType, receiverForCheck == intType || receiverForCheck == uintType || receiverForCheck == longType || receiverForCheck == ulongType)
            case "toULong": (ulongType, receiverForCheck == intType || receiverForCheck == longType || receiverForCheck == uintType || receiverForCheck == ulongType)
            case "toFloat": (floatType, receiverForCheck == intType)
            case "toByte", "toShort": (intType, receiverForCheck == intType)
            default: (sema.types.errorType, false)
            }
            if matches {
                let finalType = safeCall ? sema.types.makeNullable(targetType) : targetType
                sema.bindings.bindExprType(id, type: finalType)
                return finalType
            }
        }

        var isSuperCall = false
        var supertypeSymbols: Set<SymbolID> = []
        if !safeCall {
            isSuperCall = ast.arena.expr(receiverID).map { if case .superRef = $0 { true } else { false } } ?? false
            if isSuperCall, let currentReceiverType = ctx.implicitReceiverType,
               let classSymbol = driver.helpers.nominalSymbol(of: currentReceiverType, types: sema.types)
            {
                var queue = sema.symbols.directSupertypes(for: classSymbol)
                var visited: Set<SymbolID> = [classSymbol]
                while !queue.isEmpty {
                    let next = queue.removeFirst()
                    if visited.insert(next).inserted {
                        supertypeSymbols.insert(next)
                        queue.append(contentsOf: sema.symbols.directSupertypes(for: next))
                    }
                }
            }
        }

        let memberLookupType = (isSuperCall ? ctx.implicitReceiverType : nil) ?? lookupReceiverType

        // Detect class-name receiver: when the receiver is a name reference to
        // a class/interface/enumClass symbol, only companion members should be
        // accessible (not instance methods).  This prevents `Foo.instanceMethod()`
        // from resolving when there is no companion with that name.
        let classNameReceiverNominalSymbol: SymbolID? = {
            if let receiverSymbolID = sema.bindings.identifierSymbol(for: receiverID),
               let receiverSymbol = sema.symbols.symbol(receiverSymbolID)
            {
                switch receiverSymbol.kind {
                case .class, .interface, .enumClass:
                    return receiverSymbolID
                default:
                    break
                }
            }
            if case let .nameRef(receiverName, _) = ast.arena.expr(receiverID) {
                return ctx.cachedScopeLookup(receiverName).first { candidate in
                    guard let symbol = sema.symbols.symbol(candidate) else {
                        return false
                    }
                    switch symbol.kind {
                    case .class, .interface, .enumClass:
                        return true
                    default:
                        return false
                    }
                }
            }
            return nil
        }()
        let isClassNameReceiver = classNameReceiverNominalSymbol != nil

        if isClassNameReceiver,
           args.isEmpty,
           let ownerSymbol = classNameReceiverNominalSymbol,
           let staticMember = resolveClassNameMemberValue(
               ownerNominalSymbol: ownerSymbol,
               memberName: calleeName,
               sema: sema
           )
        {
            if let memberSymbol = sema.symbols.symbol(staticMember.symbol),
               !ctx.visibilityChecker.isAccessible(
                   memberSymbol,
                   fromFile: ctx.currentFileID,
                   enclosingClass: ctx.enclosingClassSymbol
               )
            {
                driver.helpers.emitVisibilityError(for: memberSymbol, name: interner.resolve(calleeName), range: range, diagnostics: ctx.semaCtx.diagnostics)
                return driver.helpers.bindAndReturnErrorType(id, sema: sema)
            }
            sema.bindings.bindIdentifier(id, symbol: staticMember.symbol)
            sema.bindings.bindExprType(id, type: staticMember.type)
            return staticMember.type
        }

        if isClassNameReceiver,
           let ownerSymbol = classNameReceiverNominalSymbol,
           let owner = sema.symbols.symbol(ownerSymbol)
        {
            let nestedOwnerFQName = owner.fqName + [calleeName]
            var nestedOwnerSymbols = sema.symbols.lookupAll(fqName: nestedOwnerFQName).filter { candidate in
                guard let symbol = sema.symbols.symbol(candidate) else {
                    return false
                }
                guard sema.symbols.parentSymbol(for: candidate) == ownerSymbol else {
                    return false
                }
                switch symbol.kind {
                case .class, .enumClass, .object:
                    return true
                default:
                    return false
                }
            }
            if nestedOwnerSymbols.isEmpty {
                let shortNameNestedOwners = sema.symbols.lookupByShortName(calleeName).filter { candidate in
                    guard let symbol = sema.symbols.symbol(candidate) else {
                        return false
                    }
                    guard sema.symbols.parentSymbol(for: candidate) == ownerSymbol else {
                        return false
                    }
                    switch symbol.kind {
                    case .class, .enumClass, .object:
                        return true
                    default:
                        return false
                    }
                }
                if shortNameNestedOwners.count == 1 {
                    nestedOwnerSymbols = shortNameNestedOwners
                }
            }
            let nestedCtorFQName = owner.fqName + [calleeName, interner.intern("<init>")]
            var nestedCtorCandidates = sema.symbols.lookupAll(fqName: nestedCtorFQName).filter { candidate in
                guard let symbol = sema.symbols.symbol(candidate) else {
                    return false
                }
                return symbol.kind == .constructor
            }
            if nestedCtorCandidates.isEmpty {
                if !nestedOwnerSymbols.isEmpty {
                    let initName = interner.intern("<init>")
                    nestedCtorCandidates = sema.symbols.lookupByShortName(initName).filter { candidate in
                        guard let symbol = sema.symbols.symbol(candidate),
                              symbol.kind == .constructor
                        else {
                            return false
                        }
                        guard let parent = sema.symbols.parentSymbol(for: candidate) else {
                            return false
                        }
                        return nestedOwnerSymbols.contains(parent)
                    }
                }
            }
            if !nestedCtorCandidates.isEmpty {
                let (visibleNested, invisibleNested) = ctx.filterByVisibility(nestedCtorCandidates)
                if let firstInvisible = invisibleNested.first {
                    driver.helpers.emitVisibilityError(for: firstInvisible, name: interner.resolve(calleeName), range: range, diagnostics: ctx.semaCtx.diagnostics)
                    return driver.helpers.bindAndReturnErrorType(id, sema: sema)
                }
                if !visibleNested.isEmpty {
                    if args.isEmpty {
                        let zeroArgNested = visibleNested.first { candidate in
                            guard let signature = sema.symbols.functionSignature(for: candidate) else {
                                return false
                            }
                            return signature.parameterTypes.isEmpty
                        }
                        if let zeroArgNested,
                           let signature = sema.symbols.functionSignature(for: zeroArgNested)
                        {
                            sema.bindings.bindCall(
                                id,
                                binding: CallBinding(
                                    chosenCallee: zeroArgNested,
                                    substitutedTypeArguments: [],
                                    parameterMapping: [:]
                                )
                            )
                            let resultType = signature.returnType
                            sema.bindings.bindExprType(id, type: resultType)
                            return resultType
                        }
                    }
                    let callArgs = zip(args, argTypes).map { arg, type in
                        CallArg(label: arg.label, isSpread: arg.isSpread, type: type)
                    }
                    let call = CallExpr(range: range, calleeName: calleeName, args: callArgs, explicitTypeArgs: explicitTypeArgs)
                    let resolved = ctx.resolver.resolveCall(
                        candidates: visibleNested,
                        call: call,
                        expectedType: expectedType,
                        ctx: sema
                    )
                    if let diagnostic = resolved.diagnostic {
                        ctx.semaCtx.diagnostics.emit(diagnostic)
                        return driver.helpers.bindAndReturnErrorType(id, sema: sema)
                    }
                    if let chosen = resolved.chosenCallee,
                       let signature = sema.symbols.functionSignature(for: chosen)
                    {
                        sema.bindings.bindCall(
                            id,
                            binding: CallBinding(
                                chosenCallee: chosen,
                                substitutedTypeArguments: resolved.substitutedTypeArguments
                                    .sorted(by: { $0.key.rawValue < $1.key.rawValue })
                                    .map(\.value),
                                parameterMapping: resolved.parameterMapping
                            )
                        )
                        let resultType = signature.returnType
                        sema.bindings.bindExprType(id, type: resultType)
                        return resultType
                    }
                }
            }
            if args.isEmpty,
               let nestedOwner = nestedOwnerSymbols.first
            {
                let nestedType = sema.types.make(.classType(ClassType(
                    classSymbol: nestedOwner,
                    args: [],
                    nullability: .nonNull
                )))
                sema.bindings.bindIdentifier(id, symbol: nestedOwner)
                sema.bindings.bindExprType(id, type: nestedType)
                return nestedType
            }
        }

        // Track the companion type so we can pass it (not the owner class type)
        // as the implicit receiver when resolving the call.
        var companionReceiverType: TypeID?

        let allCandidates: [SymbolID]
        if isClassNameReceiver {
            // Class-name receiver: only companion members are valid targets.
            // Skip collectMemberFunctionCandidates which would find instance
            // methods and shadow companion members of the same name.
            if let ownerNominal = driver.helpers.nominalSymbol(of: memberLookupType, types: sema.types),
               let companionSymbol = sema.symbols.companionObjectSymbol(for: ownerNominal),
               let companionSym = sema.symbols.symbol(companionSymbol)
            {
                let companionMemberFQName = companionSym.fqName + [calleeName]

                // Try companion property access when no arguments are provided
                // (e.g. Foo.MAX_COUNT).  When args are present this is a function
                // call, so skip the property short-circuit to avoid shadowing a
                // companion function of the same name.
                if args.isEmpty {
                    let propertyCandidate = sema.symbols.lookupAll(fqName: companionMemberFQName).first(where: { cid in
                        guard let sym = sema.symbols.symbol(cid),
                              sym.kind == .property,
                              sema.symbols.parentSymbol(for: cid) == companionSymbol
                        else {
                            return false
                        }
                        return true
                    })
                    if let propSymbol = propertyCandidate,
                       let propType = sema.symbols.propertyType(for: propSymbol)
                    {
                        // Check visibility before returning the property.
                        if let propSym = sema.symbols.symbol(propSymbol),
                           !ctx.visibilityChecker.isAccessible(
                               propSym,
                               fromFile: ctx.currentFileID,
                               enclosingClass: ctx.enclosingClassSymbol
                           )
                        {
                            driver.helpers.emitVisibilityError(for: propSym, name: interner.resolve(calleeName), range: range, diagnostics: ctx.semaCtx.diagnostics)
                            return driver.helpers.bindAndReturnErrorType(id, sema: sema)
                        }
                        // Re-bind receiver to companion type for correct KIR lowering
                        let compType = sema.types.make(.classType(ClassType(classSymbol: companionSymbol, args: [], nullability: .nonNull)))
                        sema.bindings.bindExprType(receiverID, type: compType)
                        sema.bindings.bindIdentifier(id, symbol: propSymbol)
                        sema.bindings.bindExprType(id, type: propType)
                        return propType
                    }
                }

                // Then try companion function candidates
                var companionCandidates: [SymbolID] = []
                for candidate in sema.symbols.lookupAll(fqName: companionMemberFQName) {
                    guard let symbol = sema.symbols.symbol(candidate),
                          symbol.kind == .function,
                          sema.symbols.parentSymbol(for: candidate) == companionSymbol,
                          let signature = sema.symbols.functionSignature(for: candidate),
                          signature.receiverType != nil
                    else {
                        continue
                    }
                    companionCandidates.append(candidate)
                }
                if !companionCandidates.isEmpty {
                    companionReceiverType = sema.types.make(.classType(ClassType(classSymbol: companionSymbol, args: [], nullability: .nonNull)))
                    // Re-bind receiver expression to companion type so KIR
                    // lowering passes the companion singleton (not the owner
                    // class) as the first argument to the companion function.
                    sema.bindings.bindExprType(receiverID, type: companionReceiverType!)
                }
                allCandidates = companionCandidates
            } else {
                allCandidates = []
            }
        } else {
            // Normal instance receiver: use standard member lookup with
            // companion fallback via collectMemberFunctionCandidates.
            let memberCandidates = driver.helpers.collectMemberFunctionCandidates(
                named: calleeName,
                receiverType: memberLookupType,
                sema: sema,
                allowedOwnerSymbols: isSuperCall && !supertypeSymbols.isEmpty ? supertypeSymbols : nil
            )
            if !memberCandidates.isEmpty {
                // Check if the found candidates belong to a companion object so we
                // can supply the correct implicit receiver type later.
                if let first = memberCandidates.first,
                   let parentSymbol = sema.symbols.parentSymbol(for: first),
                   let ownerNominal = driver.helpers.nominalSymbol(of: memberLookupType, types: sema.types),
                   parentSymbol != ownerNominal,
                   sema.symbols.companionObjectSymbol(for: ownerNominal) == parentSymbol
                {
                    companionReceiverType = sema.types.make(.classType(ClassType(classSymbol: parentSymbol, args: [], nullability: .nonNull)))
                }
                allCandidates = memberCandidates
            } else {
                // Try inner class constructor resolution: outer.Inner() → Inner's <init>
                let innerCtorCandidates = driver.helpers.collectInnerClassConstructorCandidates(
                    named: calleeName,
                    receiverType: memberLookupType,
                    sema: sema,
                    interner: interner
                )
                if !innerCtorCandidates.isEmpty {
                    allCandidates = innerCtorCandidates
                } else {
                    allCandidates = ctx.cachedScopeLookup(calleeName).filter { candidate in
                        guard let symbol = ctx.cachedSymbol(candidate),
                              symbol.kind == .function,
                              let signature = sema.symbols.functionSignature(for: candidate) else { return false }
                        guard signature.receiverType != nil else { return false }
                        if isSuperCall, !supertypeSymbols.isEmpty {
                            return sema.symbols.parentSymbol(for: candidate).map { supertypeSymbols.contains($0) } ?? false
                        }
                        return true
                    }
                }
            }
        }
        let isNullLiteralReceiver = if case let .nameRef(name, _) = ast.arena.expr(receiverID) { interner.resolve(name) == "null" } else { false }

        let isChannelReceiver = isChannelReceiverType(
            lookupReceiverType,
            sema: sema,
            interner: interner
        )
        if !isClassNameReceiver, isChannelReceiver {
            let memberName = interner.resolve(calleeName)
            switch (memberName, args.count) {
            case ("send", 1), ("close", 0):
                let resultType = sema.types.unitType
                let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
                sema.bindings.bindExprType(id, type: finalType)
                return finalType
            case ("receive", 0):
                let resultType = sema.types.nullableAnyType
                let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
                sema.bindings.bindExprType(id, type: finalType)
                return finalType
            default:
                break
            }
        }

        let (visible, invisible) = ctx.filterByVisibility(allCandidates)
        var candidates = visible
        if hasLeadingLocaleArgument {
            candidates.removeAll { candidate in
                isSyntheticStringFormatCandidate(candidate, sema: sema, interner: interner)
            }
        }
        if candidates.isEmpty {
            if isClassNameReceiver,
               args.isEmpty,
               let classNameReceiverNominalSymbol,
               let staticMember = resolveClassNameMemberValue(
                   ownerNominalSymbol: classNameReceiverNominalSymbol,
                   memberName: calleeName,
                   sema: sema
               )
            {
                if let memberSymbol = sema.symbols.symbol(staticMember.symbol),
                   !ctx.visibilityChecker.isAccessible(
                       memberSymbol,
                       fromFile: ctx.currentFileID,
                       enclosingClass: ctx.enclosingClassSymbol
                   )
                {
                    driver.helpers.emitVisibilityError(for: memberSymbol, name: interner.resolve(calleeName), range: range, diagnostics: ctx.semaCtx.diagnostics)
                    return driver.helpers.bindAndReturnErrorType(id, sema: sema)
                }
                sema.bindings.bindIdentifier(id, symbol: staticMember.symbol)
                sema.bindings.bindExprType(id, type: staticMember.type)
                return staticMember.type
            }
            if args.isEmpty,
               interner.resolve(calleeName) == "length"
            {
                let receiverTypeForCheck = safeCall
                    ? sema.types.makeNonNullable(lookupReceiverType)
                    : lookupReceiverType
                if sema.types.isSubtype(receiverTypeForCheck, sema.types.stringType) {
                    let resultType = sema.types.intType
                    let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
                    sema.bindings.bindExprType(id, type: finalType)
                    return finalType
                }
            }
            if args.isEmpty,
               interner.resolve(calleeName) == "code"
            {
                let receiverTypeForCheck = safeCall
                    ? sema.types.makeNonNullable(lookupReceiverType)
                    : lookupReceiverType
                if receiverTypeForCheck == sema.types.charType {
                    let resultType = sema.types.intType
                    let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
                    sema.bindings.bindExprType(id, type: finalType)
                    return finalType
                }
            }
            if args.isEmpty {
                let receiverTypeForCheck = safeCall
                    ? sema.types.makeNonNullable(lookupReceiverType)
                    : lookupReceiverType
                if receiverTypeForCheck == sema.types.charType {
                    let calleeStr = interner.resolve(calleeName)
                    let resultType: TypeID? = switch calleeStr {
                    case "isDigit", "isLetter", "isLetterOrDigit", "isWhitespace":
                        sema.types.booleanType
                    default:
                        nil
                    }
                    if let resultType {
                        let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
                        sema.bindings.bindExprType(id, type: finalType)
                        return finalType
                    }
                }
            }
            // String stdlib: nullable-receiver 0-arg methods (NULL-002)
            // isNullOrEmpty/isNullOrBlank accept String? receiver directly (no safe-call needed).
            if args.isEmpty {
                let calleeStr = interner.resolve(calleeName)
                if !isNullLiteralReceiver,
                   calleeStr == "isNullOrEmpty" || calleeStr == "isNullOrBlank"
                {
                    // Strip nullability so that String? and String both match.
                    let baseType = sema.types.makeNonNullable(lookupReceiverType)
                    if sema.types.isSubtype(baseType, sema.types.stringType) {
                        let resultType = sema.types.booleanType
                        sema.bindings.bindExprType(id, type: resultType)
                        return resultType
                    }
                }
            }
            // String stdlib: 0-arg methods (STDLIB-006)
            let listCharType = makeSyntheticListType(
                symbols: sema.symbols,
                types: sema.types,
                interner: interner,
                elementType: sema.types.make(.primitive(.char, .nonNull))
            )
            if args.isEmpty {
                let receiverTypeForCheck = safeCall
                    ? sema.types.makeNonNullable(lookupReceiverType)
                    : lookupReceiverType
                if sema.types.isSubtype(receiverTypeForCheck, sema.types.stringType) {
                    let calleeStr = interner.resolve(calleeName)
                    let resultType: TypeID? = switch calleeStr {
                    case "trim":
                        sema.types.stringType
                    case "lowercase", "uppercase":
                        sema.types.stringType
                    case "toInt":
                        sema.types.intType
                    case "toIntOrNull":
                        sema.types.make(.primitive(.int, .nullable))
                    case "toDouble":
                        sema.types.make(.primitive(.double, .nonNull))
                    case "toDoubleOrNull":
                        sema.types.make(.primitive(.double, .nullable))
                    case "reversed":
                        sema.types.stringType
                    case "toList", "toCharArray":
                        listCharType
                    default:
                        nil
                    }
                    if let resultType {
                        let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
                        sema.bindings.bindExprType(id, type: finalType)
                        return finalType
                    }
                }
            }
            // String stdlib: 1-arg methods (STDLIB-006)
            if args.count == 1 {
                let receiverTypeForCheck = safeCall
                    ? sema.types.makeNonNullable(lookupReceiverType)
                    : lookupReceiverType
                let arg0Type = sema.types.makeNonNullable(argTypes[0])
                if sema.types.isSubtype(receiverTypeForCheck, sema.types.stringType),
                   sema.types.isSubtype(arg0Type, sema.types.stringType)
                {
                    let calleeStr = interner.resolve(calleeName)
                    let resultType: TypeID? = switch calleeStr {
                    case "startsWith", "endsWith", "contains":
                        sema.types.make(.primitive(.boolean, .nonNull))
                    case "split":
                        sema.types.anyType
                    case "indexOf", "lastIndexOf":
                        sema.types.make(.primitive(.int, .nonNull))
                    default:
                        nil
                    }
                    if let resultType {
                        let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
                        sema.bindings.bindExprType(id, type: finalType)
                        return finalType
                    }
                }
            }
            if args.count == 1 {
                let receiverTypeForCheck = safeCall
                    ? sema.types.makeNonNullable(lookupReceiverType)
                    : lookupReceiverType
                let arg0Type = sema.types.makeNonNullable(argTypes[0])
                if sema.types.isSubtype(receiverTypeForCheck, sema.types.stringType),
                   sema.types.isSubtype(arg0Type, sema.types.intType)
                {
                    let calleeStr = interner.resolve(calleeName)
                    let resultType: TypeID? = switch calleeStr {
                    case "repeat", "drop", "take", "takeLast", "dropLast":
                        sema.types.stringType
                    default:
                        nil
                    }
                    if let resultType {
                        let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
                        sema.bindings.bindExprType(id, type: finalType)
                        return finalType
                    }
                }
            }
            // String stdlib: 1-arg substring overload (STDLIB-009)
            if args.count == 1 {
                let receiverTypeForCheck = safeCall
                    ? sema.types.makeNonNullable(lookupReceiverType)
                    : lookupReceiverType
                let startType = sema.types.makeNonNullable(argTypes[0])
                if sema.types.isSubtype(receiverTypeForCheck, sema.types.stringType),
                   sema.types.isSubtype(startType, sema.types.intType)
                {
                    let calleeStr = interner.resolve(calleeName)
                    if calleeStr == "substring" {
                        let finalType = safeCall ? sema.types.makeNullable(sema.types.stringType) : sema.types.stringType
                        sema.bindings.bindExprType(id, type: finalType)
                        return finalType
                    }
                }
            }
            // String stdlib: 2-arg methods (STDLIB-006)
            if args.count == 2, interner.resolve(calleeName) == "replace" {
                let receiverTypeForCheck = safeCall
                    ? sema.types.makeNonNullable(lookupReceiverType)
                    : lookupReceiverType
                let oldType = sema.types.makeNonNullable(argTypes[0])
                let newType = sema.types.makeNonNullable(argTypes[1])
                if sema.types.isSubtype(receiverTypeForCheck, sema.types.stringType),
                   sema.types.isSubtype(oldType, sema.types.stringType),
                   sema.types.isSubtype(newType, sema.types.stringType)
                {
                    let finalType = safeCall ? sema.types.makeNullable(sema.types.stringType) : sema.types.stringType
                    sema.bindings.bindExprType(id, type: finalType)
                    return finalType
                }
            }
            // String stdlib: 2-arg substring overload (STDLIB-009)
            if args.count == 2 {
                let receiverTypeForCheck = safeCall
                    ? sema.types.makeNonNullable(lookupReceiverType)
                    : lookupReceiverType
                let startType = sema.types.makeNonNullable(argTypes[0])
                let endType = sema.types.makeNonNullable(argTypes[1])
                if sema.types.isSubtype(receiverTypeForCheck, sema.types.stringType),
                   sema.types.isSubtype(startType, sema.types.intType),
                   sema.types.isSubtype(endType, sema.types.intType),
                   interner.resolve(calleeName) == "substring"
                {
                    let finalType = safeCall ? sema.types.makeNullable(sema.types.stringType) : sema.types.stringType
                    sema.bindings.bindExprType(id, type: finalType)
                    return finalType
                }
            }
            // String stdlib: format(vararg args) (STDLIB-006)
            if interner.resolve(calleeName) == "format", !hasLeadingLocaleArgument {
                let receiverTypeForCheck = safeCall
                    ? sema.types.makeNonNullable(lookupReceiverType)
                    : lookupReceiverType
                if sema.types.isSubtype(receiverTypeForCheck, sema.types.stringType) {
                    if let boundType = tryBindSyntheticStringFormatFallback(
                        id,
                        calleeName: calleeName,
                        receiverType: receiverTypeForCheck,
                        args: args,
                        argTypes: argTypes,
                        range: range,
                        ctx: ctx,
                        expectedType: expectedType,
                        explicitTypeArgs: explicitTypeArgs,
                        safeCall: safeCall
                    ) {
                        return boundType
                    }
                }
            }
            // For non-empty-arg member calls, try member property/field lookup.
            // This handles callable property syntax (e.g. `receiver.f(...)`).
            // Skip this for class-name receivers — only companion members are
            // accessible via `ClassName.member`, not instance properties.
            if !isClassNameReceiver,
               !args.isEmpty,
               let propResult = driver.helpers.lookupMemberProperty(
                   named: calleeName,
                   receiverType: memberLookupType,
                   sema: sema
               )
            {
                // Check visibility before trying callable-style resolution.
                if let propSymbol = sema.symbols.symbol(propResult.symbol),
                   !ctx.visibilityChecker.isAccessible(propSymbol, fromFile: ctx.currentFileID, enclosingClass: ctx.enclosingClassSymbol)
                {
                    driver.helpers.emitVisibilityError(for: propSymbol, name: interner.resolve(calleeName), range: range, diagnostics: ctx.semaCtx.diagnostics)
                    return driver.helpers.bindAndReturnErrorType(id, sema: sema)
                }

                // Property value call with function type (`receiver.f(...)`).
                if let callableType = inferFunctionTypeOrError(from: propResult.type, sema: sema) {
                    if let callableResult = inferCallableValueInvocation(
                        id,
                        calleeType: callableType,
                        callableTarget: .localValue(propResult.symbol),
                        args: args,
                        argTypes: argTypes,
                        range: range,
                        ctx: ctx,
                        expectedType: expectedType
                    ) {
                        let finalType = safeCall ? sema.types.makeNullable(callableResult) : callableResult
                        sema.bindings.bindExprType(id, type: finalType)
                        return finalType
                    }
                    return driver.helpers.bindAndReturnErrorType(id, sema: sema)
                }

                // Property value call through `operator fun invoke(...)`.
                let invokeName = interner.intern("invoke")
                let invokeCandidates = driver.helpers.collectMemberFunctionCandidates(
                    named: invokeName,
                    receiverType: propResult.type,
                    sema: sema
                ).filter { candidateID in
                    guard let sym = sema.symbols.symbol(candidateID) else { return false }
                    return sym.flags.contains(.operatorFunction)
                }

                if !invokeCandidates.isEmpty {
                    let resolvedArgs = zip(args, argTypes).map { argument, type in
                        CallArg(label: argument.label, isSpread: argument.isSpread, type: type)
                    }
                    let resolved = ctx.resolver.resolveCall(
                        candidates: invokeCandidates,
                        call: CallExpr(
                            range: range,
                            calleeName: invokeName,
                            args: resolvedArgs,
                            explicitTypeArgs: explicitTypeArgs
                        ),
                        expectedType: expectedType,
                        implicitReceiverType: propResult.type,
                        ctx: ctx.semaCtx
                    )
                    if let diagnostic = resolved.diagnostic {
                        ctx.semaCtx.diagnostics.emit(diagnostic)
                        return driver.helpers.bindAndReturnErrorType(id, sema: sema)
                    }
                    if let chosen = resolved.chosenCallee {
                        let returnType = bindCallAndResolveReturnType(id, chosen: chosen, resolved: resolved, sema: sema)
                        sema.bindings.markInvokeOperatorCall(id)
                        let finalType = safeCall ? sema.types.makeNullable(returnType) : returnType
                        sema.bindings.bindExprType(id, type: finalType)
                        return finalType
                    }
                }
            }

            if !isClassNameReceiver,
               args.isEmpty,
               let propResult = driver.helpers.lookupMemberProperty(
                   named: calleeName,
                   receiverType: memberLookupType,
                   sema: sema
               )
            {
                // Check visibility before returning the property.
                if let propSymbol = sema.symbols.symbol(propResult.symbol),
                   !ctx.visibilityChecker.isAccessible(
                       propSymbol,
                       fromFile: ctx.currentFileID,
                       enclosingClass: ctx.enclosingClassSymbol
                   )
                {
                    driver.helpers.emitVisibilityError(for: propSymbol, name: interner.resolve(calleeName), range: range, diagnostics: ctx.semaCtx.diagnostics)
                    return driver.helpers.bindAndReturnErrorType(id, sema: sema)
                }
                sema.bindings.bindIdentifier(id, symbol: propResult.symbol)
                let finalType = safeCall ? sema.types.makeNullable(propResult.type) : propResult.type
                sema.bindings.bindExprType(id, type: finalType)
                return finalType
            }
            if !isClassNameReceiver,
               args.isEmpty,
               let extensionPropertyType = resolveExtensionPropertyGetter(
                   id: id,
                   calleeName: calleeName,
                   range: range,
                   receiverType: memberLookupType,
                   expectedType: expectedType,
                   ctx: ctx
               )
            {
                let finalType = safeCall ? sema.types.makeNullable(extensionPropertyType) : extensionPropertyType
                sema.bindings.bindExprType(id, type: finalType)
                return finalType
            }
            if lookupReceiverType == sema.types.errorType {
                return driver.helpers.bindAndReturnErrorType(id, sema: sema)
            }
            // Kotlin infix `to` is effectively a universal extension used by
            // destructuring-friendly literals (e.g. `1 to "a"`). Keep a
            // lightweight fallback when no symbol candidate was discovered.
            if !isClassNameReceiver,
               args.count == 1,
               interner.resolve(calleeName) == "to"
            {
                let resultType = sema.types.anyType
                let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
                sema.bindings.bindExprType(id, type: finalType)
                return finalType
            }
            if let firstInvisible = invisible.first {
                driver.helpers.emitVisibilityError(for: firstInvisible, name: interner.resolve(calleeName), range: range, diagnostics: ctx.semaCtx.diagnostics)
                return driver.helpers.bindAndReturnErrorType(id, sema: sema)
            }
            if let fallbackType = tryCollectionMemberFallback(
                id,
                calleeName: calleeName,
                isClassNameReceiver: isClassNameReceiver,
                safeCall: safeCall,
                receiverID: receiverID,
                args: args,
                ctx: ctx,
                locals: &locals
            ) {
                return fallbackType
            }
            // Flow member access fallback (CORO-003): allow flow chain calls
            // only when receiver provenance is known as Flow.
            if !isClassNameReceiver, isFlowReceiver {
                let memberName = interner.resolve(calleeName)
                let flowMembers: Set = ["map", "filter", "take", "collect"]
                if flowMembers.contains(memberName) {
                    let acceptsArity = args.count == 1
                    if acceptsArity, memberName == "map" || memberName == "filter" || memberName == "collect" {
                        let expectsLambdaTypeConstraint = switch ast.arena.expr(args[0].expr) {
                        case .callableRef:
                            false
                        default:
                            true
                        }
                        let lambdaReturnType: TypeID = switch memberName {
                        case "filter":
                            sema.types.make(.primitive(.boolean, .nonNull))
                        case "collect":
                            sema.types.unitType
                        default:
                            sema.types.anyType
                        }
                        let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                            params: [flowElementType],
                            returnType: lambdaReturnType,
                            isSuspend: memberName == "collect",
                            nullability: .nonNull
                        )))
                        if expectsLambdaTypeConstraint {
                            _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
                        } else {
                            _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals)
                        }
                    }

                    if acceptsArity {
                        if memberName == "map" || memberName == "filter" || memberName == "take" {
                            sema.bindings.markFlowExpr(id)
                            let resultElementType: TypeID = switch memberName {
                            case "map":
                                if case let .lambdaLiteral(_, bodyExpr, _, _) = ast.arena.expr(args[0].expr),
                                   let mappedType = sema.bindings.exprType(for: bodyExpr)
                                {
                                    mappedType
                                } else {
                                    sema.types.anyType
                                }
                            case "filter", "take":
                                flowElementType
                            default:
                                sema.types.anyType
                            }
                            sema.bindings.bindFlowElementType(resultElementType, forExpr: id)
                        }
                        let resultType: TypeID = memberName == "collect"
                            ? sema.types.unitType
                            : sema.types.anyType
                        let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
                        sema.bindings.bindExprType(id, type: finalType)
                        return finalType
                    }
                }
            }

            let isCoroutineHandleReceiver = isCoroutineHandleReceiverType(
                lookupReceiverType,
                sema: sema,
                interner: interner
            )
            if !isClassNameReceiver, args.isEmpty, isCoroutineHandleReceiver {
                let memberName = interner.resolve(calleeName)
                switch memberName {
                case "cancel":
                    let resultType = sema.types.unitType
                    let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
                    sema.bindings.bindExprType(id, type: finalType)
                    return finalType
                case "join":
                    let resultType = sema.types.unitType
                    let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
                    sema.bindings.bindExprType(id, type: finalType)
                    return finalType
                case "await":
                    let resultType = sema.types.nullableAnyType
                    let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
                    sema.bindings.bindExprType(id, type: finalType)
                    return finalType
                default:
                    break
                }
            }
            // Builder DSL member functions (STDLIB-002).
            if ctx.isBuilderLambdaScope, let activeBuilderKind = ctx.builderKind {
                let name = interner.resolve(calleeName)
                let isBuilderMember: Bool = switch activeBuilderKind {
                case .buildString: name == "append" && args.count == 1
                case .buildList: name == "add" && args.count == 1
                case .buildMap: name == "put" && args.count == 2
                }
                if isBuilderMember {
                    sema.bindings.bindExprType(id, type: sema.types.unitType)
                    return sema.types.unitType
                }
            }

            ctx.semaCtx.diagnostics.error("KSWIFTK-SEMA-0024", "Unresolved member function '\(interner.resolve(calleeName))'.", range: range)
            return driver.helpers.bindAndReturnErrorType(id, sema: sema)
        }

        // Use the companion type as implicit receiver when the candidates were
        // redirected from the owner class to its companion object.
        let effectiveReceiverType = companionReceiverType ?? lookupReceiverType

        let resolvedArgs = zip(args, argTypes).map { CallArg(label: $0.label, isSpread: $0.isSpread, type: $1) }
        let resolved = ctx.resolver.resolveCall(
            candidates: candidates,
            call: CallExpr(range: range, calleeName: calleeName, args: resolvedArgs, explicitTypeArgs: explicitTypeArgs),
            expectedType: expectedType,
            implicitReceiverType: effectiveReceiverType,
            ctx: ctx.semaCtx
        )
        if let diagnostic = resolved.diagnostic {
            if isClassNameReceiver,
               args.isEmpty,
               let classNameReceiverNominalSymbol,
               let staticMember = resolveClassNameMemberValue(
                   ownerNominalSymbol: classNameReceiverNominalSymbol,
                   memberName: calleeName,
                   sema: sema
               )
            {
                if let memberSymbol = sema.symbols.symbol(staticMember.symbol),
                   !ctx.visibilityChecker.isAccessible(
                       memberSymbol,
                       fromFile: ctx.currentFileID,
                       enclosingClass: ctx.enclosingClassSymbol
                   )
                {
                    driver.helpers.emitVisibilityError(
                        for: memberSymbol,
                        name: interner.resolve(calleeName),
                        range: range,
                        diagnostics: ctx.semaCtx.diagnostics
                    )
                    return driver.helpers.bindAndReturnErrorType(id, sema: sema)
                }
                sema.bindings.bindIdentifier(id, symbol: staticMember.symbol)
                sema.bindings.bindExprType(id, type: staticMember.type)
                return staticMember.type
            }
            if let fallbackType = tryCollectionMemberFallback(
                id,
                calleeName: calleeName,
                isClassNameReceiver: isClassNameReceiver,
                safeCall: safeCall,
                receiverID: receiverID,
                args: args,
                ctx: ctx,
                locals: &locals
            ) {
                return fallbackType
            }
            if let projectionDiagnostic = makeProjectionViolationDiagnostic(
                candidates: candidates,
                receiverType: lookupReceiverType,
                calleeName: calleeName,
                range: range,
                sema: sema,
                interner: interner
            ) {
                ctx.semaCtx.diagnostics.emit(projectionDiagnostic)
            } else {
                ctx.semaCtx.diagnostics.emit(diagnostic)
            }
            return driver.helpers.bindAndReturnErrorType(id, sema: sema)
        }
        guard let chosen = resolved.chosenCallee else {
            if isClassNameReceiver,
               args.isEmpty,
               let classNameReceiverNominalSymbol,
               let staticMember = resolveClassNameMemberValue(
                   ownerNominalSymbol: classNameReceiverNominalSymbol,
                   memberName: calleeName,
                   sema: sema
               )
            {
                if let memberSymbol = sema.symbols.symbol(staticMember.symbol),
                   !ctx.visibilityChecker.isAccessible(
                       memberSymbol,
                       fromFile: ctx.currentFileID,
                       enclosingClass: ctx.enclosingClassSymbol
                   )
                {
                    driver.helpers.emitVisibilityError(
                        for: memberSymbol,
                        name: interner.resolve(calleeName),
                        range: range,
                        diagnostics: ctx.semaCtx.diagnostics
                    )
                    return driver.helpers.bindAndReturnErrorType(id, sema: sema)
                }
                sema.bindings.bindIdentifier(id, symbol: staticMember.symbol)
                sema.bindings.bindExprType(id, type: staticMember.type)
                return staticMember.type
            }
            if let fallbackType = tryCollectionMemberFallback(
                id,
                calleeName: calleeName,
                isClassNameReceiver: isClassNameReceiver,
                safeCall: safeCall,
                receiverID: receiverID,
                args: args,
                ctx: ctx,
                locals: &locals
            ) {
                return fallbackType
            }
            ctx.semaCtx.diagnostics.error("KSWIFTK-SEMA-0024", "Unresolved member function '\(interner.resolve(calleeName))'.", range: range)
            return driver.helpers.bindAndReturnErrorType(id, sema: sema)
        }
        driver.helpers.checkDeprecation(
            for: chosen,
            sema: sema,
            interner: interner,
            range: range,
            diagnostics: ctx.semaCtx.diagnostics
        )
        // P5-112: Prohibit super.foo() calls to abstract members.
        if isSuperCall,
           let chosenSym = sema.symbols.symbol(chosen),
           chosenSym.flags.contains(SymbolFlags.abstractType),
           chosenSym.kind == SymbolKind.function || chosenSym.kind == SymbolKind.property
        {
            let memberName = interner.resolve(calleeName)
            ctx.semaCtx.diagnostics.error(
                "KSWIFTK-SEMA-ABSTRACT",
                "Cannot call abstract member '\(memberName)' via super.",
                range: range
            )
            return driver.helpers.bindAndReturnErrorType(id, sema: sema)
        }

        // --- Use-site variance projection check ---
        // When the receiver has projected type arguments (e.g. MutableList<out Number>),
        // check that the member access respects variance constraints.
        if let signature = sema.symbols.functionSignature(for: chosen),
           let varianceResult = sema.types.buildVarianceProjectionSubstitutions(
               receiverType: lookupReceiverType,
               signature: signature,
               symbols: sema.symbols
           )
        {
            // Check if any parameter uses a write-forbidden type parameter
            if !allowsProjectedReceiverUnsafeVariance(chosen, sema: sema, interner: interner),
               let violatingParamIndex = sema.types.checkVarianceViolationInParameters(
                   signature: signature,
                   writeForbiddenSymbols: varianceResult.writeForbiddenSymbols
               )
            {
                let paramType = sema.types.renderType(signature.parameterTypes[violatingParamIndex])
                ctx.semaCtx.diagnostics.error(
                    "KSWIFTK-SEMA-VAR-OUT",
                    "A type projection on the receiver prevents calling '\(interner.resolve(calleeName))' because the type parameter appears in an 'in' position (parameter type '\(paramType)').",
                    range: range
                )
                return driver.helpers.bindAndReturnErrorType(id, sema: sema)
            }

            // For projected types, merge the solver's substitution with the
            // variance projection (projection overrides receiver type params).
            let typeVarBySymbol = sema.types.makeTypeVarBySymbol(signature.typeParameterSymbols)
            let mergedSubstitution = resolved.substitutedTypeArguments.merging(
                varianceResult.covariantSubstitution,
                uniquingKeysWith: { _, projected in projected }
            )
            sema.bindings.bindCall(
                id,
                binding: CallBinding(
                    chosenCallee: chosen,
                    substitutedTypeArguments: mergedSubstitution
                        .sorted(by: { $0.key.rawValue < $1.key.rawValue })
                        .map(\.value),
                    parameterMapping: resolved.parameterMapping
                )
            )
            sema.bindings.bindCallableTarget(id, target: .symbol(chosen))
            let projectedReturnType = sema.types.substituteTypeParameters(
                in: signature.returnType,
                substitution: mergedSubstitution,
                typeVarBySymbol: typeVarBySymbol
            )
            if isSuperCall { sema.bindings.markSuperCall(id) }
            let finalType = safeCall ? sema.types.makeNullable(projectedReturnType) : projectedReturnType
            sema.bindings.bindExprType(id, type: finalType)
            return finalType
        }

        let returnType = bindCallAndResolveReturnType(id, chosen: chosen, resolved: resolved, sema: sema)
        if isSuperCall { sema.bindings.markSuperCall(id) }
        let finalType = safeCall ? sema.types.makeNullable(returnType) : returnType
        sema.bindings.bindExprType(id, type: finalType)
        return finalType
    }

    private func isJavaUtilLocaleType(
        _ type: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        guard let symbolID = driver.helpers.nominalSymbol(
            of: sema.types.makeNonNullable(type),
            types: sema.types
        ),
            let symbol = sema.symbols.symbol(symbolID)
        else {
            return false
        }
        return symbol.fqName == [
            interner.intern("java"),
            interner.intern("util"),
            interner.intern("Locale"),
        ]
    }

    private func isSyntheticStringFormatCandidate(
        _ symbolID: SymbolID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        guard let symbol = sema.symbols.symbol(symbolID),
              symbol.fqName == [
                  interner.intern("kotlin"),
                  interner.intern("text"),
                  interner.intern("format"),
              ],
              let signature = sema.symbols.functionSignature(for: symbolID)
        else {
            return false
        }
        return signature.receiverType == sema.types.stringType
    }

    private func makeSyntheticListType(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        elementType: TypeID
    ) -> TypeID {
        let listFQName: [InternedString] = [
            interner.intern("kotlin"),
            interner.intern("collections"),
            interner.intern("List"),
        ]
        guard let listSymbol = symbols.lookup(fqName: listFQName) else {
            return types.anyType
        }
        return types.make(.classType(ClassType(
            classSymbol: listSymbol,
            args: [.out(elementType)],
            nullability: .nonNull
        )))
    }

    private func tryBindSyntheticStringFormatFallback(
        _ id: ExprID,
        calleeName: InternedString,
        receiverType: TypeID,
        args: [CallArgument],
        argTypes: [TypeID],
        range: SourceRange,
        ctx: TypeInferenceContext,
        expectedType: TypeID?,
        explicitTypeArgs: [TypeID],
        safeCall: Bool
    ) -> TypeID? {
        let sema = ctx.sema
        let interner = ctx.interner
        let candidates = ctx.cachedScopeLookup(calleeName).filter { candidate in
            isSyntheticStringFormatCandidate(candidate, sema: sema, interner: interner)
        }
        guard !candidates.isEmpty else {
            return nil
        }

        let resolvedArgs = zip(args, argTypes).map { argument, type in
            CallArg(label: argument.label, isSpread: argument.isSpread, type: type)
        }
        let resolved = ctx.resolver.resolveCall(
            candidates: candidates,
            call: CallExpr(
                range: range,
                calleeName: calleeName,
                args: resolvedArgs,
                explicitTypeArgs: explicitTypeArgs
            ),
            expectedType: expectedType,
            implicitReceiverType: receiverType,
            ctx: ctx.semaCtx
        )
        guard resolved.diagnostic == nil,
              let chosen = resolved.chosenCallee
        else {
            return nil
        }

        let returnType = bindCallAndResolveReturnType(id, chosen: chosen, resolved: resolved, sema: sema)
        let finalType = safeCall ? sema.types.makeNullable(returnType) : returnType
        sema.bindings.bindExprType(id, type: finalType)
        return finalType
    }

    private func getCollectionElementType(_ type: TypeID, sema: SemaModule, interner: StringInterner) -> TypeID {
        let nonNullType = sema.types.makeNonNullable(type)
        guard case let .classType(classType) = sema.types.kind(of: nonNullType) else {
            return sema.types.anyType
        }

        let name = sema.symbols.symbol(classType.classSymbol).map { interner.resolve($0.name) } ?? ""
        if name == "Map" || name.contains("Map"), classType.args.count == 2 {
            let keyType = switch classType.args[0] {
            case let .invariant(id), let .out(id), let .in(id): id
            case .star: sema.types.anyType
            }
            let valueType = switch classType.args[1] {
            case let .invariant(id), let .out(id), let .in(id): id
            case .star: sema.types.anyType
            }
            let entryFQName: [InternedString] = [
                interner.intern("kotlin"),
                interner.intern("collections"),
                interner.intern("Map"),
                interner.intern("Entry"),
            ]
            if let entrySymbol = sema.symbols.lookup(fqName: entryFQName) ?? sema.symbols.lookupByShortName(interner.intern("Entry")).first {
                return sema.types.make(.classType(ClassType(
                    classSymbol: entrySymbol,
                    args: [.out(keyType), .out(valueType)],
                    nullability: .nonNull
                )))
            }
            return makeSyntheticPairType(
                symbols: sema.symbols,
                types: sema.types,
                interner: interner,
                firstType: keyType,
                secondType: valueType
            )
        }

        if let firstArg = classType.args.first {
            return switch firstArg {
            case let .invariant(id), let .out(id), let .in(id): id
            case .star: sema.types.anyType
            }
        }
        return sema.types.anyType
    }

    private func isMapLikeCollectionType(_ type: TypeID, sema: SemaModule, interner: StringInterner) -> Bool {
        let nonNullType = sema.types.makeNonNullable(type)
        guard case let .classType(classType) = sema.types.kind(of: nonNullType) else {
            return false
        }
        let name = sema.symbols.symbol(classType.classSymbol).map { interner.resolve($0.name) } ?? ""
        return (name == "Map" || name.contains("Map")) && classType.args.count == 2
    }

    private func makeSyntheticPairType(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        firstType: TypeID,
        secondType: TypeID
    ) -> TypeID {
        let pairFQName: [InternedString] = [
            interner.intern("kotlin"),
            interner.intern("Pair"),
        ]
        let pairSymbol = symbols.lookup(fqName: pairFQName) ?? symbols.lookupByShortName(interner.intern("Pair")).first
        guard let pairSym = pairSymbol else {
            return types.anyType
        }
        return types.make(.classType(ClassType(
            classSymbol: pairSym,
            args: [.invariant(firstType), .invariant(secondType)],
            nullability: .nonNull
        )))
    }
}

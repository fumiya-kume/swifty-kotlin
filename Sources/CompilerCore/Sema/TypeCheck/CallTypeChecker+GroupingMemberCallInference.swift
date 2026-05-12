/// Inference for `Grouping.aggregate*` / `fold*` / `reduce*` /
/// `eachCount*` member calls (STDLIB-285/286), plus the
/// `isNullableCollectionIsNullOrEmptyReceiver` predicate that the
/// member-call inference dispatcher consults.
///
/// Split out from `CallTypeChecker+MemberCallInference.swift`.
extension CallTypeChecker {
    func tryGroupingMemberCall(
        _ id: ExprID,
        calleeName: InternedString,
        receiverID: ExprID,
        receiverType: TypeID,
        args: [CallArgument],
        safeCall: Bool,
        expectedType: TypeID?,
        ast: ASTModule,
        sema: SemaModule,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) -> TypeID? {
        let interner = ctx.interner
        let knownNames = KnownCompilerNames(interner: interner)
        guard let groupingKeyType = resolvedGroupingKeyType(of: receiverType, sema: sema, interner: interner) else {
            return nil
        }
        let groupingElementType = resolvedCollectionElementType(
            receiverID: receiverID,
            receiverType: receiverType,
            sema: sema,
            interner: interner,
            ctx: ctx,
            locals: &locals
        )
        let calleeStr = interner.resolve(calleeName)
        let mapSymbol = lookupStdlibSymbol("Map", symbols: sema.symbols, interner: interner)

        func makeMapType(valueType: TypeID) -> TypeID {
            guard let mapSymbol else {
                return sema.types.anyType
            }
            return sema.types.make(.classType(ClassType(
                classSymbol: mapSymbol,
                args: [.invariant(groupingKeyType), .invariant(valueType)],
                nullability: .nonNull
            )))
        }

        func memberTypeArgument(_ type: TypeID, index: Int) -> TypeID? {
            guard case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(type)),
                  classType.args.indices.contains(index)
            else {
                return nil
            }
            return switch classType.args[index] {
            case let .invariant(id), let .out(id), let .in(id):
                id
            case .star:
                nil
            }
        }

        func lookupGroupingMember(named name: String, externalLinkName: String, parameterCount: Int) -> SymbolID? {
            let memberFQName: [InternedString] = [
                interner.intern("kotlin"),
                interner.intern("collections"),
                interner.intern("Grouping"),
                interner.intern(name),
            ]
            return sema.symbols.lookupAll(fqName: memberFQName).first(where: { candidate in
                guard let signature = sema.symbols.functionSignature(for: candidate) else {
                    return false
                }
                return sema.symbols.externalLinkName(for: candidate) == externalLinkName
                    && signature.parameterTypes.count == parameterCount
                    && sema.symbols.symbol(candidate)?.flags.contains(.synthetic) == true
            })
        }

        func bindGroupingMemberCall(
            chosen: SymbolID,
            substitutedTypeArguments: [TypeID],
            parameterMapping: [Int: Int]
        ) {
            sema.bindings.bindCall(
                id,
                binding: CallBinding(
                    chosenCallee: chosen,
                    substitutedTypeArguments: substitutedTypeArguments,
                    parameterMapping: parameterMapping
                )
            )
            sema.bindings.bindCallableTarget(id, target: .symbol(chosen))
        }

        switch calleeStr {
        case "eachCount":
            guard args.isEmpty else {
                ctx.semaCtx.diagnostics.error(
                    "KSWIFTK-SEMA-0024",
                    "No viable overload found for call.",
                    range: ast.arena.exprRange(id)
                )
                return driver.helpers.bindAndReturnErrorType(id, sema: sema)
            }
            let resultType = makeMapType(valueType: sema.types.intType)
            let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
            sema.bindings.bindExprType(id, type: finalType)
            return finalType

        case "aggregate":
            guard args.count == 1 else {
                ctx.semaCtx.diagnostics.error(
                    "KSWIFTK-SEMA-0024",
                    "No viable overload found for call.",
                    range: ast.arena.exprRange(id)
                )
                return driver.helpers.bindAndReturnErrorType(id, sema: sema)
            }
            let expectedAggregateValueType = memberTypeArgument(expectedType ?? sema.types.anyType, index: 1)
                ?? sema.types.anyType
            let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                params: [
                    groupingKeyType,
                    sema.types.makeNullable(expectedAggregateValueType),
                    groupingElementType,
                    sema.types.booleanType,
                ],
                returnType: expectedAggregateValueType
            )))
            if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
            }
            _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
            let aggregateValueType = expectedAggregateValueType == sema.types.anyType
                ? inferredLambdaReturnType(argExpr: args[0].expr, ast: ast, sema: sema)
                : expectedAggregateValueType
            let resultType = makeMapType(valueType: aggregateValueType)
            if let chosen = lookupGroupingMember(named: "aggregate", externalLinkName: "kk_grouping_aggregate", parameterCount: 1) {
                bindGroupingMemberCall(
                    chosen: chosen,
                    substitutedTypeArguments: [groupingElementType, groupingKeyType, aggregateValueType],
                    parameterMapping: [0: 0]
                )
            }
            let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
            sema.bindings.bindExprType(id, type: finalType)
            return finalType

        case "aggregateTo":
            guard args.count == 2 else {
                ctx.semaCtx.diagnostics.error(
                    "KSWIFTK-SEMA-0024",
                    "No viable overload found for call.",
                    range: ast.arena.exprRange(id)
                )
                return driver.helpers.bindAndReturnErrorType(id, sema: sema)
            }
            let destinationType = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals)
            let destinationValueType = memberTypeArgument(destinationType, index: 1) ?? sema.types.anyType
            let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                params: [
                    groupingKeyType,
                    sema.types.makeNullable(destinationValueType),
                    groupingElementType,
                    sema.types.booleanType,
                ],
                returnType: destinationValueType
            )))
            if let lambdaExpr = ast.arena.expr(args[1].expr), lambdaExpr.isLambdaOrCallableRef {
                sema.bindings.markCollectionHOFLambdaExpr(args[1].expr)
            }
            _ = driver.inferExpr(args[1].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
            if let chosen = lookupGroupingMember(named: "aggregateTo", externalLinkName: "kk_grouping_aggregateTo", parameterCount: 2) {
                bindGroupingMemberCall(
                    chosen: chosen,
                    substitutedTypeArguments: [groupingElementType, groupingKeyType, destinationValueType],
                    parameterMapping: [0: 0, 1: 1]
                )
            }
            let finalType = safeCall ? sema.types.makeNullable(destinationType) : destinationType
            sema.bindings.bindExprType(id, type: finalType)
            return finalType

        case "fold":
            guard args.count == 2 else {
                ctx.semaCtx.diagnostics.error(
                    "KSWIFTK-SEMA-0024",
                    "No viable overload found for call.",
                    range: ast.arena.exprRange(id)
                )
                return driver.helpers.bindAndReturnErrorType(id, sema: sema)
            }
            let expectedGroupingValueType: TypeID = if let expectedType,
                                                       case let .classType(expectedClassType) = sema.types.kind(of: sema.types.makeNonNullable(expectedType)),
                                                       let expectedSymbol = sema.symbols.symbol(expectedClassType.classSymbol),
                                                       knownNames.isMapLikeSymbol(expectedSymbol),
                                                       expectedClassType.args.count >= 2
            {
                switch expectedClassType.args[1] {
                case let .invariant(id), let .out(id), let .in(id): id
                case .star: sema.types.anyType
                }
            } else {
                sema.types.anyType
            }
            let firstArgLabel = args[0].label.map { interner.resolve($0) }
            let useInitialValueSelectorOverload = if let firstArgLabel {
                firstArgLabel == "initialValueSelector"
            } else if case .lambdaLiteral = ast.arena.expr(args[0].expr) {
                true
            } else {
                ast.arena.expr(args[0].expr)?.isLambdaOrCallableRef ?? false
            }
            if useInitialValueSelectorOverload {
                let initialValueSelectorExpectedType = sema.types.make(.functionType(FunctionType(
                    params: [groupingKeyType, groupingElementType],
                    returnType: expectedGroupingValueType
                )))
                let initialValueSelectorType = driver.inferExpr(
                    args[0].expr,
                    ctx: ctx,
                    locals: &locals,
                    expectedType: initialValueSelectorExpectedType
                )
                if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                    sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
                }
                let groupingResultValueType: TypeID = if case let .functionType(fnType) = sema.types.kind(of: initialValueSelectorType) {
                    fnType.returnType
                } else if expectedGroupingValueType != sema.types.anyType {
                    expectedGroupingValueType
                } else {
                    sema.types.anyType
                }
                let operationExpectedType = sema.types.make(.functionType(FunctionType(
                    params: [groupingKeyType, groupingResultValueType, groupingElementType],
                    returnType: groupingResultValueType
                )))
                if let lambdaExpr = ast.arena.expr(args[1].expr), lambdaExpr.isLambdaOrCallableRef {
                    sema.bindings.markCollectionHOFLambdaExpr(args[1].expr)
                }
                _ = driver.inferExpr(args[1].expr, ctx: ctx, locals: &locals, expectedType: operationExpectedType)
                let resultType = makeMapType(valueType: groupingResultValueType)
                let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
                sema.bindings.bindExprType(id, type: finalType)
                return finalType
            } else {
                let initialType = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: expectedGroupingValueType)
                let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                    params: [groupingKeyType, initialType, groupingElementType],
                    returnType: initialType
                )))
                if let lambdaExpr = ast.arena.expr(args[1].expr), lambdaExpr.isLambdaOrCallableRef {
                    sema.bindings.markCollectionHOFLambdaExpr(args[1].expr)
                }
                _ = driver.inferExpr(args[1].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
                let resultType = makeMapType(valueType: initialType)
                let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
                sema.bindings.bindExprType(id, type: finalType)
                return finalType
            }

        case "reduce":
            guard args.count == 1 else {
                ctx.semaCtx.diagnostics.error(
                    "KSWIFTK-SEMA-0024",
                    "No viable overload found for call.",
                    range: ast.arena.exprRange(id)
                )
                return driver.helpers.bindAndReturnErrorType(id, sema: sema)
            }
            let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                params: [groupingElementType, groupingElementType],
                returnType: groupingElementType
            )))
            if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
            }
            _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
            let resultType = makeMapType(valueType: groupingElementType)
            let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
            sema.bindings.bindExprType(id, type: finalType)
            return finalType

        default:
            return nil
        }
    }

    func isNullableCollectionIsNullOrEmptyReceiver(
        _ receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        guard case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(receiverType)),
              let symbol = sema.symbols.symbol(classType.classSymbol)
        else {
            return false
        }
        switch KnownCompilerNames(interner: interner).collectionKind(of: symbol) {
        case .map?, .set?, .array?, .list?, .collection?:
            return true
        case .sequence?, nil:
            return false
        }
    }

}

import Foundation

/// Helpers split from `CallTypeChecker+MemberCallInference.swift`:
/// Synthetic-stdlib bind/try fallbacks (String, BigInteger, Duration, Map, ThreadLocal, ReadWriteLock, Comparator, Result, KClass associatedObject) plus collection / numeric / closeable / locale type-extractor helpers used from within `inferMemberCallImpl`.
///
/// Split out to isolate merge conflicts between parallel stdlib PRs.
extension CallTypeChecker {

    func isJavaUtilLocaleType(
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

    func isMutableListType(
        _ type: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        let knownNames = KnownCompilerNames(interner: interner)
        guard let symbolID = driver.helpers.nominalSymbol(
            of: sema.types.makeNonNullable(type),
            types: sema.types
        ),
            let symbol = sema.symbols.symbol(symbolID)
        else {
            return false
        }
        return symbol.name == knownNames.mutableList
            || symbol.fqName == knownNames.kotlinCollectionsMutableListFQName
    }

    func isSyntheticStringFormatCandidate(
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

    func tryBindSyntheticStringFormatFallback(
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
        tryBindSyntheticStringMemberFallback(
            id,
            calleeName: calleeName,
            receiverType: receiverType,
            args: args,
            argTypes: argTypes,
            range: range,
            ctx: ctx,
            expectedType: expectedType,
            explicitTypeArgs: explicitTypeArgs,
            safeCall: safeCall
        )
    }

    func tryBindSyntheticStringMemberFallback(
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
        var candidates = ctx.cachedScopeLookup(calleeName).filter { candidate in
            isSyntheticStringMemberCandidate(
                candidate,
                named: calleeName,
                receiverType: receiverType,
                sema: sema,
                interner: interner
            )
        }
        if candidates.isEmpty {
            let stringMemberFQName = [
                interner.intern("kotlin"),
                interner.intern("text"),
                calleeName,
            ]
            candidates = sema.symbols.lookupAll(fqName: stringMemberFQName).filter { candidate in
                isSyntheticStringMemberCandidate(
                    candidate,
                    named: calleeName,
                    receiverType: receiverType,
                    sema: sema,
                    interner: interner
                )
            }
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
        if let diagnostic = resolved.diagnostic {
            ctx.semaCtx.diagnostics.emit(diagnostic)
            sema.bindings.bindExprType(id, type: sema.types.errorType)
            return sema.types.errorType
        }
        guard let chosen = resolved.chosenCallee else {
            return nil
        }

        let returnType = bindCallAndResolveReturnType(id, chosen: chosen, resolved: resolved, sema: sema)
        let finalType = safeCall ? sema.types.makeNullable(returnType) : returnType
        sema.bindings.bindExprType(id, type: finalType)
        return finalType
    }

    func tryBindSyntheticBigIntegerMemberFallback(
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
        let normalizedReceiverType = sema.types.makeNonNullable(receiverType)
        let bigIntegerFQName = [
            interner.intern("java"),
            interner.intern("math"),
            interner.intern("BigInteger"),
        ]
        guard let bigIntegerSymbol = sema.symbols.lookup(fqName: bigIntegerFQName),
              case let .classType(receiverClass) = sema.types.kind(of: normalizedReceiverType),
              receiverClass.classSymbol == bigIntegerSymbol
        else {
            return nil
        }

        let extensionFQName = [
            interner.intern("kotlin"),
            calleeName,
        ]
        let candidates = sema.symbols.lookupAll(fqName: extensionFQName).filter { candidate in
            guard let symbol = sema.symbols.symbol(candidate),
                  symbol.kind == .function,
                  let signature = sema.symbols.functionSignature(for: candidate)
            else {
                return false
            }
            return signature.receiverType == normalizedReceiverType &&
                signature.parameterTypes == [normalizedReceiverType]
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
        if let diagnostic = resolved.diagnostic {
            ctx.semaCtx.diagnostics.emit(diagnostic)
            sema.bindings.bindExprType(id, type: sema.types.errorType)
            return sema.types.errorType
        }
        guard let chosen = resolved.chosenCallee else {
            return nil
        }

        let returnType = bindCallAndResolveReturnType(id, chosen: chosen, resolved: resolved, sema: sema)
        let finalType = safeCall ? sema.types.makeNullable(returnType) : returnType
        sema.bindings.bindExprType(id, type: finalType)
        return finalType
    }

    func isSyntheticStringMemberCandidate(
        _ symbolID: SymbolID,
        named calleeName: InternedString,
        receiverType actualReceiverType: TypeID? = nil,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        guard let symbol = sema.symbols.symbol(symbolID),
              symbol.fqName == [
                  interner.intern("kotlin"),
                  interner.intern("text"),
                  calleeName,
              ],
              let signature = sema.symbols.functionSignature(for: symbolID)
        else {
            return false
        }
        guard let candidateReceiverType = signature.receiverType else {
            return false
        }
        guard isSyntheticStringLikeType(candidateReceiverType, sema: sema) else {
            return false
        }
        if let actualReceiverType {
            return sema.types.isSubtype(
                sema.types.makeNonNullable(actualReceiverType),
                sema.types.makeNonNullable(candidateReceiverType)
            )
        }
        return true
    }

    func bindSyntheticStringMemberDirectlyIfAvailable(
        _ id: ExprID,
        calleeName: InternedString,
        argumentCount: Int,
        receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) {
        let normalizedReceiverType = sema.types.makeNonNullable(receiverType)
        guard isSyntheticStringLikeType(normalizedReceiverType, sema: sema) else {
            return
        }
        let stringMemberFQName = [
            interner.intern("kotlin"),
            interner.intern("text"),
            calleeName,
        ]
        guard let chosen = sema.symbols.lookupAll(fqName: stringMemberFQName).first(where: { candidate in
                  isSyntheticStringMemberCandidate(
                      candidate,
                      named: calleeName,
                      receiverType: normalizedReceiverType,
                      sema: sema,
                      interner: interner
                  )
                      && (sema.symbols.functionSignature(for: candidate)?.parameterTypes.count ?? Int.max) == argumentCount
              })
        else {
            return
        }
        let mapping = Dictionary(uniqueKeysWithValues: (0..<argumentCount).map { ($0, $0) })
        sema.bindings.bindCall(
            id,
            binding: CallBinding(
                chosenCallee: chosen,
                substitutedTypeArguments: [],
                parameterMapping: mapping
            )
        )
        sema.bindings.bindCallableTarget(id, target: .symbol(chosen))
    }

    func syntheticCharSequenceType(sema: SemaModule) -> TypeID? {
        guard let charSequenceSymbol = sema.types.charSequenceInterfaceSymbol else {
            return nil
        }
        return sema.types.make(.classType(ClassType(
            classSymbol: charSequenceSymbol,
            args: [],
            nullability: .nonNull
        )))
    }

    func isSyntheticStringLikeType(_ type: TypeID, sema: SemaModule) -> Bool {
        let nonNullType = sema.types.makeNonNullable(type)
        if nonNullType == sema.types.stringType {
            return true
        }
        guard let charSequenceType = syntheticCharSequenceType(sema: sema) else {
            return false
        }
        return nonNullType == charSequenceType
    }

    func getCollectionElementType(_ type: TypeID, sema: SemaModule, interner: StringInterner) -> TypeID {
        let knownNames = KnownCompilerNames(interner: interner)
        let nonNullType = sema.types.makeNonNullable(type)
        guard case let .classType(classType) = sema.types.kind(of: nonNullType) else {
            return sema.types.anyType
        }

        if let symbol = sema.symbols.symbol(classType.classSymbol),
           knownNames.isMapLikeSymbol(symbol),
           classType.args.count == 2
        {
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

    func resolvedGroupingKeyType(
        of type: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> TypeID? {
        let knownNames = KnownCompilerNames(interner: interner)
        let nonNullType = sema.types.makeNonNullable(type)
        guard case let .classType(classType) = sema.types.kind(of: nonNullType),
              let symbol = sema.symbols.symbol(classType.classSymbol),
              knownNames.isGroupingSymbol(symbol),
              classType.args.count >= 2
        else {
            return nil
        }
        return switch classType.args[1] {
        case let .invariant(id), let .out(id), let .in(id):
            id
        case .star:
            sema.types.anyType
        }
    }

    func tryDurationToComponentsMemberCall(
        _ id: ExprID,
        calleeName: InternedString,
        receiverType: TypeID,
        args: [CallArgument],
        explicitTypeArgs: [TypeID],
        expectedType: TypeID?,
        safeCall: Bool,
        ast: ASTModule,
        sema: SemaModule,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) -> TypeID? {
        let interner = ctx.interner
        guard interner.resolve(calleeName) == "toComponents",
              args.count == 1,
              explicitTypeArgs.count <= 1,
              isKotlinDurationType(receiverType, sema: sema, interner: interner),
              let lambdaExpr = ast.arena.expr(args[0].expr),
              lambdaExpr.isLambdaOrCallableRef
        else {
            return nil
        }

        let lambdaArity: Int
        if case let .lambdaLiteral(params, _, _, _) = lambdaExpr, !params.isEmpty {
            lambdaArity = params.count
        } else {
            lambdaArity = 5
        }

        let actionParameterTypes: [TypeID]
        let externalLinkName: String
        switch lambdaArity {
        case 2:
            actionParameterTypes = [sema.types.longType, sema.types.intType]
            externalLinkName = "kk_duration_toComponents_seconds"
        case 3:
            actionParameterTypes = [sema.types.longType, sema.types.intType, sema.types.intType]
            externalLinkName = "kk_duration_toComponents_minutes"
        case 4:
            actionParameterTypes = [sema.types.longType, sema.types.intType, sema.types.intType, sema.types.intType]
            externalLinkName = "kk_duration_toComponents_hours"
        case 5:
            actionParameterTypes = [
                sema.types.longType,
                sema.types.intType,
                sema.types.intType,
                sema.types.intType,
                sema.types.intType,
            ]
            externalLinkName = "kk_duration_toComponents_days"
        default:
            return nil
        }

        let expectedReturnType = explicitTypeArgs.first ?? expectedType ?? sema.types.anyType
        let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
            params: actionParameterTypes,
            returnType: expectedReturnType,
            isSuspend: false,
            nullability: .nonNull
        )))
        sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
        let inferredActionType = driver.inferExpr(
            args[0].expr,
            ctx: ctx,
            locals: &locals,
            expectedType: lambdaExpectedType
        )

        let resultType: TypeID = if let explicit = explicitTypeArgs.first {
            explicit
        } else if expectedType != nil, expectedReturnType != sema.types.anyType {
            expectedReturnType
        } else if case let .functionType(functionType) = sema.types.kind(
            of: sema.types.makeNonNullable(inferredActionType)
        ) {
            functionType.returnType
        } else {
            inferredLambdaReturnType(argExpr: args[0].expr, ast: ast, sema: sema)
        }

        let durationMemberFQName = [
            interner.intern("kotlin"),
            interner.intern("time"),
            interner.intern("Duration"),
            calleeName,
        ]
        if let chosen = sema.symbols.lookupAll(fqName: durationMemberFQName).first(where: { candidate in
            sema.symbols.externalLinkName(for: candidate) == externalLinkName
        }) {
            sema.bindings.bindCall(
                id,
                binding: CallBinding(
                    chosenCallee: chosen,
                    substitutedTypeArguments: [resultType],
                    parameterMapping: [0: 0]
                )
            )
            sema.bindings.bindCallableTarget(id, target: .symbol(chosen))
        }

        let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
        sema.bindings.bindExprType(id, type: finalType)
        return finalType
    }

    func isKotlinDurationType(
        _ type: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        guard case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(type)),
              let symbol = sema.symbols.symbol(classType.classSymbol)
        else {
            return false
        }
        return symbol.fqName == [
            interner.intern("kotlin"),
            interner.intern("time"),
            interner.intern("Duration"),
        ]
    }

    /// Extract the inferred return type from a lambda argument.
    /// Checks the lambda body expression first, then falls back to the function
    /// type of the argument expression. Returns `anyType` if neither is available.
    func inferredLambdaReturnType(
        argExpr: ExprID,
        ast: ASTModule,
        sema: SemaModule
    ) -> TypeID {
        if case let .lambdaLiteral(_, bodyExpr, _, _) = ast.arena.expr(argExpr) {
            return sema.bindings.exprType(for: bodyExpr) ?? sema.types.anyType
        } else if case let .functionType(fnType) = sema.types.kind(
            of: sema.bindings.exprType(for: argExpr) ?? sema.types.anyType
        ) {
            return fnType.returnType
        } else {
            return sema.types.anyType
        }
    }

    /// Extract the element type from a List type.
    /// If the type is List<R> (or similar single-type-arg list), returns R.
    /// Returns `anyType` for non-list types to avoid mis-inferring element types
    /// from unrelated generic types (e.g., Pair<K,V>).
    func extractListElementType(
        _ type: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> TypeID {
        let knownNames = KnownCompilerNames(interner: interner)
        let nonNullType = sema.types.makeNonNullable(type)
        guard case let .classType(classType) = sema.types.kind(of: nonNullType),
              let symbol = sema.symbols.symbol(classType.classSymbol),
              knownNames.isConcreteListLikeSymbol(symbol),
              classType.args.count == 1,
              let firstArg = classType.args.first
        else {
            return sema.types.anyType
        }
        return switch firstArg {
        case let .invariant(id), let .out(id), let .in(id): id
        case .star: sema.types.anyType
        }
    }

    /// Extract the element type from flattenable Iterable/Sequence-like return types.
    func extractIterableOrSequenceElementType(
        _ type: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> TypeID {
        let knownNames = KnownCompilerNames(interner: interner)
        let nonNullType = sema.types.makeNonNullable(type)
        guard case let .classType(classType) = sema.types.kind(of: nonNullType),
              let symbol = sema.symbols.symbol(classType.classSymbol),
              classType.args.count == 1,
              let firstArg = classType.args.first
        else {
            return sema.types.anyType
        }
        let symbolName = interner.resolve(symbol.name)
        let isFlattenable = knownNames.isConcreteListLikeSymbol(symbol)
            || knownNames.isSetLikeSymbol(symbol)
            || knownNames.isSequenceSymbol(symbol)
            || symbolName == "Iterable"
            || symbolName == "Collection"
        guard isFlattenable else {
            return sema.types.anyType
        }
        return switch firstArg {
        case let .invariant(id), let .out(id), let .in(id): id
        case .star: sema.types.anyType
        }
    }

    /// Extract the element type T from a Comparator<T> receiver type.
    /// Returns `nil` if the receiver does not resolve to Comparator.
    func resolvedComparatorElementType(
        of type: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> TypeID? {
        let comparatorFQName: [InternedString] = [
            interner.intern("kotlin"),
            interner.intern("Comparator"),
        ]
        var visited: Set<SymbolID> = []
        return resolvedComparatorElementType(
            of: type,
            comparatorFQName: comparatorFQName,
            sema: sema,
            visited: &visited
        )
    }

    func resolvedComparatorElementType(
        of type: TypeID,
        comparatorFQName: [InternedString],
        sema: SemaModule,
        visited: inout Set<SymbolID>
    ) -> TypeID? {
        let nonNullType = sema.types.makeNonNullable(type)
        switch sema.types.kind(of: nonNullType) {
        case let .classType(classType):
            guard let symbol = sema.symbols.symbol(classType.classSymbol),
                  symbol.fqName == comparatorFQName,
                  let firstArg = classType.args.first
            else {
                return nil
            }
            return switch firstArg {
            case let .invariant(id), let .out(id), let .in(id): id
            case .star: sema.types.anyType
            }

        case let .intersection(parts):
            for part in parts {
                if let elementType = resolvedComparatorElementType(
                    of: part,
                    comparatorFQName: comparatorFQName,
                    sema: sema,
                    visited: &visited
                ) {
                    return elementType
                }
            }
            return nil

        case let .typeParam(typeParam):
            guard visited.insert(typeParam.symbol).inserted else {
                return nil
            }
            for bound in sema.symbols.typeParameterUpperBounds(for: typeParam.symbol) {
                if let elementType = resolvedComparatorElementType(
                    of: bound,
                    comparatorFQName: comparatorFQName,
                    sema: sema,
                    visited: &visited
                ) {
                    return elementType
                }
            }
            return nil

        default:
            return nil
        }
    }

    func resolvedCollectionElementType(
        receiverID: ExprID,
        receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) -> TypeID {
        let directElementType = getCollectionElementType(receiverType, sema: sema, interner: interner)
        if directElementType != sema.types.anyType {
            return directElementType
        }
        guard let receiverExpr = ctx.ast.arena.expr(receiverID) else {
            return directElementType
        }
        switch receiverExpr {
        case let .call(calleeExpr, _, args, _):
            guard let callee = ctx.ast.arena.expr(calleeExpr),
                  case let .nameRef(name, _) = callee
            else {
                return directElementType
            }
            let sequenceOfName = interner.intern("sequenceOf")
            if name == sequenceOfName {
                let elementTypes = args.map { argument in
                    driver.inferExpr(argument.expr, ctx: ctx, locals: &locals, expectedType: nil)
                }
                guard !elementTypes.isEmpty else {
                    return sema.types.anyType
                }
                let hasNullableElement = elementTypes.contains { inferredType in
                    inferredType == sema.types.nullableNothingType
                        || sema.types.makeNonNullable(inferredType) != inferredType
                }
                let concreteTypes = elementTypes.compactMap { inferredType -> TypeID? in
                    if inferredType == sema.types.nullableNothingType {
                        return nil
                    }
                    return sema.types.makeNonNullable(inferredType)
                }
                let baseType = concreteTypes.isEmpty ? sema.types.anyType : sema.types.lub(concreteTypes)
                return hasNullableElement ? sema.types.makeNullable(baseType) : baseType
            }
            let generateSequenceName = interner.intern("generateSequence")
            if name == generateSequenceName, let firstArg = args.first {
                let firstArgType = driver.inferExpr(firstArg.expr, ctx: ctx, locals: &locals, expectedType: nil)
                if case let .functionType(functionType) = sema.types.kind(of: sema.types.makeNonNullable(firstArgType)),
                   functionType.params.isEmpty
                {
                    return sema.types.makeNonNullable(functionType.returnType)
                }
                return firstArgType
            }
            return directElementType
        default:
            return directElementType
        }
    }

    func isMapLikeCollectionType(_ type: TypeID, sema: SemaModule, interner: StringInterner) -> Bool {
        let knownNames = KnownCompilerNames(interner: interner)
        let nonNullType = sema.types.makeNonNullable(type)
        guard case let .classType(classType) = sema.types.kind(of: nonNullType),
              let symbol = sema.symbols.symbol(classType.classSymbol)
        else {
            return false
        }
        return knownNames.isMapLikeSymbol(symbol) && classType.args.count == 2
    }

    func isConcreteListLikeType(_ type: TypeID, sema: SemaModule, interner: StringInterner) -> Bool {
        let knownNames = KnownCompilerNames(interner: interner)
        let nonNullType = sema.types.makeNonNullable(type)
        guard case let .classType(classType) = sema.types.kind(of: nonNullType),
              let symbol = sema.symbols.symbol(classType.classSymbol)
        else {
            return false
        }
        return knownNames.isConcreteListLikeSymbol(symbol) && classType.args.count == 1
    }

    func makeSyntheticPairType(
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

    // MARK: - Numeric companion static functions (STDLIB-NUM-130)

    /// Returns `(returnType, externalLinkName)` for built-in primitive companion static functions
    /// like `Double.fromBits(bits: Long)` and `Float.fromBits(bits: Int)`.
    func numericCompanionFunction(
        typeName: String,
        memberName: String,
        sema: SemaModule
    ) -> (TypeID, String)? {
        let types = sema.types
        switch (typeName, memberName) {
        case ("Double", "fromBits"):
            return (types.doubleType, "kk_double_fromBits")
        case ("Float", "fromBits"):
            return (types.floatType, "kk_float_fromBits")
        default:
            return nil
        }
    }

    // MARK: - Numeric companion constants (STDLIB-153)

    func numericCompanionConstant(
        typeName: String,
        memberName: String,
        sema: SemaModule
    ) -> (TypeID, KIRExprKind)? {
        let types = sema.types
        switch (typeName, memberName) {
        // Int (32-bit in Kotlin)
        case ("Int", "MAX_VALUE"): return (types.intType, .intLiteral(Int64(Int32.max)))
        case ("Int", "MIN_VALUE"): return (types.intType, .intLiteral(Int64(Int32.min)))
        case ("Int", "SIZE_BITS"): return (types.intType, .intLiteral(32))
        case ("Int", "SIZE_BYTES"): return (types.intType, .intLiteral(4))
        // Long (64-bit)
        case ("Long", "MAX_VALUE"): return (types.longType, .longLiteral(Int64.max))
        case ("Long", "MIN_VALUE"): return (types.longType, .longLiteral(Int64.min))
        case ("Long", "SIZE_BITS"): return (types.intType, .intLiteral(64))
        case ("Long", "SIZE_BYTES"): return (types.intType, .intLiteral(8))
        // Short
        case ("Short", "MAX_VALUE"): return (types.intType, .intLiteral(Int64(Int16.max)))
        case ("Short", "MIN_VALUE"): return (types.intType, .intLiteral(Int64(Int16.min)))
        // Byte
        case ("Byte", "MAX_VALUE"): return (types.intType, .intLiteral(Int64(Int8.max)))
        case ("Byte", "MIN_VALUE"): return (types.intType, .intLiteral(Int64(Int8.min)))
        // UInt (32-bit unsigned)
        case ("UInt", "MAX_VALUE"): return (types.uintType, .uintLiteral(UInt64(UInt32.max)))
        case ("UInt", "MIN_VALUE"): return (types.uintType, .uintLiteral(0))
        case ("UInt", "SIZE_BITS"): return (types.intType, .intLiteral(32))
        case ("UInt", "SIZE_BYTES"): return (types.intType, .intLiteral(4))
        // ULong (64-bit unsigned)
        case ("ULong", "MAX_VALUE"): return (types.ulongType, .ulongLiteral(UInt64.max))
        case ("ULong", "MIN_VALUE"): return (types.ulongType, .ulongLiteral(0))
        case ("ULong", "SIZE_BITS"): return (types.intType, .intLiteral(64))
        case ("ULong", "SIZE_BYTES"): return (types.intType, .intLiteral(8))
        // UByte (8-bit unsigned)
        case ("UByte", "MAX_VALUE"): return (types.ubyteType, .uintLiteral(UInt64(UInt8.max)))
        case ("UByte", "MIN_VALUE"): return (types.ubyteType, .uintLiteral(0))
        case ("UByte", "SIZE_BITS"): return (types.intType, .intLiteral(8))
        case ("UByte", "SIZE_BYTES"): return (types.intType, .intLiteral(1))
        // UShort (16-bit unsigned)
        case ("UShort", "MAX_VALUE"): return (types.ushortType, .uintLiteral(UInt64(UInt16.max)))
        case ("UShort", "MIN_VALUE"): return (types.ushortType, .uintLiteral(0))
        case ("UShort", "SIZE_BITS"): return (types.intType, .intLiteral(16))
        case ("UShort", "SIZE_BYTES"): return (types.intType, .intLiteral(2))
        // Float
        case ("Float", "MAX_VALUE"): return (types.floatType, .floatLiteral(Double(Float.greatestFiniteMagnitude)))
        case ("Float", "MIN_VALUE"): return (types.floatType, .floatLiteral(Double(Float.leastNonzeroMagnitude)))
        case ("Float", "NaN"): return (types.floatType, .floatLiteral(Double(Float.nan)))
        case ("Float", "POSITIVE_INFINITY"): return (types.floatType, .floatLiteral(Double(Float.infinity)))
        case ("Float", "NEGATIVE_INFINITY"): return (types.floatType, .floatLiteral(Double(-Float.infinity)))
        // Double
        case ("Double", "MAX_VALUE"): return (types.doubleType, .doubleLiteral(Double.greatestFiniteMagnitude))
        case ("Double", "MIN_VALUE"): return (types.doubleType, .doubleLiteral(Double.leastNonzeroMagnitude))
        case ("Double", "NaN"): return (types.doubleType, .doubleLiteral(Double.nan))
        case ("Double", "POSITIVE_INFINITY"): return (types.doubleType, .doubleLiteral(Double.infinity))
        case ("Double", "NEGATIVE_INFINITY"): return (types.doubleType, .doubleLiteral(-Double.infinity))
        default: return nil
        }
    }

    /// Returns true if `receiverType` conforms to Closeable,
    /// so that `.use {}` is only treated as a scope function on Closeable receivers.
    /// Note: AutoCloseable is registered as a typealias to Closeable (see
    /// HeaderHelpers+SyntheticCloseableStubs.swift), so checking Closeable alone
    /// covers both Closeable and AutoCloseable receivers.
    ///
    /// As a fallback for synthetic IO types (BufferedReader, BufferedWriter, InputStream,
    /// OutputStream) that implement Closeable through the nominal supertype chain registered
    /// by registerSyntheticFileIOStubs, we also accept any class type whose class symbol
    /// has a `close()` member function registered with no parameters — this ensures that
    /// `file.bufferedReader().use { }` and similar patterns resolve correctly.
    func isCloseableReceiver(_ receiverType: TypeID, sema: SemaModule, interner: StringInterner) -> Bool {
        guard let closeableType = sema.types.closeableTypeID else {
            return false
        }
        let nonNullReceiver = sema.types.makeNonNullable(receiverType)
        if sema.types.isSubtype(nonNullReceiver, closeableType) {
            return true
        }
        // STDLIB-030-BUG-01: When the receiver is a type parameter (e.g. `T` in
        // `fun <T : AutoCloseable> useIt(t: T)`), the general isSubtype now traverses
        // upper bounds (see Subtyping.swift). As an explicit fallback, also check directly:
        // if any registered upper bound of T is a subtype of Closeable, accept it.
        if case let .typeParam(typeParam) = sema.types.kind(of: nonNullReceiver) {
            let upperBounds = sema.symbols.typeParameterUpperBounds(for: typeParam.symbol)
            for bound in upperBounds {
                let nonNullBound = sema.types.makeNonNullable(bound)
                if sema.types.isSubtype(nonNullBound, closeableType) {
                    return true
                }
            }
        }
        // Fallback: check if the class explicitly declares Closeable or AutoCloseable
        // in its registered supertype list.  This handles synthetic IO types
        // (BufferedReader, BufferedWriter, InputStream, OutputStream) whose supertypes
        // are registered via registerSyntheticFileIOStubs / setDirectSupertypes, without
        // accidentally treating every class that happens to define close() as Closeable.
        guard let closeableSymbol = sema.types.closeableInterfaceSymbol,
              case let .classType(classType) = sema.types.kind(of: nonNullReceiver)
        else {
            return false
        }
        let directSupertypes = sema.symbols.directSupertypes(for: classType.classSymbol)
        return directSupertypes.contains(closeableSymbol)
    }

    // MARK: - Result helpers (STDLIB-590)

    /// Extract the element type T from a Result<out T> receiver type.
    func extractResultElementType(
        _ receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> TypeID? {
        let knownNames = KnownCompilerNames(interner: interner)
        let nonNull = sema.types.makeNonNullable(receiverType)
        guard case let .classType(classType) = sema.types.kind(of: nonNull),
              let symbol = sema.symbols.symbol(classType.classSymbol),
              symbol.fqName == knownNames.kotlinResultFQName,
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

    /// Look up a synthetic Result member function by name.
    func lookupResultMember(
        _ name: String,
        sema: SemaModule,
        interner: StringInterner
    ) -> SymbolID? {
        let knownNames = KnownCompilerNames(interner: interner)
        let memberFQName = knownNames.kotlinResultFQName + [interner.intern(name)]
        return sema.symbols.lookupAll(fqName: memberFQName).first(where: { symbolID in
            guard let sym = sema.symbols.symbol(symbolID) else { return false }
            return sym.kind == .function && sym.flags.contains(.synthetic)
        })
    }

    /// Construct a Result<T> type from an element type.
    func makeResultType(
        elementType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> TypeID? {
        let knownNames = KnownCompilerNames(interner: interner)
        guard let resultClassSymbol = sema.symbols.lookup(fqName: knownNames.kotlinResultFQName) else {
            return nil
        }
        return sema.types.make(.classType(ClassType(
            classSymbol: resultClassSymbol,
            args: [.out(elementType)],
            nullability: .nonNull
        )))
    }

    func tryBindThreadLocalGetOrSetFallback(
        _ id: ExprID,
        calleeName: InternedString,
        safeCall: Bool,
        receiverType: TypeID,
        args: [CallArgument],
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) -> TypeID? {
        let sema = ctx.sema
        let interner = ctx.interner

        guard interner.resolve(calleeName) == "getOrSet",
              args.count == 1,
              let threadLocalSymbol = sema.symbols.lookup(fqName: [
                  interner.intern("java"),
                  interner.intern("lang"),
                  interner.intern("ThreadLocal"),
              ]),
              case let .classType(receiverClassType) = sema.types.kind(of: sema.types.makeNonNullable(receiverType)),
              receiverClassType.classSymbol == threadLocalSymbol
        else {
            return nil
        }

        let visibleCandidates = ctx.filterByVisibility(ctx.cachedScopeLookup(calleeName)).visible
        guard let chosen = visibleCandidates.first(where: { candidate in
            sema.symbols.externalLinkName(for: candidate) == "kk_thread_local_getOrSet"
        }),
        let signature = sema.symbols.functionSignature(for: chosen)
        else {
            return nil
        }

        let elementType: TypeID = if let arg = receiverClassType.args.first {
            switch arg {
            case let .invariant(inner), let .out(inner), let .in(inner):
                inner
            case .star:
                sema.types.nullableAnyType
            }
        } else {
            sema.types.nullableAnyType
        }

        let defaultLambdaType = sema.types.make(.functionType(FunctionType(
            params: [],
            returnType: elementType,
            nullability: .nonNull
        )))
        _ = driver.inferExpr(
            args[0].expr,
            ctx: ctx,
            locals: &locals,
            expectedType: defaultLambdaType
        )

        let typeVarBySymbol = sema.types.makeTypeVarBySymbol(signature.typeParameterSymbols)
        let substitution: [TypeVarID: TypeID] = if let typeParameterSymbol = signature.typeParameterSymbols.first,
                                                   let typeVar = typeVarBySymbol[typeParameterSymbol]
        {
            [typeVar: elementType]
        } else {
            [:]
        }

        let returnType = bindCallAndResolveReturnType(
            id,
            chosen: chosen,
            resolved: ResolvedCall(
                chosenCallee: chosen,
                substitutedTypeArguments: substitution,
                parameterMapping: [0: 0],
                diagnostic: nil
            ),
            sema: sema
        )
        let finalType = safeCall ? sema.types.makeNullable(returnType) : returnType
        sema.bindings.bindExprType(id, type: finalType)
        return finalType
    }

    func tryBindMapGetOrElseFallback(
        _ id: ExprID,
        calleeName: InternedString,
        safeCall: Bool,
        receiverType: TypeID,
        args: [CallArgument],
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) -> TypeID? {
        let sema = ctx.sema
        let interner = ctx.interner
        let knownNames = KnownCompilerNames(interner: interner)

        guard calleeName == knownNames.getOrElse,
              args.count == 2,
              case let .classType(receiverClassType) = sema.types.kind(of: sema.types.makeNonNullable(receiverType)),
              let receiverSymbol = sema.symbols.symbol(receiverClassType.classSymbol),
              knownNames.isMapLikeSymbol(receiverSymbol),
              receiverClassType.args.count >= 2
        else {
            return nil
        }

        let valueType: TypeID = switch receiverClassType.args[1] {
        case let .invariant(inner), let .out(inner), let .in(inner):
            inner
        case .star:
            sema.types.anyType
        }

        _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals)
        let defaultLambdaType = sema.types.make(.functionType(FunctionType(
            params: [],
            returnType: valueType,
            nullability: .nonNull
        )))
        _ = driver.inferExpr(
            args[1].expr,
            ctx: ctx,
            locals: &locals,
            expectedType: defaultLambdaType
        )

        let fallbackCallee = sema.symbols.lookupAll(fqName: [
            interner.intern("kotlin"),
            interner.intern("collections"),
            interner.intern("Map"),
            knownNames.getOrElse,
        ]).first(where: { candidate in
            sema.symbols.externalLinkName(for: candidate) == "kk_map_getOrElse"
        })

        if let fallbackCallee {
            sema.bindings.bindCall(
                id,
                binding: CallBinding(
                    chosenCallee: fallbackCallee,
                    substitutedTypeArguments: [],
                    parameterMapping: [0: 0, 1: 1]
                )
            )
            sema.bindings.bindCallableTarget(id, target: .symbol(fallbackCallee))
        }

        let finalType = safeCall ? sema.types.makeNullable(valueType) : valueType
        sema.bindings.bindExprType(id, type: finalType)
        return finalType
    }

    func tryBindMapWithDefaultFallback(
        _ id: ExprID,
        calleeName: InternedString,
        safeCall: Bool,
        receiverType: TypeID,
        args: [CallArgument],
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) -> TypeID? {
        let sema = ctx.sema
        let interner = ctx.interner
        let knownNames = KnownCompilerNames(interner: interner)
        let withDefaultName = interner.intern("withDefault")

        guard calleeName == withDefaultName,
              args.count == 1,
              case let .classType(receiverClassType) = sema.types.kind(of: sema.types.makeNonNullable(receiverType)),
              let receiverSymbol = sema.symbols.symbol(receiverClassType.classSymbol),
              knownNames.isMapLikeSymbol(receiverSymbol),
              receiverClassType.args.count >= 2
        else {
            return nil
        }

        let keyType: TypeID = switch receiverClassType.args[0] {
        case let .invariant(inner), let .out(inner), let .in(inner):
            inner
        case .star:
            sema.types.anyType
        }
        let valueType: TypeID = switch receiverClassType.args[1] {
        case let .invariant(inner), let .out(inner), let .in(inner):
            inner
        case .star:
            sema.types.anyType
        }

        let defaultLambdaType = sema.types.make(.functionType(FunctionType(
            params: [keyType],
            returnType: valueType,
            nullability: .nonNull
        )))
        sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
        _ = driver.inferExpr(
            args[0].expr,
            ctx: ctx,
            locals: &locals,
            expectedType: defaultLambdaType
        )

        let fallbackCallee = sema.symbols.lookupAll(fqName: [
            interner.intern("kotlin"),
            interner.intern("collections"),
            interner.intern("Map"),
            withDefaultName,
        ]).first(where: { candidate in
            sema.symbols.externalLinkName(for: candidate) == "kk_map_withDefault"
        })

        if let fallbackCallee {
            sema.bindings.bindCall(
                id,
                binding: CallBinding(
                    chosenCallee: fallbackCallee,
                    substitutedTypeArguments: [keyType, valueType],
                    parameterMapping: [0: 0]
                )
            )
            sema.bindings.bindCallableTarget(id, target: .symbol(fallbackCallee))
        }

        let resultType = sema.types.makeNonNullable(receiverType)
        let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
        sema.bindings.bindExprType(id, type: finalType)
        return finalType
    }

    func tryBindReadWriteLockReadFallback(
        _ id: ExprID,
        calleeName: InternedString,
        safeCall: Bool,
        receiverType: TypeID,
        args: [CallArgument],
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) -> TypeID? {
        let sema = ctx.sema
        let interner = ctx.interner

        guard interner.resolve(calleeName) == "read",
              args.count == 1,
              let lockSymbol = sema.symbols.lookup(fqName: [
                  interner.intern("java"),
                  interner.intern("util"),
                  interner.intern("concurrent"),
                  interner.intern("locks"),
                  interner.intern("ReentrantReadWriteLock"),
              ]),
              case let .classType(receiverClassType) = sema.types.kind(of: sema.types.makeNonNullable(receiverType)),
              receiverClassType.classSymbol == lockSymbol
        else {
            return nil
        }

        let visibleCandidates = ctx.filterByVisibility(ctx.cachedScopeLookup(calleeName)).visible
        let chosen = visibleCandidates.first(where: { candidate in
            sema.symbols.externalLinkName(for: candidate) == "kk_reentrant_read_write_lock_read"
        }) ?? sema.symbols.lookupAll(fqName: [
            interner.intern("kotlin"),
            interner.intern("concurrent"),
            interner.intern("read"),
        ]).first(where: { candidate in
            sema.symbols.externalLinkName(for: candidate) == "kk_reentrant_read_write_lock_read"
        })

        guard let chosen,
              let signature = sema.symbols.functionSignature(for: chosen)
        else {
            return nil
        }

        let inferredActionType = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals)
        let resultElementType: TypeID
        if case let .functionType(functionType) = sema.types.kind(of: sema.types.makeNonNullable(inferredActionType)) {
            resultElementType = functionType.returnType
        } else {
            resultElementType = sema.types.anyType
        }

        let typeVarBySymbol = sema.types.makeTypeVarBySymbol(signature.typeParameterSymbols)
        let substitution: [TypeVarID: TypeID] = if let typeParameterSymbol = signature.typeParameterSymbols.first,
                                                   let typeVar = typeVarBySymbol[typeParameterSymbol]
        {
            [typeVar: resultElementType]
        } else {
            [:]
        }

        let returnType = bindCallAndResolveReturnType(
            id,
            chosen: chosen,
            resolved: ResolvedCall(
                chosenCallee: chosen,
                substitutedTypeArguments: substitution,
                parameterMapping: [0: 0],
                diagnostic: nil
            ),
            sema: sema
        )
        let finalType = safeCall ? sema.types.makeNullable(returnType) : returnType
        sema.bindings.bindExprType(id, type: finalType)
        return finalType
    }

    func tryBindComparatorMemberFallback(
        _ id: ExprID,
        calleeName: InternedString,
        safeCall: Bool,
        receiverType: TypeID,
        args: [CallArgument],
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) -> TypeID? {
        let sema = ctx.sema
        let interner = ctx.interner

        guard let comparatorElementType = resolvedComparatorElementType(
                  of: receiverType,
                  sema: sema,
                  interner: interner
              )
        else {
            return nil
        }

        let calleeStr = interner.resolve(calleeName)
        if args.count == 2, ["thenBy", "thenByDescending"].contains(calleeStr) {
            let keyComparatorType = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals)
            guard let keyType = resolvedComparatorElementType(
                of: keyComparatorType,
                sema: sema,
                interner: interner
            ) else {
                return nil
            }
            let expectedLambdaType = sema.types.make(.functionType(FunctionType(
                params: [comparatorElementType],
                returnType: keyType,
                isSuspend: false,
                nullability: .nonNull
            )))
            _ = driver.inferExpr(
                args[1].expr,
                ctx: ctx,
                locals: &locals,
                expectedType: expectedLambdaType
            )

            let comparatorMemberFQName: [InternedString] = [
                interner.intern("kotlin"),
                interner.intern("Comparator"),
                calleeName,
            ]
            let externalLinkName = switch calleeStr {
            case "thenBy":
                "kk_comparator_then_by_comparator_selector"
            default:
                "kk_comparator_then_by_descending_comparator_selector"
            }
            guard let chosen = sema.symbols.lookupAll(fqName: comparatorMemberFQName).first(where: { candidate in
                sema.symbols.externalLinkName(for: candidate) == externalLinkName
            }) else {
                return nil
            }

            sema.bindings.bindCall(
                id,
                binding: CallBinding(
                    chosenCallee: chosen,
                    substitutedTypeArguments: [comparatorElementType, keyType],
                    parameterMapping: [0: 0, 1: 1]
                )
            )
            sema.bindings.bindCallableTarget(id, target: .symbol(chosen))

            let resultType = sema.types.makeNonNullable(receiverType)
            let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
            sema.bindings.bindExprType(id, type: finalType)
            return finalType
        }

        guard args.count == 1 else {
            return nil
        }

        let expectedLambdaType: TypeID
        switch calleeStr {
        case "thenBy", "thenByDescending":
            expectedLambdaType = sema.types.make(.functionType(FunctionType(
                params: [comparatorElementType],
                returnType: sema.types.anyType,
                isSuspend: false,
                nullability: .nonNull
            )))
        case "thenComparator", "thenDescending":
            expectedLambdaType = sema.types.make(.functionType(FunctionType(
                params: [comparatorElementType, comparatorElementType],
                returnType: sema.types.intType,
                isSuspend: false,
                nullability: .nonNull
            )))
        default:
            return nil
        }

        _ = driver.inferExpr(
            args[0].expr,
            ctx: ctx,
            locals: &locals,
            expectedType: expectedLambdaType
        )

        let comparatorMemberFQName: [InternedString] = [
            interner.intern("kotlin"),
            interner.intern("Comparator"),
            calleeName,
        ]
        guard let chosen = sema.symbols.lookupAll(fqName: comparatorMemberFQName).first(where: { candidate in
            guard let signature = sema.symbols.functionSignature(for: candidate) else {
                return false
            }
            return sema.symbols.symbol(candidate)?.flags.contains(.synthetic) == true
                && signature.parameterTypes.count == 1
        }) else {
            return nil
        }

        sema.bindings.bindCall(
            id,
            binding: CallBinding(
                chosenCallee: chosen,
                substitutedTypeArguments: [],
                parameterMapping: [0: 0]
            )
        )
        sema.bindings.bindCallableTarget(id, target: .symbol(chosen))

        let resultType = sema.types.makeNonNullable(receiverType)
        let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
        sema.bindings.bindExprType(id, type: finalType)
        return finalType
    }

    func bindKClassFindAssociatedObjectCall(
        _ id: ExprID,
        args: [CallArgument],
        explicitTypeArgs: [TypeID],
        range: SourceRange,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) -> TypeID {
        let sema = ctx.sema
        let interner = ctx.interner

        for arg in args {
            _ = driver.inferExpr(arg.expr, ctx: ctx, locals: &locals)
        }

        let functionFQName: [InternedString] = [
            interner.intern("kotlin"),
            interner.intern("reflect"),
            interner.intern("findAssociatedObject"),
        ]
        if let chosen = sema.symbols.lookupAll(fqName: functionFQName).first(where: { candidate in
            sema.symbols.symbol(candidate)?.kind == .function
        }) {
            sema.bindings.bindCall(
                id,
                binding: CallBinding(
                    chosenCallee: chosen,
                    substitutedTypeArguments: explicitTypeArgs,
                    parameterMapping: [:]
                )
            )
            sema.bindings.bindCallableTarget(id, target: .symbol(chosen))
            driver.helpers.checkOptIn(
                for: chosen,
                ctx: ctx,
                range: range,
                diagnostics: ctx.semaCtx.diagnostics
            )
        }

        let nullableAnyType = sema.types.makeNullable(sema.types.anyType)
        sema.bindings.bindExprType(id, type: nullableAnyType)
        return nullableAnyType
    }
}

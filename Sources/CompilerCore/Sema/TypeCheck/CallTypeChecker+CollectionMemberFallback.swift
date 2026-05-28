// swiftlint:disable file_length
import RuntimeABI

/// Member-call fallback resolution for Collection-typed receivers
/// (List / Iterable / Set / Sequence / Collection): supported-member
/// check, parameter-mapping, result-type inference, lambda-expectation
/// inference, and the receiver-kind predicates.
///
/// Split out from `CallTypeChecker+MemberCallFallbacks.swift`.
extension CallTypeChecker {
    func tryCollectionMemberFallback(
        _ id: ExprID,
        calleeName: InternedString,
        isClassNameReceiver: Bool,
        safeCall: Bool,
        receiverID: ExprID,
        args: [CallArgument],
        ctx: TypeInferenceContext,
        expectedType: TypeID? = nil,
        locals: inout LocalBindings
    ) -> TypeID? {
        let sema = ctx.sema
        let interner = ctx.interner

        let memberName = interner.resolve(calleeName)
        if sema.bindings.exprTypes[receiverID] == nil {
            _ = driver.inferExpr(receiverID, ctx: ctx, locals: &locals)
        }
        let isArrayReceiver = isArrayLikeReceiver(receiverID: receiverID, sema: sema, interner: interner)
        let isIterableWindowedTransformCall: Bool = {
            guard memberName == "windowed",
                  (2...4).contains(args.count),
                  isIterableLikeReceiver(receiverID: receiverID, sema: sema, interner: interner),
                  let lastArgExpr = args.last?.expr,
                  let lastArgExprNode = ctx.ast.arena.expr(lastArgExpr)
            else {
                return false
            }
            return lastArgExprNode.isLambdaOrCallableRef
        }()
        let isIterableChunkedTransformCall: Bool = {
            guard memberName == "chunked",
                  args.count == 2,
                  isIterableLikeReceiver(receiverID: receiverID, sema: sema, interner: interner),
                  let lastArgExpr = args.last?.expr,
                  let lastArgExprNode = ctx.ast.arena.expr(lastArgExpr)
            else {
                return false
            }
            return lastArgExprNode.isLambdaOrCallableRef
        }()
        let isIterableFirstNotNullOfCall: Bool = {
            guard memberName == "firstNotNullOf",
                  args.count == 1,
                  isIterableLikeReceiver(receiverID: receiverID, sema: sema, interner: interner),
                  let firstArgExpr = args.first?.expr,
                  let firstArgNode = ctx.ast.arena.expr(firstArgExpr)
            else {
                return false
            }
            return firstArgNode.isLambdaOrCallableRef
        }()
        let isIterableFirstNotNullOfOrNullCall: Bool = {
            guard memberName == "firstNotNullOfOrNull",
                  args.count == 1,
                  isIterableLikeReceiver(receiverID: receiverID, sema: sema, interner: interner),
                  let firstArgExpr = args.first?.expr,
                  let firstArgNode = ctx.ast.arena.expr(firstArgExpr)
            else {
                return false
            }
            return firstArgNode.isLambdaOrCallableRef
        }()
        let isIterableRequireNoNullsCall =
            memberName == "requireNoNulls"
            && args.isEmpty
            && isIterableLikeReceiver(receiverID: receiverID, sema: sema, interner: interner)
        let isCollectionReceiver = isCollectionLikeReceiver(receiverID: receiverID, sema: sema, interner: interner)
        let isSequenceReceiver = isSequenceLikeReceiver(receiverID: receiverID, sema: sema, interner: interner)
        // Allow arrays to fall through to collection fallback only when
        // tryArrayMemberFallback does not handle the member (isSupportedArrayMember returns false).
        guard !isClassNameReceiver,
              !(isArrayReceiver && isSupportedArrayMember(memberName)),
              isCollectionReceiver
                || isSequenceReceiver
                || isIterableWindowedTransformCall
                || isIterableChunkedTransformCall
                || isIterableFirstNotNullOfCall
                || isIterableFirstNotNullOfOrNullCall
                || isIterableRequireNoNullsCall
        else {
            return nil
        }

        let isIterableReceiver = isIterableLikeReceiver(receiverID: receiverID, sema: sema, interner: interner)
        let isMapReceiver = isMapLikeCollectionReceiver(receiverID: receiverID, sema: sema, interner: interner)
        let isSetReceiver = isSetLikeCollectionReceiver(receiverID: receiverID, sema: sema, interner: interner)
        let isMutableCollectionReceiverFlag = isMutableCollectionReceiver(receiverID: receiverID, sema: sema, interner: interner)
        let isMutableListReceiver = isMutableListCollectionReceiver(receiverID: receiverID, sema: sema, interner: interner)
        let isMutableSetReceiver = isMutableSetCollectionReceiver(receiverID: receiverID, sema: sema, interner: interner)
        let isMutableMapReceiver = isMutableMapCollectionReceiver(receiverID: receiverID, sema: sema, interner: interner)
        let isListReceiver = isConcreteListLikeCollectionReceiver(receiverID: receiverID, sema: sema, interner: interner)
        let addAllFirstArgumentExpr: ExprID? = if memberName == "addAll",
                                                  args.count == 1,
                                                  let firstArg = args.first {
            firstArg.expr
        } else {
            nil
        }
        if let addAllFirstArgumentExpr,
           sema.bindings.exprTypes[addAllFirstArgumentExpr] == nil
        {
            _ = driver.inferExpr(addAllFirstArgumentExpr, ctx: ctx, locals: &locals)
        }
        let isAddAllArrayArgument = addAllFirstArgumentExpr.map {
            isArrayLikeReceiver(receiverID: $0, sema: sema, interner: interner)
        } ?? false
        let isAddAllSequenceArgument: Bool = if let addAllFirstArgumentExpr,
                                                let firstArgType = sema.bindings.exprTypes[addAllFirstArgumentExpr] {
            isSequenceLikeType(firstArgType, sema: sema, interner: interner)
        } else {
            false
        }
        let isAddAllIterableArgument: Bool = if let addAllFirstArgumentExpr,
                                                let firstArgType = sema.bindings.exprTypes[addAllFirstArgumentExpr] {
            isIterableLikeReceiver(receiverID: addAllFirstArgumentExpr, sema: sema, interner: interner)
                && !isCollectionLikeType(firstArgType, sema: sema, interner: interner)
                && !isSequenceLikeType(firstArgType, sema: sema, interner: interner)
        } else {
            false
        }
        guard isSupportedCollectionFallbackMember(
            calleeName,
            isIterableReceiver: isIterableReceiver,
            isListReceiver: isListReceiver,
            isSequenceReceiver: isSequenceReceiver,
            isMapReceiver: isMapReceiver,
            isSetReceiver: isSetReceiver,
            isMutableCollectionReceiver: isMutableCollectionReceiverFlag,
            isMutableListReceiver: isMutableListReceiver,
            isMutableSetReceiver: isMutableSetReceiver,
            isMutableMapReceiver: isMutableMapReceiver,
            isAddAllArrayArgument: isAddAllArrayArgument,
            isAddAllSequenceArgument: isAddAllSequenceArgument,
            isAddAllIterableArgument: isAddAllIterableArgument,
            interner: interner
        ),
        isValidCollectionFallbackArity(
            calleeName,
            argCount: args.count,
            isMapReceiver: isMapReceiver,
            isSetReceiver: isSetReceiver,
            isSequenceReceiver: isSequenceReceiver,
            isListReceiver: isListReceiver,
            isMutableCollectionReceiver: isMutableCollectionReceiverFlag,
            isMutableMapReceiver: isMutableMapReceiver,
            isMutableSetReceiver: isMutableSetReceiver,
            isMutableListReceiver: isMutableListReceiver,
            isAddAllArrayArgument: isAddAllArrayArgument,
            isAddAllSequenceArgument: isAddAllSequenceArgument,
            isAddAllIterableArgument: isAddAllIterableArgument,
            interner: interner
        )
        else {
            return nil
        }

        // Provide contextual function type for collection HOF lambda inference.
        let receiverElementType = collectionFallbackElementType(receiverID: receiverID, sema: sema, interner: interner)
        if let expectation = collectionFallbackLambdaExpectation(
            memberName: calleeName,
            argCount: args.count,
            receiverElementType: receiverElementType,
            isMapReceiver: isMapReceiver,
            isSetReceiver: isSetReceiver,
            isMutableMapReceiver: isMutableMapReceiver,
            args: args,
            ctx: ctx,
            interner: interner,
            sema: sema
        ),
            args.indices.contains(expectation.argumentIndex)
        {
            let lambdaArgExpr = args[expectation.argumentIndex].expr
            if let lambdaExpr = ctx.ast.arena.expr(lambdaArgExpr), lambdaExpr.isLambdaOrCallableRef {
                sema.bindings.markCollectionHOFLambdaExpr(lambdaArgExpr)
            }
            _ = driver.inferExpr(
                lambdaArgExpr,
                ctx: ctx,
                locals: &locals,
                expectedType: expectation.expectedType
            )
        }
        if memberName == "addAll", args.count == 1 {
            _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals)
        }

        if isCollectionReturningMember(
            calleeName,
            isMapReceiver: isMapReceiver,
            isListReceiver: isListReceiver,
            isSetReceiver: isSetReceiver,
            interner: interner
        ) {
            sema.bindings.markCollectionExpr(id)
        }

        if let fallbackCallee = resolveCollectionFallbackCallee(
            memberName: calleeName,
            receiverID: receiverID,
            argExprs: args.map(\.expr),
            argCount: args.count,
            ctx: ctx,
            sema: sema,
            interner: interner
        ) {
            if let invalidFallbackType = validateCollectionFallbackCallee(
                fallbackCallee,
                exprID: id,
                calleeName: calleeName,
                safeCall: safeCall,
                receiverID: receiverID,
                ctx: ctx
            ) {
                return invalidFallbackType
            }
            let parameterMapping = buildCollectionFallbackParameterMapping(
                memberName: calleeName,
                args: args,
                fallbackCallee: fallbackCallee,
                sema: sema,
                interner: interner
            )
            sema.bindings.bindCall(
                id,
                binding: CallBinding(
                    chosenCallee: fallbackCallee,
                    substitutedTypeArguments: [],
                    parameterMapping: parameterMapping
                )
            )
            sema.bindings.bindCallableTarget(id, target: .symbol(fallbackCallee))
        }

        var resultType = collectionFallbackResultType(
            memberName: calleeName,
            receiverElementType: receiverElementType,
            isMapReceiver: isMapReceiver,
            isListReceiver: isListReceiver,
            isSetReceiver: isSetReceiver,
            isSequenceReceiver: isSequenceReceiver,
            args: args,
            ctx: ctx,
            sema: sema,
            expectedType: expectedType,
            interner: interner
        )
        // When the receiver is Sequence, sequence-returning operations (map,
        // filter, etc.) should return Sequence<E> so the KIR builder's
        // sequence HOF handler recognises chained calls (STDLIB-471).
        if isSequenceReceiver,
           isCollectionReturningMember(calleeName, isMapReceiver: false, isListReceiver: false, isSetReceiver: false, interner: interner),
           resultType == sema.types.anyType
        {
            resultType = makeSyntheticSequenceType(
                symbols: sema.symbols,
                types: sema.types,
                interner: interner,
                elementType: receiverElementType
            )
        }
        let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
        sema.bindings.bindExprType(id, type: finalType)
        return finalType
    }

    private func validateCollectionFallbackCallee(
        _ fallbackCallee: SymbolID,
        exprID: ExprID,
        calleeName: InternedString,
        safeCall: Bool,
        receiverID: ExprID,
        ctx: TypeInferenceContext
    ) -> TypeID? {
        let sema = ctx.sema
        let interner = ctx.interner
        let receiverType = sema.bindings.exprTypes[receiverID] ?? sema.types.anyType
        let diagnosticRange = ctx.ast.arena.exprRange(exprID) ?? ctx.ast.arena.exprRange(receiverID)

        if let diagnosticRange,
           let projectionDiagnostic = makeProjectionViolationDiagnostic(
            candidates: [fallbackCallee],
            receiverType: receiverType,
            calleeName: calleeName,
            range: diagnosticRange,
            sema: sema,
            interner: interner
        ) {
            ctx.semaCtx.diagnostics.emit(projectionDiagnostic)
            let invalidType = safeCall ? sema.types.makeNullable(sema.types.errorType) : sema.types.errorType
            sema.bindings.bindExprType(exprID, type: invalidType)
            return invalidType
        }

        guard let signature = sema.symbols.functionSignature(for: fallbackCallee),
              signature.classTypeParameterCount > 0,
              case let .classType(receiverClassType) = sema.types.kind(of: sema.types.makeNonNullable(receiverType))
        else {
            return nil
        }

        let typeVarBySymbol = sema.types.makeTypeVarBySymbol(signature.typeParameterSymbols)
        var substitution: [TypeVarID: TypeID] = [:]
        let receiverTypeParamCount = min(
            signature.classTypeParameterCount,
            receiverClassType.args.count,
            signature.typeParameterSymbols.count
        )

        for index in 0 ..< receiverTypeParamCount {
            let concreteType: TypeID = switch receiverClassType.args[index] {
            case let .invariant(type), let .out(type), let .in(type):
                type
            case .star:
                sema.types.anyType
            }
            let typeParamSymbol = signature.typeParameterSymbols[index]
            if let typeVar = typeVarBySymbol[typeParamSymbol] {
                substitution[typeVar] = concreteType
            }
        }

        for index in 0 ..< receiverTypeParamCount {
            let typeParamSymbol = signature.typeParameterSymbols[index]
            guard let typeVar = typeVarBySymbol[typeParamSymbol],
                  let substitutedType = substitution[typeVar]
            else {
                continue
            }

            let signatureUpperBounds: [TypeID] = if index < signature.typeParameterUpperBoundsList.count {
                signature.typeParameterUpperBoundsList[index]
            } else {
                []
            }
            let symbolUpperBounds = sema.symbols.typeParameterUpperBounds(for: typeParamSymbol)
            let upperBounds = signatureUpperBounds + symbolUpperBounds.filter { bound in
                !signatureUpperBounds.contains(bound)
            }

            for bound in upperBounds {
                let substitutedBound = sema.types.substituteTypeParameters(
                    in: bound,
                    substitution: substitution,
                    typeVarBySymbol: typeVarBySymbol
                )
                if !sema.types.isSubtype(substitutedType, substitutedBound) {
                    if let diagnosticRange {
                        ctx.semaCtx.diagnostics.error(
                            "KSWIFTK-SEMA-BOUND",
                            "Type argument does not satisfy upper bound constraint.",
                            range: diagnosticRange
                        )
                    }
                    let invalidType = safeCall ? sema.types.makeNullable(sema.types.anyType) : sema.types.anyType
                    sema.bindings.bindExprType(exprID, type: invalidType)
                    return invalidType
                }
            }
        }

        return nil
    }

    private func buildCollectionFallbackParameterMapping(
        memberName: InternedString,
        args: [CallArgument],
        fallbackCallee: SymbolID,
        sema: SemaModule,
        interner: StringInterner
    ) -> [Int: Int] {
        // Build a parameter mapping so that user-provided arguments are correctly
        // assigned to the right parameter slots. Without this, normalizedCallArguments
        // treats all parameters with hasDefault=true as using their default values,
        // ignoring user-provided args entirely.
        guard !args.isEmpty else {
            return [:]
        }
        guard let signature = sema.symbols.functionSignature(for: fallbackCallee) else {
            return [:]
        }
        let paramCount = signature.parameterTypes.count
        // Build a name->index map from the parameter symbols.
        var paramNameToIndex: [InternedString: Int] = [:]
        for (paramIndex, paramSymbol) in signature.valueParameterSymbols.enumerated() {
            if let paramSymbolInfo = sema.symbols.symbol(paramSymbol) {
                let paramName = paramSymbolInfo.name
                if paramName != .invalid {
                    paramNameToIndex[paramName] = paramIndex
                }
            }
        }
        var mapping: [Int: Int] = [:]
        var positionalParamIndex = 0
        for (argIndex, arg) in args.enumerated() {
            if let label = arg.label, let paramIndex = paramNameToIndex[label] {
                // Named argument: map to the named parameter
                mapping[argIndex] = paramIndex
            } else {
                // Positional argument: advance to next unoccupied parameter index
                // (skip any params that are already claimed by named args)
                while positionalParamIndex < paramCount
                    && mapping.values.contains(positionalParamIndex)
                {
                    positionalParamIndex += 1
                }
                if positionalParamIndex < paramCount {
                    mapping[argIndex] = positionalParamIndex
                    positionalParamIndex += 1
                }
            }
        }
        return mapping
    }

    private func resolveCollectionFallbackCallee(
        memberName: InternedString,
        receiverID: ExprID,
        argExprs: [ExprID] = [],
        argCount: Int,
        ctx: TypeInferenceContext,
        sema: SemaModule,
        interner: StringInterner
    ) -> SymbolID? {
        let receiverType = sema.bindings.exprTypes[receiverID] ?? sema.types.anyType
        guard let root = driver.helpers.nominalSymbol(of: sema.types.makeNonNullable(receiverType), types: sema.types) else {
            return nil
        }
        var queue: [SymbolID] = [root]
        var visited: Set<SymbolID> = []
        while !queue.isEmpty {
            let owner = queue.removeFirst()
            guard visited.insert(owner).inserted,
                  let ownerSymbol = sema.symbols.symbol(owner)
            else {
                continue
            }
            let memberFQName = ownerSymbol.fqName + [memberName]
            var allCandidates = sema.symbols.lookupAll(fqName: memberFQName).filter { candidate in
                guard let symbol = sema.symbols.symbol(candidate),
                      symbol.kind == .function,
                      sema.symbols.parentSymbol(for: candidate) == owner,
                      sema.symbols.functionSignature(for: candidate) != nil
                else {
                    return false
                }
                return true
            }
            for candidate in sema.symbols.lookupByShortName(memberName) {
                guard !allCandidates.contains(candidate),
                      let symbol = sema.symbols.symbol(candidate),
                      symbol.kind == .function,
                      sema.symbols.parentSymbol(for: candidate) == owner,
                      sema.symbols.functionSignature(for: candidate) != nil
                else {
                    continue
                }
                allCandidates.append(candidate)
            }
            // STDLIB-214: For slice(IntRange) vs slice(Iterable<Int>), prefer the
            // IntRange overload (kk_list_slice) when the first argument is a range expression,
            // and the Iterable overload (kk_list_slice_iterable) otherwise.
            if argCount == 1,
               allCandidates.count > 1,
               let firstArgExpr = argExprs.first,
               allCandidates.contains(where: { sema.symbols.externalLinkName(for: $0) == "kk_list_slice" }),
               allCandidates.contains(where: { sema.symbols.externalLinkName(for: $0) == "kk_list_slice_iterable" })
            {
                let isRangeArg = sema.bindings.isRangeExpr(firstArgExpr)
                let targetLinkName = isRangeArg ? "kk_list_slice" : "kk_list_slice_iterable"
                if let sliceMatch = allCandidates.first(where: { candidate in
                    sema.symbols.externalLinkName(for: candidate) == targetLinkName
                }) {
                    return sliceMatch
                }
            }
            if argCount == 1,
               allCandidates.count > 1,
               let firstArgExpr = argExprs.first,
               allCandidates.contains(where: { sema.symbols.externalLinkName(for: $0) == "kk_array_sliceArray_range" }),
               allCandidates.contains(where: { sema.symbols.externalLinkName(for: $0) == "kk_array_sliceArray_iterable" })
            {
                let isRangeArg = sema.bindings.isRangeExpr(firstArgExpr)
                let targetLinkName = isRangeArg ? "kk_array_sliceArray_range" : "kk_array_sliceArray_iterable"
                if let sliceArrayMatch = allCandidates.first(where: { candidate in
                    sema.symbols.externalLinkName(for: candidate) == targetLinkName
                }) {
                    return sliceArrayMatch
                }
            }
            if memberName == interner.intern("binarySearch") {
                let hasLambdaArg = argExprs.first.map { sema.bindings.isCollectionHOFLambdaExpr($0) } ?? false
                if argCount == 1,
                   hasLambdaArg,
                   let compareMatch = allCandidates.first(where: { candidate in
                       sema.symbols.externalLinkName(for: candidate) == "kk_list_binarySearch_compare"
                   })
                {
                    return compareMatch
                }
                if argCount >= 2,
                   let comparatorMatch = allCandidates.first(where: { candidate in
                       sema.symbols.externalLinkName(for: candidate) == "kk_list_binarySearch_comparator"
                   })
                {
                    return comparatorMatch
                }
            }
            if memberName == interner.intern("nextInt"),
               argCount == 1,
               allCandidates.contains(where: { sema.symbols.externalLinkName(for: $0) == "kk_random_nextInt_until" }),
               allCandidates.contains(where: { sema.symbols.externalLinkName(for: $0) == "kk_random_nextInt_rangeObject" }),
               let firstArgExpr = argExprs.first
            {
                let firstArgType = sema.bindings.exprTypes[firstArgExpr] ?? sema.types.anyType
                let isIntRangeArg = sema.bindings.isRangeExpr(firstArgExpr)
                    || nominalRangeElementType(for: firstArgType, sema: sema, interner: interner) == sema.types.intType
                let targetLinkName = isIntRangeArg ? "kk_random_nextInt_rangeObject" : "kk_random_nextInt_until"
                if let match = allCandidates.first(where: { candidate in
                    sema.symbols.externalLinkName(for: candidate) == targetLinkName
                }) {
                    return match
                }
            }
            if memberName == interner.intern("addAll"),
               argCount == 1,
               let firstArgExpr = argExprs.first,
               isArrayLikeReceiver(receiverID: firstArgExpr, sema: sema, interner: interner),
               let arrayMatch = allCandidates.first(where: { candidate in
                   guard let signature = sema.symbols.functionSignature(for: candidate),
                         let parameterType = signature.parameterTypes.first
                   else {
                       return false
                   }
                   return isCollectionFallbackArrayLikeType(parameterType, sema: sema, interner: interner)
               })
            {
                return arrayMatch
            }
            if memberName == interner.intern("addAll"),
               argCount == 1,
               let firstArgExpr = argExprs.first,
               let firstArgType = sema.bindings.exprTypes[firstArgExpr],
               isSequenceLikeType(firstArgType, sema: sema, interner: interner),
               let sequenceMatch = allCandidates.first(where: { candidate in
                   guard let sig = sema.symbols.functionSignature(for: candidate),
                         sig.parameterTypes.count == 1,
                         let firstParamType = sig.parameterTypes.first
                   else {
                       return false
                   }
                   return isSequenceLikeType(firstParamType, sema: sema, interner: interner)
               })
            {
                return sequenceMatch
            }
            if memberName == interner.intern("addAll"),
               argCount == 1,
               let firstArgExpr = argExprs.first,
               isIterableLikeReceiver(receiverID: firstArgExpr, sema: sema, interner: interner),
               !isCollectionLikeType(sema.bindings.exprTypes[firstArgExpr] ?? sema.types.anyType, sema: sema, interner: interner),
               let iterableMatch = allCandidates.first(where: { candidate in
                   guard let signature = sema.symbols.functionSignature(for: candidate),
                         let parameterType = signature.parameterTypes.first
                   else {
                       return false
                   }
                   return isCollectionFallbackIterableLikeType(parameterType, sema: sema, interner: interner)
               })
            {
                return iterableMatch
            }

        let lastArgIsFunctionLike: Bool = if let lastExpr = argExprs.last,
                                             let lastExprNode = ctx.ast.arena.expr(lastExpr) {
            lastExprNode.isLambdaOrCallableRef
        } else {
            false
        }
        if lastArgIsFunctionLike,
           let lambdaMatch = allCandidates.first(where: { candidate in
               guard let sig = sema.symbols.functionSignature(for: candidate) else { return false }
               guard sig.parameterTypes.count == argCount,
                     let lastParamType = sig.parameterTypes.last
               else {
                   return false
               }
               switch sema.types.kind(of: sema.types.makeNonNullable(lastParamType)) {
               case .functionType:
                   return true
               default:
                   return false
               }
           }) {
            return lambdaMatch
        }
        // Prefer the overload whose parameter count matches the call-site
        // argument count so that e.g. windowed(3, 2, true) resolves to the
        // 3-param overload (kk_list_windowed_partial) instead of the 2-param
        // one (kk_list_windowed).
        if let exactMatch = allCandidates.first(where: { candidate in
            guard let sig = sema.symbols.functionSignature(for: candidate) else { return false }
            return sig.parameterTypes.count == argCount
        }) {
            return exactMatch
        }
        if let first = allCandidates.first {
            return first
        }
        queue.append(contentsOf: sema.symbols.directSupertypes(for: owner))
        }
        return nil
    }

    private func isCollectionFallbackArrayLikeType(
        _ type: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        let knownNames = KnownCompilerNames(interner: interner)
        guard case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(type)),
              let symbol = sema.symbols.symbol(classType.classSymbol)
        else {
            return false
        }
        return knownNames.isArrayLikeName(symbol.name)
    }

    private func isCollectionFallbackIterableLikeType(
        _ type: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        guard case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(type)),
              let symbol = sema.symbols.symbol(classType.classSymbol)
        else {
            return false
        }
        return symbol.name == interner.intern("Iterable")
            || symbol.fqName == [
                interner.intern("kotlin"),
                interner.intern("collections"),
                interner.intern("Iterable"),
            ]
    }

    private func stdlibSurfaceOwnerKindsForCollectionFallback(
        isIterableReceiver: Bool,
        isListReceiver: Bool,
        isSequenceReceiver: Bool,
        isMapReceiver: Bool,
        isSetReceiver: Bool
    ) -> [StdlibSurfaceOwnerKind] {
        if isMapReceiver {
            return [.map]
        }
        if isSequenceReceiver {
            return [.sequence]
        }
        if isSetReceiver {
            return [.set]
        }
        if isIterableReceiver || isListReceiver {
            return [.list]
        }
        return []
    }

    private func stdlibSurfaceSpecsForCollectionFallback(
        memberName: InternedString,
        ownerKinds: [StdlibSurfaceOwnerKind],
        interner: StringInterner
    ) -> [StdlibSurfaceSpec] {
        let resolvedName = interner.resolve(memberName)
        return ownerKinds.flatMap { ownerKind in
            StdlibSurfaceSpec.collectionHOFSpecs(ownerKind: ownerKind, memberName: resolvedName)
        }
    }

    private func stdlibSurfaceSpecForCollectionFallback(
        memberName: InternedString,
        argCount: Int,
        ownerKinds: [StdlibSurfaceOwnerKind],
        interner: StringInterner
    ) -> StdlibSurfaceSpec? {
        stdlibSurfaceSpecsForCollectionFallback(
            memberName: memberName,
            ownerKinds: ownerKinds,
            interner: interner
        )
        .first { $0.arity.accepts(argCount) }
    }

    private func stdlibSurfaceCollectionReturning(_ spec: StdlibSurfaceSpec) -> Bool {
        switch spec.returnStrategy {
        case .destinationArgument, .list, .set, .map, .sequence, .receiver:
            return true
        case .any, .nullableAny, .receiverElement, .nullableReceiverElement,
             .unit, .boolean, .int, .double:
            return false
        }
    }

    private func isSetReturningCollectionBinaryMember(
        _ memberName: InternedString,
        interner: StringInterner
    ) -> Bool {
        switch memberName {
        case interner.intern("intersect"),
             interner.intern("union"),
             interner.intern("subtract"):
            return true
        default:
            return false
        }
    }

    func isSupportedCollectionFallbackMember(
        _ memberName: InternedString,
        isIterableReceiver: Bool,
        isListReceiver: Bool,
        isSequenceReceiver: Bool,
        isMapReceiver: Bool,
        isSetReceiver: Bool,
        isMutableCollectionReceiver: Bool,
        isMutableListReceiver: Bool,
        isMutableSetReceiver: Bool = false,
        isMutableMapReceiver: Bool,
        isAddAllArrayArgument: Bool = false,
        isAddAllSequenceArgument: Bool = false,
        isAddAllIterableArgument: Bool = false,
        interner: StringInterner
    ) -> Bool {
        let knownNames = KnownCompilerNames(interner: interner)
        let surfaceOwnerKinds = stdlibSurfaceOwnerKindsForCollectionFallback(
            isIterableReceiver: isIterableReceiver,
            isListReceiver: isListReceiver,
            isSequenceReceiver: isSequenceReceiver,
            isMapReceiver: isMapReceiver,
            isSetReceiver: isSetReceiver
        )
        if !stdlibSurfaceSpecsForCollectionFallback(
            memberName: memberName,
            ownerKinds: surfaceOwnerKinds,
            interner: interner
        ).isEmpty {
            return true
        }
        let collectionMembers: Set = [
            knownNames.size,
            knownNames.isEmpty,
            interner.intern("get"),
            interner.intern("contains"),
            interner.intern("containsAll"),
            interner.intern("first"),
            interner.intern("last"),
            interner.intern("indexOf"),
            interner.intern("lastIndexOf"),
            interner.intern("indexOfFirst"),
            interner.intern("indexOfLast"),
            interner.intern("count"),
            interner.intern("iterator"),
            interner.intern("filterNotNull"),
            interner.intern("filterIsInstanceTo"),
            interner.intern("filterNotNullTo"),
            interner.intern("fold"),
            interner.intern("foldRight"),
            interner.intern("foldIndexed"),
            interner.intern("foldRightIndexed"),
            interner.intern("reduce"),
            interner.intern("reduceRight"),
            interner.intern("reduceRightIndexed"),
            interner.intern("reduceRightIndexedOrNull"),
            interner.intern("reduceRightOrNull"),
            interner.intern("reduceOrNull"),
            interner.intern("reduceIndexed"),
            interner.intern("reduceIndexedOrNull"),
            interner.intern("scan"),
            interner.intern("scanIndexed"),
            interner.intern("runningFold"),
            interner.intern("runningFoldIndexed"),
            interner.intern("runningReduce"),
            interner.intern("runningReduceIndexed"),
            interner.intern("scanReduce"),
            interner.intern("sortedBy"),
            interner.intern("find"),
            interner.intern("zip"),
            interner.intern("unzip"),
            interner.intern("withIndex"),
            interner.intern("min"),
            interner.intern("maxOrNull"),
            interner.intern("minOrNull"),
            interner.intern("asSequence"),
            interner.intern("asIterable"),
            interner.intern("toList"),
            interner.intern("toCollection"),
            interner.intern("toTypeArray"),
            interner.intern("toTypedArray"),
            interner.intern("toCharArray"),
            interner.intern("toBooleanArray"),
            interner.intern("toShortArray"),
            interner.intern("toDoubleArray"),
            interner.intern("toFloatArray"),
            interner.intern("toIntArray"),
            interner.intern("toLongArray"),
            interner.intern("toByteArray"),
            interner.intern("toUByteArray"),
            interner.intern("toUShortArray"),
            interner.intern("toUIntArray"),
            interner.intern("toULongArray"),
            interner.intern("take"),
            interner.intern("drop"),
            interner.intern("reversed"),
            interner.intern("asReversed"),
            interner.intern("sorted"),
            interner.intern("shuffled"),
            interner.intern("distinct"),
            interner.intern("distinctBy"),
            interner.intern("flatten"),
            interner.intern("chunked"),
            interner.intern("windowed"),
            interner.intern("sortedDescending"),
            interner.intern("sortedByDescending"),
            interner.intern("sortedWith"),
            interner.intern("partition"),
            interner.intern("filterIsInstance"),
            interner.intern("firstOrNull"),
            interner.intern("lastOrNull"),
            interner.intern("singleOrNull"),
            interner.intern("joinToString"),
            interner.intern("elementAt"),
            interner.intern("single"),
            interner.intern("toMutableList"),
            interner.intern("sum"),
            interner.intern("average"),
            interner.intern("minusElement"),
        ]
        let listOnlyMembers: Set = [
            interner.intern("subList"),
            interner.intern("slice"),
            interner.intern("getOrNull"),
            interner.intern("elementAtOrNull"),
            interner.intern("binarySearch"),
            interner.intern("binarySearchBy"),
        ]
        let collectionSpecificMembers: Set = [
            interner.intern("firstOrNull"),
            interner.intern("lastOrNull"),
            interner.intern("singleOrNull"),
        ]
        let mutableListOnlyMembers: Set = [
            interner.intern("sort"),
            interner.intern("sortBy"),
            interner.intern("sortByDescending"),
        ]
        let mutableCollectionMembers: Set = [
            interner.intern("addAll"),
            interner.intern("removeAll"),
            interner.intern("retainAll"),
        ]
        let mapOnlyMembers: Set = [
            interner.intern("containsKey"),
            interner.intern("containsValue"),
            knownNames.getValue,
            knownNames.getOrDefault,
            interner.intern("plus"),
            interner.intern("minus"),
        ]
        if listOnlyMembers.contains(memberName) {
            return isListReceiver
        }
        if collectionSpecificMembers.contains(memberName) {
            return isListReceiver || isSetReceiver || isSequenceReceiver
        }
        if memberName == knownNames.getOrElse {
            return isListReceiver || isMapReceiver
        }
        if memberName == interner.intern("elementAtOrElse") {
            return isListReceiver
        }
        if mapOnlyMembers.contains(memberName) {
            return isMapReceiver
        }
        if isSetReturningCollectionBinaryMember(memberName, interner: interner) {
            return isListReceiver || isSetReceiver
        }
        if mutableListOnlyMembers.contains(memberName) {
            return isMutableListReceiver
        }
        if mutableCollectionMembers.contains(memberName) {
            return isMutableListReceiver
                || isMutableSetReceiver
                || (
                    memberName == interner.intern("addAll")
                        && isMutableCollectionReceiver
                        && (isAddAllArrayArgument || isAddAllSequenceArgument || isAddAllIterableArgument)
                )
        }
        if memberName == knownNames.getOrPut || memberName == knownNames.putAll {
            return isMutableMapReceiver
        }
        if memberName == interner.intern("requireNoNulls") {
            return isIterableReceiver || isListReceiver || isSetReceiver || isSequenceReceiver
        }
        return collectionMembers.contains(memberName)
    }

    func isCollectionReturningMember(
        _ memberName: InternedString,
        isMapReceiver: Bool,
        isListReceiver: Bool,
        isSetReceiver: Bool,
        interner: StringInterner
    ) -> Bool {
        let surfaceOwnerKinds: [StdlibSurfaceOwnerKind] = if isMapReceiver {
            [.map]
        } else if isSetReceiver {
            [.set]
        } else if isListReceiver {
            [.list]
        } else {
            []
        }
        if let spec = stdlibSurfaceSpecsForCollectionFallback(
            memberName: memberName,
            ownerKinds: surfaceOwnerKinds,
            interner: interner
        ).first {
            return stdlibSurfaceCollectionReturning(spec)
        }

        let collectionReturningMembers: Set = [
            interner.intern("asSequence"), interner.intern("asIterable"), interner.intern("filterNotNull"), interner.intern("requireNoNulls"),
            interner.intern("filterIsInstanceTo"), interner.intern("reduceTo"),
            interner.intern("zip"), interner.intern("toList"), interner.intern("toTypeArray"), interner.intern("toTypedArray"), interner.intern("take"), interner.intern("drop"), interner.intern("reversed"), interner.intern("asReversed"),
            interner.intern("sorted"), interner.intern("distinct"), interner.intern("distinctBy"), interner.intern("flatten"), interner.intern("chunked"), interner.intern("windowed"), interner.intern("withIndex"),
            interner.intern("shuffled"),
            interner.intern("sortedDescending"), interner.intern("sortedByDescending"), interner.intern("sortedWith"),
            interner.intern("filterIsInstance"),
            interner.intern("toCollection"),
            interner.intern("subList"), interner.intern("slice"),
            interner.intern("scan"), interner.intern("scanIndexed"),
            interner.intern("runningFold"), interner.intern("runningFoldIndexed"),
            interner.intern("runningReduce"), interner.intern("runningReduceIndexed"),
            interner.intern("scanReduce"),
            interner.intern("toMutableList"),
            interner.intern("minusElement"),
        ]
        if memberName == interner.intern("plus") ||
            memberName == interner.intern("minus")
        {
            return isMapReceiver
        }
        if isSetReturningCollectionBinaryMember(memberName, interner: interner) {
            return isListReceiver || isSetReceiver
        }
        return collectionReturningMembers.contains(memberName)
    }

    func isValidCollectionFallbackArity(
        _ memberName: InternedString,
        argCount: Int,
        isMapReceiver: Bool,
        isSetReceiver: Bool,
        isSequenceReceiver: Bool,
        isListReceiver: Bool,
        isMutableCollectionReceiver: Bool,
        isMutableMapReceiver: Bool,
        isMutableSetReceiver: Bool = false,
        isMutableListReceiver: Bool,
        isAddAllArrayArgument: Bool = false,
        isAddAllSequenceArgument: Bool = false,
        isAddAllIterableArgument: Bool = false,
        interner: StringInterner
    ) -> Bool {
        let knownNames = KnownCompilerNames(interner: interner)
        let surfaceOwnerKinds = stdlibSurfaceOwnerKindsForCollectionFallback(
            isIterableReceiver: true,
            isListReceiver: true,
            isSequenceReceiver: isSequenceReceiver,
            isMapReceiver: isMapReceiver,
            isSetReceiver: isSetReceiver
        )
        let surfaceSpecs = stdlibSurfaceSpecsForCollectionFallback(
            memberName: memberName,
            ownerKinds: surfaceOwnerKinds,
            interner: interner
        )
        if surfaceSpecs.contains(where: { $0.arity.accepts(argCount) }) {
            return true
        }
        if isSetReturningCollectionBinaryMember(memberName, interner: interner) {
            return (isListReceiver || isSetReceiver) && argCount == 1
        }
        switch memberName {
        case knownNames.size, knownNames.isEmpty, interner.intern("iterator"), interner.intern("asSequence"),
             interner.intern("asIterable"),
             interner.intern("toList"), interner.intern("toTypeArray"), interner.intern("toTypedArray"), interner.intern("reversed"),
            interner.intern("asReversed"), interner.intern("sorted"),
             interner.intern("distinct"), interner.intern("flatten"), interner.intern("withIndex"),
             interner.intern("min"), interner.intern("maxOrNull"), interner.intern("minOrNull"), interner.intern("sortedDescending"), interner.intern("filterIsInstance"),
             interner.intern("firstOrNull"), interner.intern("lastOrNull"), interner.intern("singleOrNull"), interner.intern("sort"),
             interner.intern("toMutableList"), interner.intern("sum"), interner.intern("average"),
             interner.intern("requireNoNulls"):
            return argCount == 0
        case interner.intern("joinToString"):
            return (0 ... 3).contains(argCount)
        case interner.intern("shuffled"):
            return argCount == 0 || argCount == 1
        case interner.intern("filterNotNull"), interner.intern("unzip"), interner.intern("eachCount"):
            return argCount == 0
        case interner.intern("get"), interner.intern("getOrNull"), interner.intern("elementAtOrNull"),
             interner.intern("contains"), interner.intern("containsAll"), interner.intern("indexOf"), interner.intern("lastIndexOf"), interner.intern("indexOfFirst"), interner.intern("indexOfLast"), interner.intern("binarySearch"),
             interner.intern("sortedBy"), interner.intern("find"), interner.intern("reduce"), interner.intern("reduceOrNull"), interner.intern("reduceIndexedOrNull"), interner.intern("runningReduce"), interner.intern("runningReduceIndexed"), interner.intern("scanReduce"), interner.intern("take"), interner.intern("drop"), interner.intern("zip"),
             interner.intern("filterIndexed"),
             interner.intern("sortedByDescending"), interner.intern("sortedWith"), interner.intern("partition"),
             interner.intern("sortBy"), interner.intern("sortByDescending"), interner.intern("distinctBy"),
             interner.intern("maxBy"), interner.intern("minBy"), interner.intern("maxByOrNull"), interner.intern("minByOrNull"),
             interner.intern("maxOfOrNull"), interner.intern("minOfOrNull"),
             interner.intern("maxOf"), interner.intern("minOf"),
             interner.intern("maxWith"), interner.intern("maxWithOrNull"),
             interner.intern("minWith"), interner.intern("minWithOrNull"),
             interner.intern("elementAt"),
             interner.intern("minusElement"):
            if memberName == interner.intern("binarySearch") {
                return (1...4).contains(argCount)
            }
            return argCount == 1
        case interner.intern("binarySearchBy"):
            return argCount == 2 || argCount == 3 || argCount == 4
        case interner.intern("toCollection"), interner.intern("filterIsInstanceTo"), interner.intern("filterNotNullTo"):
            return argCount == 1
        case interner.intern("reduceTo"):
            return argCount == 2
        case interner.intern("containsKey"):
            return isMapReceiver && argCount == 1
        case knownNames.getValue:
            return isMapReceiver && argCount == 1
        case knownNames.getOrDefault:
            return isMapReceiver && argCount == 2
        case knownNames.getOrElse:
            return argCount == 2
        case interner.intern("elementAtOrElse"):
            return argCount == 2
        case knownNames.getOrPut:
            return isMutableMapReceiver && argCount == 2
        case interner.intern("addAll"), interner.intern("removeAll"), interner.intern("retainAll"):
            return (
                isMutableListReceiver
                    || isMutableSetReceiver
                    || (
                        memberName == interner.intern("addAll")
                            && isMutableCollectionReceiver
                            && (isAddAllArrayArgument || isAddAllSequenceArgument || isAddAllIterableArgument)
                    )
            ) && argCount == 1
        case knownNames.putAll:
            return isMutableMapReceiver && argCount == 1
        case interner.intern("plus"), interner.intern("minus"):
            return isMapReceiver && argCount == 1
        case interner.intern("fold"), interner.intern("foldRight"), interner.intern("foldIndexed"), interner.intern("foldRightIndexed"), interner.intern("scan"), interner.intern("scanIndexed"), interner.intern("runningFold"), interner.intern("runningFoldIndexed"), interner.intern("subList"):
            return argCount == 2
        case interner.intern("slice"):
            return argCount == 1
        case interner.intern("reduceRight"), interner.intern("reduceRightIndexed"), interner.intern("reduceRightIndexedOrNull"), interner.intern("reduceRightOrNull"), interner.intern("reduceIndexed"), interner.intern("reduceIndexedOrNull"), interner.intern("runningReduceIndexed"):
            return argCount == 1
        case interner.intern("windowed"):
            return argCount == 1 || argCount == 2 || argCount == 3 || argCount == 4
        case interner.intern("chunked"):
            return argCount == 1 || argCount == 2
        case interner.intern("count"), interner.intern("first"), interner.intern("last"),
             interner.intern("single"):
            return argCount == 0 || argCount == 1
        default:
            return true
        }
    }

    private func stdlibSurfaceResultType(
        for spec: StdlibSurfaceSpec,
        memberName: InternedString,
        receiverElementType: TypeID,
        isMapReceiver: Bool,
        args: [CallArgument],
        sema: SemaModule,
        interner: StringInterner
    ) -> TypeID? {
        switch spec.returnStrategy {
        case .any, .nullableAny:
            return nil
        case .receiver:
            guard isMapReceiver else { return nil }
            let mapEntryTypes = stdlibSurfaceMapEntryTypes(receiverElementType: receiverElementType, sema: sema)
            return makeSyntheticMapType(
                symbols: sema.symbols,
                types: sema.types,
                interner: interner,
                keyType: mapEntryTypes.key,
                valueType: mapEntryTypes.value
            )
        case .receiverElement:
            return receiverElementType
        case .nullableReceiverElement:
            return sema.types.makeNullable(receiverElementType)
        case .destinationArgument:
            guard let firstArg = args.first else { return nil }
            return sema.bindings.exprTypes[firstArg.expr] ?? sema.types.anyType
        case .unit:
            return sema.types.unitType
        case .boolean:
            return sema.types.booleanType
        case .int:
            return sema.types.intType
        case .double:
            return sema.types.doubleType
        case .list:
            if memberName == interner.intern("flatMapIndexed") {
                return nil
            }
            let elementType = memberName == interner.intern("filterNotNull")
                ? sema.types.makeNonNullable(receiverElementType)
                : receiverElementType
            return makeSyntheticListType(
                symbols: sema.symbols,
                types: sema.types,
                interner: interner,
                elementType: elementType
            )
        case .set:
            return makeSyntheticSetType(
                symbols: sema.symbols,
                types: sema.types,
                interner: interner,
                elementType: receiverElementType
            )
        case .map:
            return makeSyntheticMapType(
                symbols: sema.symbols,
                types: sema.types,
                interner: interner,
                keyType: sema.types.anyType,
                valueType: sema.types.anyType
            )
        case .sequence:
            if memberName == interner.intern("flatMapIndexed") {
                return nil
            }
            let elementType = memberName == interner.intern("filterNotNull")
                ? sema.types.makeNonNullable(receiverElementType)
                : receiverElementType
            return makeSyntheticSequenceType(
                symbols: sema.symbols,
                types: sema.types,
                interner: interner,
                elementType: elementType
            )
        }
    }

    func collectionFallbackResultType(
        memberName: InternedString,
        receiverElementType: TypeID,
        isMapReceiver: Bool,
        isListReceiver: Bool,
        isSetReceiver: Bool,
        isSequenceReceiver: Bool = false,
        args: [CallArgument],
        ctx: TypeInferenceContext,
        sema: SemaModule,
        expectedType: TypeID? = nil,
        interner: StringInterner
    ) -> TypeID {
        let knownNames = KnownCompilerNames(interner: interner)
        let surfaceOwnerKinds = stdlibSurfaceOwnerKindsForCollectionFallback(
            isIterableReceiver: true,
            isListReceiver: isListReceiver,
            isSequenceReceiver: isSequenceReceiver,
            isMapReceiver: isMapReceiver,
            isSetReceiver: isSetReceiver
        )
        // chunked(size): returns Sequence<List<T>> for sequence receivers,
        // List<List<T>> for list/collection receivers.
        if memberName == interner.intern("chunked"), args.count == 1 {
            let chunkType = makeSyntheticListType(
                symbols: sema.symbols,
                types: sema.types,
                interner: interner,
                elementType: receiverElementType
            )
            if isSequenceReceiver {
                return makeSyntheticSequenceType(
                    symbols: sema.symbols,
                    types: sema.types,
                    interner: interner,
                    elementType: chunkType
                )
            }
            if let listSymbol = sema.symbols.lookup(fqName: [
                interner.intern("kotlin"),
                interner.intern("collections"),
                interner.intern("List"),
            ]) {
                return sema.types.make(.classType(ClassType(
                    classSymbol: listSymbol,
                    args: [.out(chunkType)],
                    nullability: .nonNull
                )))
            }
        }
        if let surfaceSpec = stdlibSurfaceSpecForCollectionFallback(
            memberName: memberName,
            argCount: args.count,
            ownerKinds: surfaceOwnerKinds,
            interner: interner
        ),
           let resultType = stdlibSurfaceResultType(
            for: surfaceSpec,
            memberName: memberName,
            receiverElementType: receiverElementType,
            isMapReceiver: isMapReceiver,
            args: args,
            sema: sema,
            interner: interner
           ) {
            return resultType
        }
        let intReturningMembers: Set = [
            interner.intern("size"),
            interner.intern("indexOf"),
            interner.intern("lastIndexOf"),
            interner.intern("indexOfFirst"),
            interner.intern("indexOfLast"),
            interner.intern("count"),
            interner.intern("binarySearch"),
            interner.intern("binarySearchBy"),
        ]
        if intReturningMembers.contains(memberName) {
            return sema.types.make(.primitive(.int, .nonNull))
        }

        // sum()/maxBy() use the receiver element type as the result.
        if memberName == interner.intern("sum") || memberName == interner.intern("maxBy") {
            return receiverElementType
        }

        if memberName == interner.intern("average") {
            return sema.types.doubleType
        }

        if memberName == interner.intern("toTypeArray"),
           !isMapReceiver,
           !isSetReceiver,
           !isSequenceReceiver,
           let arraySymbol = sema.symbols.lookup(fqName: [
               interner.intern("kotlin"),
               interner.intern("Array"),
           ])
        {
            return sema.types.make(.classType(ClassType(
                classSymbol: arraySymbol,
                args: [.invariant(receiverElementType)],
                nullability: .nonNull
            )))
        }

        if memberName == interner.intern("chunked") && args.count == 2 {
            let transformExpr = args[1].expr
            // Prefer the lambda body's inferred type over the stored function type,
            // because inferLambdaLiteralExpr binds the lambda to the *expected* type
            // (e.g. (List<T>) -> Any) rather than the *inferred* return type.
            let lambdaReturnType: TypeID = {
                if let lambdaNode = ctx.ast.arena.expr(transformExpr),
                   case let .lambdaLiteral(_, body: bodyExprID, _, _) = lambdaNode,
                   let bodyType = sema.bindings.exprTypes[bodyExprID],
                   bodyType != sema.types.nothingType
                {
                    return bodyType
                }
                if let transformType = sema.bindings.exprTypes[transformExpr],
                   case let .functionType(fnType) = sema.types.kind(of: transformType),
                   fnType.returnType != sema.types.anyType
                {
                    return fnType.returnType
                }
                return sema.types.anyType
            }()

            if isSequenceReceiver {
                return makeSyntheticSequenceType(
                    symbols: sema.symbols,
                    types: sema.types,
                    interner: interner,
                    elementType: lambdaReturnType
                )
            }

            if let listSymbol = sema.symbols.lookupByShortName(interner.intern("List")).first {
                return sema.types.make(.classType(ClassType(
                    classSymbol: listSymbol,
                    args: [.out(lambdaReturnType)],
                    nullability: .nonNull
                )))
            }
            return sema.types.anyType
        }

        if memberName == interner.intern("windowed") {
            let lastArgIsFunctionLike: Bool = if let lastExpr = args.last?.expr,
                                                 let lastExprNode = ctx.ast.arena.expr(lastExpr) {
                lastExprNode.isLambdaOrCallableRef
            } else {
                false
            }
            if !lastArgIsFunctionLike,
               let listSymbol = sema.symbols.lookupByShortName(interner.intern("List")).first
            {
                let windowType = sema.types.make(.classType(ClassType(
                    classSymbol: listSymbol,
                    args: [.invariant(receiverElementType)],
                    nullability: .nonNull
                )))
                if isSequenceReceiver {
                    return makeSyntheticSequenceType(
                        symbols: sema.symbols,
                        types: sema.types,
                        interner: interner,
                        elementType: windowType
                    )
                }
                return sema.types.make(.classType(ClassType(
                    classSymbol: listSymbol,
                    args: [.out(windowType)],
                    nullability: .nonNull
                )))
            }
        }

        if memberName == interner.intern("requireNoNulls") {
            let elementType = sema.types.makeNonNullable(receiverElementType)
            if isSequenceReceiver {
                return makeSyntheticSequenceType(
                    symbols: sema.symbols,
                    types: sema.types,
                    interner: interner,
                    elementType: elementType
                )
            }
            if let iterableSymbol = sema.symbols.lookup(fqName: [
                interner.intern("kotlin"),
                interner.intern("collections"),
                interner.intern("Iterable"),
            ]) {
                return sema.types.make(.classType(ClassType(
                    classSymbol: iterableSymbol,
                    args: [.out(elementType)],
                    nullability: .nonNull
                )))
            }
        }

        let boolReturningMembers: Set = [
            knownNames.isEmpty, interner.intern("contains"), interner.intern("containsAll"),
            interner.intern("containsKey"),
            interner.intern("addAll"), interner.intern("removeAll"), interner.intern("retainAll"),
        ]
        if boolReturningMembers.contains(memberName) {
            return sema.types.make(.primitive(.boolean, .nonNull))
        }

        if memberName == interner.intern("sort") ||
            memberName == interner.intern("sortBy") ||
            memberName == interner.intern("sortByDescending")
        {
            return sema.types.unitType
        }

        if memberName == interner.intern("joinToString") {
            return sema.types.stringType
        }

        if memberName == knownNames.putAll {
            return sema.types.unitType
        }

        let destinationCollectionReturningMembers: Set = [
            interner.intern("filterIsInstanceTo"),
            interner.intern("filterNotNullTo"),
            interner.intern("reduceTo"),
            interner.intern("toCollection"),
        ]
        if destinationCollectionReturningMembers.contains(memberName),
           let firstArg = args.first
        {
            return sema.bindings.exprTypes[firstArg.expr] ?? sema.types.anyType
        }

        if memberName == interner.intern("flatMapIndexed") {
            let lambdaReturnType: TypeID = if let firstArg = args.first,
                                              case let .functionType(fnType) = sema.types.kind(
                                                  of: sema.bindings.exprTypes[firstArg.expr] ?? sema.types.anyType
                                              ) {
                fnType.returnType
            } else {
                sema.types.anyType
            }
            let flattenedElementType: TypeID = if case let .classType(classType) = sema.types.kind(
                of: sema.types.makeNonNullable(lambdaReturnType)
            ), let firstArg = classType.args.first {
                switch firstArg {
                case let .invariant(type), let .out(type), let .in(type):
                    type
                case .star:
                    sema.types.anyType
                }
            } else {
                sema.types.anyType
            }
            if isSequenceReceiver {
                return makeSyntheticSequenceType(
                    symbols: sema.symbols,
                    types: sema.types,
                    interner: interner,
                    elementType: flattenedElementType
                )
            }
            if let listSymbol = sema.symbols.lookupByShortName(interner.intern("List")).first {
                return sema.types.make(.classType(ClassType(
                    classSymbol: listSymbol,
                    args: [.invariant(flattenedElementType)],
                    nullability: .nonNull
                )))
            }
            return sema.types.anyType
        }

        if memberName == interner.intern("find") {
            return sema.types.makeNullable(receiverElementType)
        }

        if memberName == interner.intern("firstNotNullOf") {
            if let expectedType {
                return sema.types.makeNonNullable(expectedType)
            }
            guard let firstArg = args.first else { return sema.types.anyType }
            if case let .functionType(fnType) = sema.types.kind(of: sema.bindings.exprTypes[firstArg.expr] ?? sema.types.anyType) {
                return sema.types.makeNonNullable(fnType.returnType)
            }
            return sema.types.anyType
        }

        if memberName == interner.intern("firstNotNullOfOrNull") {
            if let expectedType {
                return sema.types.makeNullable(sema.types.makeNonNullable(expectedType))
            }
            guard let firstArg = args.first else { return sema.types.nullableAnyType }
            if case let .functionType(fnType) = sema.types.kind(of: sema.bindings.exprTypes[firstArg.expr] ?? sema.types.anyType) {
                return sema.types.makeNullable(sema.types.makeNonNullable(fnType.returnType))
            }
            return sema.types.nullableAnyType
        }

        if memberName == interner.intern("asIterable") {
            return makeSyntheticIterableType(
                symbols: sema.symbols,
                types: sema.types,
                interner: interner,
                elementType: receiverElementType
            )
        }

        if memberName == interner.intern("elementAt")
            || memberName == interner.intern("single")
        {
            return receiverElementType
        }

        if memberName == interner.intern("getOrNull")
            || memberName == interner.intern("elementAtOrNull")
            || memberName == interner.intern("firstOrNull")
            || memberName == interner.intern("lastOrNull")
            || memberName == interner.intern("singleOrNull")
        {
            return sema.types.makeNullable(receiverElementType)
        }

        if memberName == knownNames.getOrElse, !isMapReceiver {
            return receiverElementType
        }

        if memberName == interner.intern("elementAtOrElse") {
            return receiverElementType
        }

        if memberName == interner.intern("plus") || memberName == interner.intern("minus") {
            // plus/minus return the same Map type as the receiver.
            // receiverElementType for maps is Map.Entry<K,V>, so reconstruct Map<K,V>.
            if case let .classType(entryType) = sema.types.kind(of: receiverElementType),
               entryType.args.count >= 2
            {
                let keyArg = entryType.args[0]
                let valueArg = entryType.args[1]
                if let mapSymbol = sema.symbols.lookup(fqName: [
                    interner.intern("kotlin"),
                    interner.intern("collections"),
                    interner.intern("Map"),
                ]) {
                    return sema.types.make(.classType(ClassType(
                        classSymbol: mapSymbol,
                        args: [keyArg, valueArg],
                        nullability: .nonNull
                    )))
                }
            }
            return sema.types.anyType
        }

        if memberName == knownNames.getValue
            || memberName == knownNames.getOrDefault
            || memberName == knownNames.getOrPut
            || (memberName == knownNames.getOrElse && isMapReceiver)
        {
            if case let .classType(classType) = sema.types.kind(of: receiverElementType),
               classType.args.count >= 2
            {
                return switch classType.args[1] {
                case let .invariant(t), let .out(t), let .in(t): t
                case .star: sema.types.anyType
                }
            }
            return sema.types.anyType
        }

        if memberName == interner.intern("minBy") || memberName == interner.intern("min") {
            return receiverElementType
        }

        if memberName == interner.intern("maxOrNull")
            || memberName == interner.intern("minOrNull")
            || memberName == interner.intern("maxByOrNull")
            || memberName == interner.intern("minByOrNull")
            || memberName == interner.intern("firstOrNull")
            || memberName == interner.intern("lastOrNull")
            || memberName == interner.intern("singleOrNull")
        {
            return sema.types.makeNullable(receiverElementType)
        }

        if memberName == interner.intern("maxOfOrNull")
            || memberName == interner.intern("minOfOrNull")
        {
            return sema.types.nullableAnyType
        }

        if (memberName == interner.intern("toList")
            || memberName == interner.intern("subList")
            || memberName == interner.intern("slice")
            || memberName == interner.intern("minusElement")),
           let listSymbol = sema.symbols.lookupByShortName(interner.intern("List")).first
        {
            if memberName == interner.intern("minusElement"), isSequenceReceiver {
                return makeSyntheticSequenceType(
                    symbols: sema.symbols,
                    types: sema.types,
                    interner: interner,
                    elementType: receiverElementType
                )
            }
            return sema.types.make(.classType(ClassType(
                classSymbol: listSymbol,
                args: [.invariant(receiverElementType)],
                nullability: .nonNull
            )))
        }

        if memberName == interner.intern("toTypedArray") {
            return makeSyntheticArrayType(
                symbols: sema.symbols,
                types: sema.types,
                interner: interner,
                elementType: receiverElementType
            )
        }

        if memberName == interner.intern("toIntArray"),
           let intArraySymbol = sema.symbols.lookup(fqName: [
               interner.intern("kotlin"),
               interner.intern("IntArray"),
           ])
        {
            return sema.types.make(.classType(ClassType(
                classSymbol: intArraySymbol,
                args: [],
                nullability: .nonNull
            )))
        }

        if memberName == interner.intern("toCharArray"),
           let charArraySymbol = sema.symbols.lookup(fqName: [
               interner.intern("kotlin"),
               interner.intern("CharArray"),
           ])
        {
            return sema.types.make(.classType(ClassType(
                classSymbol: charArraySymbol,
                args: [],
                nullability: .nonNull
            )))
        }

        if memberName == interner.intern("toBooleanArray"),
           let booleanArraySymbol = sema.symbols.lookup(fqName: [
               interner.intern("kotlin"),
               interner.intern("BooleanArray"),
           ])
        {
            return sema.types.make(.classType(ClassType(
                classSymbol: booleanArraySymbol,
                args: [],
                nullability: .nonNull
            )))
        }

        if memberName == interner.intern("toShortArray"),
           let shortArraySymbol = sema.symbols.lookup(fqName: [
               interner.intern("kotlin"),
               interner.intern("ShortArray"),
           ])
        {
            return sema.types.make(.classType(ClassType(
                classSymbol: shortArraySymbol,
                args: [],
                nullability: .nonNull
            )))
        }

        if memberName == interner.intern("toDoubleArray"),
           let doubleArraySymbol = sema.symbols.lookup(fqName: [
               interner.intern("kotlin"),
               interner.intern("DoubleArray"),
           ])
        {
            return sema.types.make(.classType(ClassType(
                classSymbol: doubleArraySymbol,
                args: [],
                nullability: .nonNull
            )))
        }

        if memberName == interner.intern("toFloatArray"),
           let floatArraySymbol = sema.symbols.lookup(fqName: [
               interner.intern("kotlin"),
               interner.intern("FloatArray"),
           ])
        {
            return sema.types.make(.classType(ClassType(
                classSymbol: floatArraySymbol,
                args: [],
                nullability: .nonNull
            )))
        }

        if memberName == interner.intern("toLongArray"),
           let longArraySymbol = sema.symbols.lookup(fqName: [
               interner.intern("kotlin"),
               interner.intern("LongArray"),
           ])
        {
            return sema.types.make(.classType(ClassType(
                classSymbol: longArraySymbol,
                args: [],
                nullability: .nonNull
            )))
        }

        if memberName == interner.intern("toByteArray"),
           let byteArraySymbol = sema.symbols.lookup(fqName: [
               interner.intern("kotlin"),
               interner.intern("ByteArray"),
           ])
        {
            return sema.types.make(.classType(ClassType(
                classSymbol: byteArraySymbol,
                args: [],
                nullability: .nonNull
            )))
        }

        if memberName == interner.intern("toUByteArray"),
           let ubyteArraySymbol = sema.symbols.lookup(fqName: [
               interner.intern("kotlin"),
               interner.intern("UByteArray"),
           ])
        {
            return sema.types.make(.classType(ClassType(
                classSymbol: ubyteArraySymbol,
                args: [],
                nullability: .nonNull
            )))
        }

        if memberName == interner.intern("toUShortArray"),
           let ushortArraySymbol = sema.symbols.lookup(fqName: [
               interner.intern("kotlin"),
               interner.intern("UShortArray"),
           ])
        {
            return sema.types.make(.classType(ClassType(
                classSymbol: ushortArraySymbol,
                args: [],
                nullability: .nonNull
            )))
        }

        if memberName == interner.intern("toUIntArray"),
           let uintArraySymbol = sema.symbols.lookup(fqName: [
               interner.intern("kotlin"),
               interner.intern("UIntArray"),
           ])
        {
            return sema.types.make(.classType(ClassType(
                classSymbol: uintArraySymbol,
                args: [],
                nullability: .nonNull
            )))
        }

        if memberName == interner.intern("toULongArray"),
           let ulongArraySymbol = sema.symbols.lookup(fqName: [
               interner.intern("kotlin"),
               interner.intern("ULongArray"),
           ])
        {
            return sema.types.make(.classType(ClassType(
                classSymbol: ulongArraySymbol,
                args: [],
                nullability: .nonNull
            )))
        }

        if memberName == interner.intern("toMutableList"),
           let mutableListSymbol = sema.symbols.lookupByShortName(interner.intern("MutableList")).first
        {
            return sema.types.make(.classType(ClassType(
                classSymbol: mutableListSymbol,
                args: [.invariant(receiverElementType)],
                nullability: .nonNull
            )))
        }

        if memberName == interner.intern("reduceOrNull")
            || memberName == interner.intern("reduceIndexedOrNull")
        {
            return sema.types.makeNullable(receiverElementType)
        }

        if (memberName == interner.intern("runningReduce")
            || memberName == interner.intern("runningReduceIndexed")
            || memberName == interner.intern("scanReduce")),
           let listSymbol = sema.symbols.lookupByShortName(interner.intern("List")).first
        {
            return sema.types.make(.classType(ClassType(
                classSymbol: listSymbol,
                args: [.invariant(receiverElementType)],
                nullability: .nonNull
            )))
        }

        if (memberName == interner.intern("scan")
            || memberName == interner.intern("scanIndexed")
            || memberName == interner.intern("runningFold")
            || memberName == interner.intern("runningFoldIndexed")),
           let listSymbol = sema.symbols.lookupByShortName(interner.intern("List")).first
        {
            // scan/runningFold variants return List<R> where R is the accumulator type,
            // derived from the initial value (first argument).
            let accumulatorType: TypeID
            if args.count >= 1, let inferredInitType = sema.bindings.exprTypes[args[0].expr] {
                accumulatorType = inferredInitType
            } else {
                accumulatorType = sema.types.anyType
            }
            return sema.types.make(.classType(ClassType(
                classSymbol: listSymbol,
                args: [.invariant(accumulatorType)],
                nullability: .nonNull
            )))
        }

        if (isListReceiver || isSetReceiver),
           isSetReturningCollectionBinaryMember(memberName, interner: interner),
           let setSymbol = sema.symbols.lookup(fqName: [
               interner.intern("kotlin"),
               interner.intern("collections"),
               interner.intern("Set"),
           ])
        {
            return sema.types.make(.classType(ClassType(
                classSymbol: setSymbol,
                args: [.invariant(receiverElementType)],
                nullability: .nonNull
            )))
        }

        if memberName == interner.intern("withIndex"),
           let iterableSymbol = sema.symbols.lookup(fqName: [
               interner.intern("kotlin"),
               interner.intern("collections"),
               interner.intern("Iterable"),
           ]),
           let indexedValueSymbol = sema.symbols.lookup(fqName: [
               interner.intern("kotlin"),
               interner.intern("collections"),
               interner.intern("IndexedValue"),
           ])
        {
            let indexedValueType = sema.types.make(.classType(ClassType(
                classSymbol: indexedValueSymbol,
                args: [.out(receiverElementType)],
                nullability: .nonNull
            )))
            return sema.types.make(.classType(ClassType(
                classSymbol: iterableSymbol,
                args: [.out(indexedValueType)],
                nullability: .nonNull
            )))
        }

        // sorted(), sortedDescending(), sortedWith(), sorted(comparator): return List<E>
        // reversed(), asReversed(), distinct(), distinctBy(): return List<E>
        let listPreservingMembers: Set = [
            interner.intern("sorted"),
            interner.intern("sortedDescending"),
            interner.intern("sortedWith"),
            interner.intern("shuffled"),
            interner.intern("reversed"),
            interner.intern("asReversed"),
            interner.intern("distinct"),
            interner.intern("distinctBy"),
        ]
        if memberName == interner.intern("shuffled"), isSequenceReceiver {
            return makeSyntheticSequenceType(
                symbols: sema.symbols,
                types: sema.types,
                interner: interner,
                elementType: receiverElementType
            )
        }
        if (memberName == interner.intern("sorted") || memberName == interner.intern("sortedDescending")),
           isSequenceReceiver
        {
            return makeSyntheticSequenceType(
                symbols: sema.symbols,
                types: sema.types,
                interner: interner,
                elementType: receiverElementType
            )
        }
        if listPreservingMembers.contains(memberName),
           let listSymbol = sema.symbols.lookupByShortName(interner.intern("List")).first
        {
            return sema.types.make(.classType(ClassType(
                classSymbol: listSymbol,
                args: [.invariant(receiverElementType)],
                nullability: .nonNull
            )))
        }

        // flatten(): for List<List<E>>, returns List<E> (element type of the outer list elements).
        // Skip this for sequence receivers — the existing sequence HOF logic handles them,
        // and mixed-type sequence flatten should fail gracefully (matching kotlinc).
        if memberName == interner.intern("flatten"),
           !isSequenceReceiver,
           let listSymbol = sema.symbols.lookupByShortName(interner.intern("List")).first
        {
            // The receiverElementType is List<E> (the inner list). Extract E from it.
            let innerElementType: TypeID
            if case let .classType(innerListType) = sema.types.kind(of: receiverElementType),
               let firstArg = innerListType.args.first
            {
                innerElementType = switch firstArg {
                case let .invariant(t), let .out(t), let .in(t): t
                case .star: sema.types.anyType
                }
            } else {
                innerElementType = sema.types.anyType
            }
            return sema.types.make(.classType(ClassType(
                classSymbol: listSymbol,
                args: [.invariant(innerElementType)],
                nullability: .nonNull
            )))
        }

        // zip(other): returns List<Pair<A,B>> where A is receiver element type and B is other element type
        if memberName == interner.intern("zip"),
           !args.isEmpty,
           let listSymbol = sema.symbols.lookupByShortName(interner.intern("List")).first,
           let pairSymbol = sema.symbols.lookupByShortName(interner.intern("Pair")).first
        {
            // Try to get the element type of the other list from the first argument
            let otherElementType: TypeID
            if let otherListType = sema.bindings.exprTypes[args[0].expr] {
                let nonNullOther = sema.types.makeNonNullable(otherListType)
                if case let .classType(classType) = sema.types.kind(of: nonNullOther),
                   let firstArg = classType.args.first
                {
                    otherElementType = switch firstArg {
                    case let .invariant(t), let .out(t), let .in(t): t
                    case .star: sema.types.anyType
                    }
                } else {
                    otherElementType = sema.types.anyType
                }
            } else {
                otherElementType = sema.types.anyType
            }
            let pairType = sema.types.make(.classType(ClassType(
                classSymbol: pairSymbol,
                args: [.invariant(receiverElementType), .invariant(otherElementType)],
                nullability: .nonNull
            )))
            return sema.types.make(.classType(ClassType(
                classSymbol: listSymbol,
                args: [.invariant(pairType)],
                nullability: .nonNull
            )))
        }

        // unzip(): for List<Pair<A,B>>, returns Pair<List<A>, List<B>>
        if memberName == interner.intern("unzip"),
           let listSymbol = sema.symbols.lookupByShortName(interner.intern("List")).first,
           let pairSymbol = sema.symbols.lookupByShortName(interner.intern("Pair")).first
        {
            // receiverElementType should be Pair<A, B>; extract A and B
            let aType: TypeID
            let bType: TypeID
            if case let .classType(pairClassType) = sema.types.kind(of: receiverElementType),
               pairClassType.args.count >= 2
            {
                aType = switch pairClassType.args[0] {
                case let .invariant(t), let .out(t), let .in(t): t
                case .star: sema.types.anyType
                }
                bType = switch pairClassType.args[1] {
                case let .invariant(t), let .out(t), let .in(t): t
                case .star: sema.types.anyType
                }
            } else {
                aType = sema.types.anyType
                bType = sema.types.anyType
            }
            let listAType = sema.types.make(.classType(ClassType(
                classSymbol: listSymbol,
                args: [.invariant(aType)],
                nullability: .nonNull
            )))
            let listBType = sema.types.make(.classType(ClassType(
                classSymbol: listSymbol,
                args: [.invariant(bType)],
                nullability: .nonNull
            )))
            return sema.types.make(.classType(ClassType(
                classSymbol: pairSymbol,
                args: [.out(listAType), .out(listBType)],
                nullability: .nonNull
            )))
        }

        // iterator(): returns Iterator<E>
        if memberName == interner.intern("iterator"),
           let iteratorSymbol = sema.symbols.lookup(fqName: [
               interner.intern("kotlin"),
               interner.intern("collections"),
               interner.intern("Iterator"),
           ])
        {
            return sema.types.make(.classType(ClassType(
                classSymbol: iteratorSymbol,
                args: [.out(receiverElementType)],
                nullability: .nonNull
            )))
        }

        if isSequenceReceiver,
           memberName == interner.intern("windowed"),
           args.count == 4
        {
            let transformExpr = args[3].expr
            let transformType = sema.bindings.exprTypes[transformExpr] ?? sema.types.anyType
            let transformedElementType: TypeID
            if case let .functionType(fnType) = sema.types.kind(of: sema.types.makeNonNullable(transformType)) {
                transformedElementType = fnType.returnType
            } else {
                transformedElementType = sema.types.anyType
            }
            return makeSyntheticSequenceType(
                symbols: sema.symbols,
                types: sema.types,
                interner: interner,
                elementType: transformedElementType
            )
        }

        if isSequenceReceiver,
           memberName == interner.intern("chunked"),
           args.count == 2
        {
            let transformExpr = args[1].expr
            let transformType = sema.bindings.exprTypes[transformExpr] ?? sema.types.anyType
            let transformedElementType: TypeID
            if case let .functionType(fnType) = sema.types.kind(of: sema.types.makeNonNullable(transformType)) {
                transformedElementType = fnType.returnType
            } else {
                transformedElementType = sema.types.anyType
            }
            return makeSyntheticSequenceType(
                symbols: sema.symbols,
                types: sema.types,
                interner: interner,
                elementType: transformedElementType
            )
        }

        return sema.types.anyType
    }

    private func stdlibSurfaceDestinationTypes(
        args: [CallArgument],
        sema: SemaModule
    ) -> (collectionElement: TypeID, mapKey: TypeID, mapValue: TypeID) {
        let destinationType = args.first.flatMap { sema.bindings.exprTypes[$0.expr] } ?? sema.types.anyType
        let destinationCollectionElementType: TypeID = if case let .classType(destClassType) = sema.types.kind(of: destinationType),
                                                               destClassType.args.count >= 1
        {
            switch destClassType.args[0] {
            case let .invariant(id), let .out(id), let .in(id): id
            case .star: sema.types.anyType
            }
        } else {
            sema.types.anyType
        }
        let destinationMapKeyType: TypeID = if case let .classType(destClassType) = sema.types.kind(of: destinationType),
                                                      destClassType.args.count >= 2
        {
            switch destClassType.args[0] {
            case let .invariant(id), let .out(id), let .in(id): id
            case .star: sema.types.anyType
            }
        } else {
            sema.types.anyType
        }
        let destinationMapValueType: TypeID = if case let .classType(destClassType) = sema.types.kind(of: destinationType),
                                                        destClassType.args.count >= 2
        {
            switch destClassType.args[1] {
            case let .invariant(id), let .out(id), let .in(id): id
            case .star: sema.types.anyType
            }
        } else {
            sema.types.anyType
        }
        return (destinationCollectionElementType, destinationMapKeyType, destinationMapValueType)
    }

    private func stdlibSurfaceMapEntryTypes(
        receiverElementType: TypeID,
        sema: SemaModule
    ) -> (key: TypeID, value: TypeID) {
        guard case let .classType(entryType) = sema.types.kind(of: receiverElementType),
              entryType.args.count >= 2
        else {
            return (sema.types.anyType, sema.types.anyType)
        }
        let keyType: TypeID = switch entryType.args[0] {
        case let .invariant(id), let .out(id), let .in(id): id
        case .star: sema.types.anyType
        }
        let valueType: TypeID = switch entryType.args[1] {
        case let .invariant(id), let .out(id), let .in(id): id
        case .star: sema.types.anyType
        }
        return (keyType, valueType)
    }

    private func stdlibSurfaceLambdaReturnType(
        _ strategy: StdlibSurfaceLambdaReturnStrategy,
        args: [CallArgument],
        sema: SemaModule,
        interner: StringInterner
    ) -> TypeID {
        let destinationTypes = stdlibSurfaceDestinationTypes(args: args, sema: sema)
        switch strategy {
        case .any:
            return sema.types.anyType
        case .nullableAny:
            return sema.types.nullableAnyType
        case .boolean:
            return sema.types.booleanType
        case .int:
            return sema.types.intType
        case .double:
            return sema.types.doubleType
        case .unit:
            return sema.types.unitType
        case .destinationElement:
            return destinationTypes.collectionElement
        case .destinationMapKey:
            return destinationTypes.mapKey
        case .destinationMapValue:
            return destinationTypes.mapValue
        case .collectionOfDestinationElement:
            if let collectionSymbol = sema.symbols.lookupByShortName(interner.intern("Collection")).first {
                return sema.types.make(.classType(ClassType(
                    classSymbol: collectionSymbol,
                    args: [.out(destinationTypes.collectionElement)],
                    nullability: .nonNull
                )))
            }
            return sema.types.anyType
        case .pairOfDestinationKeyValue:
            if let pairSymbol = sema.symbols.lookupByShortName(interner.intern("Pair")).first {
                return sema.types.make(.classType(ClassType(
                    classSymbol: pairSymbol,
                    args: [.out(destinationTypes.mapKey), .out(destinationTypes.mapValue)],
                    nullability: .nonNull
                )))
            }
            return sema.types.anyType
        }
    }

    private func stdlibSurfaceLambdaExpectation(
        for spec: StdlibSurfaceSpec,
        receiverElementType: TypeID,
        args: [CallArgument],
        sema: SemaModule,
        interner: StringInterner
    ) -> (argumentIndex: Int, expectedType: TypeID)? {
        let argumentIndex: Int
        let parameterTypes: [TypeID]
        let returnStrategy: StdlibSurfaceLambdaReturnStrategy
        switch spec.lambdaExpectation {
        case .none:
            return nil
        case let .receiverElement(argumentIndex: index, returnStrategy: strategy),
             let .destinationElement(argumentIndex: index, returnStrategy: strategy):
            argumentIndex = index
            parameterTypes = [receiverElementType]
            returnStrategy = strategy
        case let .indexedReceiverElement(argumentIndex: index, returnStrategy: strategy),
             let .indexedDestinationElement(argumentIndex: index, returnStrategy: strategy):
            argumentIndex = index
            parameterTypes = [sema.types.intType, receiverElementType]
            returnStrategy = strategy
        case let .mapKey(argumentIndex: index, returnStrategy: strategy):
            let mapEntryTypes = stdlibSurfaceMapEntryTypes(receiverElementType: receiverElementType, sema: sema)
            argumentIndex = index
            parameterTypes = [mapEntryTypes.key]
            returnStrategy = strategy
        case let .mapValue(argumentIndex: index, returnStrategy: strategy):
            let mapEntryTypes = stdlibSurfaceMapEntryTypes(receiverElementType: receiverElementType, sema: sema)
            argumentIndex = index
            parameterTypes = [mapEntryTypes.value]
            returnStrategy = strategy
        }
        let returnType = stdlibSurfaceLambdaReturnType(
            returnStrategy,
            args: args,
            sema: sema,
            interner: interner
        )
        let expectedType = sema.types.make(.functionType(FunctionType(
            params: parameterTypes,
            returnType: returnType,
            isSuspend: false,
            nullability: .nonNull
        )))
        return (argumentIndex: argumentIndex, expectedType: expectedType)
    }

    func collectionFallbackLambdaExpectation(
        memberName: InternedString,
        argCount: Int,
        receiverElementType: TypeID,
        isMapReceiver: Bool,
        isSetReceiver: Bool,
        isMutableMapReceiver: Bool,
        args: [CallArgument],
        ctx: TypeInferenceContext,
        interner: StringInterner,
        sema: SemaModule
    ) -> (argumentIndex: Int, expectedType: TypeID)? {
        let surfaceOwnerKinds: [StdlibSurfaceOwnerKind] = if isMapReceiver {
            [.map]
        } else if isSetReceiver {
            [.set]
        } else {
            [.list, .sequence]
        }
        if let surfaceSpec = stdlibSurfaceSpecForCollectionFallback(
            memberName: memberName,
            argCount: argCount,
            ownerKinds: surfaceOwnerKinds,
            interner: interner
        ),
           let surfaceExpectation = stdlibSurfaceLambdaExpectation(
            for: surfaceSpec,
            receiverElementType: receiverElementType,
            args: args,
            sema: sema,
            interner: interner
           ) {
            return surfaceExpectation
        }
        let boolOneParamMembers: Set = [
            interner.intern("count"),
            interner.intern("first"),
            interner.intern("last"),
            interner.intern("single"),
            interner.intern("find"),
            interner.intern("indexOfFirst"),
            interner.intern("indexOfLast"),
            interner.intern("partition"),
        ]
        let knownNames = KnownCompilerNames(interner: interner)
        let oneParamMembers: Set = [
            interner.intern("sortedBy"),
            interner.intern("count"),
            interner.intern("first"),
            interner.intern("last"),
            interner.intern("single"),
            interner.intern("find"),
            interner.intern("sortedByDescending"),
            interner.intern("partition"),
            interner.intern("sortBy"),
            interner.intern("sortByDescending"),
            interner.intern("maxByOrNull"),
            interner.intern("minByOrNull"),
            interner.intern("maxOfOrNull"),
            interner.intern("minOfOrNull"),
            interner.intern("maxOf"),
            interner.intern("minOf"),
        ]
        let mapOnlyMembers: Set = [
            knownNames.getOrDefault,
        ]
        if mapOnlyMembers.contains(memberName) {
            guard isMapReceiver else {
                return nil
            }
        }
        if oneParamMembers.contains(memberName), argCount == 1 {
            let lambdaReturnType = boolOneParamMembers.contains(memberName)
                ? sema.types.make(.primitive(.boolean, .nonNull))
                : memberName == interner.intern("averageOf") || memberName == interner.intern("sumOf") || memberName == interner.intern("sumBy")
                ? sema.types.intType
                : memberName == interner.intern("sumByDouble")
                ? sema.types.doubleType
                : memberName == interner.intern("firstNotNullOf") || memberName == interner.intern("firstNotNullOfOrNull")
                ? sema.types.nullableAnyType
                : sema.types.anyType
            let expectedType = sema.types.make(.functionType(FunctionType(
                params: [receiverElementType],
                returnType: lambdaReturnType,
                isSuspend: false,
                nullability: .nonNull
            )))
            return (argumentIndex: 0, expectedType: expectedType)
        }

        if (memberName == interner.intern("maxWith")
            || memberName == interner.intern("maxWithOrNull")
            || memberName == interner.intern("minWith")
            || memberName == interner.intern("minWithOrNull")),
           argCount == 1,
           let comparatorSymbol = sema.symbols.lookup(fqName: [
               interner.intern("kotlin"),
               interner.intern("Comparator"),
           ])
        {
            let expectedType = sema.types.make(.classType(ClassType(
                classSymbol: comparatorSymbol,
                args: [.invariant(receiverElementType)],
                nullability: .nonNull
            )))
            return (argumentIndex: 0, expectedType: expectedType)
        }

        if (memberName == interner.intern("maxOfWith")
            || memberName == interner.intern("maxOfWithOrNull")
            || memberName == interner.intern("minOfWith")
            || memberName == interner.intern("minOfWithOrNull")),
           argCount == 2
        {
            let expectedType = sema.types.make(.functionType(FunctionType(
                params: [receiverElementType],
                returnType: sema.types.anyType,
                isSuspend: false,
                nullability: .nonNull
            )))
            return (argumentIndex: 1, expectedType: expectedType)
        }

        // chunked(size, transform): transform receives List<T> and returns R
        if memberName == interner.intern("chunked"), argCount == 2 {
            // Build List<T> for the lambda parameter type; the transform receives
            // a List<T> chunk.
            let listType: TypeID
            if let listSymbol = sema.symbols.lookup(fqName: [
                interner.intern("kotlin"),
                interner.intern("collections"),
                interner.intern("List"),
            ]) {
                listType = sema.types.make(.classType(ClassType(
                    classSymbol: listSymbol,
                    args: [.invariant(receiverElementType)],
                    nullability: .nonNull
                )))
            } else {
                listType = sema.types.anyType
            }
            let expectedType = sema.types.make(.functionType(FunctionType(
                params: [listType],
                returnType: sema.types.anyType,
                isSuspend: false,
                nullability: .nonNull
            )))
            return (argumentIndex: 1, expectedType: expectedType)
        }

        // windowed(size, step, partialWindows, transform): transform receives List<T> and returns R
        if memberName == interner.intern("windowed"), (2...4).contains(argCount) {
            let lastArgIsFunctionLike: Bool = if let lastExpr = args.last?.expr,
                                                 let lastExprNode = ctx.ast.arena.expr(lastExpr) {
                lastExprNode.isLambdaOrCallableRef
            } else {
                false
            }
            if lastArgIsFunctionLike {
                let listType: TypeID
                if let listSymbol = sema.symbols.lookup(fqName: [
                    interner.intern("kotlin"),
                    interner.intern("collections"),
                    interner.intern("List"),
                ]) {
                    listType = sema.types.make(.classType(ClassType(
                        classSymbol: listSymbol,
                        args: [.invariant(receiverElementType)],
                        nullability: .nonNull
                    )))
                } else {
                    listType = sema.types.anyType
                }
                let expectedType = sema.types.make(.functionType(FunctionType(
                    params: [listType],
                    returnType: sema.types.anyType,
                    isSuspend: false,
                    nullability: .nonNull
                )))
                return (argumentIndex: argCount - 1, expectedType: expectedType)
            }
        }

        if memberName == interner.intern("fold"), argCount == 2 {
            let expectedType = sema.types.make(.functionType(FunctionType(
                params: [sema.types.anyType, sema.types.anyType],
                returnType: sema.types.anyType,
                isSuspend: false,
                nullability: .nonNull
            )))
            return (argumentIndex: 1, expectedType: expectedType)
        }

        if memberName == interner.intern("foldIndexed"), argCount == 2 {
            let expectedType = sema.types.make(.functionType(FunctionType(
                params: [sema.types.intType, sema.types.anyType, sema.types.anyType],
                returnType: sema.types.anyType,
                isSuspend: false,
                nullability: .nonNull
            )))
            return (argumentIndex: 1, expectedType: expectedType)
        }

        if memberName == interner.intern("foldRight"), argCount == 2 {
            let expectedType = sema.types.make(.functionType(FunctionType(
                params: [sema.types.anyType, sema.types.anyType],
                returnType: sema.types.anyType,
                isSuspend: false,
                nullability: .nonNull
            )))
            return (argumentIndex: 1, expectedType: expectedType)
        }

        if memberName == interner.intern("foldRightIndexed"), argCount == 2 {
            let expectedType = sema.types.make(.functionType(FunctionType(
                params: [sema.types.intType, sema.types.anyType, sema.types.anyType],
                returnType: sema.types.anyType,
                isSuspend: false,
                nullability: .nonNull
            )))
            return (argumentIndex: 1, expectedType: expectedType)
        }

        if memberName == interner.intern("reduceRight"), argCount == 1 {
            let expectedType = sema.types.make(.functionType(FunctionType(
                params: [sema.types.anyType, sema.types.anyType],
                returnType: sema.types.anyType,
                isSuspend: false,
                nullability: .nonNull
            )))
            return (argumentIndex: 0, expectedType: expectedType)
        }

        if (memberName == interner.intern("reduce") || memberName == interner.intern("reduceOrNull")), argCount == 1 {
            let expectedType = sema.types.make(.functionType(FunctionType(
                params: [sema.types.anyType, sema.types.anyType],
                returnType: sema.types.anyType,
                isSuspend: false,
                nullability: .nonNull
            )))
            return (argumentIndex: 0, expectedType: expectedType)
        }

        if memberName == interner.intern("reduceIndexed"), argCount == 1 {
            let expectedType = sema.types.make(.functionType(FunctionType(
                params: [sema.types.intType, sema.types.anyType, sema.types.anyType],
                returnType: sema.types.anyType,
                isSuspend: false,
                nullability: .nonNull
            )))
            return (argumentIndex: 0, expectedType: expectedType)
        }

        if (memberName == interner.intern("scan")
            || memberName == interner.intern("scanIndexed")
            || memberName == interner.intern("runningFold")
            || memberName == interner.intern("runningFoldIndexed")), argCount == 2
        {
            // scan/runningFold variants: (acc: R, element: T) -> R
            // The accumulator type is unknown in the fallback path, so use Any;
            // indexed variants prepend the Int index parameter.
            let params: [TypeID] = if memberName == interner.intern("scanIndexed")
                || memberName == interner.intern("runningFoldIndexed")
            {
                [sema.types.intType, sema.types.anyType, receiverElementType]
            } else {
                [sema.types.anyType, receiverElementType]
            }
            let expectedType = sema.types.make(.functionType(FunctionType(
                params: params,
                returnType: sema.types.anyType,
                isSuspend: false,
                nullability: .nonNull
            )))
            return (argumentIndex: 1, expectedType: expectedType)
        }

        if (memberName == interner.intern("runningReduce")
            || memberName == interner.intern("runningReduceIndexed")
            || memberName == interner.intern("scanReduce")
            || memberName == interner.intern("reduceRightIndexed")
            || memberName == interner.intern("reduceRightIndexedOrNull")
            || memberName == interner.intern("reduceRightOrNull")
            || memberName == interner.intern("reduceIndexedOrNull")), argCount == 1
        {
            // reduce/runningReduce variants use receiver element type.
            let params: [TypeID] = if memberName == interner.intern("runningReduceIndexed")
                || memberName == interner.intern("reduceIndexedOrNull")
                || memberName == interner.intern("reduceRightIndexed")
                || memberName == interner.intern("reduceRightIndexedOrNull")
            {
                [sema.types.intType, receiverElementType, receiverElementType]
            } else {
                [receiverElementType, receiverElementType]
            }
            let expectedType = sema.types.make(.functionType(FunctionType(
                params: params,
                returnType: receiverElementType,
                isSuspend: false,
                nullability: .nonNull
            )))
            return (argumentIndex: 0, expectedType: expectedType)
        }

        if memberName == interner.intern("sortedWith"), argCount == 1 {
            let expectedType = sema.types.make(.functionType(FunctionType(
                params: [receiverElementType, receiverElementType],
                returnType: sema.types.intType,
                isSuspend: false,
                nullability: .nonNull
            )))
            return (argumentIndex: 0, expectedType: expectedType)
        }

        if memberName == knownNames.getOrPut, isMutableMapReceiver, argCount == 2 {
            let valueType: TypeID = if case let .classType(classType) = sema.types.kind(of: receiverElementType),
                                       classType.args.count >= 2
            {
                switch classType.args[1] {
                case let .invariant(t), let .out(t), let .in(t): t
                case .star: sema.types.anyType
                }
            } else {
                sema.types.anyType
            }
            let expectedType = sema.types.make(.functionType(FunctionType(
                params: [],
                returnType: valueType,
                isSuspend: false,
                nullability: .nonNull
            )))
            return (argumentIndex: 1, expectedType: expectedType)
        }

        if memberName == knownNames.getOrElse, isMapReceiver, argCount == 2 {
            let valueType: TypeID = if case let .classType(classType) = sema.types.kind(of: receiverElementType),
                                       classType.args.count >= 2
            {
                switch classType.args[1] {
                case let .invariant(t), let .out(t), let .in(t): t
                case .star: sema.types.anyType
                }
            } else {
                sema.types.anyType
            }
            let expectedType = sema.types.make(.functionType(FunctionType(
                params: [],
                returnType: valueType,
                isSuspend: false,
                nullability: .nonNull
            )))
            return (argumentIndex: 1, expectedType: expectedType)
        }

        // List.getOrElse(index, { default }) — lambda takes Int (index), returns element type
        if memberName == knownNames.getOrElse, !isMapReceiver, argCount == 2 {
            let expectedType = sema.types.make(.functionType(FunctionType(
                params: [sema.types.intType],
                returnType: receiverElementType,
                isSuspend: false,
                nullability: .nonNull
            )))
            return (argumentIndex: 1, expectedType: expectedType)
        }

        // List.elementAtOrElse(index, { default }) — same as getOrElse
        if memberName == interner.intern("elementAtOrElse"), argCount == 2 {
            let expectedType = sema.types.make(.functionType(FunctionType(
                params: [sema.types.intType],
                returnType: receiverElementType,
                isSuspend: false,
                nullability: .nonNull
            )))
            return (argumentIndex: 1, expectedType: expectedType)
        }

        if memberName == interner.intern("binarySearchBy"), (2...4).contains(argCount) {
            let keyType = args.indices.contains(0)
                ? (sema.bindings.exprTypes[args[0].expr] ?? sema.types.nullableAnyType)
                : sema.types.nullableAnyType
            let selectorReturnType: TypeID = if keyType == sema.types.errorType {
                sema.types.nullableAnyType
            } else {
                switch sema.types.kind(of: keyType) {
                case .nothing:
                    sema.types.nullableAnyType
                default:
                    sema.types.makeNullable(keyType)
                }
            }
            let expectedType = sema.types.make(.functionType(FunctionType(
                params: [receiverElementType],
                returnType: selectorReturnType,
                isSuspend: false,
                nullability: .nonNull
            )))
            return (argumentIndex: argCount - 1, expectedType: expectedType)
        }

        return nil
    }

    func collectionFallbackElementType(receiverID: ExprID, sema: SemaModule, interner: StringInterner) -> TypeID {
        let knownNames = KnownCompilerNames(interner: interner)
        let receiverType = sema.bindings.exprTypes[receiverID] ?? sema.types.anyType
        guard case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(receiverType))
        else {
            return sema.types.anyType
        }
        if let symbol = sema.symbols.symbol(classType.classSymbol),
           knownNames.isMapLikeSymbol(symbol),
           classType.args.count == 2
        {
            let keyType = switch classType.args[0] {
            case let .invariant(type), let .out(type), let .in(type):
                type
            case .star:
                sema.types.anyType
            }
            let valueType = switch classType.args[1] {
            case let .invariant(type), let .out(type), let .in(type):
                type
            case .star:
                sema.types.anyType
            }
            let entrySymbol = sema.symbols.lookup(fqName: [
                interner.intern("kotlin"),
                interner.intern("collections"),
                interner.intern("Map"),
                interner.intern("Entry"),
            ])
            guard let entrySymbol else {
                return sema.types.anyType
            }
            return sema.types.make(.classType(ClassType(
                classSymbol: entrySymbol,
                args: [.out(keyType), .out(valueType)],
                nullability: .nonNull
            )))
        }

        guard let firstArg = classType.args.first else {
            return sema.types.anyType
        }
        return switch firstArg {
        case let .invariant(type), let .out(type), let .in(type):
            type
        case .star:
            sema.types.anyType
        }
    }

    func isCollectionLikeReceiver(
        receiverID: ExprID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        if sema.bindings.isCollectionExpr(receiverID) {
            return true
        }
        let receiverType = sema.bindings.exprTypes[receiverID] ?? sema.types.anyType
        return isCollectionLikeType(receiverType, sema: sema, interner: interner)
    }

    func isIterableLikeReceiver(
        receiverID: ExprID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        let receiverType = sema.bindings.exprTypes[receiverID] ?? sema.types.anyType
        guard case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(receiverType)),
              let symbol = sema.symbols.symbol(classType.classSymbol)
        else {
            return false
        }
        return symbol.name == interner.intern("Iterable")
            || symbol.fqName == [
                interner.intern("kotlin"),
                interner.intern("collections"),
                interner.intern("Iterable"),
            ]
    }

    private func isSequenceLikeReceiver(
        receiverID: ExprID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        let receiverType = sema.bindings.exprTypes[receiverID] ?? sema.types.anyType
        return isSequenceLikeType(receiverType, sema: sema, interner: interner)
    }

    func isSequenceLikeType(
        _ receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        let knownNames = KnownCompilerNames(interner: interner)
        guard case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(receiverType)),
              let symbol = sema.symbols.symbol(classType.classSymbol)
        else {
            return false
        }
        return knownNames.isSequenceSymbol(symbol)
    }

    func isCollectionLikeType(
        _ receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        let knownNames = KnownCompilerNames(interner: interner)
        guard case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(receiverType)),
              let symbol = sema.symbols.symbol(classType.classSymbol)
        else {
            return false
        }
        return knownNames.isCollectionLikeSymbol(symbol)
    }

    func isListLikeType(
        _ receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        let knownNames = KnownCompilerNames(interner: interner)
        guard case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(receiverType)),
              let symbol = sema.symbols.symbol(classType.classSymbol)
        else {
            return false
        }
        return knownNames.isConcreteListLikeSymbol(symbol)
    }

    private func isMapLikeCollectionReceiver(receiverID: ExprID, sema: SemaModule, interner: StringInterner) -> Bool {
        let knownNames = KnownCompilerNames(interner: interner)
        let receiverType = sema.bindings.exprTypes[receiverID] ?? sema.types.anyType
        guard case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(receiverType)),
              let symbol = sema.symbols.symbol(classType.classSymbol)
        else {
            return false
        }
        return knownNames.isMapLikeSymbol(symbol) && classType.args.count == 2
    }

    private func isMutableListCollectionReceiver(
        receiverID: ExprID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        let knownNames = KnownCompilerNames(interner: interner)
        let receiverType = sema.bindings.exprTypes[receiverID] ?? sema.types.anyType
        guard case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(receiverType)),
              let symbol = sema.symbols.symbol(classType.classSymbol)
        else {
            return false
        }
        return (
            symbol.name == knownNames.mutableList
                || symbol.fqName == knownNames.kotlinCollectionsMutableListFQName
        ) && classType.args.count == 1
    }

    private func isMutableCollectionReceiver(
        receiverID: ExprID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        let receiverType = sema.bindings.exprTypes[receiverID] ?? sema.types.anyType
        guard case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(receiverType)),
              let symbol = sema.symbols.symbol(classType.classSymbol)
        else {
            return false
        }
        return (
            symbol.name == interner.intern("MutableCollection")
                || symbol.fqName == [
                    interner.intern("kotlin"),
                    interner.intern("collections"),
                    interner.intern("MutableCollection"),
                ]
        ) && classType.args.count == 1
    }

    private func isMutableSetCollectionReceiver(
        receiverID: ExprID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        let knownNames = KnownCompilerNames(interner: interner)
        let receiverType = sema.bindings.exprTypes[receiverID] ?? sema.types.anyType
        guard case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(receiverType)),
              let symbol = sema.symbols.symbol(classType.classSymbol)
        else {
            return false
        }
        return knownNames.isMutableSetSymbol(symbol) && classType.args.count == 1
    }

    private func isMutableMapCollectionReceiver(
        receiverID: ExprID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        let knownNames = KnownCompilerNames(interner: interner)
        let receiverType = sema.bindings.exprTypes[receiverID] ?? sema.types.anyType
        guard case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(receiverType)),
              let symbol = sema.symbols.symbol(classType.classSymbol)
        else {
            return false
        }
        return knownNames.isMutableMapSymbol(symbol) && classType.args.count == 2
    }

    private func isConcreteListLikeCollectionReceiver(
        receiverID: ExprID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        let knownNames = KnownCompilerNames(interner: interner)
        let receiverType = sema.bindings.exprTypes[receiverID] ?? sema.types.anyType
        guard case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(receiverType)),
              let symbol = sema.symbols.symbol(classType.classSymbol)
        else {
            return false
        }
        return knownNames.isConcreteListLikeSymbol(symbol) && !knownNames.isMapLikeSymbol(symbol)
    }

    private func isSetLikeCollectionReceiver(
        receiverID: ExprID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        let knownNames = KnownCompilerNames(interner: interner)
        let receiverType = sema.bindings.exprTypes[receiverID] ?? sema.types.anyType
        guard case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(receiverType)),
              let symbol = sema.symbols.symbol(classType.classSymbol)
        else {
            return false
        }
        return knownNames.collectionKind(of: symbol) == .set && classType.args.count == 1
    }

    // MARK: - Array member fallback (STDLIB-087/088/089)
}

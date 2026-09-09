
/// Helpers split from `CallTypeChecker+MemberCallInference.swift`:
/// Receiver-type predicates and synthetic-builtin dispatchers (Flow, Continuation, KClass, Channel, File, Coroutine handle).
///
/// Split out to isolate merge conflicts between parallel stdlib PRs.
extension CallTypeChecker {

    /// Safe lookup for well-known stdlib symbols (List, Map, Pair, etc.).
    /// Returns `nil` if the symbol is not found. Callers should fall back to
    /// `sema.types.anyType` when the result is nil, following the error-resilient
    /// design principle (never crash on missing symbols).
    func lookupStdlibSymbol(_ name: String, symbols: SymbolTable, interner: StringInterner) -> SymbolID? {
        symbols.lookupByShortName(interner.intern(name)).first
    }

    /// Prefer Collection<T>.toList() when both source-backed collection
    /// extensions are visible for a concrete Collection receiver.
    func preferCollectionToListCandidates(
        _ candidates: [SymbolID],
        receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> [SymbolID] {
        guard let collectionSymbol = sema.symbols.lookup(fqName: [
            interner.intern("kotlin"),
            interner.intern("collections"),
            interner.intern("Collection"),
        ]),
        let iterableSymbol = sema.symbols.lookup(fqName: [
            interner.intern("kotlin"),
            interner.intern("collections"),
            interner.intern("Iterable"),
        ]),
        let receiverNominal = driver.helpers.nominalSymbol(
            of: sema.types.makeNonNullable(receiverType),
            types: sema.types
        ),
        sema.types.isNominalSubtypeSymbol(receiverNominal, of: collectionSymbol),
        candidates.contains(where: { candidate in
            guard let receiver = sema.symbols.functionSignature(for: candidate)?.receiverType,
                  let candidateNominal = driver.helpers.nominalSymbol(
                      of: sema.types.makeNonNullable(receiver),
                      types: sema.types
                  )
            else {
                return false
            }
            return candidateNominal == collectionSymbol
        })
        else {
            return candidates
        }

        return candidates.filter { candidate in
            guard let receiver = sema.symbols.functionSignature(for: candidate)?.receiverType,
                  let candidateNominal = driver.helpers.nominalSymbol(
                      of: sema.types.makeNonNullable(receiver),
                      types: sema.types
                  )
            else {
                return true
            }
            return candidateNominal != iterableSymbol
        }
    }

    /// Kotlin prefers the extension whose receiver is the most specific type
    /// when several bundled source extensions have the same name and arity.
    /// This matters for the Collection/Iterable pairs that coexist in the
    /// upstream common stdlib (for example `toMutableList` and `plus`).
    func preferMostSpecificMemberReceiverCandidates(
        _ candidates: [SymbolID],
        receiverType: TypeID,
        argumentTypes: [TypeID] = [],
        sema: SemaModule,
        interner: StringInterner
    ) -> [SymbolID] {
        guard candidates.count > 1 else { return candidates }
        let actualReceiver = sema.types.makeNonNullable(receiverType)
        let receiverTypes: [(SymbolID, TypeID)] = candidates.compactMap { candidate in
            guard let receiver = sema.symbols.functionSignature(for: candidate)?.receiverType else {
                return nil
            }
            return (candidate, sema.types.makeNonNullable(receiver))
        }
        guard receiverTypes.count == candidates.count else { return candidates }

        // Receiver specificity must not hide a viable generic extension behind
        // a more-specific receiver overload that cannot accept the arguments.
        // For example, String.contains(String) must keep the CharSequence
        // overload when the more-specific String overload is contains(Regex).
        let potentiallyApplicableCandidates: Set<SymbolID> = if argumentTypes.isEmpty {
            Set(candidates)
        } else {
            Set(candidates.filter { candidate in
                guard let signature = sema.symbols.functionSignature(for: candidate) else {
                    return false
                }
                guard argumentTypes.count <= signature.parameterTypes.count
                    || signature.valueParameterIsVararg.contains(true)
                else {
                    return false
                }
                let parameterCount = signature.parameterTypes.count
                func normalizedFlags(_ flags: [Bool]) -> [Bool] {
                    if flags.count == parameterCount {
                        return flags
                    }
                    if flags.count > parameterCount {
                        return Array(flags.prefix(parameterCount))
                    }
                    return flags + Array(repeating: false, count: parameterCount - flags.count)
                }
                let hasDefaultValues = normalizedFlags(signature.valueParameterHasDefaultValues)
                let isVararg = normalizedFlags(signature.valueParameterIsVararg)
                if argumentTypes.count < parameterCount {
                    let omittedParameterIndices = argumentTypes.count ..< parameterCount
                    guard omittedParameterIndices.allSatisfy({
                        hasDefaultValues[$0] || isVararg[$0]
                    }) else {
                        return false
                    }
                }
                for (index, argumentType) in argumentTypes.enumerated() {
                    let parameterIndex: Int
                    if index < signature.parameterTypes.count {
                        parameterIndex = index
                    } else if let varargIndex = isVararg.firstIndex(of: true) {
                        parameterIndex = varargIndex
                    } else {
                        return false
                    }
                    let parameterType = signature.parameterTypes[parameterIndex]
                    let actual = sema.types.makeNonNullable(argumentType)
                    let expected = sema.types.makeNonNullable(parameterType)
                    if actual == sema.types.errorType
                        || expected == sema.types.errorType
                        || actual == sema.types.anyType
                        || expected == sema.types.anyType
                    {
                        continue
                    }
                    if case .typeParam = sema.types.kind(of: actual) {
                        continue
                    }
                    if case .typeParam = sema.types.kind(of: expected) {
                        continue
                    }
                    guard sema.types.isSubtype(actual, expected) else {
                        return false
                    }
                }
                return true
            })
        }
        let specificityCandidates = potentiallyApplicableCandidates.isEmpty
            ? Set(candidates)
            : potentiallyApplicableCandidates

        let collectionFQName = [
            interner.intern("kotlin"),
            interner.intern("collections"),
            interner.intern("Collection"),
        ]
        let iterableFQName = [
            interner.intern("kotlin"),
            interner.intern("collections"),
            interner.intern("Iterable"),
        ]
        var remainingCandidates = candidates
        let hasCollectionReceiver = receiverTypes.contains { _, receiver in
            driver.helpers.nominalSymbol(of: receiver, types: sema.types)
                .flatMap { sema.symbols.symbol($0)?.fqName } == collectionFQName
        }
        if hasCollectionReceiver,
           let actualNominal = driver.helpers.nominalSymbol(of: actualReceiver, types: sema.types),
           sema.types.isNominalSubtypeSymbol(
               actualNominal,
               of: sema.symbols.lookup(fqName: collectionFQName) ?? actualNominal
           )
        {
            let filtered = remainingCandidates.filter { candidate in
                guard let receiver = sema.symbols.functionSignature(for: candidate)?.receiverType,
                      let nominal = driver.helpers.nominalSymbol(of: receiver, types: sema.types),
                      let symbol = sema.symbols.symbol(nominal)
                else {
                    return true
                }
                return symbol.fqName != iterableFQName
            }
            if !filtered.isEmpty { remainingCandidates = filtered }
        }

        let actualNominal = driver.helpers.nominalSymbol(of: actualReceiver, types: sema.types)
        let lessSpecific = Set(receiverTypes.compactMap { candidate, candidateReceiver -> SymbolID? in
            guard remainingCandidates.contains(candidate), specificityCandidates.contains(candidate) else { return nil }
            let candidateNominal = driver.helpers.nominalSymbol(of: candidateReceiver, types: sema.types)
            let hasMoreSpecific = receiverTypes.contains { other, otherReceiver in
                guard remainingCandidates.contains(other), specificityCandidates.contains(other), candidate != other else { return false }
                let nominallyMoreSpecific: Bool = if let actualNominal,
                                                     let candidateNominal,
                                                     let otherNominal = driver.helpers.nominalSymbol(of: otherReceiver, types: sema.types)
                {
                    actualNominal != candidateNominal
                        && candidateNominal != otherNominal
                        && sema.types.isNominalSubtypeSymbol(actualNominal, of: otherNominal)
                        && sema.types.isNominalSubtypeSymbol(otherNominal, of: candidateNominal)
                } else {
                    false
                }
                if nominallyMoreSpecific { return true }
                guard candidate != other,
                      sema.types.isSubtype(actualReceiver, otherReceiver),
                      sema.types.isSubtype(otherReceiver, candidateReceiver)
                else {
                    return false
                }
                return !sema.types.isSubtype(candidateReceiver, otherReceiver)
            }
            return hasMoreSpecific ? candidate : nil
        })
        let filtered = remainingCandidates.filter { !lessSpecific.contains($0) }
        return filtered.isEmpty ? candidates : filtered
    }

    /// Prefer a source-backed List.unzip() over the generic Iterable.unzip()
    /// when the concrete receiver is a List. Both extensions have the same
    /// callable name and type shape after inference, so receiver nominality
    /// must decide the overload before the regular resolver sees them.
    func preferListUnzipCandidates(
        _ candidates: [SymbolID],
        receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> [SymbolID] {
        guard let listSymbol = sema.symbols.lookup(fqName: [
            interner.intern("kotlin"),
            interner.intern("collections"),
            interner.intern("List"),
        ]),
        let iterableSymbol = sema.symbols.lookup(fqName: [
            interner.intern("kotlin"),
            interner.intern("collections"),
            interner.intern("Iterable"),
        ]),
        let receiverNominal = driver.helpers.nominalSymbol(
            of: sema.types.makeNonNullable(receiverType),
            types: sema.types
        ),
        sema.types.isNominalSubtypeSymbol(receiverNominal, of: listSymbol),
        candidates.contains(where: { candidate in
            guard sema.symbols.isSourceBackedSymbol(candidate),
                  let receiver = sema.symbols.functionSignature(for: candidate)?.receiverType,
                  let candidateNominal = driver.helpers.nominalSymbol(
                      of: sema.types.makeNonNullable(receiver),
                      types: sema.types
                  )
            else {
                return false
            }
            return candidateNominal == listSymbol
        })
        else {
            return candidates
        }

        return candidates.filter { candidate in
            guard let receiver = sema.symbols.functionSignature(for: candidate)?.receiverType,
                  let candidateNominal = driver.helpers.nominalSymbol(
                      of: sema.types.makeNonNullable(receiver),
                      types: sema.types
                  )
            else {
                return true
            }
            return candidateNominal != iterableSymbol
        }
    }

    /// Prefer the source-backed List.take overload when a concrete List receiver
    /// also exposes the generic Iterable.take extension.
    ///
    /// The regular resolver cannot rank these two extension receivers because
    /// their value parameter lists are identical. Keep this preference narrowly
    /// tied to the exact List receiver and source-backed declaration so generic
    /// Iterable and other receiver families retain their normal overload sets.
    func preferListTakeCandidates(
        _ candidates: [SymbolID],
        receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> [SymbolID] {
        let listFQName = [
            interner.intern("kotlin"),
            interner.intern("collections"),
            interner.intern("List"),
        ]
        guard let listSymbol = sema.symbols.lookup(fqName: listFQName),
              let receiverNominal = driver.helpers.nominalSymbol(
                  of: sema.types.makeNonNullable(receiverType),
                  types: sema.types
              ),
              sema.types.isNominalSubtypeSymbol(receiverNominal, of: listSymbol)
        else {
            return candidates
        }

        let listTakeCandidates = candidates.filter { candidate in
            guard sema.symbols.isSourceBackedSymbol(candidate),
                  let receiver = sema.symbols.functionSignature(for: candidate)?.receiverType,
                  let candidateNominal = driver.helpers.nominalSymbol(
                      of: sema.types.makeNonNullable(receiver),
                      types: sema.types
                  )
            else {
                return false
            }
            return candidateNominal == listSymbol
        }
        return listTakeCandidates.isEmpty ? candidates : listTakeCandidates
    }

    /// Receiver check for the scope fallback that restores synthetic extensions excluded from import scopes.
    /// Aligns with `Helpers.collectMemberFunctionCandidates`: require `actual <: declared` when possible,
    /// but keep generics such as `Continuation<T>.intercepted` where `isSubtype(Continuation<Int>, Continuation<T>)`
    /// is not decided until inference (mirrors the `rangeUntil`/`genericReceiver` escape hatch there).
    func extensionSyntheticFallbackReceiverMatches(
        callSiteReceiver: TypeID,
        declaredReceiver: TypeID,
        sema: SemaModule
    ) -> Bool {
        let actual = sema.types.makeNonNullable(callSiteReceiver)
        let declared = sema.types.makeNonNullable(declaredReceiver)
        if sema.types.isSubtype(actual, declared) {
            return true
        }
        // A type parameter's upper bound is the receiver contract at the call
        // site. `T : Comparable<T>` therefore matches the source-backed
        // `Comparable<T>.compareTo` receiver even when the subtype checker
        // cannot materialize the F-bounded type parameter as a nominal type.
        if case let .typeParam(actualParam) = sema.types.kind(of: actual),
           sema.symbols.typeParameterUpperBounds(for: actualParam.symbol).contains(where: {
               sema.types.isSubtype($0, declared)
           })
        {
            return true
        }
        if case let .typeParam(actualParam) = sema.types.kind(of: actual),
           case let .classType(declaredClass) = sema.types.kind(of: declared),
           sema.symbols.typeParameterUpperBounds(for: actualParam.symbol).contains(where: { bound in
               guard case let .classType(boundClass) = sema.types.kind(of: sema.types.makeNonNullable(bound)) else {
                   return false
               }
               return boundClass.classSymbol == declaredClass.classSymbol
           })
        {
            // The type arguments of an F-bounded upper bound and a generic
            // member receiver may use different declaration-local type
            // parameter IDs; overload resolution will solve those arguments.
            return true
        }
        if case .typeParam = sema.types.kind(of: declared) {
            return true
        }
        func typeArgumentLikeMatch(actual: TypeID?, declared: TypeID?) -> Bool {
            switch (actual, declared) {
            case let (actual?, declared?):
                let actualNonNull = sema.types.makeNonNullable(actual)
                let declaredNonNull = sema.types.makeNonNullable(declared)
                if sema.types.isSubtype(actualNonNull, declaredNonNull) {
                    return true
                }
                if case .typeParam = sema.types.kind(of: declaredNonNull) {
                    return true
                }
                return false
            case (nil, nil):
                return true
            default:
                return false
            }
        }
        // Recursively checks whether a type, or any of its nested type arguments, is a type parameter.
        // Required for declared receivers like Array<CPointer<T>?> where the type param is one level deep.
        func containsTypeParam(_ t: TypeID) -> Bool {
            let nonNull = sema.types.makeNonNullable(t)
            if case .typeParam = sema.types.kind(of: nonNull) { return true }
            if case let .classType(ct) = sema.types.kind(of: nonNull) {
                return ct.args.contains(where: { arg in
                    switch arg {
                    case let .invariant(inner), let .out(inner), let .in(inner):
                        return containsTypeParam(inner)
                    case .star:
                        return false
                    }
                })
            }
            return false
        }
        if case let .functionType(declaredFn) = sema.types.kind(of: declared),
           case let .functionType(actualFn) = sema.types.kind(of: actual),
           declaredFn.isSuspend == actualFn.isSuspend,
           declaredFn.params.count == actualFn.params.count,
           typeArgumentLikeMatch(actual: actualFn.receiver, declared: declaredFn.receiver),
           zip(actualFn.params, declaredFn.params).allSatisfy({ actualParam, declaredParam in
               typeArgumentLikeMatch(actual: actualParam, declared: declaredParam)
           }),
           typeArgumentLikeMatch(actual: actualFn.returnType, declared: declaredFn.returnType)
        {
            return true
        }
        if case let .classType(declaredCt) = sema.types.kind(of: declared),
           case let .kClassType(actualKClass) = sema.types.kind(of: actual),
           declaredCt.classSymbol == sema.types.kClassInterfaceSymbol,
           declaredCt.args.contains(where: { arg in
               switch arg {
               case let .invariant(t), let .out(t):
                   return typeArgumentLikeMatch(actual: actualKClass.argument, declared: t)
               case .in:
                   return true
               case .star:
                   return true
               }
           })
        {
            return true
        }
        if case let .classType(declaredCt) = sema.types.kind(of: declared),
           case let .classType(actualCt) = sema.types.kind(of: actual),
           actualCt.classSymbol != declaredCt.classSymbol,
           sema.types.isNominalSubtypeSymbol(actualCt.classSymbol, of: declaredCt.classSymbol),
           declaredCt.args.contains(where: { arg in
               switch arg {
               case let .invariant(t), let .out(t), let .in(t):
                   return containsTypeParam(t)
               case .star:
                   return false
               }
           })
        {
            return true
        }
        if case let .classType(declaredCt) = sema.types.kind(of: declared),
           case let .classType(actualCt) = sema.types.kind(of: actual),
           actualCt.classSymbol == declaredCt.classSymbol,
           declaredCt.args.contains(where: { arg in
               switch arg {
               case let .invariant(t), let .out(t), let .in(t):
                   return containsTypeParam(t)
               case .star:
                   return false
               }
           })
        {
            return true
        }
        if case let .kClassType(declaredKClass) = sema.types.kind(of: declared),
           case let .kClassType(actualKClass) = sema.types.kind(of: actual)
        {
            return typeArgumentLikeMatch(actual: actualKClass.argument, declared: declaredKClass.argument)
        }
        return false
    }

    func tryBuiltinFlowMemberCall(
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
        let flowMembers: Set = [
            "map", "filter", "take", "collect", "collectLatest", "toList", "first",
            "single",
            "transform", "takeWhile", "dropWhile", "flatMapConcat", "flatMapMerge", "flatMapLatest",
            "buffer", "conflate", "flowOn", "debounce", "sample", "delayEach",
            "catch", "retry", "retryWhen", "onErrorReturn", "onErrorResume",
        ]
        guard flowMembers.contains(memberName) else {
            return nil
        }

        switch memberName {
        case "toList":
            // Flow.toList() — collects all emitted values into a List
            guard args.isEmpty else {
                return nil
            }
            let listSymbol = sema.symbols.lookupByShortName(ctx.interner.intern("List")).first
            let resultType: TypeID = if let listSymbol {
                sema.types.make(.classType(ClassType(
                    classSymbol: listSymbol,
                    args: [.invariant(receiverElementType)],
                    nullability: .nonNull
                )))
            } else {
                sema.types.anyType
            }
            let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
            sema.bindings.bindExprType(id, type: finalType)
            return finalType

        case "first":
            // Flow.first() — returns the first emitted value
            guard args.isEmpty else {
                return nil
            }
            let firstType = receiverElementType
            let finalType = safeCall ? sema.types.makeNullable(firstType) : firstType
            sema.bindings.bindExprType(id, type: finalType)
            return finalType

        case "single":
            // Flow.single() — returns the only emitted value.
            guard args.isEmpty else {
                return nil
            }
            let singleType = receiverElementType
            let finalType = safeCall ? sema.types.makeNullable(singleType) : singleType
            sema.bindings.bindExprType(id, type: finalType)
            return finalType

        case "take", "buffer", "debounce", "sample", "delayEach", "flowOn":
            guard args.count == 1 else {
                return nil
            }
            let expectedArgType: TypeID = memberName == "flowOn" ? sema.types.anyType : sema.types.intType
            _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: expectedArgType)
            sema.bindings.markFlowExpr(id)
            sema.bindings.bindFlowElementType(receiverElementType, forExpr: id)
            let flowType = driver.helpers.makeFlowType(
                elementType: receiverElementType, sema: sema, interner: ctx.interner
            ) ?? sema.types.anyType
            let resultType = safeCall ? sema.types.makeNullable(flowType) : flowType
            sema.bindings.bindExprType(id, type: resultType)
            return resultType

        case "conflate":
            guard args.isEmpty else {
                return nil
            }
            sema.bindings.markFlowExpr(id)
            sema.bindings.bindFlowElementType(receiverElementType, forExpr: id)
            let flowType = driver.helpers.makeFlowType(
                elementType: receiverElementType, sema: sema, interner: ctx.interner
            ) ?? sema.types.anyType
            let resultType = safeCall ? sema.types.makeNullable(flowType) : flowType
            sema.bindings.bindExprType(id, type: resultType)
            return resultType

        case "retry":
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
            let flowType = driver.helpers.makeFlowType(
                elementType: receiverElementType, sema: sema, interner: ctx.interner
            ) ?? sema.types.anyType
            let resultType = safeCall ? sema.types.makeNullable(flowType) : flowType
            sema.bindings.bindExprType(id, type: resultType)
            return resultType

        case "map", "filter", "collect", "collectLatest", "transform", "takeWhile", "dropWhile",
             "flatMapConcat", "flatMapMerge", "flatMapLatest",
             "catch", "retryWhen", "onErrorReturn", "onErrorResume":
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
            case "collect", "collectLatest":
                sema.types.unitType
            case "transform":
                // Flow.transform emits values through its collector receiver;
                // the callback itself returns Unit. The lightweight Flow
                // special case has no receiver-type inference for those
                // emissions, so keep its output type conservatively erased.
                sema.types.unitType
            case "takeWhile", "dropWhile":
                sema.types.unitType
            case "catch":
                sema.types.unitType
            case "retryWhen":
                sema.types.booleanType
            default:
                sema.types.anyType
            }
            let lambdaParameterTypes: [TypeID] = switch memberName {
            case "catch", "onErrorResume":
                [sema.types.anyType]
            case "retryWhen":
                [sema.types.anyType, sema.types.longType]
            default:
                [receiverElementType]
            }
            let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                params: lambdaParameterTypes,
                returnType: lambdaReturnType,
                isSuspend: memberName == "collect" || memberName == "collectLatest",
                nullability: .nonNull
            )))
            if expectsLambdaTypeConstraint {
                _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
            } else {
                _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals)
            }

            if memberName != "collect" && memberName != "collectLatest" {
                sema.bindings.markFlowExpr(id)
                let resultElementType: TypeID = if memberName == "map",
                                                   case let .lambdaLiteral(_, bodyExpr, _, _) = ast.arena.expr(args[0].expr),
                                                   let mappedType = sema.bindings.exprType(for: bodyExpr)
                {
                    mappedType
                } else if memberName == "transform" {
                    // The callback's Unit result is not a Flow element. Values
                    // emitted by the transform are represented by the runtime
                    // bridge and remain type-erased until a richer collector
                    // receiver model is available.
                    sema.types.anyType
                } else if memberName == "flatMapConcat" || memberName == "flatMapMerge" || memberName == "flatMapLatest" {
                    sema.types.anyType
                } else {
                    receiverElementType
                }
                sema.bindings.bindFlowElementType(resultElementType, forExpr: id)
            }

            let resultType: TypeID
            if memberName == "collect" || memberName == "collectLatest" {
                resultType = sema.types.unitType
            } else {
                let resultElement = sema.bindings.flowElementType(forExpr: id) ?? receiverElementType
                resultType = driver.helpers.makeFlowType(
                    elementType: resultElement, sema: sema, interner: ctx.interner
                ) ?? sema.types.anyType
            }
            let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
            sema.bindings.bindExprType(id, type: finalType)
            return finalType

        default:
            return nil
        }
    }

    func tryContinuationSyntheticMemberCall(
        _ id: ExprID,
        calleeName: InternedString,
        receiverType: TypeID,
        args: [CallArgument],
        range: SourceRange,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) -> TypeID? {
        let knownNames = KnownCompilerNames(interner: ctx.interner)
        guard calleeName == knownNames.resume || calleeName == knownNames.resumeWith || calleeName == knownNames.resumeWithException else {
            return nil
        }
        guard let continuationSymbol = ctx.sema.symbols.lookup(fqName: knownNames.kotlinContinuationFQName),
              let (_, receiverSymbol) = resolveClassTypeSymbol(receiverType, sema: ctx.sema),
              receiverSymbol.id == continuationSymbol
        else {
            return nil
        }
        guard args.count == 1 else {
            ctx.semaCtx.diagnostics.error(
                "KSWIFTK-SEMA-0024",
                "No viable overload found for call.",
                range: range
            )
            return driver.helpers.bindAndReturnErrorType(id, sema: ctx.sema)
        }

        var expectedArgType: TypeID = ctx.sema.types.anyType
        if calleeName == knownNames.resume,
           let classType = resolveClassType(receiverType, sema: ctx.sema),
           let continuationArg = classType.args.first
        {
            switch continuationArg {
            case let .invariant(type), let .out(type), let .in(type):
                expectedArgType = type
            case .star:
                expectedArgType = ctx.sema.types.anyType
            }
        } else if calleeName == knownNames.resumeWith,
                  let classType = resolveClassType(receiverType, sema: ctx.sema),
                  let continuationArg = classType.args.first,
                  let resultSymbol = ctx.sema.symbols.lookup(fqName: [ctx.interner.intern("kotlin"), ctx.interner.intern("Result")])
        {
            let innerType: TypeID
            switch continuationArg {
            case let .invariant(type), let .out(type), let .in(type):
                innerType = type
            case .star:
                innerType = ctx.sema.types.anyType
            }
            expectedArgType = ctx.sema.types.make(.classType(ClassType(
                classSymbol: resultSymbol,
                args: [.out(innerType)],
                nullability: .nonNull
            )))
        }

        _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: expectedArgType)

        let expectedExternalLinkName = if calleeName == knownNames.resume {
            "kk_coroutine_continuation_resume"
        } else if calleeName == knownNames.resumeWith {
            "kk_coroutine_continuation_resume_with"
        } else {
            "kk_coroutine_continuation_resume_with_exception"
        }
        let functionSymbol = ctx.sema.symbols.lookupByShortName(calleeName).first(where: { candidate in
            guard let symbol = ctx.sema.symbols.symbol(candidate),
                  symbol.kind == .function
            else {
                return false
            }
            return ctx.sema.symbols.externalLinkName(for: candidate) == expectedExternalLinkName
        })
        if let functionSymbol {
            ctx.sema.bindings.bindCall(id, binding: CallBinding(
                chosenCallee: functionSymbol,
                substitutedTypeArguments: [],
                parameterMapping: [0: 0]
            ))
            ctx.sema.bindings.bindIdentifier(id, symbol: functionSymbol)
            ctx.sema.bindings.bindExprType(id, type: ctx.sema.types.unitType)
            return ctx.sema.types.unitType
        }
        return nil
    }

    func isCoroutineHandleReceiverType(
        _ receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        let knownNames = KnownCompilerNames(interner: interner)
        guard let (_, symbol) = resolveClassTypeSymbol(receiverType, sema: sema) else {
            return false
        }
        return knownNames.isCoroutineHandleSymbol(symbol)
    }

    /// Returns true when the receiver type is java.io.File.
    func isFileType(
        _ receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        let nonNullType = sema.types.makeNonNullable(receiverType)
        guard let (_, symbol) = resolveClassTypeSymbol(nonNullType, sema: sema) else {
            return false
        }
        return symbol.fqName.count >= 2
            && interner.resolve(symbol.fqName.last!) == "File"
            && interner.resolve(symbol.fqName[symbol.fqName.count - 2]) == "io"
    }

    /// Returns true when the receiver type is java.io.BufferedReader.
    /// Used by Reader-targeted special-case lambda inference (STDLIB-IO-FN-040)
    /// where the `useLines` extension on `kotlin.io.Reader` resolves to the
    /// synthetic `BufferedReader.useLines` stub registered by
    /// `registerSyntheticFileIOStubs`.
    func isBufferedReaderType(
        _ receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        let nonNullType = sema.types.makeNonNullable(receiverType)
        guard let (_, symbol) = resolveClassTypeSymbol(nonNullType, sema: sema) else {
            return false
        }
        return symbol.fqName.count >= 2
            && interner.resolve(symbol.fqName.last!) == "BufferedReader"
            && interner.resolve(symbol.fqName[symbol.fqName.count - 2]) == "io"
    }

    func isChannelReceiverType(
        _ receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        let knownNames = KnownCompilerNames(interner: interner)
        guard let (_, symbol) = resolveClassTypeSymbol(receiverType, sema: sema) else {
            return false
        }
        return knownNames.isChannelSymbol(symbol)
    }

    func kClassReceiverArgumentType(
        _ receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> TypeID? {
        let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
        if case let .kClassType(kClassType) = sema.types.kind(of: nonNullReceiverType) {
            return kClassType.argument
        }

        guard let (classType, symbol) = resolveClassTypeSymbol(nonNullReceiverType, sema: sema) else {
            return nil
        }

        let kotlinReflectKClassFQName = [
            interner.intern("kotlin"),
            interner.intern("reflect"),
            interner.intern("KClass"),
        ]
        let kClassName = interner.intern("KClass")
        let isKClassSymbol = symbol.fqName == kotlinReflectKClassFQName
            || (symbol.name == kClassName && symbol.fqName.isEmpty)
        guard isKClassSymbol else {
            return nil
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

    /// Handles numeric companion access on a type-name receiver:
    ///
    ///   - **Constants** (STDLIB-153): `Int.MAX_VALUE`, `Double.NaN`, `Float.POSITIVE_INFINITY`, etc.
    ///     when `args.isEmpty` — looked up via `numericCompanionConstant`.
    /// Returns the inferred type when handled, or `nil` to fall through. Both
    /// branches require the receiver to be a `nameRef` (typed identifier) that
    /// is not currently bound as a local — an Int *value* named `Int` shadows
    /// the type and falls through.
    func tryInferNumericCompanionMemberCall(
        _ id: ExprID,
        receiverID: ExprID,
        calleeName: InternedString,
        args: [CallArgument],
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) -> TypeID? {
        let ast = ctx.ast
        let sema = ctx.sema
        let interner = ctx.interner

        guard case let .nameRef(receiverName, _) = ast.arena.expr(receiverID),
              locals[receiverName] == nil
        else {
            return nil
        }

        let receiverStr = interner.resolve(receiverName)
        let memberStr = interner.resolve(calleeName)

        // STDLIB-153: Numeric companion constants — Int.MAX_VALUE, Double.NaN, etc.
        if args.isEmpty,
           let (constantType, constantValue) = numericCompanionConstant(
               typeName: receiverStr, memberName: memberStr, sema: sema
           )
        {
            sema.bindings.bindConstExprValue(id, value: constantValue)
            sema.bindings.bindExprType(id, type: constantType)
            return constantType
        }

        // Primitive companion functions are represented as source-backed
        // top-level functions until primitive Companion types are modeled.
        // Select a matching overload by its signature rather than by a
        // function-name or runtime-link special case.
        guard memberStr == "fromBits",
              args.count == 1,
              let receiverType = driver.helpers.resolveBuiltinTypeName(
                  receiverName, types: sema.types, interner: interner
              )
        else {
            return nil
        }
        let resultType: TypeID? = if receiverType == sema.types.doubleType {
            sema.types.doubleType
        } else if receiverType == sema.types.floatType {
            sema.types.floatType
        } else {
            nil
        }
        guard let resultType else {
            return nil
        }

        // Unsuffixed integer literals widen to the parameter type only when
        // the expression is inferred with an expected type. Numeric companion
        // fromBits overloads take Long for Double and Int for Float.
        let expectedArgumentType = receiverType == sema.types.doubleType
            ? sema.types.longType
            : sema.types.intType
        let argumentTypes = args.map { argument in
            driver.inferExpr(
                argument.expr,
                ctx: ctx,
                locals: &locals,
                expectedType: expectedArgumentType
            )
        }
        let sourceFQName = [interner.intern("kotlin"), calleeName]
        guard let chosenCallee = sema.symbols.lookupAll(fqName: sourceFQName).first(where: { candidate in
            guard let symbol = sema.symbols.symbol(candidate),
                  symbol.kind == .function,
                  sema.symbols.isSourceBackedSymbol(candidate),
                  let signature = sema.symbols.functionSignature(for: candidate),
                  signature.receiverType == nil,
                  signature.returnType == resultType,
                  signature.parameterTypes.count == argumentTypes.count
            else {
                return false
            }
            return zip(signature.parameterTypes, argumentTypes).allSatisfy { parameterType, argumentType in
                argumentType == parameterType || sema.types.isSubtype(argumentType, parameterType)
            }
        }) else {
            return nil
        }

        sema.bindings.bindIdentifier(id, symbol: chosenCallee)
        sema.bindings.bindCall(
            id,
            binding: CallBinding(
                chosenCallee: chosenCallee,
                substitutedTypeArguments: [],
                parameterMapping: [0: 0]
            )
        )
        sema.bindings.bindCallableTarget(id, target: .symbol(chosenCallee))
        sema.bindings.bindExprType(id, type: resultType)
        // Lowering must not pass the type-name receiver as a runtime value.
        sema.bindings.bindExprType(receiverID, type: sema.types.unitType)
        return resultType
    }

    /// This legacy inference path still owns many special cases while the split-out helpers
    /// are being migrated.
}

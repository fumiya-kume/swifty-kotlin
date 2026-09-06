import Foundation

/// Helpers split from `CallTypeChecker+MemberCallInference.swift`:
/// Synthetic-stdlib bind/try fallbacks (String, Duration, Map, ThreadLocal, ReadWriteLock, Comparator, Result, KClass associatedObject) plus collection / numeric / closeable / locale type-extractor helpers used from within `inferMemberCallImpl`.
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
        guard let (classType, symbol) = resolveClassTypeSymbol(nonNullType, sema: sema) else {
            return sema.types.anyType
        }

        if knownNames.isMapLikeSymbol(symbol),
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
        guard let (classType, symbol) = resolveClassTypeSymbol(type, sema: sema),
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
        guard let (classType, symbol) = resolveClassTypeSymbol(type, sema: sema),
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
        case .classType:
            guard let (classType, symbol) = resolveClassTypeSymbol(nonNullType, sema: sema),
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
        case .call:
            return directElementType
        default:
            return directElementType
        }
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

    // MARK: - Numeric companion constants (STDLIB-153)

    func numericCompanionConstant(
        typeName: String,
        memberName: String,
        sema: SemaModule
    ) -> (TypeID, KIRExprKind)? {
        let types = sema.types
        switch (typeName, memberName) {
        // Byte
        case ("Byte", "MAX_VALUE"): return (types.intType, .intLiteral(Int64(Int8.max)))
        case ("Byte", "MIN_VALUE"): return (types.intType, .intLiteral(Int64(Int8.min)))
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

    /// Returns true if `receiverType` conforms to AutoCloseable,
    /// so that `.use {}` is only treated as a scope function on closeable receivers.
    /// Note: `kotlin.io.Closeable` now extends `kotlin.AutoCloseable` (see the
    /// source-backed closeable cache and Stdlib/kotlin/AutoCloseable.kt),
    /// so checking AutoCloseable covers both Closeable and AutoCloseable receivers.
    ///
    /// As a fallback for synthetic IO types (BufferedReader, BufferedWriter, InputStream,
    /// OutputStream) that implement Closeable through the nominal supertype chain registered
    /// by registerSyntheticFileIOStubs, we also accept any class type whose class symbol
    /// has a `close()` member function registered with no parameters — this ensures that
    /// `file.bufferedReader().use { }` and similar patterns resolve correctly.
    func isCloseableReceiver(_ receiverType: TypeID, sema: SemaModule) -> Bool {
        guard let autoCloseableType = sema.types.closeableTypeID else {
            return false
        }
        let nonNullReceiver = sema.types.makeNonNullable(receiverType)
        if sema.types.isSubtype(nonNullReceiver, autoCloseableType) {
            return true
        }
        // STDLIB-030-BUG-01: When the receiver is a type parameter (e.g. `T` in
        // `fun <T : AutoCloseable> useIt(t: T)`), the general isSubtype now traverses
        // upper bounds (see Subtyping.swift). As an explicit fallback, also check directly:
        // if any registered upper bound of T is a subtype of AutoCloseable, accept it.
        if case let .typeParam(typeParam) = sema.types.kind(of: nonNullReceiver) {
            let upperBounds = sema.symbols.typeParameterUpperBounds(for: typeParam.symbol)
            for bound in upperBounds {
                let nonNullBound = sema.types.makeNonNullable(bound)
                if sema.types.isSubtype(nonNullBound, autoCloseableType) {
                    return true
                }
            }
        }
        // Fallback: check if the class explicitly declares AutoCloseable or Closeable
        // in its registered supertype list.  This handles synthetic IO types
        // (BufferedReader, BufferedWriter, InputStream, OutputStream) whose supertypes
        // are registered via registerSyntheticFileIOStubs / setDirectSupertypes, without
        // accidentally treating every class that happens to define close() as closeable.
        let closeableSymbols: [SymbolID] = [
            sema.types.closeableInterfaceSymbol,
            sema.types.ioCloseableInterfaceSymbol
        ].compactMap { $0 }
        guard !closeableSymbols.isEmpty,
              case let .classType(classType) = sema.types.kind(of: nonNullReceiver)
        else {
            return false
        }
        let directSupertypes = sema.symbols.directSupertypes(for: classType.classSymbol)
        return closeableSymbols.contains(where: { directSupertypes.contains($0) })
    }

    /// Extracts the native struct type T from a `CValue<T>` receiver.
    func extractCValueCStructContentType(
        _ receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> TypeID? {
        guard let classType = resolveClassType(receiverType, sema: sema),
              let cValueSymbol = sema.symbols.lookup(fqName: [
                  interner.intern("kotlinx"),
                  interner.intern("cinterop"),
                  interner.intern("CValue"),
              ]),
              let cStructVarSymbol = sema.symbols.lookup(fqName: [
                  interner.intern("kotlinx"),
                  interner.intern("cinterop"),
                  interner.intern("CStructVar"),
              ]),
              classType.classSymbol == cValueSymbol,
              let firstArg = classType.args.first
        else {
            return nil
        }
        let contentType: TypeID = switch firstArg {
        case let .invariant(type), let .out(type), let .in(type):
            sema.types.makeNonNullable(type)
        case .star:
            sema.types.anyType
        }
        let cStructVarType = sema.types.make(.classType(ClassType(
            classSymbol: cStructVarSymbol,
            args: [],
            nullability: .nonNull
        )))
        guard sema.types.isSubtype(contentType, cStructVarType) else {
            return nil
        }
        return contentType
    }

    /// Extract the element type T from a Result<T> receiver type.
    func extractResultElementType(
        _ receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> TypeID? {
        let knownNames = KnownCompilerNames(interner: interner)
        guard let (classType, symbol) = resolveClassTypeSymbol(receiverType, sema: sema),
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

    /// Look up a source-backed or synthetic Result member function by name.
    func lookupResultMember(
        _ name: String,
        sema: SemaModule,
        interner: StringInterner
    ) -> SymbolID? {
        let knownNames = KnownCompilerNames(interner: interner)
        let memberFQName = knownNames.kotlinResultFQName + [interner.intern(name)]
        let candidates = sema.symbols.lookupAll(fqName: memberFQName).filter { symbolID in
            guard let sym = sema.symbols.symbol(symbolID) else { return false }
            return sym.kind == .function
        }
        return candidates.first { symbolID in
            !(sema.symbols.symbol(symbolID)?.flags.contains(.synthetic) ?? false)
        } ?? candidates.first
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
            args: [.invariant(elementType)],
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
              let receiverClassType = resolveClassType(receiverType, sema: sema),
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
        func comparisonsExtension(parameterCount: Int) -> SymbolID? {
            let fqName = [
                interner.intern("kotlin"),
                interner.intern("comparisons"),
                calleeName,
            ]
            return sema.symbols.lookupAll(fqName: fqName).first(where: { candidate in
                guard let signature = sema.symbols.functionSignature(for: candidate),
                      signature.parameterTypes.count == parameterCount,
                      let receiver = signature.receiverType,
                      resolvedComparatorElementType(of: receiver, sema: sema, interner: interner) != nil
                else {
                    return false
                }
                return true
            })
        }

        if args.count == 1,
           ["then", "thenDescending"].contains(calleeStr),
           let argumentExpr = ctx.ast.arena.expr(args[0].expr),
           !argumentExpr.isLambdaOrCallableRef
        {
            let argumentType = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals)
            let comparatorFQName = [
                interner.intern("kotlin"),
                interner.intern("Comparator"),
            ]
            guard let comparatorSymbol = sema.symbols.lookup(fqName: comparatorFQName) else {
                return nil
            }
            let expectedComparatorType = sema.types.make(.classType(ClassType(
                classSymbol: comparatorSymbol,
                // Comparator is declaration-site contravariant, so its
                // invariant instantiation already accepts Comparator<in T>
                // arguments without double-applying the `in` projection.
                args: [.invariant(comparatorElementType)],
                nullability: .nonNull
            )))
            guard sema.types.isSubtype(argumentType, expectedComparatorType) else {
                return nil
            }

            let fqName = [
                interner.intern("kotlin"),
                interner.intern("comparisons"),
                calleeName,
            ]
            guard let chosen = sema.symbols.lookupAll(fqName: fqName).first(where: { candidate in
                guard let signature = sema.symbols.functionSignature(for: candidate),
                      signature.parameterTypes.count == 1,
                      let parameterType = signature.parameterTypes.first,
                      resolvedComparatorElementType(
                          of: parameterType,
                          sema: sema,
                          interner: interner
                      ) != nil,
                      let receiver = signature.receiverType,
                      resolvedComparatorElementType(of: receiver, sema: sema, interner: interner) != nil
                else {
                    return false
                }
                return true
            }) else {
                return nil
            }

            sema.bindings.bindCall(
                id,
                binding: CallBinding(
                    chosenCallee: chosen,
                    substitutedTypeArguments: [comparatorElementType],
                    parameterMapping: [0: 0]
                )
            )
            sema.bindings.bindCallableTarget(id, target: .symbol(chosen))

            let resultType = sema.types.makeNonNullable(receiverType)
            let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
            sema.bindings.bindExprType(id, type: finalType)
            return finalType
        }

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

            guard let chosen = comparisonsExtension(parameterCount: 2) else {
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

        if args.count == 0, calleeStr == "reversed" {
            guard let chosen = comparisonsExtension(parameterCount: 0) else {
                return nil
            }

            sema.bindings.bindCall(
                id,
                binding: CallBinding(
                    chosenCallee: chosen,
                    substitutedTypeArguments: [],
                    parameterMapping: [:]
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

        guard let chosen = comparisonsExtension(parameterCount: 1) else {
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

    /// STDLIB-REFLECT-065: `KClass<*>.findAnnotation<T>()`. This is a reified
    /// intrinsic with no value parameters — the annotation class to search for
    /// is only available via `explicitTypeArgs`, so it must be recorded here
    /// (there is no real `chosenCallee` to hang it off of via `CallBinding`,
    /// since — like `findAssociatedObject` above — the call is dispatched
    /// directly to a runtime intrinsic rather than a real function body).
    func bindKClassFindAnnotationCall(
        _ id: ExprID,
        args: [CallArgument],
        explicitTypeArgs: [TypeID],
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) -> TypeID {
        let sema = ctx.sema

        for arg in args {
            _ = driver.inferExpr(arg.expr, ctx: ctx, locals: &locals)
        }

        if let searchType = explicitTypeArgs.first {
            sema.bindings.bindFindAnnotationSearchType(id, type: searchType)
        }

        let nullableAnyType = sema.types.makeNullable(sema.types.anyType)
        sema.bindings.bindExprType(id, type: nullableAnyType)
        return nullableAnyType
    }
}

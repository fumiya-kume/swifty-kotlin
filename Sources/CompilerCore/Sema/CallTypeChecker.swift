import Foundation

/// Handles call expression type inference (function calls, member calls, safe member calls).
final class CallTypeChecker {
    unowned let driver: TypeCheckDriver

    init(driver: TypeCheckDriver) {
        self.driver = driver
    }

    func inferCallExpr(
        _ id: ExprID,
        calleeID: ExprID,
        args: [CallArgument],
        range: SourceRange,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings,
        expectedType: TypeID?,
        explicitTypeArgs: [TypeID] = []
    ) -> TypeID {
        let ast = ctx.ast
        let sema = ctx.sema
        let interner = ctx.interner

        let argTypes = args.map { argument in
            driver.inferExpr(argument.expr, ctx: ctx, locals: &locals)
        }

        let calleeExpr = ast.arena.expr(calleeID)
        let calleeName: InternedString?
        if case .nameRef(let name, _) = calleeExpr {
            calleeName = name
        } else {
            calleeName = nil
        }

        var candidates: [SymbolID]
        var callInvisible: [SemanticSymbol] = []
        if let calleeName {
            let allCallCandidates = ctx.cachedScopeLookup(calleeName).filter { candidate in
                guard let symbol = ctx.cachedSymbol(candidate) else { return false }
                return symbol.kind == .function || symbol.kind == .constructor
            }
            let (vis, invis) = ctx.filterByVisibility(allCallCandidates)
            candidates = vis
            callInvisible = invis
            if candidates.isEmpty, let local = locals[calleeName] {
                if let sym = ctx.cachedSymbol(local.symbol), sym.kind == .function {
                    candidates = [local.symbol]
                }
            }
            if candidates.isEmpty {
                let classSymbols = ctx.cachedScopeLookup(calleeName).filter { candidate in
                    guard let symbol = ctx.cachedSymbol(candidate) else { return false }
                    return symbol.kind == .class || symbol.kind == .enumClass || symbol.kind == .annotationClass
                }
                if let classSym = classSymbols.first,
                   let classSymbol = ctx.cachedSymbol(classSym) {
                    // P5-112: Prohibit direct instantiation of abstract classes.
                    if classSymbol.flags.contains(.abstractType) {
                        let className = classSymbol.fqName.map { interner.resolve($0) }.joined(separator: ".")
                        ctx.semaCtx.diagnostics.error(
                            "KSWIFTK-SEMA-ABSTRACT",
                            "Cannot create an instance of abstract class '\(className)'.",
                            range: range
                        )
                        sema.bindings.bindExprType(id, type: sema.types.errorType)
                        return sema.types.errorType
                    }
                    let initName = interner.intern("<init>")
                    let ctorFQName = classSymbol.fqName + [initName]
                    let ctorSymbols = sema.symbols.lookupAll(fqName: ctorFQName)
                    if !ctorSymbols.isEmpty {
                        let (vis, invis) = ctx.filterByVisibility(ctorSymbols)
                        candidates = vis
                        callInvisible.append(contentsOf: invis)
                    }
                }
            }
        } else {
            candidates = []
        }
        if !candidates.isEmpty {
            let resolvedArgs: [CallArg] = zip(args, argTypes).map { argument, type in
                CallArg(label: argument.label, isSpread: argument.isSpread, type: type)
            }
            let resolved = ctx.resolver.resolveCall(
                candidates: candidates,
                call: CallExpr(
                    range: range,
                    calleeName: calleeName ?? InternedString(),
                    args: resolvedArgs,
                    explicitTypeArgs: explicitTypeArgs
                ),
                expectedType: expectedType,
                implicitReceiverType: ctx.implicitReceiverType,
                ctx: ctx.semaCtx
            )
            if let diagnostic = resolved.diagnostic {
                ctx.semaCtx.diagnostics.emit(diagnostic)
                sema.bindings.bindExprType(id, type: sema.types.errorType)
                return sema.types.errorType
            }
            guard let chosen = resolved.chosenCallee else {
                let nameStr = calleeName.map { interner.resolve($0) } ?? "<unknown>"
                ctx.semaCtx.diagnostics.error(
                    "KSWIFTK-SEMA-0023",
                    "Unresolved function '\(nameStr)'.",
                    range: range
                )
                sema.bindings.bindExprType(id, type: sema.types.errorType)
                return sema.types.errorType
            }
            let returnType = bindCallAndResolveReturnType(id, chosen: chosen, resolved: resolved, sema: sema)
            sema.bindings.bindExprType(id, type: returnType)
            return returnType
        }

        var callableTarget: CallableTarget?
        var callableCalleeType: TypeID?
        if let calleeName,
           let local = locals[calleeName] {
            if !local.isInitialized {
                ctx.semaCtx.diagnostics.error(
                    "KSWIFTK-SEMA-0031",
                    "Variable '\(interner.resolve(calleeName))' must be initialized before use.",
                    range: range
                )
            }
            sema.bindings.bindIdentifier(calleeID, symbol: local.symbol)
            sema.bindings.bindExprType(calleeID, type: local.type)
            let localSymbolKind = ctx.cachedSymbol(local.symbol)?.kind
            if localSymbolKind != .function {
                callableTarget = .localValue(local.symbol)
                callableCalleeType = local.type
            }
        } else if calleeName == nil {
            let contextualReturnType = expectedType ?? sema.types.anyType
            let contextualCalleeType = sema.types.make(.functionType(FunctionType(
                params: argTypes,
                returnType: contextualReturnType,
                isSuspend: false,
                nullability: .nonNull
            )))
            callableCalleeType = driver.inferExpr(
                calleeID,
                ctx: ctx,
                locals: &locals,
                expectedType: contextualCalleeType
            )
            callableTarget = driver.helpers.callableTargetForCalleeExpr(calleeID, sema: sema)
        }

        if let callableCalleeType,
           let result = inferCallableValueInvocation(
               id, calleeType: callableCalleeType, callableTarget: callableTarget,
               args: args, argTypes: argTypes, range: range, ctx: ctx, expectedType: expectedType
           ) {
            return result
        }

        // Invoke operator fallback: if callee is not a function type, check if
        // its type has an `operator fun invoke(...)` member and resolve through
        // the overload resolver as a member call.
        if let callableCalleeType {
            let invokeName = interner.intern("invoke")
            let invokeCandidates = driver.helpers.collectMemberFunctionCandidates(
                named: invokeName,
                receiverType: callableCalleeType,
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
                    implicitReceiverType: callableCalleeType,
                    ctx: ctx.semaCtx
                )
                if let diagnostic = resolved.diagnostic {
                    ctx.semaCtx.diagnostics.emit(diagnostic)
                    sema.bindings.bindExprType(id, type: sema.types.errorType)
                    return sema.types.errorType
                }
                if let chosen = resolved.chosenCallee {
                    let returnType = bindCallAndResolveReturnType(id, chosen: chosen, resolved: resolved, sema: sema)
                    sema.bindings.markInvokeOperatorCall(id)
                    sema.bindings.bindExprType(id, type: returnType)
                    return returnType
                }
            }
        }

        if let builtinType = driver.helpers.kxMiniCoroutineBuiltinReturnType(
            calleeName: calleeName,
            argumentCount: args.count,
            sema: sema,
            interner: interner
        ) {
            sema.bindings.bindExprType(id, type: builtinType)
            return builtinType
        }
        if let calleeName,
           interner.resolve(calleeName) == "println",
           args.count <= 1 {
            sema.bindings.bindExprType(id, type: sema.types.unitType)
            return sema.types.unitType
        }
        // Collection literal factory functions (P5-84).
        if let calleeName {
            let name = interner.resolve(calleeName)
            switch name {
            case "listOf", "mutableListOf", "emptyList",
                 "arrayOf", "intArrayOf", "longArrayOf",
                 "mapOf", "mutableMapOf", "emptyMap",
                 "setOf", "mutableSetOf", "emptySet",
                 "listOfNotNull":
                sema.bindings.markCollectionExpr(id)
                sema.bindings.bindExprType(id, type: sema.types.anyType)
                return sema.types.anyType
            default:
                break
            }
        }
        if let firstInvisible = callInvisible.first, let calleeName {
            driver.helpers.emitVisibilityError(for: firstInvisible, name: interner.resolve(calleeName), range: range, diagnostics: ctx.semaCtx.diagnostics)
        } else {
            let nameStr = calleeName.map { interner.resolve($0) } ?? "<unknown>"
            ctx.semaCtx.diagnostics.error(
                "KSWIFTK-SEMA-0023",
                "Unresolved function '\(nameStr)'.",
                range: range
            )
        }
        sema.bindings.bindExprType(id, type: sema.types.errorType)
        return sema.types.errorType
    }

    func inferMemberCallExpr(
        _ id: ExprID,
        receiverID: ExprID,
        calleeName: InternedString,
        args: [CallArgument],
        range: SourceRange,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings,
        expectedType: TypeID?,
        explicitTypeArgs: [TypeID] = []
    ) -> TypeID {
        inferMemberCallImpl(id, receiverID: receiverID, calleeName: calleeName, args: args, range: range, ctx: ctx, locals: &locals, expectedType: expectedType, explicitTypeArgs: explicitTypeArgs, safeCall: false)
    }

    func inferSafeMemberCallExpr(
        _ id: ExprID,
        receiverID: ExprID,
        calleeName: InternedString,
        args: [CallArgument],
        range: SourceRange,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings,
        expectedType: TypeID?,
        explicitTypeArgs: [TypeID] = []
    ) -> TypeID {
        inferMemberCallImpl(id, receiverID: receiverID, calleeName: calleeName, args: args, range: range, ctx: ctx, locals: &locals, expectedType: expectedType, explicitTypeArgs: explicitTypeArgs, safeCall: true)
    }

    private func inferMemberCallImpl(
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

        let receiverType = driver.inferExpr(receiverID, ctx: ctx, locals: &locals)
        let argTypes = args.map { driver.inferExpr($0.expr, ctx: ctx, locals: &locals) }
        let lookupReceiverType = safeCall ? sema.types.makeNonNullable(receiverType) : receiverType

        // Primitive member function: Int/Long.inv() → same type (P5-103)
        if interner.resolve(calleeName) == "inv",
           args.isEmpty {
            let intType = sema.types.make(.primitive(.int, .nonNull))
            let longType = sema.types.make(.primitive(.long, .nonNull))
            if lookupReceiverType == intType || lookupReceiverType == longType {
                let resultType = lookupReceiverType
                let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
                sema.bindings.bindExprType(id, type: finalType)
                return finalType
            }
        }

        var isSuperCall = false
        var supertypeSymbols: Set<SymbolID> = []
        if !safeCall {
            isSuperCall = ast.arena.expr(receiverID).map { if case .superRef = $0 { true } else { false } } ?? false
            if isSuperCall, let currentReceiverType = ctx.implicitReceiverType,
               let classSymbol = driver.helpers.nominalSymbol(of: currentReceiverType, types: sema.types) {
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
        let isClassNameReceiver: Bool = {
            guard let receiverSymbolID = sema.bindings.identifierSymbol(for: receiverID),
                  let receiverSymbol = sema.symbols.symbol(receiverSymbolID) else {
                return false
            }
            return receiverSymbol.kind == .class || receiverSymbol.kind == .interface || receiverSymbol.kind == .enumClass
        }()

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
               let companionSym = sema.symbols.symbol(companionSymbol) {
                let companionMemberFQName = companionSym.fqName + [calleeName]

                // Try companion property access when no arguments are provided
                // (e.g. Foo.MAX_COUNT).  When args are present this is a function
                // call, so skip the property short-circuit to avoid shadowing a
                // companion function of the same name.
                if args.isEmpty {
                    let propertyCandidate = sema.symbols.lookupAll(fqName: companionMemberFQName).first(where: { cid in
                        guard let sym = sema.symbols.symbol(cid),
                              sym.kind == .property,
                              sema.symbols.parentSymbol(for: cid) == companionSymbol else {
                            return false
                        }
                        return true
                    })
                    if let propSymbol = propertyCandidate,
                       let propType = sema.symbols.propertyType(for: propSymbol) {
                        // Check visibility before returning the property.
                        if let propSym = sema.symbols.symbol(propSymbol),
                           !ctx.visibilityChecker.isAccessible(propSym, fromFile: ctx.currentFileID, enclosingClass: ctx.enclosingClassSymbol) {
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
                          signature.receiverType != nil else {
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
                   sema.symbols.companionObjectSymbol(for: ownerNominal) == parentSymbol {
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
        let (visible, invisible) = ctx.filterByVisibility(allCandidates)
        let candidates = visible
        if candidates.isEmpty {
            // For zero-arg member calls, try member property/field lookup.
            // This handles `receiver.property` syntax (e.g. `this@Outer.x`).
            // Skip this for class-name receivers — only companion members are
            // accessible via `ClassName.member`, not instance properties.
            if !isClassNameReceiver,
               args.isEmpty,
               let propResult = driver.helpers.lookupMemberProperty(
                   named: calleeName,
                   receiverType: memberLookupType,
                   sema: sema
               ) {
                // Check visibility before returning the property.
                if let propSymbol = sema.symbols.symbol(propResult.symbol),
                   !ctx.visibilityChecker.isAccessible(propSymbol, fromFile: ctx.currentFileID, enclosingClass: ctx.enclosingClassSymbol) {
                    driver.helpers.emitVisibilityError(for: propSymbol, name: interner.resolve(calleeName), range: range, diagnostics: ctx.semaCtx.diagnostics)
                    return driver.helpers.bindAndReturnErrorType(id, sema: sema)
                }
                sema.bindings.bindIdentifier(id, symbol: propResult.symbol)
                let finalType = safeCall ? sema.types.makeNullable(propResult.type) : propResult.type
                sema.bindings.bindExprType(id, type: finalType)
                return finalType
            }
            if lookupReceiverType == sema.types.errorType {
                return driver.helpers.bindAndReturnErrorType(id, sema: sema)
            }
            if let firstInvisible = invisible.first {
                driver.helpers.emitVisibilityError(for: firstInvisible, name: interner.resolve(calleeName), range: range, diagnostics: ctx.semaCtx.diagnostics)
                return driver.helpers.bindAndReturnErrorType(id, sema: sema)
            }
            // Collection member access fallback (P5-84): allow only members
            // that have corresponding runtime implementations in
            // CollectionLiteralLoweringPass and CallLowerer.
            if !isClassNameReceiver, sema.bindings.isCollectionExpr(receiverID) {
                let memberName = interner.resolve(calleeName)
                let collectionMembers: Set<String> = [
                    "size", "get", "contains", "containsKey",
                    "isEmpty", "first", "last", "indexOf",
                    "count", "iterator"
                ]
                if collectionMembers.contains(memberName) {
                    let resultType: TypeID
                    switch memberName {
                    case "size", "count", "indexOf":
                        resultType = sema.types.make(.primitive(.int, .nonNull))
                    case "isEmpty", "contains", "containsKey":
                        resultType = sema.types.make(.primitive(.boolean, .nonNull))
                    default:
                        resultType = sema.types.anyType
                    }
                    let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
                    sema.bindings.bindExprType(id, type: finalType)
                    return finalType
                }
            }
            if safeCall {
                let resultType = sema.types.nullableAnyType
                sema.bindings.bindExprType(id, type: resultType)
                return resultType
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
            ctx.semaCtx.diagnostics.emit(diagnostic)
            return driver.helpers.bindAndReturnErrorType(id, sema: sema)
        }
        guard let chosen = resolved.chosenCallee else {
            ctx.semaCtx.diagnostics.error("KSWIFTK-SEMA-0024", "Unresolved member function '\(interner.resolve(calleeName))'.", range: range)
            return driver.helpers.bindAndReturnErrorType(id, sema: sema)
        }
        // P5-112: Prohibit super.foo() calls to abstract members.
        if isSuperCall,
           let chosenSym = sema.symbols.symbol(chosen),
           chosenSym.flags.contains(.abstractType),
           (chosenSym.kind == .function || chosenSym.kind == .property) {
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
           ) {
            // Check if any parameter uses a write-forbidden type parameter
            if let violatingParamIndex = sema.types.checkVarianceViolationInParameters(
                signature: signature,
                writeForbiddenSymbols: varianceResult.writeForbiddenSymbols
            ) {
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

    func bindCallAndResolveReturnType(
        _ id: ExprID,
        chosen: SymbolID,
        resolved: ResolvedCall,
        sema: SemaModule
    ) -> TypeID {
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
        sema.bindings.bindCallableTarget(id, target: .symbol(chosen))
        if let signature = sema.symbols.functionSignature(for: chosen) {
            let typeVarBySymbol = sema.types.makeTypeVarBySymbol(signature.typeParameterSymbols)
            return sema.types.substituteTypeParameters(
                in: signature.returnType,
                substitution: resolved.substitutedTypeArguments,
                typeVarBySymbol: typeVarBySymbol
            )
        }
        return sema.types.anyType
    }

    private func inferCallableValueInvocation(
        _ id: ExprID,
        calleeType: TypeID,
        callableTarget: CallableTarget?,
        args: [CallArgument],
        argTypes: [TypeID],
        range: SourceRange,
        ctx: TypeInferenceContext,
        expectedType: TypeID?
    ) -> TypeID? {
        let ast = ctx.ast
        let sema = ctx.sema
        let nonNullCalleeType = sema.types.makeNonNullable(calleeType)
        guard case .functionType(let functionType) = sema.types.kind(of: nonNullCalleeType) else {
            return nil
        }
        guard !args.contains(where: { $0.label != nil || $0.isSpread }),
              functionType.params.count == argTypes.count else {
            ctx.semaCtx.diagnostics.error(
                "KSWIFTK-SEMA-0002",
                "No viable overload found for call.",
                range: range
            )
            sema.bindings.bindExprType(id, type: sema.types.errorType)
            return sema.types.errorType
        }
        var parameterMapping: [Int: Int] = [:]
        for index in argTypes.indices {
            parameterMapping[index] = index
            driver.emitSubtypeConstraint(
                left: argTypes[index],
                right: functionType.params[index],
                range: ast.arena.exprRange(args[index].expr) ?? range,
                solver: ConstraintSolver(),
                sema: sema,
                diagnostics: ctx.semaCtx.diagnostics
            )
        }
        if let expectedType {
            driver.emitSubtypeConstraint(
                left: functionType.returnType,
                right: expectedType,
                range: range,
                solver: ConstraintSolver(),
                sema: sema,
                diagnostics: ctx.semaCtx.diagnostics
            )
        }
        sema.bindings.bindCallableValueCall(
            id,
            binding: CallableValueCallBinding(
                target: callableTarget,
                functionType: nonNullCalleeType,
                parameterMapping: parameterMapping
            )
        )
        if let callableTarget {
            sema.bindings.bindCallableTarget(id, target: callableTarget)
        }
        sema.bindings.bindExprType(id, type: functionType.returnType)
        return functionType.returnType
    }
}

import Foundation

// swiftlint:disable file_length function_body_length cyclomatic_complexity

extension CallTypeChecker {
    func inferRegularMemberCall(
        _ request: MemberCallInferenceRequest,
        receiverType: TypeID,
        locals: inout LocalBindings
    ) -> TypeID {
        let id = request.id
        let receiverID = request.receiverID
        let calleeName = request.calleeName
        let args = request.args
        let range = request.range
        let ctx = request.ctx
        let expectedType = request.expectedType
        let explicitTypeArgs = request.explicitTypeArgs
        let safeCall = request.safeCall
        let ast = ctx.ast
        let sema = ctx.sema
        let interner = ctx.interner
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
        // Infer argument types for the normal resolution path (scope functions,
        // collection HOFs, and comparator HOFs infer their lambda args with
        // expected type above and return).
        // Skip lambda literals and callable refs so that their first inference
        // happens inside prepareCallArguments with a contextual expected type,
        // preventing a stale no-expectedType binding from poisoning the cache.
        let argTypes = args.map { arg -> TypeID in
            if let expr = ast.arena.expr(arg.expr) {
                switch expr {
                case .lambdaLiteral, .callableRef:
                    return sema.bindings.exprType(for: arg.expr) ?? sema.types.anyType
                default:
                    break
                }
            }
            let inferredType = sema.bindings.exprType(for: arg.expr)
                ?? driver.inferExpr(arg.expr, ctx: ctx, locals: &locals)
            if calleeName == interner.intern("coerceIn"),
               let rangeType = floatingPointRangeArgumentType(
                   arg.expr,
                   ast: ast,
                   sema: sema,
                   interner: interner
               )
            {
                // Floating-point range expressions use a scalar lowering type for
                // the existing range runtime path, but source-backed coerceIn
                // resolves against ClosedFloatingPointRange<T>.
                return rangeType
            }
            return inferredType
        }

        let hasLeadingLocaleArgument = calleeName == interner.intern("format")
            && argTypes.first.map { isJavaUtilLocaleType($0, sema: sema, interner: interner) } == true
        let lookupReceiverType = safeCall ? sema.types.makeNonNullable(receiverType) : receiverType
        // Primitive member function: Int/Long/UInt/ULong.inv() → same type (P5-103, TYPE-005)
        if let result = tryInferRegularMemberCallPrimitiveSpecials(
            request,
            receiverType: receiverType,
            lookupReceiverType: lookupReceiverType,
            argTypes: argTypes,
            locals: &locals
        ) {
            return result
        }

        var isSuperCall = false
        var supertypeSymbols: Set<SymbolID> = []
        var qualifiedSuperType: SymbolID?
        if !safeCall {
            if let superExpr = ast.arena.expr(receiverID), case let .superRef(interfaceQualifier, _) = superExpr {
                isSuperCall = true
                if let currentReceiverType = ctx.implicitReceiverType,
                   let classSymbol = driver.helpers.nominalSymbol(of: currentReceiverType, types: sema.types)
                {
                    // Handle qualified super: super<Interface>
                    if let qualifier = interfaceQualifier {
                        let qualifierStr = ctx.interner.resolve(qualifier)
                        let directSupertypes = sema.symbols.directSupertypes(for: classSymbol)

                        // Find the specified interface in direct supertypes
                        for superID in directSupertypes {
                            guard let superSym = sema.symbols.symbol(superID) else { continue }
                            if superSym.kind == .interface, ctx.interner.resolve(superSym.name) == qualifierStr {
                                qualifiedSuperType = superID
                                supertypeSymbols.insert(superID)
                                break
                            }
                        }

                        if qualifiedSuperType == nil {
                            ctx.semaCtx.diagnostics.error(
                                "KSWIFTK-SEMA-0054",
                                "No type '\(qualifierStr)' found in direct supertypes for qualified 'super'.",
                                range: ast.arena.exprRange(receiverID)
                            )
                        }
                    } else {
                        // Handle unqualified super: search all supertypes
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
            }
        }

        let rangeSourceMemberLookupType: TypeID? = if !isSuperCall,
                                                      isBundledRangeSourceMember(calleeName, interner: interner)
        {
            sourceLevelRangeMemberLookupType(
                receiverExpr: receiverID,
                receiverType: lookupReceiverType,
                sema: sema,
                interner: interner
            )
        } else {
            nil
        }
        let memberLookupType = (isSuperCall ? ctx.implicitReceiverType : nil) ?? rangeSourceMemberLookupType ?? lookupReceiverType

        // Detect class-name receiver: when the receiver is a name reference to
        // a class/interface/enumClass symbol, only companion members should be
        // accessible (not instance methods).  This prevents `Foo.instanceMethod()`
        // from resolving when there is no companion with that name.
        let classNameReceiverNominalSymbol: SymbolID? = {
            if let receiverSymbolID = sema.bindings.identifierSymbol(for: receiverID),
               let receiverSymbol = sema.symbols.symbol(receiverSymbolID)
            {
                switch receiverSymbol.kind {
                case .class, .interface, .enumClass, .annotationClass:
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
                    case .class, .interface, .enumClass, .annotationClass:
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
            let staticMethodFQName = owner.fqName + [calleeName]
            var staticMethodCandidates = sema.symbols.lookupAll(fqName: staticMethodFQName).filter { candidate in
                guard let symbol = sema.symbols.symbol(candidate),
                      symbol.kind == .function,
                      sema.symbols.parentSymbol(for: candidate) == ownerSymbol,
                      let signature = sema.symbols.functionSignature(for: candidate)
                else {
                    return false
                }
                return signature.receiverType == nil
            }
            if staticMethodCandidates.isEmpty {
                staticMethodCandidates = sema.symbols.lookupByShortName(calleeName).filter { candidate in
                    guard let symbol = sema.symbols.symbol(candidate),
                          symbol.kind == .function,
                          sema.symbols.parentSymbol(for: candidate) == ownerSymbol,
                          let signature = sema.symbols.functionSignature(for: candidate)
                    else {
                        return false
                    }
                    return signature.receiverType == nil
                }
            }
            if !staticMethodCandidates.isEmpty {
                let (visibleStaticMethods, invisibleStaticMethods) = ctx.filterByVisibility(staticMethodCandidates)
                if let firstInvisible = invisibleStaticMethods.first {
                    driver.helpers.emitVisibilityError(
                        for: firstInvisible,
                        name: interner.resolve(calleeName),
                        range: range,
                        diagnostics: ctx.semaCtx.diagnostics
                    )
                    return driver.helpers.bindAndReturnErrorType(id, sema: sema)
                }
                if !visibleStaticMethods.isEmpty {
                    let callArgs = zip(args, argTypes).map { arg, type in
                        CallArg(label: arg.label, isSpread: arg.isSpread, type: type)
                    }
                    let call = CallExpr(
                        range: range,
                        calleeName: calleeName,
                        args: callArgs,
                        explicitTypeArgs: explicitTypeArgs
                    )
                    let resolved = ctx.resolver.resolveCall(
                        candidates: visibleStaticMethods,
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
                        sema.bindings.bindCallableTarget(id, target: .symbol(chosen))
                        sema.bindings.bindIdentifier(id, symbol: chosen)
                        let typeVarBySymbol = sema.types.makeTypeVarBySymbol(signature.typeParameterSymbols)
                        let resultType = sema.types.substituteTypeParameters(
                            in: signature.returnType,
                            substitution: resolved.substitutedTypeArguments,
                            typeVarBySymbol: typeVarBySymbol
                        )
                        sema.bindings.bindExprType(id, type: resultType)
                        return resultType
                    }
                }
            }

            if owner.kind == .enumClass {
                // A class-name receiver can also select a source-backed extension
                // declared on the nominal type itself. This is distinct from the
                // companion-extension path below: enum APIs such as
                // `RequiresOptIn.Level.entries` are represented as extensions on
                // `Level`, while `valueOf`/`entries` generated by enum synthesis
                // remain companion members. Imported stdlib artifacts expose the
                // source-backed form as synthetic symbols, so recover it by short
                // name when it is not present in the file scope.
                let ownerType = sema.types.make(.classType(ClassType(
                    classSymbol: ownerSymbol,
                    args: [],
                    nullability: .nonNull
                )))
                if args.isEmpty,
                   sema.bundledIndex.contains(
                       ownerFQName: owner.fqName,
                       name: calleeName,
                       arity: 0
                   ),
                   let extensionPropertyType = resolveExtensionPropertyGetter(
                       id: id,
                       calleeName: calleeName,
                       range: range,
                       receiverType: ownerType,
                       expectedType: expectedType,
                       ctx: ctx
                   )
                {
                    sema.bindings.bindExprType(receiverID, type: ownerType)
                    sema.bindings.bindExprType(id, type: extensionPropertyType)
                    return extensionPropertyType
                }

                var ownerExtensionCandidates = ctx.cachedScopeLookup(calleeName).filter { candidate in
                    guard let symbol = sema.symbols.symbol(candidate),
                          symbol.kind == .function,
                          let signature = sema.symbols.functionSignature(for: candidate),
                          let receiver = signature.receiverType
                    else {
                        return false
                    }
                    guard sema.bundledIndex.contains(
                        ownerFQName: owner.fqName,
                        name: calleeName,
                        arity: signature.parameterTypes.count
                    ) else {
                        return false
                    }
                    return extensionSyntheticFallbackReceiverMatches(
                        callSiteReceiver: ownerType,
                        declaredReceiver: receiver,
                        sema: sema
                    )
                }
                if ownerExtensionCandidates.isEmpty {
                    ownerExtensionCandidates = sema.symbols.lookupByShortName(calleeName).filter { candidate in
                        guard let symbol = sema.symbols.symbol(candidate),
                              symbol.kind == .function,
                              symbol.flags.contains(.synthetic),
                              let signature = sema.symbols.functionSignature(for: candidate),
                              let receiver = signature.receiverType
                        else {
                            return false
                        }
                        guard sema.bundledIndex.contains(
                            ownerFQName: owner.fqName,
                            name: calleeName,
                            arity: signature.parameterTypes.count
                        ) else {
                            return false
                        }
                        return extensionSyntheticFallbackReceiverMatches(
                            callSiteReceiver: ownerType,
                            declaredReceiver: receiver,
                            sema: sema
                        )
                    }
                }
                let (visibleOwnerExtensions, invisibleOwnerExtensions) = ctx.filterByVisibility(ownerExtensionCandidates)
                if let firstInvisible = invisibleOwnerExtensions.first {
                    driver.helpers.emitVisibilityError(
                        for: firstInvisible,
                        name: interner.resolve(calleeName),
                        range: range,
                        diagnostics: ctx.semaCtx.diagnostics
                    )
                    return driver.helpers.bindAndReturnErrorType(id, sema: sema)
                }
                if !visibleOwnerExtensions.isEmpty {
                    let callArgs = zip(args, argTypes).map { arg, type in
                        CallArg(label: arg.label, isSpread: arg.isSpread, type: type)
                    }
                    let call = CallExpr(
                        range: range,
                        calleeName: calleeName,
                        args: callArgs,
                        explicitTypeArgs: explicitTypeArgs
                    )
                    let resolved = ctx.resolver.resolveCall(
                        candidates: visibleOwnerExtensions,
                        call: call,
                        expectedType: expectedType,
                        implicitReceiverType: ownerType,
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
                        sema.bindings.bindCallableTarget(id, target: .symbol(chosen))
                        sema.bindings.bindIdentifier(id, symbol: chosen)
                        let typeVarBySymbol = sema.types.makeTypeVarBySymbol(signature.typeParameterSymbols)
                        let resultType = sema.types.substituteTypeParameters(
                            in: signature.returnType,
                            substitution: resolved.substitutedTypeArguments,
                            typeVarBySymbol: typeVarBySymbol
                        )
                        driver.helpers.checkDeprecation(
                            for: chosen,
                            sema: sema,
                            interner: interner,
                            range: range,
                            diagnostics: ctx.semaCtx.diagnostics
                        )
                        driver.helpers.checkOptIn(
                            for: chosen,
                            ctx: ctx,
                            range: range,
                            diagnostics: ctx.semaCtx.diagnostics
                        )
                        sema.bindings.bindExprType(receiverID, type: ownerType)
                        sema.bindings.bindExprType(id, type: resultType)
                        return resultType
                    }
                }
            }

            let nestedOwnerFQName = owner.fqName + [calleeName]
            var nestedOwnerSymbols = sema.symbols.lookupAll(fqName: nestedOwnerFQName).filter { candidate in
                guard let symbol = sema.symbols.symbol(candidate) else {
                    return false
                }
                guard sema.symbols.parentSymbol(for: candidate) == ownerSymbol else {
                    return false
                }
                switch symbol.kind {
                case .class, .enumClass, .object, .annotationClass:
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
                    case .class, .enumClass, .object, .annotationClass:
                        return true
                    default:
                        return false
                    }
                }
                if shortNameNestedOwners.count == 1 {
                    nestedOwnerSymbols = shortNameNestedOwners
                }
            }
            // `Owner.Nested` and `Owner.Nested()` share the same zero-arg
            // `.memberCall` shape, but the AST arena records whether parentheses
            // were written. This is mostly unambiguous when
            // no valid constructor-call reading could exist in the first
            // place: enum class constructors are always implicitly private
            // (never callable from outside the enum body) and `object`
            // declarations have no constructor at all, so a nested enum/object
            // reference must be the bare type/nested-owner (needed e.g. for
            // `Owner.Nested.ENTRY`, where `Nested` is the receiver of a
            // further static member access). A parenthesis-less nested annotation
            // class is likewise a qualifier, while an explicit call must continue
            // through constructor resolution. A nested `class`, in
            // contrast, may have a genuine public zero-arg constructor (e.g.
            // `Outer.Builder()`), so it falls through to constructor
            // resolution below, preserving the pre-existing behavior.
            if args.isEmpty, let nestedOwner = nestedOwnerSymbols.first,
               let nestedOwnerKind = sema.symbols.symbol(nestedOwner)?.kind,
               nestedOwnerKind == .enumClass || nestedOwnerKind == .object
                   || (nestedOwnerKind == .annotationClass && !ast.arena.isExplicitCall(id))
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
        }

        if !isClassNameReceiver,
           args.isEmpty,
           !ast.arena.isExplicitCall(id),
           let propResult = driver.helpers.lookupMemberProperty(
               named: calleeName,
               receiverType: memberLookupType,
               sema: sema
           )
        {
            if let propSymbol = sema.symbols.symbol(propResult.symbol),
               !ctx.visibilityChecker.isAccessible(
                   propSymbol,
                   fromFile: ctx.currentFileID,
                   enclosingClass: ctx.enclosingClassSymbol
               )
            {
                driver.helpers.emitVisibilityError(
                    for: propSymbol,
                    name: interner.resolve(calleeName),
                    range: range,
                    diagnostics: ctx.semaCtx.diagnostics
                )
                return driver.helpers.bindAndReturnErrorType(id, sema: sema)
            }
            sema.bindings.bindIdentifier(id, symbol: propResult.symbol)
            let finalType = safeCall ? sema.types.makeNullable(propResult.type) : propResult.type
            sema.bindings.bindExprType(id, type: finalType)
            return finalType
        }
        if !isClassNameReceiver,
           args.isEmpty,
           !ast.arena.isExplicitCall(id),
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

        // Track the companion type so we can pass it (not the owner class type)
        // as the implicit receiver when resolving the call.
        var companionReceiverType: TypeID?

        var allCandidates: [SymbolID]
        if isClassNameReceiver {
            // Class-name receiver: only companion members are valid targets.
            // Skip collectMemberFunctionCandidates which would find instance
            // methods and shadow companion members of the same name.
            if let ownerNominal = classNameReceiverNominalSymbol,
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
                        driver.helpers.checkDeprecation(
                            for: propSymbol,
                            sema: sema,
                            interner: interner,
                            range: range,
                            diagnostics: ctx.semaCtx.diagnostics
                        )
                        driver.helpers.checkOptIn(
                            for: propSymbol,
                            ctx: ctx,
                            range: range,
                            diagnostics: ctx.semaCtx.diagnostics
                        )
                        // Re-bind receiver to companion type for correct KIR lowering
                        let compType = sema.types.make(.classType(ClassType(classSymbol: companionSymbol, args: [], nullability: .nonNull)))
                        sema.bindings.bindExprType(receiverID, type: compType)
                        sema.bindings.bindIdentifier(id, symbol: propSymbol)
                        sema.bindings.bindExprType(id, type: propType)
                        return propType
                    }

                    // Fall back to a Companion-scoped extension property
                    // (e.g. `val Duration.Companion.ZERO: Duration`) written as
                    // Kotlin source at package scope with the Companion as receiver.
                    let compTypeForExt = sema.types.make(.classType(ClassType(classSymbol: companionSymbol, args: [], nullability: .nonNull)))
                    if let extensionPropertyType = resolveExtensionPropertyGetter(
                        id: id,
                        calleeName: calleeName,
                        range: range,
                        receiverType: compTypeForExt,
                        expectedType: expectedType,
                        ctx: ctx
                    ) {
                        sema.bindings.bindExprType(receiverID, type: compTypeForExt)
                        sema.bindings.bindExprType(id, type: extensionPropertyType)
                        return extensionPropertyType
                    }
                }

                // Then try companion function candidates
                var companionCandidates: [SymbolID] = []
                for candidate in sema.symbols.lookupAll(fqName: companionMemberFQName) {
                    guard let symbol = sema.symbols.symbol(candidate),
                          symbol.kind == .function,
                          sema.symbols.parentSymbol(for: candidate) == companionSymbol,
                          sema.symbols.functionSignature(for: candidate) != nil
                    else {
                        continue
                    }
                    companionCandidates.append(candidate)
                }
                let companionTypeForExtensionLookup = sema.types.make(.classType(ClassType(classSymbol: companionSymbol, args: [], nullability: .nonNull)))
                if companionCandidates.isEmpty {
                    // Fall back to Companion-scoped extension functions
                    // (e.g. `fun Duration.Companion.parse(value: String): Duration`)
                    // written as Kotlin source at package scope. These are resolved
                    // via scope lookup (like ordinary extension functions), not the
                    // direct-member FQName lookup above.
                    companionCandidates = ctx.cachedScopeLookup(calleeName).filter { candidate in
                        guard let symbol = ctx.cachedSymbol(candidate),
                              symbol.kind == .function,
                              let signature = sema.symbols.functionSignature(for: candidate),
                              let recv = signature.receiverType
                        else { return false }
                        return extensionSyntheticFallbackReceiverMatches(
                            callSiteReceiver: companionTypeForExtensionLookup,
                            declaredReceiver: recv,
                            sema: sema
                        )
                    }
                }
                if companionCandidates.isEmpty {
                    // Precompiled library extensions are not inserted into
                    // file scopes, because their receiver is resolved during
                    // member-call inference. Recover those synthetic
                    // declarations by short name for class-name receivers.
                    companionCandidates = sema.symbols.lookupByShortName(calleeName).filter { candidate in
                        guard let symbol = sema.symbols.symbol(candidate),
                              symbol.kind == .function,
                              symbol.flags.contains(.synthetic),
                              let signature = sema.symbols.functionSignature(for: candidate),
                              let recv = signature.receiverType
                        else {
                            return false
                        }
                        return extensionSyntheticFallbackReceiverMatches(
                            callSiteReceiver: companionTypeForExtensionLookup,
                            declaredReceiver: recv,
                            sema: sema
                        )
                    }
                }
                if !companionCandidates.isEmpty {
                    companionReceiverType = companionTypeForExtensionLookup
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
            let allowedOwnerSymbols = isSuperCall && !supertypeSymbols.isEmpty ?
                (qualifiedSuperType != nil ? [qualifiedSuperType!] : supertypeSymbols) : nil
            let rangeSourceCandidates = rangeSourceMemberLookupType.map {
                collectRangeSourceExtensionCandidates(
                    named: calleeName,
                    receiverType: $0,
                    sema: sema,
                    interner: interner
                )
            } ?? []
            let atomicSourceCandidates: [SymbolID] = if rangeSourceCandidates.isEmpty,
                isBundledAtomicSourceMember(calleeName, interner: interner),
                isBundledAtomicSourceReceiver(memberLookupType, sema: sema, interner: interner)
            {
                collectAtomicSourceExtensionCandidates(
                    named: calleeName,
                    receiverType: memberLookupType,
                    sema: sema,
                    interner: interner
                )
            } else {
                []
            }
            let primitiveArraySourceCandidates = collectPrimitiveArraySourceHOFs(
                named: calleeName,
                receiverType: memberLookupType,
                sema: sema,
                interner: interner
            )
            let arrayConversionSourceCandidates = collectArraySourceConversionCandidates(
                named: calleeName,
                receiverType: memberLookupType,
                sema: sema,
                interner: interner
            )
            var mutableMapPutAllSourceCandidates: [SymbolID] = []
            if interner.resolve(calleeName) == "putAll",
               ReceiverClassifier(sema: sema, interner: interner).isMutableMapType(memberLookupType),
               args.count == 1,
               let argumentType = argTypes.first,
               !ReceiverClassifier(sema: sema, interner: interner).isMapLikeCollectionType(argumentType)
            {
                let argumentExpr = args[0].expr
                let isArrayArgument = ReceiverClassifier(sema: sema, interner: interner)
                    .isArrayLikeReceiver(receiverID: argumentExpr)
                let isSequenceArgument = ReceiverClassifier(sema: sema, interner: interner)
                    .isSequenceLikeType(argumentType)
                mutableMapPutAllSourceCandidates = sema.symbols.lookupAll(fqName: [
                    interner.intern("kotlin"),
                    interner.intern("collections"),
                    calleeName,
                ]).filter { candidate in
                    guard let candidateSymbol = sema.symbols.symbol(candidate),
                          candidateSymbol.kind == .function,
                          (!candidateSymbol.flags.contains(.synthetic)
                              || sema.symbols.isSourceBackedSymbol(candidate)),
                          let signature = sema.symbols.functionSignature(for: candidate),
                          let receiver = signature.receiverType,
                          signature.parameterTypes.count == 1,
                          let receiverSymbol = driver.helpers.nominalSymbol(of: receiver, types: sema.types),
                          let receiverInfo = sema.symbols.symbol(receiverSymbol),
                          let parameterSymbol = driver.helpers.nominalSymbol(
                              of: signature.parameterTypes[0], types: sema.types
                          ),
                          let parameterInfo = sema.symbols.symbol(parameterSymbol)
                    else {
                        return false
                    }
                    guard receiverInfo.fqName == [
                        interner.intern("kotlin"),
                        interner.intern("collections"),
                        interner.intern("MutableMap"),
                    ] else {
                        return false
                    }
                    if isArrayArgument {
                        return parameterInfo.fqName == [
                            interner.intern("kotlin"),
                            interner.intern("Array"),
                        ]
                    }
                    if isSequenceArgument {
                        return parameterInfo.fqName == [
                            interner.intern("kotlin"),
                            interner.intern("sequences"),
                            interner.intern("Sequence"),
                        ]
                    }
                    return parameterInfo.fqName == [
                        interner.intern("kotlin"),
                        interner.intern("collections"),
                        interner.intern("Iterable"),
                    ]
                }
            }
            let memberCandidates: [SymbolID]
            if !arrayConversionSourceCandidates.isEmpty {
                memberCandidates = arrayConversionSourceCandidates
            } else if !mutableMapPutAllSourceCandidates.isEmpty {
                memberCandidates = mutableMapPutAllSourceCandidates
            } else if !primitiveArraySourceCandidates.isEmpty {
                // Primitive-array HOFs are bundled Kotlin extensions. Prefer the
                // exact source receiver over synthetic member stubs, including
                // joinToString(transform), whose legacy stub shares the same name.
                memberCandidates = primitiveArraySourceCandidates
            } else if !rangeSourceCandidates.isEmpty {
                memberCandidates = rangeSourceCandidates
            } else if !atomicSourceCandidates.isEmpty {
                memberCandidates = atomicSourceCandidates
            } else {
                memberCandidates = driver.helpers.collectMemberFunctionCandidates(
                    named: calleeName,
                    receiverType: memberLookupType,
                    sema: sema,
                    allowedOwnerSymbols: allowedOwnerSymbols,
                    interner: interner
                )
            }
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
                    let nonNullReceiverForScope = sema.types.makeNonNullable(memberLookupType)
                    var scopeCandidates = ctx.cachedScopeLookup(calleeName).filter { candidate in
                        guard let symbol = ctx.cachedSymbol(candidate),
                              symbol.kind == .function,
                              let signature = sema.symbols.functionSignature(for: candidate) else { return false }
                        guard let recv = signature.receiverType else { return false }
                        guard extensionSyntheticFallbackReceiverMatches(
                            callSiteReceiver: nonNullReceiverForScope,
                            declaredReceiver: recv,
                            sema: sema
                        ) else { return false }
                        if isSuperCall, !supertypeSymbols.isEmpty {
                            return sema.symbols.parentSymbol(for: candidate).map { supertypeSymbols.contains($0) } ?? false
                        }
                        return true
                    }
                    // Primitive-array HOFs are top-level extensions in
                    // kotlin.collections. Default-import lookup may stop at a
                    // same-named Sequence extension first (notably for
                    // UByteArray/UShortArray), so prefer the exact source
                    // receiver overload when one is present.
                    let primitiveArraySourceCandidates = collectPrimitiveArraySourceHOFs(
                        named: calleeName,
                        receiverType: nonNullReceiverForScope,
                        sema: sema,
                        interner: interner
                    )
                    let arrayConversionSourceCandidates = collectArraySourceConversionCandidates(
                        named: calleeName,
                        receiverType: nonNullReceiverForScope,
                        sema: sema,
                        interner: interner
                    )
                    if !arrayConversionSourceCandidates.isEmpty {
                        scopeCandidates = arrayConversionSourceCandidates
                    } else if !primitiveArraySourceCandidates.isEmpty {
                        scopeCandidates = primitiveArraySourceCandidates
                    }
                    // Extension functions are excluded from scope by the scope
                    // builder so they don't shadow top-level calls.  Fall back
                    // to a direct symbol-table lookup by short name to find
                    // synthetic extension functions (e.g. Double.pow).
                    if scopeCandidates.isEmpty {
                        let nonNullReceiver = sema.types.makeNonNullable(memberLookupType)
                        scopeCandidates = sema.symbols.lookupByShortName(calleeName).filter { candidate in
                            guard let symbol = sema.symbols.symbol(candidate),
                                  symbol.kind == .function,
                                  let signature = sema.symbols.functionSignature(for: candidate),
                                  let recvType = signature.receiverType
                            else { return false }
                            // Include bundled/user Kotlin source extensions, not only
                            // synthetic stubs, so source-backed Sequence transforms
                            // (map, filter, etc.) are visible as member-call candidates.
                            let isSourceBackedExtension = sema.symbols.isSourceBackedSymbol(candidate)
                            guard symbol.flags.contains(.synthetic) || isSourceBackedExtension else {
                                return false
                            }
                            // Exclude property accessor functions (getter/setter)
                            // whose parent is a property symbol.  Their short name
                            // is "get"/"set" and must not pollute member lookup.
                            if let parentID = sema.symbols.parentSymbol(for: candidate),
                               let parentSym = sema.symbols.symbol(parentID),
                               parentSym.kind == .property
                            {
                                return false
                            }
                            return extensionSyntheticFallbackReceiverMatches(
                                callSiteReceiver: nonNullReceiver,
                                declaredReceiver: recvType,
                                sema: sema
                            )
                        }
                    }
                    // Bundled stdlib extensions on flat-representation receivers
                    // (e.g. String.startsWith in kotlin.text) live only in scope,
                    // but a same-named extension declared in the current package
                    // (e.g. File.startsWith) fully shadows them because ordinary
                    // scope lookup stops at the innermost binding. Merge the whole
                    // scope chain and filter by receiver to recover them.
                    if scopeCandidates.isEmpty {
                        let nonNullReceiverForChain = sema.types.makeNonNullable(memberLookupType)
                        scopeCandidates = ctx.scope.lookupMergingChain(calleeName).filter { candidate in
                            guard let symbol = ctx.cachedSymbol(candidate),
                                  symbol.kind == .function,
                                  let signature = sema.symbols.functionSignature(for: candidate),
                                  let recv = signature.receiverType
                            else { return false }
                            if let parentID = sema.symbols.parentSymbol(for: candidate),
                               let parentSym = sema.symbols.symbol(parentID),
                               parentSym.kind == .property
                            {
                                return false
                            }
                            return extensionSyntheticFallbackReceiverMatches(
                                callSiteReceiver: nonNullReceiverForChain,
                                declaredReceiver: recv,
                                sema: sema
                            )
                        }
                    }
                    // Bundled stdlib extension functions are conceptually members
                    // of their receiver type (e.g. AtomicIntArray.loadAt) and must
                    // resolve on member-style calls without an explicit import, the
                    // same way synthetic stubs used to. Ordinary scope lookup only
                    // finds them when imported, so as a final fallback — reached only
                    // when the call would otherwise be unresolved — match bundled
                    // stdlib extensions by receiver type.
                    if scopeCandidates.isEmpty {
                        scopeCandidates = collectBundledStdlibExtensionCandidates(
                            named: calleeName,
                            receiverType: memberLookupType,
                            sema: sema,
                            interner: interner
                        )
                    }
                    allCandidates = scopeCandidates
                }
            }
        }
        // MutableMap.remove(key) has a source-backed projected-key overload in
        // addition to the retained interface member. Prefer the Kotlin source
        // declaration for ordinary MutableMap receiver calls while preserving
        // the synthetic member for interface and lowering bridges.
        if interner.resolve(calleeName) == "remove",
           ReceiverClassifier(sema: sema, interner: interner).isMutableMapType(memberLookupType),
           args.count == 1
        {
            let mutableMapRemoveCandidates = sema.symbols.lookupByShortName(calleeName).filter { candidate in
                guard let candidateSymbol = sema.symbols.symbol(candidate),
                      candidateSymbol.kind == .function,
                      (!candidateSymbol.flags.contains(.synthetic)
                          || sema.symbols.isSourceBackedSymbol(candidate)),
                      let signature = sema.symbols.functionSignature(for: candidate),
                      signature.parameterTypes.count == 1,
                      let receiver = signature.receiverType,
                      let receiverSymbol = driver.helpers.nominalSymbol(of: receiver, types: sema.types),
                      let symbol = sema.symbols.symbol(receiverSymbol)
                else {
                    return false
                }
                return symbol.fqName == [
                    interner.intern("kotlin"),
                    interner.intern("collections"),
                    interner.intern("MutableMap"),
                ]
            }
            if !mutableMapRemoveCandidates.isEmpty {
                allCandidates = mutableMapRemoveCandidates
            }
        }
        // A mutable map has a source-backed iterator overload whose return type
        // is MutableIterator<MutableMap.MutableEntry<K, V>>. If the inherited
        // synthetic collection surface won the initial lookup, prefer the
        // exact bundled extension before ordinary overload resolution.
        if interner.resolve(calleeName) == "iterator",
           ReceiverClassifier(sema: sema, interner: interner).isMutableMapType(memberLookupType)
        {
            let mutableMapIteratorCandidates = sema.symbols.lookupByShortName(calleeName).filter { candidate in
                guard sema.symbols.isSourceBackedSymbol(candidate),
                      let signature = sema.symbols.functionSignature(for: candidate),
                      let receiver = signature.receiverType,
                      let receiverSymbol = driver.helpers.nominalSymbol(of: receiver, types: sema.types),
                      let symbol = sema.symbols.symbol(receiverSymbol)
                else {
                    return false
                }
                return symbol.fqName == [
                    interner.intern("kotlin"),
                    interner.intern("collections"),
                    interner.intern("MutableMap"),
                ]
            }
            if !mutableMapIteratorCandidates.isEmpty {
                allCandidates = mutableMapIteratorCandidates
            }
        }
        // `MutableMap.getValue(key)` is the read-only Map extension. The
        // MutableMap delegated accessor has the same short name but requires
        // `(thisRef, KProperty<*>)`; keep that two-argument delegate surface
        // out of ordinary one-argument member calls.
        if interner.resolve(calleeName) == "getValue",
           ReceiverClassifier(sema: sema, interner: interner).isMutableMapType(memberLookupType),
           args.count == 1
        {
            let mapGetValueCandidates = sema.symbols.lookupByShortName(calleeName).filter { candidate in
                guard let candidateSymbol = sema.symbols.symbol(candidate),
                      candidateSymbol.kind == .function,
                      (!candidateSymbol.flags.contains(.synthetic)
                          || sema.symbols.isSourceBackedSymbol(candidate)),
                      let signature = sema.symbols.functionSignature(for: candidate),
                      signature.parameterTypes.count == 1,
                      let receiver = signature.receiverType,
                      let receiverSymbol = driver.helpers.nominalSymbol(of: receiver, types: sema.types),
                      let symbol = sema.symbols.symbol(receiverSymbol)
                else {
                    return false
                }
                return symbol.fqName == [
                    interner.intern("kotlin"),
                    interner.intern("collections"),
                    interner.intern("Map"),
                ]
            }
            if !mapGetValueCandidates.isEmpty {
                allCandidates = mapGetValueCandidates
            }
        }

        let isNullLiteralReceiver = if case let .nameRef(name, _) = ast.arena.expr(receiverID) {
            name == KnownCompilerNames(interner: interner).null
        } else {
            false
        }

        let isChannelReceiver = isChannelReceiverType(
            lookupReceiverType,
            sema: sema,
            interner: interner
        )
        if !isClassNameReceiver, isChannelReceiver {
            let memberName = interner.resolve(calleeName)
            // KSP-678: close / isClosedForReceive / isClosedForSend are resolved
            // through bundled Kotlin source (Channels.kt) via normal candidate
            // resolution below; only the suspension core send / receive are
            // special-cased here.
            switch (memberName, args.count) {
            case ("send", 1):
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

        // Prefer the concrete kotlin.text String.compareTo overloads over the
        // generic Comparable<T>.compareTo member, which otherwise leaves
        // String.compareTo(String) ambiguous after both surfaces are available.
        if !isClassNameReceiver,
           interner.resolve(calleeName) == "compareTo",
           args.count == 1 || args.count == 2
        {
            let receiverTypeForCheck = safeCall
                ? sema.types.makeNonNullable(lookupReceiverType)
                : lookupReceiverType
            let arg0Type = sema.types.makeNonNullable(argTypes[0])
            let stringArgMatches = sema.types.isSubtype(arg0Type, sema.types.stringType)
            let boolArgMatches = args.count == 1
                || sema.types.isSubtype(sema.types.makeNonNullable(argTypes[1]), sema.types.booleanType)
            if sema.types.isSubtype(receiverTypeForCheck, sema.types.stringType),
               stringArgMatches,
               boolArgMatches
            {
                if let boundType = tryBindSyntheticStringMemberFallback(
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
                let finalType = safeCall
                    ? sema.types.makeNullable(sema.types.intType)
                    : sema.types.intType
                sema.bindings.bindExprType(id, type: finalType)
                return finalType
            }
        }

        let (visible, invisible) = ctx.filterByVisibility(allCandidates)
        var candidates = preferMostSpecificMemberReceiverCandidates(
            visible,
            receiverType: lookupReceiverType,
            argumentTypes: argTypes,
            sema: sema,
            interner: interner
        )
        // Kotlin selects MutableMap.withDefault over the less-specific
        // Map.withDefault extension for a MutableMap receiver. Resolve this
        // subtype preference before trailing-lambda overload inference sees
        // two otherwise identical function shapes.
        if interner.resolve(calleeName) == "withDefault",
           ReceiverClassifier(sema: sema, interner: interner).isMutableMapType(lookupReceiverType)
        {
            let mutableMapCandidates = candidates.filter { candidate in
                guard sema.symbols.isSourceBackedSymbol(candidate),
                      let signature = sema.symbols.functionSignature(for: candidate),
                      let receiver = signature.receiverType,
                      let receiverSymbol = driver.helpers.nominalSymbol(of: receiver, types: sema.types),
                      let symbol = sema.symbols.symbol(receiverSymbol)
                else {
                    return false
                }
                return symbol.fqName == [
                    interner.intern("kotlin"),
                    interner.intern("collections"),
                    interner.intern("MutableMap"),
                ]
            }
            if !mutableMapCandidates.isEmpty {
                candidates = mutableMapCandidates
            }
        }
        if interner.resolve(calleeName) == "coerceIn",
           !args.contains(where: { sema.bindings.isFloatingPointRangeExpr($0.expr) })
        {
            // The generic ClosedFloatingPointRange overload must not turn a
            // scalar call with the wrong arity or argument type into a type
            // constraint failure. Kotlin reports those calls as no overload.
            candidates.removeAll { candidate in
                guard let signature = sema.symbols.functionSignature(for: candidate),
                      signature.typeParameterSymbols.count == 1,
                      signature.parameterTypes.count == 1,
                      let (_, parameterSymbol) = resolveClassTypeSymbol(
                          signature.parameterTypes[0], sema: sema
                      )
                else {
                    return false
                }
                return interner.resolve(parameterSymbol.name) == "ClosedFloatingPointRange"
            }
        }
        if interner.resolve(calleeName) == "coerceIn",
           args.contains(where: { sema.bindings.isFloatingPointRangeExpr($0.expr) })
        {
            // Imported `.kklib` metadata does not make a generic extension whose
            // receiver is a type parameter visible through the receiver-type
            // fallback above. Recover the source-backed range overloads here so
            // the same call resolves with bundled source injection and a library.
            let genericRangeCandidates = sema.symbols.lookupByShortName(calleeName).filter { candidate in
                guard let symbol = sema.symbols.symbol(candidate),
                      symbol.kind == .function,
                      sema.symbols.isSourceBackedSymbol(candidate),
                      let signature = sema.symbols.functionSignature(for: candidate),
                      signature.typeParameterSymbols.count == 1,
                      signature.parameterTypes.count == 1,
                      let (_, parameterSymbol) = resolveClassTypeSymbol(
                          signature.parameterTypes[0], sema: sema
                      )
                else {
                    return false
                }
                let parameterName = interner.resolve(parameterSymbol.name)
                return parameterName == "ClosedFloatingPointRange"
            }
            candidates.append(contentsOf: genericRangeCandidates.filter { !candidates.contains($0) })
        }
        if interner.resolve(calleeName) == "toList" {
            candidates = preferCollectionToListCandidates(
                candidates,
                receiverType: lookupReceiverType,
                sema: sema,
                interner: interner
            )
        }
        if interner.resolve(calleeName) == "take" {
            candidates = preferListTakeCandidates(
                candidates,
                receiverType: lookupReceiverType,
                sema: sema,
                interner: interner
            )
        }
        if interner.resolve(calleeName) == "unzip" {
            candidates = preferListUnzipCandidates(
                candidates,
                receiverType: lookupReceiverType,
                sema: sema,
                interner: interner
            )
        }
        if isNullLiteralReceiver,
           args.isEmpty,
           interner.resolve(calleeName) == "isNullOrEmpty",
           let charSequenceType = syntheticCharSequenceType(sema: sema),
           candidates.contains(where: { candidate in
               sema.symbols.functionSignature(for: candidate)?.receiverType == sema.types.makeNullable(charSequenceType)
           })
        {
            // Kotlin stdlib also provides Array/Collection/Map nullable-receiver
            // isNullOrEmpty overloads. They are still lowered through synthetic
            // typed-receiver fallbacks here, but a bare null receiver must see the
            // same ambiguous overload set as kotlinc.
            ctx.semaCtx.diagnostics.error(
                "KSWIFTK-SEMA-0003",
                "Ambiguous overload resolution.",
                range: range
            )
            sema.bindings.bindExprType(id, type: sema.types.errorType)
            return sema.types.errorType
        }
        if hasLeadingLocaleArgument {
            candidates.removeAll { candidate in
                isSyntheticStringFormatCandidate(candidate, sema: sema, interner: interner)
            }
        }
        if interner.resolve(calleeName) == "trimMargin" {
            let receiverTypeForCheck = safeCall
                ? sema.types.makeNonNullable(lookupReceiverType)
                : lookupReceiverType
            if sema.types.isSubtype(receiverTypeForCheck, sema.types.stringType) {
                if !explicitTypeArgs.isEmpty {
                    ctx.semaCtx.diagnostics.error(
                        "KSWIFTK-SEMA-0002",
                        "No viable overload found for call.",
                        range: range
                    )
                    sema.bindings.bindExprType(id, type: sema.types.errorType)
                    return sema.types.errorType
                }
                let trimMarginFQName = [
                    interner.intern("kotlin"),
                    interner.intern("text"),
                    calleeName,
                ]
                let chosen = sema.symbols.lookupAll(fqName: trimMarginFQName).first(where: { symbolID in
                    guard let signature = sema.symbols.functionSignature(for: symbolID),
                          signature.receiverType == sema.types.stringType
                    else {
                        return false
                    }
                    switch args.count {
                    case 0:
                        return signature.parameterTypes.isEmpty
                    case 1:
                        return signature.parameterTypes.count == 1
                            && sema.types.isSubtype(sema.types.makeNonNullable(argTypes[0]), signature.parameterTypes[0])
                    default:
                        return false
                    }
                })
                if let chosen {
                    let returnType = bindCallAndResolveReturnType(
                        id,
                        chosen: chosen,
                        resolved: ResolvedCall(
                            chosenCallee: chosen,
                            substitutedTypeArguments: [:],
                            parameterMapping: args.isEmpty ? [:] : [0: 0],
                            diagnostic: nil
                        ),
                        sema: sema
                    )
                    let finalType = safeCall ? sema.types.makeNullable(returnType) : returnType
                    sema.bindings.bindExprType(id, type: finalType)
                    return finalType
                }
            }
        }
        if candidates.isEmpty {
            return inferRegularMemberCallWithoutCandidates(
                request,
                receiverType: receiverType,
                lookupReceiverType: lookupReceiverType,
                memberLookupType: memberLookupType,
                argTypes: argTypes,
                isClassNameReceiver: isClassNameReceiver,
                classNameReceiverNominalSymbol: classNameReceiverNominalSymbol,
                isNullLiteralReceiver: isNullLiteralReceiver,
                isFlowReceiver: isFlowReceiver,
                flowElementType: flowElementType,
                hasLeadingLocaleArgument: hasLeadingLocaleArgument,
                invisibleCandidates: invisible,
                locals: &locals
            )
        }

        // Use the companion type as implicit receiver when the candidates were
        // redirected from the owner class to its companion object.
        let effectiveReceiverType = companionReceiverType ?? rangeSourceMemberLookupType ?? lookupReceiverType
        // STDLIB-pipeline §5: take/drop/chunked/windowed have real require()
        // validation in SequenceWindowChunk.kt as of MIGRATION-SEQ-005. When
        // normal candidate lookup already resolved one of these names to that
        // source declaration, the synthetic collection-member fallback below
        // must not discard it — Kotlin-source candidates take priority over
        // the synthetic shortcut so chosenCallee binds to the real
        // declaration and its require() executes.
        //
        // Excludes calls with a trailing HOF lambda (chunked(size) { ... },
        // windowed(size, step) { ... }): tryCollectionMemberFallback below
        // derives the transform overload's result element type from the
        // lambda body's inferred return type (see
        // CallTypeChecker+CollectionMemberFallback.swift), which the generic
        // overload resolver cannot reproduce and fails with conflicting type
        // variable bounds. Those overloads keep going through the synthetic
        // fallback and their require() bypass is tracked separately.
        let hasTrailingLambdaArg = args.last.map { ast.arena.expr($0.expr)?.isLambdaOrCallableRef ?? false } ?? false
        // STDLIB-pipeline §5 / KSP-441: Source-backed Sequence transforms
        // (map, filter, etc.) must bind to the real Kotlin declaration so the
        // object-expression pipeline runs instead of a `kk_*` runtime shortcut.
        let sourceBackedCollectionMemberNames: Set<String> = ["take", "drop", "chunked", "windowed", "asSequence", "constrainOnce", "orEmpty", "distinct", "flatten", "filterNotNull", "withIndex", "toList", "toMutableList", "toSet", "toMutableSet", "toHashSet", "toSortedSet", "toCollection", "toMap", "unzip", "union", "intersect", "subtract", "plus", "plusElement", "minus", "minusElement", "average", "sliceArray", "reversedArray", "asList", "toTypedArray"]
        let sourceBackedTrailingLambdaMemberNames: Set<String> = ["map", "filter", "filterNot", "mapIndexed", "mapNotNull", "filterIndexed", "onEach", "onEachIndexed", "ifEmpty", "flatMap", "flatMapIndexed", "joinTo", "joinToString", "isNotEmpty"]
        let memberNameText = interner.resolve(calleeName)
        let isMutableMapIteratorSource = memberNameText == "iterator"
            && ReceiverClassifier(sema: sema, interner: interner).isMutableMapType(memberLookupType)
        // KSP-687 resolves Array.joinToString through the dedicated primitive
        // and generic-array source candidates. KSP-429's broad trailing-lambda
        // gate is for List/Iterable source calls; applying it to Array receivers
        // prevents the array resolver from binding the source overload.
        let isArrayJoinToString = memberNameText == "joinToString"
            && isArrayLikeReceiver(receiverID: receiverID, sema: sema, interner: interner)
        let isSourceBackedMemberName = sourceBackedCollectionMemberNames.contains(memberNameText)
            || (sourceBackedTrailingLambdaMemberNames.contains(memberNameText) && !isArrayJoinToString)
            || isMutableMapIteratorSource
        let hasSourceBackedCandidate = isSourceBackedMemberName
            && (!sourceBackedCollectionMemberNames.contains(memberNameText) || !hasTrailingLambdaArg)
            && candidates.contains { candidateID in
                sema.symbols.isSourceBackedSymbol(candidateID)
            }
        // Synthetic collection members need to short-circuit before the generic
        // overload resolver so their trailing-lambda expectations stay concrete.
        if !hasSourceBackedCandidate, let fallbackType = tryCollectionMemberFallback(
            id,
            calleeName: calleeName,
            isClassNameReceiver: isClassNameReceiver,
            safeCall: safeCall,
            receiverID: receiverID,
            args: args,
            ctx: ctx,
            expectedType: expectedType,
            locals: &locals
        ) {
            return fallbackType
        }
        if let fallbackType = tryBindThreadLocalGetOrSetFallback(
            id,
            calleeName: calleeName,
            safeCall: safeCall,
            receiverType: lookupReceiverType,
            args: args,
            ctx: ctx,
            locals: &locals
        ) {
            return fallbackType
        }
        if let fallbackType = tryBindComparatorMemberFallback(
            id,
            calleeName: calleeName,
            safeCall: safeCall,
            receiverType: lookupReceiverType,
            args: args,
            ctx: ctx,
            locals: &locals
        ) {
            return fallbackType
        }
        var cachedNonLambdaArgTypes: [Int: TypeID] = [:]
        for (index, argument) in args.enumerated() {
            guard let argumentExpr = ast.arena.expr(argument.expr) else {
                continue
            }
            switch argumentExpr {
            case .lambdaLiteral, .callableRef:
                continue
            default:
                cachedNonLambdaArgTypes[index] = argTypes[index]
            }
        }
        let preparedArgs = prepareCallArguments(
            args: args,
            candidates: candidates,
            preInferredNonLambdaArgTypes: cachedNonLambdaArgTypes,
            explicitTypeArgs: explicitTypeArgs,
            receiverType: effectiveReceiverType,
            ctx: ctx,
            locals: &locals
        )
        let resolved = resolveCallRespectingLambdaReturnType(
            candidates: candidates,
            args: args,
            argTypes: preparedArgs.argTypes,
            range: range,
            calleeName: calleeName,
            explicitTypeArgs: explicitTypeArgs,
            expectedType: expectedType,
            implicitReceiverType: effectiveReceiverType,
            lambdaLiteralIndices: preparedArgs.lambdaLiteralIndices,
            inputOnlyLambdaIndices: preparedArgs.inputOnlyLambdaIndices,
            blockedLambdaRefinement: preparedArgs.blockedLambdaRefinement,
            hasUnresolvableImplicitLambdaParameter: preparedArgs.hasUnresolvableImplicitLambdaParameter,
            ctx: ctx
        )
        if let diagnostic = resolved.diagnostic {
            if diagnostic.code == "KSWIFTK-SEMA-BOUND" {
                let callee = interner.resolve(calleeName)
                if callee == "sorted" || callee == "sortedDescending" {
                    ctx.semaCtx.diagnostics.emit(diagnostic)
                    return driver.helpers.bindAndReturnErrorType(id, sema: sema)
                }
            }
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
            if let projectionDiagnostic = makeProjectionViolationDiagnostic(
                candidates: candidates,
                receiverType: lookupReceiverType,
                calleeName: calleeName,
                range: range,
                sema: sema,
                interner: interner
            ) {
                ctx.semaCtx.diagnostics.emit(projectionDiagnostic)
                return driver.helpers.bindAndReturnErrorType(id, sema: sema)
            }
            if let fallbackType = tryRegexMemberFallback(
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
            if let fallbackType = tryKFunctionMemberFallback(
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
            if let fallbackType = tryStringMemberFallback(
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
            if let fallbackType = tryPathCharsetReadExtensionFallback(
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
            if let fallbackType = tryNativePlacementAllocExtensionFallback(
                id,
                calleeName: calleeName,
                isClassNameReceiver: isClassNameReceiver,
                safeCall: safeCall,
                receiverID: receiverID,
                args: args,
                explicitTypeArgs: explicitTypeArgs,
                ctx: ctx
            ) {
                return fallbackType
            }
            if let fallbackType = tryNativeCInteropReadValueExtensionFallback(
                id,
                calleeName: calleeName,
                isClassNameReceiver: isClassNameReceiver,
                safeCall: safeCall,
                receiverID: receiverID,
                args: args,
                ctx: ctx
            ) {
                return fallbackType
            }
            if let fallbackType = tryFileMemberFallback(
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
            if let fallbackType = tryArrayMemberFallback(
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
            if let fallbackType = tryRangeMemberFallback(
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
            if let projectionDiagnostic = makeProjectionViolationDiagnostic(
                candidates: candidates,
                receiverType: lookupReceiverType,
                calleeName: calleeName,
                range: range,
                sema: sema,
                interner: interner
            ) {
                ctx.semaCtx.diagnostics.emit(projectionDiagnostic)
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
                expectedType: expectedType,
                locals: &locals
            ) {
                return fallbackType
            }
            if let fallbackType = tryRegexMemberFallback(
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
            if let fallbackType = tryKFunctionMemberFallback(
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
            if let fallbackType = tryStringMemberFallback(
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
            if let fallbackType = tryFileMemberFallback(
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
            if let fallbackType = tryArrayMemberFallback(
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
            if let fallbackType = tryRangeMemberFallback(
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
        driver.helpers.checkOptIn(
            for: chosen,
            ctx: ctx,
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
                let paramType = sema.types.displayName(
                    of: signature.parameterTypes[violatingParamIndex],
                    symbols: sema.symbols,
                    interner: interner
                )
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
        // `Deferred.await()` resolves here as a normal candidate (the synthetic
        // member declared in HeaderHelpers+SyntheticCoroutineRegistry.swift), whose
        // signature hardcodes `Any` since `Deferred` has no class-level type
        // parameter. Narrow it using the element type tracked by
        // `coroutineBuilderNarrowedReturnType` for the `async {}` call that
        // produced this receiver.
        let adjustedReturnType: TypeID = if sema.symbols.externalLinkName(for: chosen) == "kk_kxmini_async_await" {
            deferredAwaitResultType(receiverID: receiverID, fallback: returnType, ast: ast, sema: sema)
        } else {
            returnType
        }
        if isSuperCall { sema.bindings.markSuperCall(id) }
        let finalType = safeCall ? sema.types.makeNullable(adjustedReturnType) : adjustedReturnType
        sema.bindings.bindExprType(id, type: finalType)
        return finalType
    }

    private func floatingPointRangeArgumentType(
        _ exprID: ExprID,
        ast: ASTModule,
        sema: SemaModule,
        interner: StringInterner
    ) -> TypeID? {
        guard sema.bindings.isFloatingPointRangeExpr(exprID),
              let rangeSymbol = sema.symbols.lookup(fqName: [
                  interner.intern("kotlin"),
                  interner.intern("ranges"),
                  interner.intern("ClosedFloatingPointRange"),
              ])
        else {
            return nil
        }
        let elementType: TypeID = if let elementType = sema.bindings.floatingPointRangeElementType(forExpr: exprID) {
            elementType
        } else if case let .binary(_, lhs, rhs, _) = ast.arena.expr(exprID),
                  sema.bindings.exprType(for: lhs) == sema.types.floatType
                      || sema.bindings.exprType(for: rhs) == sema.types.floatType
        {
            sema.types.floatType
        } else {
            sema.types.doubleType
        }
        return sema.types.make(.classType(ClassType(
            classSymbol: rangeSymbol,
            args: [.invariant(elementType)],
            nullability: .nonNull
        )))
    }

    /// Whether `receiverType`'s nominal owner is one of the atomic stdlib classes
    /// whose bundled `*At`/alias source is the live implementation. Gates the
    /// importless bundled-extension member fallback so it never surfaces the
    /// dead-mirror bundled sources of other stdlib families.
    private func isAtomicMigrationReceiver(
        _ receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        let nonNull = sema.types.makeNonNullable(receiverType)
        guard let owner = driver.helpers.nominalSymbol(of: nonNull, types: sema.types),
              let symbol = sema.symbols.symbol(owner)
        else {
            return false
        }
        let fqName = symbol.fqName.map { interner.resolve($0) }.joined(separator: ".")
        switch fqName {
        case "kotlin.concurrent.atomics.AtomicInt",
             "kotlin.concurrent.atomics.AtomicLong",
             "kotlin.concurrent.atomics.AtomicBoolean",
             "kotlin.concurrent.atomics.AtomicReference",
             "kotlin.concurrent.atomics.AtomicIntArray",
             "kotlin.concurrent.atomics.AtomicLongArray",
             "kotlin.concurrent.AtomicInt",
             "kotlin.concurrent.AtomicLong",
             "kotlin.concurrent.AtomicBoolean",
             "kotlin.concurrent.AtomicReference",
             "kotlin.concurrent.AtomicIntArray",
             "kotlin.concurrent.AtomicLongArray":
            return true
        default:
            return false
        }
    }

    /// Finds bundled stdlib extension functions named `calleeName` whose receiver
    /// matches `receiverType`. Bundled stdlib extensions (e.g. the atomic-array
    /// `loadAt`/`storeAt` migration source) are conceptually members and should be
    /// callable without an explicit import, but ordinary scope lookup only exposes
    /// them when imported. This is used as a final member-call resolution fallback,
    /// so it only affects calls that would otherwise be unresolved. Membership is
    /// gated by `sema.bundledIndex` so user-declared extensions are never surfaced
    /// here without import.
    func collectBundledStdlibExtensionCandidates(
        named calleeName: InternedString,
        receiverType: TypeID,
        requireOperator: Bool = false,
        sema: SemaModule,
        interner: StringInterner
    ) -> [SymbolID] {
        // This importless-member fallback exists only for the atomic stdlib
        // migration (KSP-672 and the scalar alias mirror): those bundled sources
        // are the live implementation and their synthetic stubs are intentionally
        // skipped. Other bundled stdlib sources (collection/sequence/text HOFs)
        // are dead mirrors whose canonical lowering goes through runtime helpers,
        // so surfacing them here would wrongly pre-empt that path.
        guard isAtomicMigrationReceiver(receiverType, sema: sema, interner: interner) else {
            return []
        }
        let nonNullReceiver = sema.types.makeNonNullable(receiverType)
        return sema.symbols.lookupByShortName(calleeName).filter { candidate in
            guard let symbol = sema.symbols.symbol(candidate),
                  symbol.kind == .function,
                  let signature = sema.symbols.functionSignature(for: candidate),
                  let declaredReceiver = signature.receiverType
            else {
                return false
            }
            // Source-backed bundled stdlib extensions are not synthetic; imported
            // stdlib artifact symbols are synthetic + importedLibrary and should
            // still be considered here so shared-path code can resolve them.
            if symbol.flags.contains(.synthetic), !symbol.flags.contains(.importedLibrary) {
                return false
            }
            if requireOperator, !symbol.flags.contains(.operatorFunction) {
                return false
            }
            // Property accessor functions share the short names get/set; their
            // parent is a property symbol and must not pollute member lookup.
            if let parentID = sema.symbols.parentSymbol(for: candidate),
               let parentSym = sema.symbols.symbol(parentID),
               parentSym.kind == .property
            {
                return false
            }
            guard let key = BundledDeclarationIndex.memberKey(
                for: symbol,
                symbolID: candidate,
                symbols: sema.symbols,
                types: sema.types,
                interner: interner
            ), sema.bundledIndex.contains(key)
            else {
                return false
            }
            return extensionSyntheticFallbackReceiverMatches(
                callSiteReceiver: nonNullReceiver,
                declaredReceiver: declaredReceiver,
                sema: sema
            )
        }
    }

    private func isBundledRangeSourceMember(
        _ calleeName: InternedString,
        interner: StringInterner
    ) -> Bool {
        switch interner.resolve(calleeName) {
        case "contains", "isEmpty", "iterator",
             "toList", "forEach", "map", "mapIndexed", "mapNotNull",
             "filter", "filterIndexed", "filterNot",
             "take", "drop", "sorted", "average", "random", "randomOrNull":
            return true
        default:
            return false
        }
    }

    func sourceLevelRangeMemberLookupType(
        receiverExpr: ExprID,
        receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> TypeID? {
        guard let rangeKind = sourceLevelRangeMemberReceiverKind(
            receiverExpr: receiverExpr,
            receiverType: receiverType,
            sema: sema,
            interner: interner
        ) else {
            return nil
        }

        let typeName: String
        switch rangeKind {
        case .intRange:
            typeName = "IntRange"
        case .longRange:
            typeName = "LongRange"
        case .charRange:
            typeName = "CharRange"
        case .uintRange:
            typeName = "UIntRange"
        case .ulongRange:
            typeName = "ULongRange"
        case .intProgression:
            typeName = "IntProgression"
        case .longProgression:
            typeName = "LongProgression"
        case .charProgression:
            typeName = "CharProgression"
        case .uintProgression:
            typeName = "UIntProgression"
        case .ulongProgression:
            typeName = "ULongProgression"
        case .iterable, .list, .set, .collection, .map, .sequence, .string, .charSequence:
            return nil
        }

        guard let symbol = sema.symbols.lookup(fqName: [
            interner.intern("kotlin"),
            interner.intern("ranges"),
            interner.intern(typeName),
        ]) else {
            return nil
        }
        return sema.types.make(.classType(ClassType(
            classSymbol: symbol,
            args: [],
            nullability: .nonNull
        )))
    }

    private func sourceLevelRangeMemberReceiverKind(
        receiverExpr: ExprID,
        receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> MemberDispatchReceiverKind? {
        let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
        if let (_, symbol) = resolveClassTypeSymbol(nonNullReceiverType, sema: sema) {
            switch interner.resolve(symbol.name) {
            case "IntRange":
                return .intRange
            case "LongRange":
                return .longRange
            case "CharRange":
                return .charRange
            case "UIntRange":
                return .uintRange
            case "ULongRange":
                return .ulongRange
            case "IntProgression":
                return .intProgression
            case "LongProgression":
                return .longProgression
            case "CharProgression":
                return .charProgression
            case "UIntProgression":
                return .uintProgression
            case "ULongProgression":
                return .ulongProgression
            default:
                return nil
            }
        }

        guard sema.bindings.isRangeExpr(receiverExpr) else {
            return nil
        }
        if sema.bindings.isFloatingPointRangeExpr(receiverExpr) {
            return nil
        }
        if sema.bindings.isCharRangeExpr(receiverExpr) {
            return .charRange
        }
        if sema.bindings.isULongRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.ulongType {
            return .ulongRange
        }
        if sema.bindings.isUIntRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.uintType {
            return .uintRange
        }
        if nonNullReceiverType == sema.types.longType {
            return .longRange
        }
        if nonNullReceiverType == sema.types.intType {
            return .intRange
        }
        return nil
    }

    private func collectRangeSourceExtensionCandidates(
        named calleeName: InternedString,
        receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> [SymbolID] {
        let rangesFQName = [
            interner.intern("kotlin"),
            interner.intern("ranges"),
        ]
        guard let rangesPackageSymbol = sema.symbols.lookup(fqName: rangesFQName) else {
            return []
        }
        let nonNullReceiver = sema.types.makeNonNullable(receiverType)
        return sema.symbols.lookupAll(fqName: rangesFQName + [calleeName])
            .filter { candidate in
                guard let symbol = sema.symbols.symbol(candidate),
                      symbol.kind == .function,
                      !symbol.flags.contains(.synthetic),
                      sema.symbols.parentSymbol(for: candidate) == rangesPackageSymbol,
                      let signature = sema.symbols.functionSignature(for: candidate),
                      let declaredReceiver = signature.receiverType
                else {
                    return false
                }
                return extensionSyntheticFallbackReceiverMatches(
                    callSiteReceiver: nonNullReceiver,
                    declaredReceiver: declaredReceiver,
                    sema: sema
                )
            }
            .sorted { $0.rawValue < $1.rawValue }
    }

    /// The CAS-loop update operators migrated to bundled Kotlin source
    /// (`AtomicMigration.kt`).  Like the range-source members these live as
    /// package-scoped extension functions in `kotlin.concurrent`, so they must
    /// be recovered by an explicit source lookup rather than ordinary
    /// member-call resolution.
    private func isBundledAtomicSourceMember(
        _ calleeName: InternedString,
        interner: StringInterner
    ) -> Bool {
        switch interner.resolve(calleeName) {
        case "compareAndExchange", "getAndUpdate", "updateAndGet", "fetchAndUpdate", "updateAndFetch",
             "fetchAndUpdateAt", "updateAt", "updateAndFetchAt", "compareAndSet":
            return true
        default:
            return false
        }
    }

    /// True when `receiverType` is one of the atomic box types whose CAS-loop
    /// update operators are provided by bundled Kotlin source.
    private func isBundledAtomicSourceReceiver(
        _ receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        guard let nominal = driver.helpers.nominalSymbol(of: sema.types.makeNonNullable(receiverType), types: sema.types),
              let symbol = sema.symbols.symbol(nominal)
        else {
            return false
        }
        let fqName = symbol.fqName
        guard fqName.count >= 2 else { return false }
        let name = interner.resolve(fqName[fqName.count - 1])
        switch name {
        case "AtomicInt", "AtomicLong", "AtomicBoolean", "AtomicReference",
             "AtomicArray", "AtomicIntArray", "AtomicLongArray", "AtomicInteger":
            return true
        default:
            return false
        }
    }

    /// Recover bundled `kotlin.concurrent` extension functions (the migrated CAS
    /// loops in `AtomicMigration.kt`) as member candidates for atomic receivers.
    private func collectAtomicSourceExtensionCandidates(
        named calleeName: InternedString,
        receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> [SymbolID] {
        let kotlin = interner.intern("kotlin")
        let concurrent = interner.intern("concurrent")
        let atomics = interner.intern("atomics")
        let packageFQNames: [[InternedString]] = [
            [kotlin, concurrent],
            [kotlin, concurrent, atomics],
        ]
        let nonNullReceiver = sema.types.makeNonNullable(receiverType)
        var candidates: [SymbolID] = []
        for packageFQName in packageFQNames {
            let memberFQName = packageFQName + [calleeName]
            candidates.append(contentsOf: sema.symbols.lookupAll(fqName: memberFQName)
                .filter { candidate in
                    // Top-level bundled extension functions declared directly in
                    // the package (identified by their exact FQ name so class
                    // members with the same short name are excluded). The
                    // package symbol identity cannot be used because synthetic
                    // atomic stubs create a distinct package symbol from the one
                    // owning the bundled source declarations.
                    guard let symbol = sema.symbols.symbol(candidate),
                          symbol.kind == .function,
                          !symbol.flags.contains(.synthetic),
                          symbol.fqName == memberFQName,
                          let signature = sema.symbols.functionSignature(for: candidate),
                          let declaredReceiver = signature.receiverType
                    else {
                        return false
                    }
                    return extensionSyntheticFallbackReceiverMatches(
                        callSiteReceiver: nonNullReceiver,
                        declaredReceiver: declaredReceiver,
                        sema: sema
                    )
                })
        }
        return candidates.sorted { $0.rawValue < $1.rawValue }
    }
}
// swiftlint:enable cyclomatic_complexity file_length function_body_length

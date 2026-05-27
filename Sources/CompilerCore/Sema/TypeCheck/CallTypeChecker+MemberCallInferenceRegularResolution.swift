// swiftlint:disable file_length function_body_length cyclomatic_complexity
import Foundation

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
        let argTypes = args.enumerated().map { _, arg -> TypeID in
            if let expr = ast.arena.expr(arg.expr) {
                switch expr {
                case .lambdaLiteral, .callableRef:
                    return sema.bindings.exprType(for: arg.expr) ?? sema.types.anyType
                default:
                    break
                }
            }
            return sema.bindings.exprType(for: arg.expr) ?? driver.inferExpr(arg.expr, ctx: ctx, locals: &locals)
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
        var qualifiedSuperType: SymbolID? = nil
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

        if !isClassNameReceiver,
           args.isEmpty,
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

        let allCandidates: [SymbolID]
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
            let allowedOwnerSymbols = isSuperCall && !supertypeSymbols.isEmpty ?
                (qualifiedSuperType != nil ? [qualifiedSuperType!] : supertypeSymbols) : nil
            let memberCandidates = driver.helpers.collectMemberFunctionCandidates(
                named: calleeName,
                receiverType: memberLookupType,
                sema: sema,
                allowedOwnerSymbols: allowedOwnerSymbols,
                interner: interner
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
                    // Extension functions are excluded from scope by the scope
                    // builder so they don't shadow top-level calls.  Fall back
                    // to a direct symbol-table lookup by short name to find
                    // synthetic extension functions (e.g. Double.pow, roundToInt).
                    if scopeCandidates.isEmpty {
                        let nonNullReceiver = sema.types.makeNonNullable(memberLookupType)
                        scopeCandidates = sema.symbols.lookupByShortName(calleeName).filter { candidate in
                            guard let symbol = sema.symbols.symbol(candidate),
                                  symbol.kind == .function,
                                  symbol.flags.contains(.synthetic),
                                  let signature = sema.symbols.functionSignature(for: candidate),
                                  let recvType = signature.receiverType
                            else { return false }
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
                    allCandidates = scopeCandidates
                }
            }
        }
        if allCandidates.isEmpty,
           let boundType = tryBindSyntheticBigIntegerMemberFallback(
               id,
               calleeName: calleeName,
               receiverType: memberLookupType,
               args: args,
               argTypes: argTypes,
               range: range,
               ctx: ctx,
               expectedType: expectedType,
               explicitTypeArgs: explicitTypeArgs,
               safeCall: safeCall
           )
        {
            return boundType
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
            case ("isClosedForReceive", 0), ("isClosedForSend", 0):
                let resultType = sema.types.booleanType
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
        var candidates = visible
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
        let effectiveReceiverType = companionReceiverType ?? lookupReceiverType
        // Synthetic collection members need to short-circuit before the generic
        // overload resolver so their trailing-lambda expectations stay concrete.
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
        if let fallbackType = tryBindMapGetOrElseFallback(
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
        if let fallbackType = tryBindMapWithDefaultFallback(
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
        if let fallbackType = tryBindReadWriteLockReadFallback(
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
                ctx: ctx,
                locals: &locals
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
}

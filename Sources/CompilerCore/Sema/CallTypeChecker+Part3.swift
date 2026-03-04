import Foundation

// Handles call expression type inference (function calls, member calls, safe member calls).
// Derived from TypeCheckSemaPhase+InferCallsAndBinary.swift.

extension CallTypeChecker {
    // swiftlint:disable:next cyclomatic_complexity function_body_length
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

        // ── T::class.simpleName / T::class.qualifiedName ──────────────
        // Detect member access on a class-reference expression (callableRef
        // with member "class").  The result type is nullable String.
        // We eagerly infer the receiver so classRefTargetType gets bound,
        // then verify it was actually set (guards against `x::class` where
        // x is a local variable rather than a type name).
        if case let .callableRef(_, refMember, _) = ast.arena.expr(receiverID),
           interner.resolve(refMember) == "class"
        { // swiftlint:disable:this opening_brace
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
        // Defer inference of lambda arguments for collection HOFs so that the
        // contextual function type (and thus implicit `it`) is available.
        let collectionHOFNames: Set<String> = ["map", "filter", "forEach", "flatMap", "any", "none", "all"]
        let isCollectionHOF = collectionHOFNames.contains(interner.resolve(calleeName))
            && sema.bindings.isCollectionExpr(receiverID)
        let argTypes = args.map { arg -> TypeID in
            if isCollectionHOF,
               let argExpr = ast.arena.expr(arg.expr),
               case .lambdaLiteral = argExpr
            { // swiftlint:disable:this opening_brace
                return sema.types.anyType // placeholder; re-inferred later with expected type
            }
            return driver.inferExpr(arg.expr, ctx: ctx, locals: &locals)
        }
        let lookupReceiverType = safeCall ? sema.types.makeNonNullable(receiverType) : receiverType
        // Primitive member function: Int/Long/UInt/ULong.inv() → same type (P5-103, TYPE-005)
        if interner.resolve(calleeName) == "inv",
           args.isEmpty {
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
                   isIntegerRhs {
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
                   rhsType == intType {
                    // shift amount must be Int; receiver can be Int/Long/UInt/ULong
                    let finalType = safeCall ? sema.types.makeNullable(receiverForCheck) : receiverForCheck
                    sema.bindings.bindExprType(id, type: finalType)
                    return finalType
                }
            default:
                break
            }
        }

        // Stdlib infix function: Any.to(Any) → Pair (represented as Any) (FUNC-002)
        if interner.resolve(calleeName) == "to",
           args.count == 1 {
            _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals)
            let resultType = sema.types.anyType
            let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
            sema.bindings.bindExprType(id, type: finalType)
            return finalType
        }

        // Primitive member function: Int/Long.toString(radix: Int) → String (EXPR-003)
        if interner.resolve(calleeName) == "toString",
           args.count == 1 {
            let intType = sema.types.make(.primitive(.int, .nonNull))
            let longType = sema.types.make(.primitive(.long, .nonNull))
            let stringType = sema.types.make(.primitive(.string, .nonNull))
            let receiverForCheck = safeCall
                ? sema.types.makeNonNullable(lookupReceiverType)
                : lookupReceiverType
            if receiverForCheck == intType || receiverForCheck == longType,
               argTypes[0] == intType {
                let finalType = safeCall ? sema.types.makeNullable(stringType) : stringType
                sema.bindings.bindExprType(id, type: finalType)
                return finalType
            }
        }

        // Primitive conversion: toInt(), toUInt(), toLong(), toULong() (TYPE-005)
        if args.isEmpty {
            let intType = sema.types.make(.primitive(.int, .nonNull))
            let longType = sema.types.make(.primitive(.long, .nonNull))
            let uintType = sema.types.make(.primitive(.uint, .nonNull))
            let ulongType = sema.types.make(.primitive(.ulong, .nonNull))
            let receiverForCheck = safeCall
                ? sema.types.makeNonNullable(lookupReceiverType)
                : lookupReceiverType
            let calleeStr = interner.resolve(calleeName)
            let (targetType, matches): (TypeID, Bool) = switch calleeStr {
            case "toInt": (intType, receiverForCheck == uintType || receiverForCheck == ulongType || receiverForCheck == intType || receiverForCheck == longType)
            case "toUInt": (uintType, receiverForCheck == intType || receiverForCheck == longType || receiverForCheck == uintType || receiverForCheck == ulongType)
            case "toLong": (longType, receiverForCheck == intType || receiverForCheck == uintType || receiverForCheck == longType || receiverForCheck == ulongType)
            case "toULong": (ulongType, receiverForCheck == intType || receiverForCheck == longType || receiverForCheck == uintType || receiverForCheck == ulongType)
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
            // swiftlint:disable:next opening_brace
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
            guard let receiverSymbolID = sema.bindings.identifierSymbol(for: receiverID),
                  let receiverSymbol = sema.symbols.symbol(receiverSymbolID)
            else {
                return nil
            }
            switch receiverSymbol.kind {
            case .class, .interface, .enumClass:
                return receiverSymbolID
            default:
                return nil
            }
        }()
        let isClassNameReceiver = classNameReceiverNominalSymbol != nil

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
            // swiftlint:disable:next opening_brace
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
                    // swiftlint:disable:next opening_brace
                    {
                        // Check visibility before returning the property.
                        if let propSym = sema.symbols.symbol(propSymbol),
                           !ctx.visibilityChecker.isAccessible(
                               propSym,
                               fromFile: ctx.currentFileID,
                               enclosingClass: ctx.enclosingClassSymbol
                           )
                        // swiftlint:disable:next opening_brace
                        {
                            // swiftlint:disable:next line_length
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
            if isClassNameReceiver,
               args.isEmpty,
               let classNameReceiverNominalSymbol,
               let staticMember = resolveClassNameMemberValue(
                   ownerNominalSymbol: classNameReceiverNominalSymbol,
                   memberName: calleeName,
                   sema: sema
               ) {
                if let memberSymbol = sema.symbols.symbol(staticMember.symbol),
                   !ctx.visibilityChecker.isAccessible(
                       memberSymbol,
                       fromFile: ctx.currentFileID,
                       enclosingClass: ctx.enclosingClassSymbol
                   ) {
                    // swiftlint:disable:next line_length
                    driver.helpers.emitVisibilityError(for: memberSymbol, name: interner.resolve(calleeName), range: range, diagnostics: ctx.semaCtx.diagnostics)
                    return driver.helpers.bindAndReturnErrorType(id, sema: sema)
                }
                sema.bindings.bindIdentifier(id, symbol: staticMember.symbol)
                sema.bindings.bindExprType(id, type: staticMember.type)
                return staticMember.type
            }
            if args.isEmpty,
               interner.resolve(calleeName) == "length" {
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
            // swiftlint:disable:next opening_brace
            {
                // Check visibility before trying callable-style resolution.
                if let propSymbol = sema.symbols.symbol(propResult.symbol),
                   // swiftlint:disable:next line_length
                   !ctx.visibilityChecker.isAccessible(propSymbol, fromFile: ctx.currentFileID, enclosingClass: ctx.enclosingClassSymbol)
                // swiftlint:disable:next opening_brace
                {
                    // swiftlint:disable:next line_length
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
                        // swiftlint:disable:next line_length
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
            // swiftlint:disable:next opening_brace
            {
                // Check visibility before returning the property.
                if let propSymbol = sema.symbols.symbol(propResult.symbol),
                   !ctx.visibilityChecker.isAccessible(
                       propSymbol,
                       fromFile: ctx.currentFileID,
                       enclosingClass: ctx.enclosingClassSymbol
                   )
                // swiftlint:disable:next opening_brace
                {
                    // swiftlint:disable:next line_length
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
            // swiftlint:disable:next opening_brace
            {
                let finalType = safeCall ? sema.types.makeNullable(extensionPropertyType) : extensionPropertyType
                sema.bindings.bindExprType(id, type: finalType)
                return finalType
            }
            if lookupReceiverType == sema.types.errorType {
                return driver.helpers.bindAndReturnErrorType(id, sema: sema)
            }
            if let firstInvisible = invisible.first {
                // swiftlint:disable:next line_length
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
                    "count", "iterator",
                    "map", "filter", "forEach", "flatMap",
                    "any", "none", "all",
                    "asSequence", "toList", "take" // swiftlint:disable:this trailing_comma
                ]
                if collectionMembers.contains(memberName) {
                    let resultType: TypeID = switch memberName {
                    case "size", "count", "indexOf":
                        sema.types.make(.primitive(.int, .nonNull))
                    case "isEmpty", "contains", "containsKey",
                         "any", "none", "all":
                        sema.types.make(.primitive(.boolean, .nonNull))
                    case "forEach":
                        sema.types.unitType
                    case "asSequence", "toList", "take",
                         "map", "filter", "flatMap":
                        sema.types.anyType
                    default:
                        sema.types.anyType
                    }
                    // For higher-order collection functions, provide contextual
                    // function type for the trailing lambda argument so that Sema
                    // can infer the implicit `it` parameter type.
                    if ["map", "filter", "forEach", "flatMap", "any", "none", "all"].contains(memberName),
                       args.count == 1
                    { // swiftlint:disable:this opening_brace
                        let lambdaReturnType: TypeID = switch memberName {
                        case "filter", "any", "none", "all":
                            sema.types.make(.primitive(.boolean, .nonNull))
                        default:
                            sema.types.anyType
                        }
                        let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                            params: [sema.types.anyType],
                            returnType: lambdaReturnType,
                            isSuspend: false,
                            nullability: .nonNull
                        )))
                        // Re-infer the lambda argument with the contextual function type.
                        _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
                    }
                    sema.bindings.markCollectionExpr(id)
                    let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
                    sema.bindings.bindExprType(id, type: finalType)
                    return finalType
                }
            }
            let isCoroutineHandleReceiver = if case .primitive = sema.types.kind(of: lookupReceiverType) {
                false
            } else {
                true
            }
            if !isClassNameReceiver, args.isEmpty, isCoroutineHandleReceiver {
                let memberName = interner.resolve(calleeName)
                switch memberName {
                case "cancel":
                    let resultType = sema.types.unitType
                    let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
                    sema.bindings.bindExprType(id, type: finalType)
                    return finalType
                case "join", "await":
                    let resultType = sema.types.nullableAnyType
                    let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
                    sema.bindings.bindExprType(id, type: finalType)
                    return finalType
                default:
                    break
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
            ctx.semaCtx.diagnostics.error("KSWIFTK-SEMA-0024", "Unresolved member function '\(interner.resolve(calleeName))'.", range: range)
            return driver.helpers.bindAndReturnErrorType(id, sema: sema)
        }
        // P5-112: Prohibit super.foo() calls to abstract members.
        if isSuperCall,
           let chosenSym = sema.symbols.symbol(chosen),
           chosenSym.flags.contains(.abstractType),
           chosenSym.kind == .function || chosenSym.kind == .property {
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
        // swiftlint:disable:next opening_brace
        {
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

    private func resolveClassNameMemberValue(
        ownerNominalSymbol: SymbolID,
        memberName: InternedString,
        sema: SemaModule
    ) -> (symbol: SymbolID, type: TypeID)? {
        guard let owner = sema.symbols.symbol(ownerNominalSymbol) else {
            return nil
        }
        let memberFQName = owner.fqName + [memberName]
        let candidates = sema.symbols.lookupAll(fqName: memberFQName).sorted(by: { $0.rawValue < $1.rawValue })
        for candidate in candidates {
            guard let candidateSymbol = sema.symbols.symbol(candidate) else {
                continue
            }
            switch candidateSymbol.kind {
            case .field:
                if let fieldType = sema.symbols.propertyType(for: candidate) {
                    return (candidate, fieldType)
                }
            case .object:
                let objectType = sema.types.make(.classType(ClassType(
                    classSymbol: candidate,
                    args: [],
                    nullability: .nonNull
                )))
                return (candidate, objectType)
            default:
                continue
            }
        }
        return nil
    }

    private func makeProjectionViolationDiagnostic(
        candidates: [SymbolID],
        receiverType: TypeID,
        calleeName: InternedString,
        range: SourceRange,
        sema: SemaModule,
        interner: StringInterner
    ) -> Diagnostic? {
        var firstViolatedParamType: TypeID?
        var hasProjectionCompatibleCandidate = false

        for candidate in candidates {
            guard let signature = sema.symbols.functionSignature(for: candidate),
                  let varianceResult = sema.types.buildVarianceProjectionSubstitutions(
                      receiverType: receiverType,
                      signature: signature,
                      symbols: sema.symbols
                  )
            else {
                continue
            }

            if let violatingParamIndex = sema.types.checkVarianceViolationInParameters(
                signature: signature,
                writeForbiddenSymbols: varianceResult.writeForbiddenSymbols
            ) {
                if firstViolatedParamType == nil {
                    firstViolatedParamType = signature.parameterTypes[violatingParamIndex]
                }
            } else {
                hasProjectionCompatibleCandidate = true
            }
        }

        guard !hasProjectionCompatibleCandidate,
              let violatingParamType = firstViolatedParamType
        else {
            return nil
        }

        let renderedParamType = sema.types.renderType(violatingParamType)
        return Diagnostic(
            severity: .error,
            code: "KSWIFTK-SEMA-VAR-OUT",
            message: "A type projection on the receiver prevents calling '\(interner.resolve(calleeName))' because the type parameter appears in an 'in' position (parameter type '\(renderedParamType)').",
            primaryRange: range,
            secondaryRanges: []
        )
    }

    private func resolveExtensionPropertyGetter(
        id: ExprID,
        calleeName: InternedString,
        range: SourceRange,
        receiverType: TypeID,
        expectedType: TypeID?,
        ctx: TypeInferenceContext
    ) -> TypeID? {
        let sema = ctx.sema
        let visible = ctx.filterByVisibility(ctx.cachedScopeLookup(calleeName)).visible
        var getterCandidates: [SymbolID] = []
        for candidate in visible {
            guard let symbol = sema.symbols.symbol(candidate),
                  symbol.kind == .property,
                  sema.symbols.extensionPropertyReceiverType(for: candidate) != nil,
                  let getterAccessor = sema.symbols.extensionPropertyGetterAccessor(for: candidate)
            else {
                continue
            }
            getterCandidates.append(getterAccessor)
        }
        guard !getterCandidates.isEmpty else {
            return nil
        }

        let resolved = ctx.resolver.resolveCall(
            candidates: getterCandidates,
            call: CallExpr(
                range: range,
                calleeName: calleeName,
                args: []
            ),
            expectedType: expectedType,
            implicitReceiverType: receiverType,
            ctx: ctx.semaCtx
        )
        if let diagnostic = resolved.diagnostic {
            ctx.semaCtx.diagnostics.emit(diagnostic)
            return nil
        }
        guard let chosen = resolved.chosenCallee else {
            return nil
        }

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
        if let ownerProperty = sema.symbols.accessorOwnerProperty(for: chosen) {
            sema.bindings.bindIdentifier(id, symbol: ownerProperty)
        }
        guard let signature = sema.symbols.functionSignature(for: chosen) else {
            return sema.types.anyType
        }
        let typeVarBySymbol = sema.types.makeTypeVarBySymbol(signature.typeParameterSymbols)
        return sema.types.substituteTypeParameters(
            in: signature.returnType,
            substitution: resolved.substitutedTypeArguments,
            typeVarBySymbol: typeVarBySymbol
        )
    }
    // swiftlint:disable:next file_length
}

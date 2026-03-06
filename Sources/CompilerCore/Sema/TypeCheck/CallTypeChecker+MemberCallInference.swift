import Foundation

// Handles call expression type inference (function calls, member calls, safe member calls).
// Derived from TypeCheckSemaPhase+InferCallsAndBinary.swift.
// File splitting is still in progress for this legacy entry point.
// swiftlint:disable file_length

extension CallTypeChecker {
    // This legacy inference path still owns many special cases while the split-out helpers
    // are being migrated. Keep lint focused on the new behavior touched by this change.
    // swiftlint:disable function_body_length cyclomatic_complexity
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
            "map", "filter", "forEach", "flatMap", "any", "none", "all",
            "fold", "reduce", "groupBy", "sortedBy", "count", "first", "last", "find",
        ]
        let flowHOFNames: Set = ["map", "filter", "collect"]
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
        let isFlowHOF = isFlowReceiver && flowHOFNames.contains(interner.resolve(calleeName))
        let isCollectionHOF = collectionHOFNames.contains(interner.resolve(calleeName))
            && sema.bindings.isCollectionExpr(receiverID)
        let argTypes = args.map { arg -> TypeID in
            if isCollectionHOF || isFlowHOF,
               let argExpr = ast.arena.expr(arg.expr),
               case .lambdaLiteral = argExpr
            {
                return sema.types.anyType // placeholder; re-inferred later with expected type
            }
            return driver.inferExpr(arg.expr, ctx: ctx, locals: &locals)
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

        // Stdlib infix function: Any.to(Any) → Pair (represented as Any) (FUNC-002)
        if interner.resolve(calleeName) == "to",
           args.count == 1
        {
            _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals)
            let resultType = sema.types.anyType
            let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
            sema.bindings.bindExprType(id, type: finalType)
            return finalType
        }

        // Primitive member function: Int/Long.toString(radix: Int) → String (EXPR-003)
        if interner.resolve(calleeName) == "toString",
           args.count == 1
        {
            let intType = sema.types.make(.primitive(.int, .nonNull))
            let longType = sema.types.make(.primitive(.long, .nonNull))
            let stringType = sema.types.make(.primitive(.string, .nonNull))
            let receiverForCheck = safeCall
                ? sema.types.makeNonNullable(lookupReceiverType)
                : lookupReceiverType
            if receiverForCheck == intType || receiverForCheck == longType,
               argTypes[0] == intType
            {
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
            if args.isEmpty {
                let receiverTypeForCheck = safeCall
                    ? sema.types.makeNonNullable(lookupReceiverType)
                    : lookupReceiverType
                if sema.types.isSubtype(receiverTypeForCheck, sema.types.stringType) {
                    let calleeStr = interner.resolve(calleeName)
                    let resultType: TypeID? = switch calleeStr {
                    case "trim":
                        sema.types.stringType
                    case "toInt":
                        sema.types.intType
                    case "toDouble":
                        sema.types.make(.primitive(.double, .nonNull))
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
            // String stdlib: format(vararg args) (STDLIB-006)
            if interner.resolve(calleeName) == "format", !hasLeadingLocaleArgument {
                let receiverTypeForCheck = safeCall
                    ? sema.types.makeNonNullable(lookupReceiverType)
                    : lookupReceiverType
                if sema.types.isSubtype(receiverTypeForCheck, sema.types.stringType) {
                    let finalType = safeCall ? sema.types.makeNullable(sema.types.stringType) : sema.types.stringType
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
                            params: [sema.types.anyType],
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
                        }
                        let resultType: TypeID = memberName == "collect"
                            ? sema.types.unitType
                            : sema.types.nullableAnyType
                        let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
                        sema.bindings.bindExprType(id, type: finalType)
                        return finalType
                    }
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
        // P5-112: Prohibit super.foo() calls to abstract members.
        if isSuperCall,
           let chosenSym = sema.symbols.symbol(chosen),
           chosenSym.flags.contains(.abstractType),
           chosenSym.kind == .function || chosenSym.kind == .property
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
    // swiftlint:enable function_body_length cyclomatic_complexity

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
}

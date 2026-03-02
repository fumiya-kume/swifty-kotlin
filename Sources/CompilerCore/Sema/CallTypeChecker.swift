import Foundation

/// Handles call expression type inference (function calls, member calls, safe member calls).
/// Derived from TypeCheckSemaPass+InferCallsAndBinary.swift.
final class CallTypeChecker { // swiftlint:disable:this type_body_length
    unowned let driver: TypeCheckDriver

    init(driver: TypeCheckDriver) {
        self.driver = driver
    }

    // swiftlint:disable:next cyclomatic_complexity function_body_length
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
        let calleeName: InternedString? = if case let .nameRef(name, _) = calleeExpr {
            name
        } else {
            nil
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
                   let classSymbol = ctx.cachedSymbol(classSym)
                {
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
           let local = locals[calleeName]
        {
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
        } else if let calleeName {
            if !ctx.cachedScopeLookup(calleeName).isEmpty {
                callableCalleeType = driver.inferExpr(
                    calleeID,
                    ctx: ctx,
                    locals: &locals,
                    expectedType: nil
                )
                callableTarget = driver.helpers.callableTargetForCalleeExpr(calleeID, sema: sema)
            }
        } else if calleeName == nil {
            let contextualCalleeType: TypeID?
            if let calleeExpr {
                switch calleeExpr {
                case .lambdaLiteral, .callableRef:
                    let contextualReturnType = expectedType ?? sema.types.anyType
                    contextualCalleeType = sema.types.make(.functionType(FunctionType(
                        params: argTypes,
                        returnType: contextualReturnType,
                        isSuspend: false,
                        nullability: .nonNull
                    )))
                default:
                    contextualCalleeType = nil
                }
            } else {
                contextualCalleeType = nil
            }
            callableCalleeType = driver.inferExpr(
                calleeID,
                ctx: ctx,
                locals: &locals,
                expectedType: contextualCalleeType
            )
            callableTarget = driver.helpers.callableTargetForCalleeExpr(calleeID, sema: sema)
        }

        if callableCalleeType == sema.types.errorType {
            sema.bindings.bindExprType(id, type: sema.types.errorType)
            return sema.types.errorType
        }

        if let callableCalleeType,
           let result = inferCallableValueInvocation(
               id, calleeType: callableCalleeType, callableTarget: callableTarget,
               args: args, argTypes: argTypes, range: range, ctx: ctx, expectedType: expectedType
           )
        {
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
           args.count <= 1
        {
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
                // Prefer the expected type from context (e.g. a type annotation
                // on the receiving variable) so that `val list: List<String?> =
                // listOf(...)` propagates the full generic type.
                // Only use expectedType if it is a generic ClassType (i.e. a
                // collection type like List<String?>), not a primitive or
                // unrelated type like Int.
                let collectionType: TypeID
                if let expectedType, expectedType != sema.types.errorType,
                   case let .classType(expectedClassType) = sema.types.kind(of: expectedType),
                   !expectedClassType.args.isEmpty
                {
                    collectionType = expectedType
                } else if !argTypes.isEmpty {
                    // Infer element type from arguments via LUB so that
                    // `listOf("a", null)` produces a nullable element type.
                    // Wrap the element type in List<E> if the synthetic
                    // List interface symbol is available, otherwise fall
                    // back to anyType.
                    let elementType = sema.types.lub(argTypes)
                    let listFQName: [InternedString] = [
                        interner.intern("kotlin"),
                        interner.intern("collections"),
                        interner.intern("List"),
                    ]
                    if let listSymbol = sema.symbols.lookup(fqName: listFQName) {
                        collectionType = sema.types.make(.classType(ClassType(
                            classSymbol: listSymbol,
                            args: [.invariant(elementType)],
                            nullability: .nonNull
                        )))
                    } else {
                        collectionType = sema.types.anyType
                    }
                } else {
                    collectionType = sema.types.anyType
                }
                sema.bindings.bindExprType(id, type: collectionType)
                return collectionType
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
}

// swiftlint:disable file_length
import Foundation

// swiftlint:disable type_body_length
/// Handles call expression type inference (function calls, member calls, safe member calls).
final class CallTypeChecker {
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

        let calleeExpr = ast.arena.expr(calleeID)
        let calleeName: InternedString? = if case let .nameRef(name, _) = calleeExpr {
            name
        } else {
            nil
        }
        // --- Builder DSL functions (STDLIB-002) ---
        // Must intercept BEFORE eager arg inference so the lambda argument
        // is inferred with the correct implicit receiver type.
        if let calleeName, args.count == 1 {
            let name = interner.resolve(calleeName)
            if let builderKind = builderDSLKind(for: name),
               shouldUseBuilderDSLSpecialHandling(calleeName: calleeName, ctx: ctx, locals: locals)
            {
                let argumentExprID = args[0].expr
                guard isValidBuilderLambdaArgument(argumentExprID, ast: ast) else {
                    ctx.semaCtx.diagnostics.error(
                        "KSWIFTK-SEMA-0002",
                        "No viable overload found for call.",
                        range: range
                    )
                    sema.bindings.bindExprType(id, type: sema.types.errorType)
                    return sema.types.errorType
                }

                let receiverType = builderDSLReceiverType(kind: builderKind, sema: sema, interner: interner)
                let returnType: TypeID = switch builderKind {
                case .buildString:
                    sema.types.stringType
                case .buildList, .buildMap:
                    sema.types.anyType
                }
                // Infer the lambda argument with the builder receiver as implicit `this`.
                var builderCtx = ctx.with(implicitReceiverType: receiverType)
                builderCtx.isBuilderLambdaScope = true
                builderCtx.builderKind = builderKind
                _ = driver.inferExpr(argumentExprID, ctx: builderCtx, locals: &locals)
                sema.bindings.markBuilderDSLExpr(id, kind: builderKind)
                sema.bindings.markCollectionExpr(id)
                sema.bindings.bindExprType(id, type: returnType)
                return returnType
            }
        }

        // --- Scope function: with(receiver, block) (STDLIB-004) ---
        // Must intercept BEFORE eager arg inference so the lambda argument
        // is inferred with the correct implicit receiver type.
        // Only intercept when no user-defined function named `with` is in scope.
        if let calleeName, args.count == 2,
           interner.resolve(calleeName) == "with",
           ctx.cachedScopeLookup(calleeName).isEmpty
        {
            // First arg is the receiver object
            let withReceiverType = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals)
            // Second arg is the lambda with receiver
            let receiverCtx = ctx.with(implicitReceiverType: withReceiverType)
            let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                receiver: withReceiverType,
                params: [],
                returnType: expectedType ?? sema.types.anyType
            )))
            let lambdaType = driver.inferExpr(
                args[1].expr, ctx: receiverCtx, locals: &locals,
                expectedType: lambdaExpectedType
            )
            let returnType: TypeID = if case let .functionType(fnType) = sema.types.kind(of: lambdaType) {
                fnType.returnType
            } else {
                sema.bindings.exprTypes[args[1].expr].flatMap { typeID in
                    if case let .functionType(fnType) = sema.types.kind(of: typeID) {
                        return fnType.returnType
                    }
                    return nil
                } ?? sema.types.anyType
            }
            sema.bindings.markScopeFunctionExpr(id, kind: .scopeWith)
            sema.bindings.bindExprType(id, type: returnType)
            return returnType
        }

        // --- Flow builder function (CORO-003) ---
        // `flow { emit(...) }` is treated as a builtin cold stream factory.
        // We infer the lambda with a flow-builder scope so unqualified `emit`
        // resolves in Sema fallback.
        if let calleeName,
           interner.resolve(calleeName) == "flow",
           args.count == 1,
           shouldUseBuiltinFlowFactorySpecialHandling(calleeName: calleeName, ctx: ctx, locals: locals)
        {
            let flowLambdaExprID = args[0].expr
            guard isValidBuilderLambdaArgument(flowLambdaExprID, ast: ast) else {
                ctx.semaCtx.diagnostics.error(
                    "KSWIFTK-SEMA-0002",
                    "No viable overload found for call.",
                    range: range
                )
                sema.bindings.bindExprType(id, type: sema.types.errorType)
                return sema.types.errorType
            }
            var flowBuilderCtx = ctx.with(implicitReceiverType: sema.types.anyType)
            flowBuilderCtx.isFlowBuilderLambdaScope = true
            let flowLambdaExpectedType = sema.types.make(.functionType(FunctionType(
                params: [],
                returnType: sema.types.unitType,
                isSuspend: true,
                nullability: .nonNull
            )))
            _ = driver.inferExpr(
                flowLambdaExprID,
                ctx: flowBuilderCtx,
                locals: &locals,
                expectedType: flowLambdaExpectedType
            )
            sema.bindings.markFlowExpr(id)
            if let explicitElementType = explicitTypeArgs.first {
                sema.bindings.bindFlowElementType(explicitElementType, forExpr: id)
            } else if let expectedType,
                      case let .classType(classType) = sema.types.kind(of: expectedType),
                      let firstArg = classType.args.first
            {
                switch firstArg {
                case let .invariant(type), let .in(type), let .out(type):
                    sema.bindings.bindFlowElementType(type, forExpr: id)
                case .star:
                    break
                }
            }
            sema.bindings.bindExprType(id, type: sema.types.anyType)
            return sema.types.anyType
        }

        // --- Flow builder lambda calls (CORO-003) ---
        // Inside `flow { ... }`, unqualified `emit` resolves as a builtin
        // effect call and returns Unit.
        if ctx.isFlowBuilderLambdaScope,
           let calleeName,
           interner.resolve(calleeName) == "emit",
           args.count == 1,
           ctx.cachedScopeLookup(calleeName).isEmpty,
           locals[calleeName] == nil
        {
            _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals)
            sema.bindings.bindExprType(id, type: sema.types.unitType)
            return sema.types.unitType
        }

        // --- Stdlib repeat(times) { ... } (STDLIB-008) ---
        // Infer the lambda argument with the expected `(Int) -> Unit` type so
        // implicit `it` resolves to the loop index.
        if let calleeName,
           interner.resolve(calleeName) == "repeat",
           args.count == 2,
           shouldUseRepeatSpecialHandling(calleeName: calleeName, locals: locals)
        {
            let intType = sema.types.intType
            let unitType = sema.types.unitType
            let countType = driver.inferExpr(
                args[0].expr,
                ctx: ctx,
                locals: &locals,
                expectedType: intType
            )
            driver.emitSubtypeConstraint(
                left: countType,
                right: intType,
                range: ast.arena.exprRange(args[0].expr) ?? range,
                solver: ConstraintSolver(),
                sema: sema,
                diagnostics: ctx.semaCtx.diagnostics
            )
            let actionExpectedType = sema.types.make(.functionType(FunctionType(
                params: [intType],
                returnType: unitType
            )))
            _ = driver.inferExpr(
                args[1].expr,
                ctx: ctx,
                locals: &locals,
                expectedType: actionExpectedType
            )
            sema.bindings.markStdlibSpecialCallExpr(id, kind: .repeatLoop)
            sema.bindings.bindExprType(id, type: unitType)
            return unitType
        }

        if let calleeName,
           args.count == 2,
           let specialKind = comparisonSpecialCallKind(for: calleeName, ctx: ctx, locals: locals)
        {
            let intType = sema.types.intType
            let lhsType = driver.inferExpr(
                args[0].expr,
                ctx: ctx,
                locals: &locals,
                expectedType: intType
            )
            let rhsType = driver.inferExpr(
                args[1].expr,
                ctx: ctx,
                locals: &locals,
                expectedType: intType
            )
            driver.emitSubtypeConstraint(
                left: lhsType,
                right: intType,
                range: ast.arena.exprRange(args[0].expr) ?? range,
                solver: ConstraintSolver(),
                sema: sema,
                diagnostics: ctx.semaCtx.diagnostics
            )
            driver.emitSubtypeConstraint(
                left: rhsType,
                right: intType,
                range: ast.arena.exprRange(args[1].expr) ?? range,
                solver: ConstraintSolver(),
                sema: sema,
                diagnostics: ctx.semaCtx.diagnostics
            )
            if let chosen = ctx.filterByVisibility(ctx.cachedScopeLookup(calleeName)).visible.first(where: { candidate in
                guard let signature = sema.symbols.functionSignature(for: candidate) else {
                    return false
                }
                return signature.parameterTypes == [intType, intType] && signature.returnType == intType
            }) {
                sema.bindings.bindCall(
                    id,
                    binding: CallBinding(
                        chosenCallee: chosen,
                        substitutedTypeArguments: [],
                        parameterMapping: [0: 0, 1: 1]
                    )
                )
                sema.bindings.bindCallableTarget(id, target: .symbol(chosen))
            }
            sema.bindings.markStdlibSpecialCallExpr(id, kind: specialKind)
            sema.bindings.bindExprType(id, type: intType)
            return intType
        }

        if let calleeName,
           interner.resolve(calleeName) == "contract",
           args.count == 1
        {
            let builderSymbol = sema.symbols.lookup(fqName: [
                interner.intern("kotlin"),
                interner.intern("contracts"),
                interner.intern("ContractBuilder"),
            ])
            let builderType = builderSymbol.map {
                sema.types.make(.classType(ClassType(classSymbol: $0, args: [], nullability: .nonNull)))
            } ?? sema.types.anyType
            let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                receiver: builderType,
                params: [],
                returnType: sema.types.unitType
            )))
            _ = driver.inferExpr(
                args[0].expr,
                ctx: ctx.with(implicitReceiverType: builderType),
                locals: &locals,
                expectedType: lambdaExpectedType
            )
            sema.bindings.bindExprType(id, type: sema.types.unitType)
            return sema.types.unitType
        }

        if let calleeName,
           interner.resolve(calleeName) == "Channel",
           args.isEmpty
        {
            let visibleCandidates = ctx.cachedScopeLookup(calleeName)
            let channelSymbol = visibleCandidates.first { candidate in
                guard let symbol = sema.symbols.symbol(candidate),
                      symbol.kind == .function
                else {
                    return false
                }
                return sema.symbols.externalLinkName(for: candidate) == "kk_channel_create"
            } ?? visibleCandidates.compactMap { candidate -> SymbolID? in
                guard let symbol = sema.symbols.symbol(candidate),
                      symbol.kind == .class,
                      sema.symbols.externalLinkName(for: candidate) == nil
                else {
                    return nil
                }
                let ctorFQName = symbol.fqName + [interner.intern("<init>")]
                return sema.symbols.lookupAll(fqName: ctorFQName).first { ctorID in
                    sema.symbols.externalLinkName(for: ctorID) == "kk_channel_create"
                }
            }.first
            if let channelSymbol {
                sema.bindings.bindCall(
                    id,
                    binding: CallBinding(
                        chosenCallee: channelSymbol,
                        substitutedTypeArguments: explicitTypeArgs,
                        parameterMapping: [:]
                    )
                )
                sema.bindings.bindCallableTarget(id, target: .symbol(channelSymbol))
                let resultType: TypeID = if let explicitTypeArg = explicitTypeArgs.first,
                                            let signature = sema.symbols.functionSignature(for: channelSymbol),
                                            case let .classType(classType) = sema.types.kind(of: signature.returnType)
                {
                    sema.types.make(.classType(ClassType(
                        classSymbol: classType.classSymbol,
                        args: [.invariant(explicitTypeArg)],
                        nullability: classType.nullability
                    )))
                } else {
                    sema.symbols.functionSignature(for: channelSymbol)?.returnType ?? sema.types.anyType
                }
                sema.bindings.bindExprType(id, type: resultType)
                return resultType
            }
        }

        if let calleeName,
           interner.resolve(calleeName) == "delay",
           args.count == 1
        {
            let delayArgType = driver.inferExpr(
                args[0].expr,
                ctx: ctx,
                locals: &locals,
                expectedType: sema.types.longType
            )
            if delayArgType == sema.types.intType,
               let argumentExpr = ast.arena.expr(args[0].expr),
               case .intLiteral = argumentExpr
            {
                sema.bindings.bindExprType(args[0].expr, type: sema.types.longType)
            } else {
                driver.emitSubtypeConstraint(
                    left: delayArgType,
                    right: sema.types.longType,
                    range: ast.arena.exprRange(args[0].expr) ?? range,
                    solver: ConstraintSolver(),
                    sema: sema,
                    diagnostics: ctx.semaCtx.diagnostics
                )
            }
            sema.bindings.bindExprType(id, type: sema.types.unitType)
            return sema.types.unitType
        }

        let coroutineLauncherName = calleeName.map { interner.resolve($0) }
        let coroutineLauncherExpectedLambdaType: TypeID?
        if let coroutineLauncherName,
           ["runBlocking", "launch", "async", "coroutineScope"].contains(coroutineLauncherName),
           let firstArg = args.first,
           let firstArgExpr = ast.arena.expr(firstArg.expr),
           case .lambdaLiteral = firstArgExpr
        {
            let lambdaReturnType: TypeID = switch coroutineLauncherName {
            case "launch":
                sema.types.unitType
            default:
                expectedType ?? sema.types.anyType
            }
            coroutineLauncherExpectedLambdaType = sema.types.make(.functionType(FunctionType(
                params: [],
                returnType: lambdaReturnType,
                isSuspend: true,
                nullability: .nonNull
            )))
        } else {
            coroutineLauncherExpectedLambdaType = nil
        }
        let withContextExpectedLambdaType: TypeID? = if let calleeName,
                                                        interner.resolve(calleeName) == "withContext",
                                                        args.count >= 2,
                                                        let secondArgExpr = ast.arena.expr(args[1].expr),
                                                        case .lambdaLiteral = secondArgExpr
        {
            sema.types.make(.functionType(FunctionType(
                params: [],
                returnType: expectedType ?? sema.types.anyType,
                isSuspend: true,
                nullability: .nonNull
            )))
        } else {
            nil
        }

        if let calleeName,
           let samCallType = inferSamConvertedCallExpr(
               id,
               calleeName: calleeName,
               args: args,
               range: range,
               ctx: ctx,
               locals: &locals,
               expectedType: expectedType,
               explicitTypeArgs: explicitTypeArgs
           )
        {
            sema.bindings.bindExprType(id, type: samCallType)
            return samCallType
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
                if let classSym = classSymbols.first, let classSymbol = ctx.cachedSymbol(classSym) {
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
        let contextualArgExpectedTypes: [TypeID?] = if candidates.count == 1,
                                                       let signature = sema.symbols.functionSignature(for: candidates[0])
        {
            args.enumerated().map { index, argument in
                if index == 0, let coroutineLauncherExpectedLambdaType {
                    return coroutineLauncherExpectedLambdaType
                }
                if index == 1, let withContextExpectedLambdaType {
                    return withContextExpectedLambdaType
                }
                guard index < signature.parameterTypes.count else {
                    return nil
                }
                let parameterType = signature.parameterTypes[index]
                if case .lambdaLiteral = ast.arena.expr(argument.expr) {
                    return parameterType
                }
                return nil
            }
        } else {
            args.indices.map { index in
                if index == 0, let coroutineLauncherExpectedLambdaType {
                    return coroutineLauncherExpectedLambdaType
                }
                if index == 1, let withContextExpectedLambdaType {
                    return withContextExpectedLambdaType
                }
                return nil
            }
        }
        let argTypes = args.enumerated().map { index, argument in
            if let contextualExpectedType = contextualArgExpectedTypes[index] {
                return driver.inferExpr(
                    argument.expr,
                    ctx: ctx,
                    locals: &locals,
                    expectedType: contextualExpectedType
                )
            }
            return driver.inferExpr(argument.expr, ctx: ctx, locals: &locals)
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
            // ANNO-001: Check for @Deprecated annotation on the resolved callee.
            driver.helpers.checkDeprecation(
                for: chosen,
                sema: sema,
                interner: interner,
                range: range,
                diagnostics: ctx.semaCtx.diagnostics
            )
            let returnType = bindCallAndResolveReturnType(id, chosen: chosen, resolved: resolved, sema: sema)
            applyContractEffects(
                chosen: chosen,
                args: args,
                argTypes: argTypes,
                ctx: ctx,
                locals: &locals
            )
            if let calleeName {
                switch interner.resolve(calleeName) {
                case "listOf", "mutableListOf", "emptyList",
                     "arrayOf", "intArrayOf", "longArrayOf",
                     "mapOf", "mutableMapOf", "emptyMap",
                     "setOf", "mutableSetOf", "emptySet",
                     "listOfNotNull":
                    sema.bindings.markCollectionExpr(id)
                default:
                    break
                }
            }
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
                    applyContractEffects(
                        chosen: chosen,
                        args: args,
                        argTypes: argTypes,
                        ctx: ctx,
                        locals: &locals
                    )
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
        // Builder DSL member functions (STDLIB-002).
        // Inside builder lambdas, unqualified `append`/`add`/`put` resolve as
        // implicit-receiver member calls that return Unit.
        if let calleeName, ctx.isBuilderLambdaScope, let activeBuilderKind = ctx.builderKind {
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
                } else if let explicitTypeArg = explicitTypeArgs.first,
                          name == "emptyList"
                {
                    collectionType = makeSyntheticListType(
                        symbols: sema.symbols,
                        types: sema.types,
                        interner: interner,
                        elementType: explicitTypeArg
                    )
                } else if let explicitTypeArg = explicitTypeArgs.first,
                          name == "mutableListOf"
                {
                    collectionType = makeSyntheticMutableListType(
                        symbols: sema.symbols,
                        types: sema.types,
                        interner: interner,
                        elementType: explicitTypeArg
                    )
                } else if !argTypes.isEmpty,
                          name == "listOf" || name == "listOfNotNull" || name == "emptyList" || name == "mutableListOf"
                {
                    // Infer element type from arguments via LUB so that
                    // `listOf("a", null)` produces List<String?>.
                    let elementType = sema.types.lub(argTypes)
                    collectionType = if name == "mutableListOf" {
                        makeSyntheticMutableListType(
                            symbols: sema.symbols,
                            types: sema.types,
                            interner: interner,
                            elementType: elementType
                        )
                    } else {
                        makeSyntheticListType(
                            symbols: sema.symbols,
                            types: sema.types,
                            interner: interner,
                            elementType: elementType
                        )
                    }
                } else if let explicitTypeArg = explicitTypeArgs.first,
                          name == "emptySet" || name == "setOf"
                {
                    collectionType = makeSyntheticSetType(
                        symbols: sema.symbols,
                        types: sema.types,
                        interner: interner,
                        elementType: explicitTypeArg
                    )
                } else if let explicitTypeArg = explicitTypeArgs.first,
                          name == "mutableSetOf"
                {
                    collectionType = makeSyntheticMutableSetType(
                        symbols: sema.symbols,
                        types: sema.types,
                        interner: interner,
                        elementType: explicitTypeArg
                    )
                } else if !argTypes.isEmpty,
                          name == "setOf" || name == "emptySet" || name == "mutableSetOf"
                {
                    let elementType = sema.types.lub(argTypes)
                    collectionType = if name == "mutableSetOf" {
                        makeSyntheticMutableSetType(
                            symbols: sema.symbols,
                            types: sema.types,
                            interner: interner,
                            elementType: elementType
                        )
                    } else {
                        makeSyntheticSetType(
                            symbols: sema.symbols,
                            types: sema.types,
                            interner: interner,
                            elementType: elementType
                        )
                    }
                } else if let expectedType, expectedType != sema.types.errorType,
                          case let .classType(expectedClassType) = sema.types.kind(of: expectedType),
                          expectedClassType.args.count == 2,
                          name == "mapOf" || name == "mutableMapOf" || name == "emptyMap"
                {
                    collectionType = expectedType
                } else if explicitTypeArgs.count == 2,
                          name == "mapOf" || name == "emptyMap"
                {
                    collectionType = makeSyntheticMapType(
                        symbols: sema.symbols,
                        types: sema.types,
                        interner: interner,
                        keyType: explicitTypeArgs[0],
                        valueType: explicitTypeArgs[1]
                    )
                } else if explicitTypeArgs.count == 2,
                          name == "mutableMapOf"
                {
                    collectionType = makeSyntheticMutableMapType(
                        symbols: sema.symbols,
                        types: sema.types,
                        interner: interner,
                        keyType: explicitTypeArgs[0],
                        valueType: explicitTypeArgs[1]
                    )
                } else if let inferredMapTypes = inferSyntheticMapKeyValueTypes(
                    from: args,
                    ctx: ctx,
                    locals: &locals
                ),
                    name == "mapOf" || name == "mutableMapOf"
                {
                    collectionType = if name == "mutableMapOf" {
                        makeSyntheticMutableMapType(
                            symbols: sema.symbols,
                            types: sema.types,
                            interner: interner,
                            keyType: inferredMapTypes.keyType,
                            valueType: inferredMapTypes.valueType
                        )
                    } else {
                        makeSyntheticMapType(
                            symbols: sema.symbols,
                            types: sema.types,
                            interner: interner,
                            keyType: inferredMapTypes.keyType,
                            valueType: inferredMapTypes.valueType
                        )
                    }
                } else if name == "mapOf" || name == "emptyMap" || name == "mutableMapOf" {
                    collectionType = if name == "mutableMapOf" {
                        makeSyntheticMutableMapType(
                            symbols: sema.symbols,
                            types: sema.types,
                            interner: interner,
                            keyType: sema.types.anyType,
                            valueType: sema.types.anyType
                        )
                    } else {
                        makeSyntheticMapType(
                            symbols: sema.symbols,
                            types: sema.types,
                            interner: interner,
                            keyType: sema.types.anyType,
                            valueType: sema.types.anyType
                        )
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
        // STDLIB-004: Inside receiver lambdas (run/apply/with), unqualified
        // function calls resolve as member calls on the implicit receiver.
        if let calleeName, let receiverType = ctx.implicitReceiverType {
            let nonNullReceiver = sema.types.makeNonNullable(receiverType)
            let name = interner.resolve(calleeName)

            // String stdlib methods (STDLIB-006) via implicit receiver
            if sema.types.isSubtype(nonNullReceiver, sema.types.stringType) {
                let listCharType = makeSyntheticListType(
                    symbols: sema.symbols,
                    types: sema.types,
                    interner: interner,
                    elementType: sema.types.make(.primitive(.char, .nonNull))
                )
                var stringResultType: TypeID?
                if args.isEmpty {
                    stringResultType = switch name {
                    case "trim": sema.types.stringType
                    case "uppercase": sema.types.stringType
                    case "lowercase": sema.types.stringType
                    case "toInt": sema.types.intType
                    case "toIntOrNull": sema.types.make(.primitive(.int, .nullable))
                    case "toDouble": sema.types.make(.primitive(.double, .nonNull))
                    case "toDoubleOrNull": sema.types.make(.primitive(.double, .nullable))
                    case "indexOf", "lastIndexOf": sema.types.intType
                    case "reversed": sema.types.stringType
                    case "toList", "toCharArray": listCharType
                    default: nil
                    }
                } else if args.count == 1 {
                    stringResultType = switch name {
                    case "startsWith", "endsWith", "contains":
                        sema.types.make(.primitive(.boolean, .nonNull))
                    case "split": sema.types.anyType
                    case "repeat", "drop", "take", "takeLast", "dropLast":
                        sema.types.stringType
                    default: nil
                    }
                } else if args.count == 2, name == "replace" {
                    stringResultType = sema.types.stringType
                }
                if let resultType = stringResultType {
                    sema.bindings.bindExprType(id, type: resultType)
                    return resultType
                }
            }

            // General member function lookup via implicit receiver
            let memberCandidates = driver.helpers.collectMemberFunctionCandidates(
                named: calleeName,
                receiverType: nonNullReceiver,
                sema: sema
            )
            if let bestCandidate = memberCandidates.first,
               let sig = sema.symbols.functionSignature(for: bestCandidate)
            {
                // Eagerly infer argument types
                for arg in args {
                    _ = driver.inferExpr(arg.expr, ctx: ctx, locals: &locals)
                }
                sema.bindings.bindIdentifier(id, symbol: bestCandidate)
                let resultType = sig.returnType
                sema.bindings.bindExprType(id, type: resultType)
                return resultType
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

    private func makeSyntheticListType(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        elementType: TypeID
    ) -> TypeID {
        let listFQName: [InternedString] = [
            interner.intern("kotlin"),
            interner.intern("collections"),
            interner.intern("List"),
        ]
        guard let listSymbol = symbols.lookup(fqName: listFQName) else {
            return types.anyType
        }
        return types.make(.classType(ClassType(
            classSymbol: listSymbol,
            args: [.out(elementType)],
            nullability: .nonNull
        )))
    }

    private func inferSyntheticMapKeyValueTypes(
        from args: [CallArgument],
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) -> (keyType: TypeID, valueType: TypeID)? {
        let sema = ctx.sema
        let interner = ctx.interner
        let ast = ctx.ast
        var keyTypes: [TypeID] = []
        var valueTypes: [TypeID] = []

        for argument in args {
            guard let expr = ast.arena.expr(argument.expr) else { return nil }
            switch expr {
            case let .memberCall(receiver, callee, _, pairArgs, _)
                where interner.resolve(callee) == "to" && pairArgs.count == 1:
                let keyType = driver.inferExpr(receiver, ctx: ctx, locals: &locals, expectedType: nil)
                let valueType = driver.inferExpr(pairArgs[0].expr, ctx: ctx, locals: &locals, expectedType: nil)
                keyTypes.append(keyType)
                valueTypes.append(valueType)
            case let .call(calleeExpr, _, pairArgs, _):
                guard pairArgs.count == 2,
                      let callee = ast.arena.expr(calleeExpr),
                      case let .nameRef(name, _) = callee,
                      interner.resolve(name) == "to"
                else {
                    return nil
                }
                let keyType = driver.inferExpr(pairArgs[0].expr, ctx: ctx, locals: &locals, expectedType: nil)
                let valueType = driver.inferExpr(pairArgs[1].expr, ctx: ctx, locals: &locals, expectedType: nil)
                keyTypes.append(keyType)
                valueTypes.append(valueType)
            default:
                return nil
            }
        }

        guard !keyTypes.isEmpty, !valueTypes.isEmpty else {
            return nil
        }
        return (sema.types.lub(keyTypes), sema.types.lub(valueTypes))
    }

    private func makeSyntheticMutableListType(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        elementType: TypeID
    ) -> TypeID {
        let mutableListFQName: [InternedString] = [
            interner.intern("kotlin"),
            interner.intern("collections"),
            interner.intern("MutableList"),
        ]
        guard let mutableListSymbol = symbols.lookup(fqName: mutableListFQName) else {
            return types.anyType
        }
        return types.make(.classType(ClassType(
            classSymbol: mutableListSymbol,
            args: [.invariant(elementType)],
            nullability: .nonNull
        )))
    }

    private func makeSyntheticSetType(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        elementType: TypeID
    ) -> TypeID {
        let setFQName: [InternedString] = [
            interner.intern("kotlin"),
            interner.intern("collections"),
            interner.intern("Set"),
        ]
        guard let setSymbol = symbols.lookup(fqName: setFQName) else {
            return types.anyType
        }
        return types.make(.classType(ClassType(
            classSymbol: setSymbol,
            args: [.out(elementType)],
            nullability: .nonNull
        )))
    }

    private func makeSyntheticMutableSetType(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        elementType: TypeID
    ) -> TypeID {
        let mutableSetFQName: [InternedString] = [
            interner.intern("kotlin"),
            interner.intern("collections"),
            interner.intern("MutableSet"),
        ]
        guard let mutableSetSymbol = symbols.lookup(fqName: mutableSetFQName) else {
            return types.anyType
        }
        return types.make(.classType(ClassType(
            classSymbol: mutableSetSymbol,
            args: [.invariant(elementType)],
            nullability: .nonNull
        )))
    }

    private func makeSyntheticMapType(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        keyType: TypeID,
        valueType: TypeID
    ) -> TypeID {
        let mapFQName: [InternedString] = [
            interner.intern("kotlin"),
            interner.intern("collections"),
            interner.intern("Map"),
        ]
        guard let mapSymbol = symbols.lookup(fqName: mapFQName) else {
            return types.anyType
        }
        return types.make(.classType(ClassType(
            classSymbol: mapSymbol,
            args: [.out(keyType), .out(valueType)],
            nullability: .nonNull
        )))
    }

    private func makeSyntheticMutableMapType(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        keyType: TypeID,
        valueType: TypeID
    ) -> TypeID {
        let mapFQName: [InternedString] = [
            interner.intern("kotlin"),
            interner.intern("collections"),
            interner.intern("MutableMap"),
        ]
        guard let mapSymbol = symbols.lookup(fqName: mapFQName) else {
            return types.anyType
        }
        return types.make(.classType(ClassType(
            classSymbol: mapSymbol,
            args: [.invariant(keyType), .invariant(valueType)],
            nullability: .nonNull
        )))
    }

    private func applyContractEffects(
        chosen: SymbolID,
        args: [CallArgument],
        argTypes: [TypeID],
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) {
        let sema = ctx.sema
        guard let effect = sema.symbols.contractNonNullEffect(for: chosen),
              effect.appliesOnAnyReturn,
              let parameterIndex = sema.symbols.functionSignature(for: chosen)?
              .valueParameterSymbols.firstIndex(of: effect.parameterSymbol),
              parameterIndex < args.count,
              parameterIndex < argTypes.count
        else {
            return
        }
        guard let argumentExpr = ctx.ast.arena.expr(args[parameterIndex].expr),
              case let .nameRef(argumentName, _) = argumentExpr,
              let local = locals[argumentName]
        else {
            return
        }
        let narrowed = ctx.dataFlow.narrowToNonNull(
            symbol: local.symbol,
            type: argTypes[parameterIndex],
            base: ctx.flowState,
            types: sema.types
        )
        if let narrowedType = narrowed.variables[local.symbol]?.possibleTypes.first {
            locals[argumentName] = (narrowedType, local.symbol, local.isMutable, local.isInitialized)
        }
    }

    func inferMemberCallExpr(
        _ id: ExprID, receiverID: ExprID, calleeName: InternedString,
        args: [CallArgument], range: SourceRange, ctx: TypeInferenceContext,
        locals: inout LocalBindings, expectedType: TypeID?, explicitTypeArgs: [TypeID] = []
    ) -> TypeID {
        inferMemberCallImpl(
            id, receiverID: receiverID, calleeName: calleeName,
            args: args, range: range, ctx: ctx, locals: &locals,
            expectedType: expectedType, explicitTypeArgs: explicitTypeArgs,
            safeCall: false
        )
    }

    func inferSafeMemberCallExpr(
        _ id: ExprID, receiverID: ExprID, calleeName: InternedString,
        args: [CallArgument], range: SourceRange, ctx: TypeInferenceContext,
        locals: inout LocalBindings, expectedType: TypeID?, explicitTypeArgs: [TypeID] = []
    ) -> TypeID {
        inferMemberCallImpl(
            id, receiverID: receiverID, calleeName: calleeName,
            args: args, range: range, ctx: ctx, locals: &locals,
            expectedType: expectedType, explicitTypeArgs: explicitTypeArgs,
            safeCall: true
        )
    }

    private func shouldUseBuiltinFlowFactorySpecialHandling(
        calleeName: InternedString,
        ctx: TypeInferenceContext,
        locals: LocalBindings
    ) -> Bool {
        if locals[calleeName] != nil {
            return false
        }
        let visibleCandidates = ctx.cachedScopeLookup(calleeName)
        if visibleCandidates.isEmpty {
            return true
        }
        let hasConflictingUserDefinedCandidate = visibleCandidates.contains { candidate in
            guard let symbol = ctx.cachedSymbol(candidate),
                  symbol.kind == .function
            else {
                return false
            }
            if symbol.flags.contains(.synthetic) {
                let fqName = symbol.fqName.map(ctx.interner.resolve)
                return fqName != ["kotlinx", "coroutines", "flow", "flow"]
            }
            let fqName = symbol.fqName.map(ctx.interner.resolve)
            return fqName != ["kotlinx", "coroutines", "flow", "flow"]
        }
        return !hasConflictingUserDefinedCandidate
    }
}

// swiftlint:enable type_body_length

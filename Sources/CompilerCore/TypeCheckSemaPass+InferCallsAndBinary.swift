import Foundation

extension TypeCheckSemaPassPhase {
    func inferBinaryExpr(
        _ id: ExprID,
        op: BinaryOp,
        lhsID: ExprID,
        rhsID: ExprID,
        range: SourceRange,
        ctx: TypeInferenceContext,
        locals: inout [InternedString: (type: TypeID, symbol: SymbolID, isMutable: Bool, isInitialized: Bool)],
        expectedType: TypeID?
    ) -> TypeID {
        let ast = ctx.ast
        let sema = ctx.sema
        let interner = ctx.interner
        let scope = ctx.scope

        let boolType = sema.types.make(.primitive(.boolean, .nonNull))
        let intType = sema.types.make(.primitive(.int, .nonNull))
        let longType = sema.types.make(.primitive(.long, .nonNull))
        let floatType = sema.types.make(.primitive(.float, .nonNull))
        let doubleType = sema.types.make(.primitive(.double, .nonNull))
        let stringType = sema.types.make(.primitive(.string, .nonNull))

        let lhs = inferExpr(lhsID, ctx: ctx, locals: &locals)
        let rhs = inferExpr(rhsID, ctx: ctx, locals: &locals)
        let lhsIsPrimitive: Bool
        if case .primitive = sema.types.kind(of: lhs) { lhsIsPrimitive = true } else { lhsIsPrimitive = false }
        let operatorName = binaryOperatorFunctionName(for: op, interner: interner)
        let memberOperatorCandidates = lhsIsPrimitive ? [] : collectMemberFunctionCandidates(
            named: operatorName,
            receiverType: lhs,
            sema: sema
        )
        let operatorCandidates: [SymbolID]
        if !memberOperatorCandidates.isEmpty {
            operatorCandidates = memberOperatorCandidates
        } else if !lhsIsPrimitive {
            operatorCandidates = scope.lookup(operatorName).filter { candidate in
                guard let symbol = sema.symbols.symbol(candidate),
                      symbol.kind == .function,
                      let signature = sema.symbols.functionSignature(for: candidate) else {
                    return false
                }
                return signature.receiverType != nil
            }
        } else {
            operatorCandidates = []
        }
        if !lhsIsPrimitive && operatorCandidates.isEmpty {
            ctx.semaCtx.diagnostics.error(
                "KSWIFTK-SEMA-0002",
                "No viable overload found for operator '\(interner.resolve(operatorName))'.",
                range: range
            )
            sema.bindings.bindExprType(id, type: sema.types.errorType)
            return sema.types.errorType
        }
        if !operatorCandidates.isEmpty {
            let resolved = ctx.resolver.resolveCall(
                candidates: operatorCandidates,
                call: CallExpr(
                    range: range,
                    calleeName: operatorName,
                    args: [CallArg(type: rhs)]
                ),
                expectedType: expectedType,
                implicitReceiverType: lhs,
                ctx: ctx.semaCtx
            )
            if let diagnostic = resolved.diagnostic {
                ctx.semaCtx.diagnostics.emit(diagnostic)
                sema.bindings.bindExprType(id, type: sema.types.errorType)
                return sema.types.errorType
            }
            guard let chosen = resolved.chosenCallee else {
                ctx.semaCtx.diagnostics.error(
                    "KSWIFTK-SEMA-0002",
                    "No viable overload found for operator '\(interner.resolve(operatorName))'.",
                    range: range
                )
                sema.bindings.bindExprType(id, type: sema.types.errorType)
                return sema.types.errorType
            }
            let returnType = bindCallAndResolveReturnType(id, chosen: chosen, resolved: resolved, sema: sema)
            sema.bindings.bindExprType(id, type: returnType)
            return returnType
        }
        let type: TypeID
        switch op {
        case .add:
            if lhs == stringType || rhs == stringType {
                type = stringType
            } else if lhs == doubleType || rhs == doubleType {
                type = doubleType
            } else if lhs == floatType || rhs == floatType {
                type = floatType
            } else if lhs == longType || rhs == longType {
                type = longType
            } else {
                type = intType
            }
        case .subtract, .multiply, .divide, .modulo:
            if lhs == doubleType || rhs == doubleType {
                type = doubleType
            } else if lhs == floatType || rhs == floatType {
                type = floatType
            } else if lhs == longType || rhs == longType {
                type = longType
            } else {
                type = intType
            }
        case .equal, .notEqual, .lessThan, .lessOrEqual, .greaterThan, .greaterOrEqual:
            type = boolType
        case .logicalAnd, .logicalOr:
            emitSubtypeConstraint(
                left: lhs, right: boolType,
                range: ast.arena.exprRange(lhsID) ?? range,
                solver: ConstraintSolver(), sema: sema,
                diagnostics: ctx.semaCtx.diagnostics
            )
            emitSubtypeConstraint(
                left: rhs, right: boolType,
                range: ast.arena.exprRange(rhsID) ?? range,
                solver: ConstraintSolver(), sema: sema,
                diagnostics: ctx.semaCtx.diagnostics
            )
            type = boolType
        case .elvis:
            let nonNullLhs = makeNonNullable(lhs, types: sema.types)
            type = sema.types.lub([nonNullLhs, rhs])
        case .rangeTo:
            type = sema.types.anyType
        }
        sema.bindings.bindExprType(id, type: type)
        return type
    }

    func inferCallExpr(
        _ id: ExprID,
        calleeID: ExprID,
        args: [CallArgument],
        range: SourceRange,
        ctx: TypeInferenceContext,
        locals: inout [InternedString: (type: TypeID, symbol: SymbolID, isMutable: Bool, isInitialized: Bool)],
        expectedType: TypeID?
    ) -> TypeID {
        let ast = ctx.ast
        let sema = ctx.sema
        let interner = ctx.interner
        let scope = ctx.scope

        let argTypes = args.map { argument in
            inferExpr(argument.expr, ctx: ctx, locals: &locals)
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
            let allCallCandidates = scope.lookup(calleeName).filter { candidate in
                guard let symbol = sema.symbols.symbol(candidate) else { return false }
                return symbol.kind == .function || symbol.kind == .constructor
            }
            let (vis, invis) = ctx.filterByVisibility(allCallCandidates)
            candidates = vis
            callInvisible = invis
            if candidates.isEmpty, let local = locals[calleeName] {
                if let sym = sema.symbols.symbol(local.symbol), sym.kind == .function {
                    candidates = [local.symbol]
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
                    args: resolvedArgs
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
            let localSymbolKind = sema.symbols.symbol(local.symbol)?.kind
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
            callableCalleeType = inferExpr(
                calleeID,
                ctx: ctx,
                locals: &locals,
                expectedType: contextualCalleeType
            )
            callableTarget = callableTargetForCalleeExpr(calleeID, sema: sema)
        }

        if let callableCalleeType {
            let nonNullCalleeType = makeNonNullable(callableCalleeType, types: sema.types)
            if case .functionType(let functionType) = sema.types.kind(of: nonNullCalleeType) {
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
                    emitSubtypeConstraint(
                        left: argTypes[index],
                        right: functionType.params[index],
                        range: ast.arena.exprRange(args[index].expr) ?? range,
                        solver: ConstraintSolver(),
                        sema: sema,
                        diagnostics: ctx.semaCtx.diagnostics
                    )
                }
                if let expectedType {
                    emitSubtypeConstraint(
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

        if let builtinType = kxMiniCoroutineBuiltinReturnType(
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
        if let firstInvisible = callInvisible.first, let calleeName {
            let visLabel = firstInvisible.visibility == .protected ? "protected" : "private"
            let code = firstInvisible.visibility == .protected ? "KSWIFTK-SEMA-0041" : "KSWIFTK-SEMA-0040"
            ctx.semaCtx.diagnostics.error(
                code,
                "Cannot access '\(interner.resolve(calleeName))': it is \(visLabel).",
                range: range
            )
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
        locals: inout [InternedString: (type: TypeID, symbol: SymbolID, isMutable: Bool, isInitialized: Bool)],
        expectedType: TypeID?
    ) -> TypeID {
        let ast = ctx.ast
        let sema = ctx.sema
        let interner = ctx.interner
        let scope = ctx.scope

        let receiverType = inferExpr(receiverID, ctx: ctx, locals: &locals)
        let argTypes = args.map { argument in
            inferExpr(argument.expr, ctx: ctx, locals: &locals)
        }

        let isSuperCall = ast.arena.expr(receiverID).map { expr in
            if case .superRef = expr { true } else { false }
        } ?? false

        var supertypeSymbols: Set<SymbolID> = []
        if isSuperCall, let currentReceiverType = ctx.implicitReceiverType,
           let classSymbol = nominalSymbol(of: currentReceiverType, types: sema.types) {
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

        let memberLookupReceiverType = (isSuperCall ? ctx.implicitReceiverType : nil) ?? receiverType
        let memberCandidates = collectMemberFunctionCandidates(
            named: calleeName,
            receiverType: memberLookupReceiverType,
            sema: sema,
            allowedOwnerSymbols: isSuperCall && !supertypeSymbols.isEmpty ? supertypeSymbols : nil
        )
        let allMemberCandidates: [SymbolID]
        if !memberCandidates.isEmpty {
            allMemberCandidates = memberCandidates
        } else {
            allMemberCandidates = scope.lookup(calleeName).filter { candidate in
                guard let symbol = sema.symbols.symbol(candidate),
                      symbol.kind == .function,
                      let signature = sema.symbols.functionSignature(for: candidate) else {
                    return false
                }
                guard signature.receiverType != nil else { return false }
                if isSuperCall, !supertypeSymbols.isEmpty {
                    if let parent = sema.symbols.parentSymbol(for: candidate) {
                        return supertypeSymbols.contains(parent)
                    }
                    return false
                }
                return true
            }
        }
        let (memberVisible, memberInvisible) = ctx.filterByVisibility(allMemberCandidates)
        let candidates = memberVisible
        if candidates.isEmpty {
            if let firstInvisible = memberInvisible.first {
                let visLabel = firstInvisible.visibility == .protected ? "protected" : "private"
                let code = firstInvisible.visibility == .protected ? "KSWIFTK-SEMA-0041" : "KSWIFTK-SEMA-0040"
                ctx.semaCtx.diagnostics.error(
                    code,
                    "Cannot access '\(interner.resolve(calleeName))': it is \(visLabel).",
                    range: range
                )
            } else {
                ctx.semaCtx.diagnostics.error(
                    "KSWIFTK-SEMA-0024",
                    "Unresolved member function '\(interner.resolve(calleeName))'.",
                    range: range
                )
            }
            sema.bindings.bindExprType(id, type: sema.types.errorType)
            return sema.types.errorType
        }

        let resolvedArgs: [CallArg] = zip(args, argTypes).map { argument, type in
            CallArg(label: argument.label, isSpread: argument.isSpread, type: type)
        }
        let resolved = ctx.resolver.resolveCall(
            candidates: candidates,
            call: CallExpr(
                range: range,
                calleeName: calleeName,
                args: resolvedArgs
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
            ctx.semaCtx.diagnostics.error(
                "KSWIFTK-SEMA-0024",
                "Unresolved member function '\(interner.resolve(calleeName))'.",
                range: range
            )
            sema.bindings.bindExprType(id, type: sema.types.errorType)
            return sema.types.errorType
        }
        let returnType = bindCallAndResolveReturnType(id, chosen: chosen, resolved: resolved, sema: sema)
        if isSuperCall {
            sema.bindings.markSuperCall(id)
        }
        sema.bindings.bindExprType(id, type: returnType)
        return returnType
    }

    func inferSafeMemberCallExpr(
        _ id: ExprID,
        receiverID: ExprID,
        calleeName: InternedString,
        args: [CallArgument],
        range: SourceRange,
        ctx: TypeInferenceContext,
        locals: inout [InternedString: (type: TypeID, symbol: SymbolID, isMutable: Bool, isInitialized: Bool)],
        expectedType: TypeID?
    ) -> TypeID {
        let sema = ctx.sema
        let interner = ctx.interner
        let scope = ctx.scope

        let receiverType = inferExpr(receiverID, ctx: ctx, locals: &locals)
        let argTypes = args.map { argument in
            inferExpr(argument.expr, ctx: ctx, locals: &locals)
        }
        let nonNullReceiver = makeNonNullable(receiverType, types: sema.types)
        let memberCandidates = collectMemberFunctionCandidates(
            named: calleeName,
            receiverType: nonNullReceiver,
            sema: sema
        )
        let allSafeMemberCandidates: [SymbolID]
        if !memberCandidates.isEmpty {
            allSafeMemberCandidates = memberCandidates
        } else {
            allSafeMemberCandidates = scope.lookup(calleeName).filter { candidate in
                guard let symbol = sema.symbols.symbol(candidate),
                      symbol.kind == .function,
                      let signature = sema.symbols.functionSignature(for: candidate) else {
                    return false
                }
                return signature.receiverType != nil
            }
        }
        let (safeMemberVisible, safeMemberInvisible) = ctx.filterByVisibility(allSafeMemberCandidates)
        let candidates = safeMemberVisible
        if candidates.isEmpty {
            if let firstInvisible = safeMemberInvisible.first {
                let visLabel = firstInvisible.visibility == .protected ? "protected" : "private"
                let code = firstInvisible.visibility == .protected ? "KSWIFTK-SEMA-0041" : "KSWIFTK-SEMA-0040"
                ctx.semaCtx.diagnostics.error(
                    code,
                    "Cannot access '\(interner.resolve(calleeName))': it is \(visLabel).",
                    range: range
                )
                sema.bindings.bindExprType(id, type: sema.types.errorType)
                return sema.types.errorType
            }
            ctx.semaCtx.diagnostics.error(
                "KSWIFTK-SEMA-0024",
                "Unresolved member function '\(interner.resolve(calleeName))'.",
                range: range
            )
            sema.bindings.bindExprType(id, type: sema.types.errorType)
            return sema.types.errorType
        }
        let resolvedArgs: [CallArg] = zip(args, argTypes).map { argument, type in
            CallArg(label: argument.label, isSpread: argument.isSpread, type: type)
        }
        let resolved = ctx.resolver.resolveCall(
            candidates: candidates,
            call: CallExpr(
                range: range,
                calleeName: calleeName,
                args: resolvedArgs
            ),
            expectedType: expectedType,
            implicitReceiverType: nonNullReceiver,
            ctx: ctx.semaCtx
        )
        if let diagnostic = resolved.diagnostic {
            ctx.semaCtx.diagnostics.emit(diagnostic)
            sema.bindings.bindExprType(id, type: sema.types.errorType)
            return sema.types.errorType
        }
        guard let chosen = resolved.chosenCallee else {
            ctx.semaCtx.diagnostics.error(
                "KSWIFTK-SEMA-0024",
                "Unresolved member function '\(interner.resolve(calleeName))'.",
                range: range
            )
            sema.bindings.bindExprType(id, type: sema.types.errorType)
            return sema.types.errorType
        }
        let returnType = bindCallAndResolveReturnType(id, chosen: chosen, resolved: resolved, sema: sema)
        let nullableReturn = makeNullable(returnType, types: sema.types)
        sema.bindings.bindExprType(id, type: nullableReturn)
        return nullableReturn
    }

    private func bindCallAndResolveReturnType(
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

    func inferCompoundAssignExpr(
        _ id: ExprID,
        op: CompoundAssignOp,
        name: InternedString,
        valueExpr: ExprID,
        range: SourceRange,
        ctx: TypeInferenceContext,
        locals: inout [InternedString: (type: TypeID, symbol: SymbolID, isMutable: Bool, isInitialized: Bool)]
    ) -> TypeID {
        let sema = ctx.sema
        let interner = ctx.interner

        let intType = sema.types.make(.primitive(.int, .nonNull))
        let stringType = sema.types.make(.primitive(.string, .nonNull))

        let valueType = inferExpr(valueExpr, ctx: ctx, locals: &locals, expectedType: nil)
        guard let local = locals[name] else {
            ctx.semaCtx.diagnostics.error(
                "KSWIFTK-SEMA-0013",
                "Unresolved local variable '\(interner.resolve(name))'.",
                range: range
            )
            sema.bindings.bindExprType(id, type: sema.types.errorType)
            return sema.types.errorType
        }
        sema.bindings.bindIdentifier(id, symbol: local.symbol)
        if !local.isInitialized {
            ctx.semaCtx.diagnostics.error(
                "KSWIFTK-SEMA-0031",
                "Variable '\(interner.resolve(name))' must be initialized before use.",
                range: range
            )
        }
        if !local.isMutable {
            ctx.semaCtx.diagnostics.error(
                "KSWIFTK-SEMA-0014",
                "Val cannot be reassigned.",
                range: range
            )
        }
        let underlyingOp = compoundAssignToBinaryOp(op)
        let resultType: TypeID
        switch underlyingOp {
        case .add:
            resultType = (local.type == stringType || valueType == stringType) ? stringType : intType
        case .subtract, .multiply, .divide, .modulo:
            resultType = intType
        default:
            resultType = local.type
        }
        locals[name] = (resultType, local.symbol, local.isMutable, local.isInitialized)
        sema.bindings.bindExprType(id, type: sema.types.unitType)
        return sema.types.unitType
    }
}

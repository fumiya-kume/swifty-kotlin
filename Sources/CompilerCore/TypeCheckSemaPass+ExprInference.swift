import Foundation

extension TypeCheckSemaPassPhase {
    func inferExpr(
        _ id: ExprID,
        ctx: TypeInferenceContext,
        locals: inout [InternedString: (type: TypeID, symbol: SymbolID, isMutable: Bool)],
        expectedType: TypeID? = nil
    ) -> TypeID {
        let ast = ctx.ast
        let sema = ctx.sema
        let interner = ctx.interner
        let scope = ctx.scope

        guard let expr = ast.arena.expr(id) else {
            return sema.types.errorType
        }

        let boolType = sema.types.make(.primitive(.boolean, .nonNull))
        let intType = sema.types.make(.primitive(.int, .nonNull))
        let stringType = sema.types.make(.primitive(.string, .nonNull))

        switch expr {
        case .intLiteral:
            sema.bindings.bindExprType(id, type: intType)
            return intType

        case .boolLiteral:
            sema.bindings.bindExprType(id, type: boolType)
            return boolType

        case .stringLiteral:
            sema.bindings.bindExprType(id, type: stringType)
            return stringType

        case .nameRef(let name, _):
            if interner.resolve(name) == "null" {
                sema.bindings.bindExprType(id, type: sema.types.nullableAnyType)
                return sema.types.nullableAnyType
            }
            if interner.resolve(name) == "this",
               let receiverType = ctx.implicitReceiverType {
                sema.bindings.bindExprType(id, type: receiverType)
                return receiverType
            }
            if let local = locals[name] {
                sema.bindings.bindIdentifier(id, symbol: local.symbol)
                sema.bindings.bindExprType(id, type: local.type)
                return local.type
            }
            let candidates = scope.lookup(name).compactMap { sema.symbols.symbol($0) }
            if let first = candidates.first {
                sema.bindings.bindIdentifier(id, symbol: first.id)
            }
            let resolvedType = candidates.first.flatMap { symbol in
                if let signature = sema.symbols.functionSignature(for: symbol.id) {
                    return signature.returnType
                }
                if symbol.kind == .property || symbol.kind == .field {
                    return sema.symbols.propertyType(for: symbol.id)
                }
                return nil
            } ?? sema.types.anyType
            sema.bindings.bindExprType(id, type: resolvedType)
            return resolvedType

        case .forExpr(let loopVariable, let iterableExpr, let bodyExpr, let range):
            let iterableType = inferExpr(iterableExpr, ctx: ctx, locals: &locals, expectedType: nil)
            var bodyLocals = locals
            if let loopVariable {
                let elementType = arrayElementType(for: iterableType, sema: sema, interner: interner) ?? sema.types.anyType
                let loopVariableSymbol = sema.symbols.define(
                    kind: .local,
                    name: loopVariable,
                    fqName: [
                        ctx.interner.intern("__for_\(id.rawValue)"),
                        loopVariable
                    ],
                    declSite: range,
                    visibility: .private,
                    flags: []
                )
                bodyLocals[loopVariable] = (elementType, loopVariableSymbol, false)
                sema.bindings.bindIdentifier(id, symbol: loopVariableSymbol)
            }
            _ = inferExpr(
                bodyExpr,
                ctx: ctx.with(loopDepth: ctx.loopDepth + 1),
                locals: &bodyLocals,
                expectedType: nil
            )
            sema.bindings.bindExprType(id, type: sema.types.unitType)
            return sema.types.unitType

        case .whileExpr(let conditionExpr, let bodyExpr, let range):
            let conditionType = inferExpr(conditionExpr, ctx: ctx, locals: &locals, expectedType: boolType)
            emitSubtypeConstraint(
                left: conditionType,
                right: boolType,
                range: ast.arena.exprRange(conditionExpr) ?? range,
                solver: ConstraintSolver(),
                sema: sema,
                diagnostics: ctx.semaCtx.diagnostics
            )
            _ = inferExpr(
                bodyExpr,
                ctx: ctx.with(loopDepth: ctx.loopDepth + 1),
                locals: &locals,
                expectedType: nil
            )
            sema.bindings.bindExprType(id, type: sema.types.unitType)
            return sema.types.unitType

        case .doWhileExpr(let bodyExpr, let conditionExpr, let range):
            _ = inferExpr(
                bodyExpr,
                ctx: ctx.with(loopDepth: ctx.loopDepth + 1),
                locals: &locals,
                expectedType: nil
            )
            let conditionType = inferExpr(conditionExpr, ctx: ctx, locals: &locals, expectedType: boolType)
            emitSubtypeConstraint(
                left: conditionType,
                right: boolType,
                range: ast.arena.exprRange(conditionExpr) ?? range,
                solver: ConstraintSolver(),
                sema: sema,
                diagnostics: ctx.semaCtx.diagnostics
            )
            sema.bindings.bindExprType(id, type: sema.types.unitType)
            return sema.types.unitType

        case .breakExpr(let range):
            if ctx.loopDepth == 0 {
                ctx.semaCtx.diagnostics.error(
                    "KSWIFTK-SEMA-0018",
                    "'break' is only allowed inside loop bodies.",
                    range: range
                )
            }
            sema.bindings.bindExprType(id, type: sema.types.unitType)
            return sema.types.unitType

        case .continueExpr(let range):
            if ctx.loopDepth == 0 {
                ctx.semaCtx.diagnostics.error(
                    "KSWIFTK-SEMA-0019",
                    "'continue' is only allowed inside loop bodies.",
                    range: range
                )
            }
            sema.bindings.bindExprType(id, type: sema.types.unitType)
            return sema.types.unitType

        case .localDecl(let name, let isMutable, let initializer, let range):
            let initializerType = inferExpr(initializer, ctx: ctx, locals: &locals, expectedType: nil)
            let localSymbol = sema.symbols.define(
                kind: .local,
                name: name,
                fqName: [
                    ctx.interner.intern("__local_\(id.rawValue)"),
                    name
                ],
                declSite: range,
                visibility: .private,
                flags: isMutable ? [.mutable] : []
            )
            locals[name] = (initializerType, localSymbol, isMutable)
            sema.bindings.bindIdentifier(id, symbol: localSymbol)
            sema.bindings.bindExprType(id, type: sema.types.unitType)
            return sema.types.unitType

        case .localAssign(let name, let value, let range):
            let valueType = inferExpr(value, ctx: ctx, locals: &locals, expectedType: nil)
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
            if !local.isMutable {
                ctx.semaCtx.diagnostics.error(
                    "KSWIFTK-SEMA-0014",
                    "Val cannot be reassigned.",
                    range: range
                )
            } else {
                emitSubtypeConstraint(
                    left: valueType,
                    right: local.type,
                    range: range,
                    solver: ConstraintSolver(),
                    sema: sema,
                    diagnostics: ctx.semaCtx.diagnostics
                )
            }
            sema.bindings.bindExprType(id, type: sema.types.unitType)
            return sema.types.unitType

        case .arrayAccess(let arrayExpr, let indexExpr, let range):
            let arrayType = inferExpr(arrayExpr, ctx: ctx, locals: &locals, expectedType: nil)
            let indexType = inferExpr(indexExpr, ctx: ctx, locals: &locals, expectedType: intType)
            emitSubtypeConstraint(
                left: indexType,
                right: intType,
                range: ast.arena.exprRange(indexExpr) ?? range,
                solver: ConstraintSolver(),
                sema: sema,
                diagnostics: ctx.semaCtx.diagnostics
            )
            let elementType = arrayElementType(for: arrayType, sema: sema, interner: interner) ?? sema.types.anyType
            sema.bindings.bindExprType(id, type: elementType)
            return elementType

        case .arrayAssign(let arrayExpr, let indexExpr, let valueExpr, let range):
            let arrayType = inferExpr(arrayExpr, ctx: ctx, locals: &locals, expectedType: nil)
            let indexType = inferExpr(indexExpr, ctx: ctx, locals: &locals, expectedType: intType)
            emitSubtypeConstraint(
                left: indexType,
                right: intType,
                range: ast.arena.exprRange(indexExpr) ?? range,
                solver: ConstraintSolver(),
                sema: sema,
                diagnostics: ctx.semaCtx.diagnostics
            )
            let elementExpectedType = arrayElementType(for: arrayType, sema: sema, interner: interner)
            let valueType = inferExpr(valueExpr, ctx: ctx, locals: &locals, expectedType: elementExpectedType)
            if let elementExpectedType {
                emitSubtypeConstraint(
                    left: valueType,
                    right: elementExpectedType,
                    range: ast.arena.exprRange(valueExpr) ?? range,
                    solver: ConstraintSolver(),
                    sema: sema,
                    diagnostics: ctx.semaCtx.diagnostics
                )
            }
            sema.bindings.bindExprType(id, type: sema.types.unitType)
            return sema.types.unitType

        case .returnExpr(let value, _):
            let resolved: TypeID
            if let value {
                resolved = inferExpr(value, ctx: ctx, locals: &locals, expectedType: expectedType)
            } else {
                resolved = sema.types.unitType
            }
            sema.bindings.bindExprType(id, type: resolved)
            return resolved

        case .ifExpr(let condition, let thenExpr, let elseExpr, _):
            let conditionType = inferExpr(condition, ctx: ctx, locals: &locals)
            if conditionType != boolType {
                emitSubtypeConstraint(
                    left: conditionType,
                    right: boolType,
                    range: ast.arena.exprRange(condition),
                    solver: ConstraintSolver(),
                    sema: sema,
                    diagnostics: ctx.semaCtx.diagnostics
                )
            }
            let thenType = inferExpr(thenExpr, ctx: ctx, locals: &locals, expectedType: expectedType)
            let resolvedType: TypeID
            if let elseExpr {
                let elseType = inferExpr(elseExpr, ctx: ctx, locals: &locals, expectedType: expectedType)
                resolvedType = sema.types.lub([thenType, elseType])
            } else {
                resolvedType = sema.types.unitType
            }
            sema.bindings.bindExprType(id, type: resolvedType)
            return resolvedType

        case .tryExpr(let body, let catchBodies, let finallyExpr, _):
            var branchTypes: [TypeID] = []
            branchTypes.append(inferExpr(body, ctx: ctx, locals: &locals, expectedType: expectedType))
            for catchBody in catchBodies {
                branchTypes.append(inferExpr(catchBody, ctx: ctx, locals: &locals, expectedType: expectedType))
            }
            if let finallyExpr {
                _ = inferExpr(finallyExpr, ctx: ctx, locals: &locals, expectedType: nil)
            }
            let resolvedType = sema.types.lub(branchTypes)
            sema.bindings.bindExprType(id, type: resolvedType)
            return resolvedType

        case .unary(let op, let operandID, let range):
            let operandType = inferExpr(operandID, ctx: ctx, locals: &locals)
            let type: TypeID
            switch op {
            case .plus, .minus:
                emitSubtypeConstraint(
                    left: operandType,
                    right: intType,
                    range: ast.arena.exprRange(operandID) ?? range,
                    solver: ConstraintSolver(),
                    sema: sema,
                    diagnostics: ctx.semaCtx.diagnostics
                )
                type = intType
            case .not:
                emitSubtypeConstraint(
                    left: operandType,
                    right: boolType,
                    range: ast.arena.exprRange(operandID) ?? range,
                    solver: ConstraintSolver(),
                    sema: sema,
                    diagnostics: ctx.semaCtx.diagnostics
                )
                type = boolType
            }
            sema.bindings.bindExprType(id, type: type)
            return type

        case .binary(let op, let lhsID, let rhsID, let range):
            let lhs = inferExpr(lhsID, ctx: ctx, locals: &locals)
            let rhs = inferExpr(rhsID, ctx: ctx, locals: &locals)
            let isPrimitiveBuiltin = (lhs == intType && (op == .add || op == .subtract || op == .multiply || op == .divide || op == .equal))
                || (lhs == stringType && (op == .add || op == .equal))
                || (lhs == boolType && op == .equal)
            if shouldResolveBinaryOperatorOverload(for: op) && !isPrimitiveBuiltin {
                let operatorName = binaryOperatorFunctionName(for: op, interner: interner)
                let operatorCandidates = scope.lookup(operatorName).filter { candidate in
                    guard let symbol = sema.symbols.symbol(candidate),
                          symbol.kind == .function,
                          let signature = sema.symbols.functionSignature(for: candidate) else {
                        return false
                    }
                    return signature.receiverType != nil
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
                        sema.bindings.bindExprType(id, type: sema.types.errorType)
                        return sema.types.errorType
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
                    let returnType: TypeID
                    if let signature = sema.symbols.functionSignature(for: chosen) {
                        let typeVarBySymbol = sema.types.makeTypeVarBySymbol(signature.typeParameterSymbols)
                        returnType = sema.types.substituteTypeParameters(
                            in: signature.returnType,
                            substitution: resolved.substitutedTypeArguments,
                            typeVarBySymbol: typeVarBySymbol
                        )
                    } else {
                        returnType = sema.types.anyType
                    }
                    sema.bindings.bindExprType(id, type: returnType)
                    return returnType
                }
            }
            let type: TypeID
            switch op {
            case .add:
                type = (lhs == stringType || rhs == stringType) ? stringType : intType
            case .subtract, .multiply, .divide:
                emitSubtypeConstraint(
                    left: lhs,
                    right: intType,
                    range: ast.arena.exprRange(lhsID) ?? range,
                    solver: ConstraintSolver(),
                    sema: sema,
                    diagnostics: ctx.semaCtx.diagnostics
                )
                emitSubtypeConstraint(
                    left: rhs,
                    right: intType,
                    range: ast.arena.exprRange(rhsID) ?? range,
                    solver: ConstraintSolver(),
                    sema: sema,
                    diagnostics: ctx.semaCtx.diagnostics
                )
                type = intType
            case .equal, .notEqual:
                type = boolType
            case .lessThan, .lessOrEqual, .greaterThan, .greaterOrEqual:
                emitSubtypeConstraint(
                    left: lhs,
                    right: intType,
                    range: ast.arena.exprRange(lhsID) ?? range,
                    solver: ConstraintSolver(),
                    sema: sema,
                    diagnostics: ctx.semaCtx.diagnostics
                )
                emitSubtypeConstraint(
                    left: rhs,
                    right: intType,
                    range: ast.arena.exprRange(rhsID) ?? range,
                    solver: ConstraintSolver(),
                    sema: sema,
                    diagnostics: ctx.semaCtx.diagnostics
                )
                type = boolType
            case .logicalAnd, .logicalOr:
                emitSubtypeConstraint(
                    left: lhs,
                    right: boolType,
                    range: ast.arena.exprRange(lhsID) ?? range,
                    solver: ConstraintSolver(),
                    sema: sema,
                    diagnostics: ctx.semaCtx.diagnostics
                )
                emitSubtypeConstraint(
                    left: rhs,
                    right: boolType,
                    range: ast.arena.exprRange(rhsID) ?? range,
                    solver: ConstraintSolver(),
                    sema: sema,
                    diagnostics: ctx.semaCtx.diagnostics
                )
                type = boolType
            }
            sema.bindings.bindExprType(id, type: type)
            return type

        case .call(let calleeID, let args, let range):
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

            let candidates: [SymbolID]
            if let calleeName {
                candidates = scope.lookup(calleeName).filter { candidate in
                    guard let symbol = sema.symbols.symbol(candidate) else { return false }
                    return symbol.kind == .function || symbol.kind == .constructor
                }
            } else {
                candidates = []
            }

            if candidates.isEmpty {
                if let builtinType = kxMiniCoroutineBuiltinReturnType(
                    calleeName: calleeName,
                    argumentCount: args.count,
                    sema: sema,
                    interner: interner
                ) {
                    sema.bindings.bindExprType(id, type: builtinType)
                    return builtinType
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
                sema.bindings.bindExprType(id, type: sema.types.errorType)
                return sema.types.errorType
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
            let returnType: TypeID
            if let signature = sema.symbols.functionSignature(for: chosen) {
                let typeVarBySymbol = sema.types.makeTypeVarBySymbol(signature.typeParameterSymbols)
                returnType = sema.types.substituteTypeParameters(
                    in: signature.returnType,
                    substitution: resolved.substitutedTypeArguments,
                    typeVarBySymbol: typeVarBySymbol
                )
            } else {
                returnType = sema.types.anyType
            }
            sema.bindings.bindExprType(id, type: returnType)
            return returnType

        case .memberCall(let receiverID, let calleeName, let args, let range):
            let receiverType = inferExpr(receiverID, ctx: ctx, locals: &locals)
            let argTypes = args.map { argument in
                inferExpr(argument.expr, ctx: ctx, locals: &locals)
            }

            let candidates = scope.lookup(calleeName).filter { candidate in
                guard let symbol = sema.symbols.symbol(candidate),
                      symbol.kind == .function,
                      let signature = sema.symbols.functionSignature(for: candidate) else {
                    return false
                }
                return signature.receiverType != nil
            }
            if candidates.isEmpty {
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
                sema.bindings.bindExprType(id, type: sema.types.errorType)
                return sema.types.errorType
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
            let returnType: TypeID
            if let signature = sema.symbols.functionSignature(for: chosen) {
                let typeVarBySymbol = sema.types.makeTypeVarBySymbol(signature.typeParameterSymbols)
                returnType = sema.types.substituteTypeParameters(
                    in: signature.returnType,
                    substitution: resolved.substitutedTypeArguments,
                    typeVarBySymbol: typeVarBySymbol
                )
            } else {
                returnType = sema.types.anyType
            }
            sema.bindings.bindExprType(id, type: returnType)
            return returnType

        case .whenExpr(let subjectID, let branches, let elseExpr, let range):
            let subjectType = inferExpr(subjectID, ctx: ctx, locals: &locals)
            let subjectLocalBinding: (name: InternedString, type: TypeID, symbol: SymbolID, isStable: Bool, isMutable: Bool)? = {
                guard let subjectExpr = ast.arena.expr(subjectID),
                      case .nameRef(let subjectName, _) = subjectExpr,
                      let local = locals[subjectName] else {
                    return nil
                }
                return (
                    subjectName, local.type, local.symbol,
                    isStableLocalSymbol(local.symbol, sema: sema),
                    local.isMutable
                )
            }()
            let hasExplicitNullBranch = branches.contains { branch in
                guard let condition = branch.condition,
                      let conditionExpr = ast.arena.expr(condition),
                      case .nameRef(let name, _) = conditionExpr else {
                    return false
                }
                return interner.resolve(name) == "null"
            }
            var branchTypes: [TypeID] = []
            var covered: Set<InternedString> = []
            var hasNullCase = false
            var hasTrueCase = false
            var hasFalseCase = false
            for branch in branches {
                var isNullBranch = false
                var branchSmartCastType: TypeID?
                if let cond = branch.condition {
                    let condType = inferExpr(cond, ctx: ctx, locals: &locals)
                    if let condExpr = ast.arena.expr(cond) {
                        switch condExpr {
                        case .boolLiteral(true, _):
                            if condType == boolType { hasTrueCase = true }
                            covered.insert(interner.intern("true"))
                        case .boolLiteral(false, _):
                            if condType == boolType { hasFalseCase = true }
                            covered.insert(interner.intern("false"))
                        case .nameRef(let name, _):
                            if interner.resolve(name) == "null" {
                                hasNullCase = true
                                isNullBranch = true
                            } else {
                                covered.insert(name)
                            }
                        default:
                            break
                        }
                    }
                    branchSmartCastType = smartCastTypeForWhenSubjectCase(
                        conditionID: cond, subjectType: subjectType,
                        ast: ast, sema: sema, interner: interner
                    )
                }
                var branchLocals = locals
                if let subjectLocalBinding, subjectLocalBinding.isStable {
                    if let branchSmartCastType {
                        branchLocals[subjectLocalBinding.name] = (
                            branchSmartCastType, subjectLocalBinding.symbol, subjectLocalBinding.isMutable
                        )
                    } else if hasExplicitNullBranch && !isNullBranch {
                        branchLocals[subjectLocalBinding.name] = (
                            makeNonNullable(subjectLocalBinding.type, types: sema.types),
                            subjectLocalBinding.symbol,
                            subjectLocalBinding.isMutable
                        )
                    }
                }
                branchTypes.append(
                    inferExpr(branch.body, ctx: ctx, locals: &branchLocals, expectedType: expectedType)
                )
            }

            if let elseExpr {
                var elseLocals = locals
                if let subjectLocalBinding,
                   subjectLocalBinding.isStable,
                   hasExplicitNullBranch {
                    elseLocals[subjectLocalBinding.name] = (
                        makeNonNullable(subjectLocalBinding.type, types: sema.types),
                        subjectLocalBinding.symbol,
                        subjectLocalBinding.isMutable
                    )
                }
                branchTypes.append(
                    inferExpr(elseExpr, ctx: ctx, locals: &elseLocals, expectedType: expectedType)
                )
            }

            let summary = WhenBranchSummary(
                coveredSymbols: covered, hasElse: elseExpr != nil,
                hasNullCase: hasNullCase, hasTrueCase: hasTrueCase,
                hasFalseCase: hasFalseCase
            )
            if !ctx.dataFlow.isWhenExhaustive(subjectType: subjectType, branches: summary, sema: sema) {
                ctx.semaCtx.diagnostics.error(
                    "KSWIFTK-SEMA-0004",
                    "Non-exhaustive when expression.",
                    range: range
                )
            }

            let type = sema.types.lub(branchTypes)
            sema.bindings.bindExprType(id, type: type)
            return type
        }
    }

    func makeNonNullable(_ type: TypeID, types: TypeSystem) -> TypeID {
        switch types.kind(of: type) {
        case .any(.nullable):
            return types.anyType

        case .primitive(let primitive, .nullable):
            return types.make(.primitive(primitive, .nonNull))

        case .classType(let classType):
            guard classType.nullability == .nullable else {
                return type
            }
            return types.make(.classType(ClassType(
                classSymbol: classType.classSymbol,
                args: classType.args,
                nullability: .nonNull
            )))

        case .typeParam(let typeParam):
            guard typeParam.nullability == .nullable else {
                return type
            }
            return types.make(.typeParam(TypeParamType(
                symbol: typeParam.symbol,
                nullability: .nonNull
            )))

        case .functionType(let functionType):
            guard functionType.nullability == .nullable else {
                return type
            }
            return types.make(.functionType(FunctionType(
                receiver: functionType.receiver,
                params: functionType.params,
                returnType: functionType.returnType,
                isSuspend: functionType.isSuspend,
                nullability: .nonNull
            )))

        default:
            return type
        }
    }

    func isStableLocalSymbol(_ symbolID: SymbolID, sema: SemaModule) -> Bool {
        guard let symbol = sema.symbols.symbol(symbolID) else {
            return false
        }
        switch symbol.kind {
        case .valueParameter, .local:
            return !symbol.flags.contains(.mutable)
        default:
            return false
        }
    }

    func arrayElementType(
        for arrayType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> TypeID? {
        guard case .classType(let classType) = sema.types.kind(of: arrayType),
              let symbol = sema.symbols.symbol(classType.classSymbol) else {
            return nil
        }
        switch interner.resolve(symbol.name) {
        case "IntArray":
            return sema.types.make(.primitive(.int, .nonNull))
        default:
            return nil
        }
    }

    func kxMiniCoroutineBuiltinReturnType(
        calleeName: InternedString?,
        argumentCount: Int,
        sema: SemaModule,
        interner: StringInterner
    ) -> TypeID? {
        guard let calleeName else {
            return nil
        }
        switch interner.resolve(calleeName) {
        case "runBlocking":
            guard argumentCount == 1 else { return nil }
            return sema.types.nullableAnyType
        case "launch":
            guard argumentCount == 1 else { return nil }
            return sema.types.unitType
        case "async":
            guard argumentCount == 1 else { return nil }
            return sema.types.nullableAnyType
        case "delay":
            guard argumentCount == 1 else { return nil }
            return sema.types.nullableAnyType
        case "kk_array_new", "IntArray":
            guard argumentCount == 1 else { return nil }
            return sema.types.anyType
        case "kk_array_get":
            guard argumentCount == 2 else { return nil }
            return sema.types.anyType
        case "kk_array_set":
            guard argumentCount == 3 else { return nil }
            return sema.types.unitType
        default:
            return nil
        }
    }

    func binaryOperatorFunctionName(for op: BinaryOp, interner: StringInterner) -> InternedString {
        switch op {
        case .add:
            return interner.intern("plus")
        case .subtract:
            return interner.intern("minus")
        case .multiply:
            return interner.intern("times")
        case .divide:
            return interner.intern("div")
        case .equal:
            return interner.intern("equals")
        case .notEqual:
            return interner.intern("equals")
        case .lessThan, .lessOrEqual, .greaterThan, .greaterOrEqual:
            return interner.intern("compareTo")
        case .logicalAnd:
            return interner.intern("and")
        case .logicalOr:
            return interner.intern("or")
        }
    }

    func shouldResolveBinaryOperatorOverload(for op: BinaryOp) -> Bool {
        switch op {
        case .add, .subtract, .multiply, .divide, .equal:
            return true
        case .notEqual, .lessThan, .lessOrEqual, .greaterThan, .greaterOrEqual, .logicalAnd, .logicalOr:
            return false
        }
    }

    func smartCastTypeForWhenSubjectCase(
        conditionID: ExprID,
        subjectType: TypeID,
        ast: ASTModule,
        sema: SemaModule,
        interner: StringInterner
    ) -> TypeID? {
        guard let conditionExpr = ast.arena.expr(conditionID) else {
            return nil
        }
        switch conditionExpr {
        case .boolLiteral:
            switch sema.types.kind(of: subjectType) {
            case .primitive(.boolean, _):
                return sema.types.make(.primitive(.boolean, .nonNull))
            default:
                return nil
            }

        case .nameRef(let name, _):
            if interner.resolve(name) == "null" {
                return nil
            }
            guard let conditionSymbolID = sema.bindings.identifierSymbols[conditionID],
                  let conditionSymbol = sema.symbols.symbol(conditionSymbolID) else {
                return nil
            }
            switch conditionSymbol.kind {
            case .field:
                guard let enumOwner = enumOwnerSymbol(for: conditionSymbol, symbols: sema.symbols),
                      nominalSymbol(of: subjectType, types: sema.types) == enumOwner else {
                    return nil
                }
                return sema.types.make(.classType(ClassType(
                    classSymbol: enumOwner,
                    args: [],
                    nullability: .nonNull
                )))

            case .class, .interface, .object, .enumClass, .annotationClass, .typeAlias:
                guard let subjectNominal = nominalSymbol(of: subjectType, types: sema.types),
                      isNominalSubtype(conditionSymbolID, of: subjectNominal, symbols: sema.symbols) else {
                    return nil
                }
                return sema.types.make(.classType(ClassType(
                    classSymbol: conditionSymbolID,
                    args: [],
                    nullability: .nonNull
                )))

            default:
                return nil
            }

        default:
            return nil
        }
    }

    func nominalSymbol(of type: TypeID, types: TypeSystem) -> SymbolID? {
        if case .classType(let classType) = types.kind(of: type) {
            return classType.classSymbol
        }
        return nil
    }

    func enumOwnerSymbol(for entrySymbol: SemanticSymbol, symbols: SymbolTable) -> SymbolID? {
        guard entrySymbol.kind == .field,
              entrySymbol.fqName.count >= 2 else {
            return nil
        }
        let ownerFQName = Array(entrySymbol.fqName.dropLast())
        return symbols.lookupAll(fqName: ownerFQName).first(where: { symbolID in
            symbols.symbol(symbolID)?.kind == .enumClass
        })
    }

    func isNominalSubtype(
        _ candidate: SymbolID,
        of base: SymbolID,
        symbols: SymbolTable
    ) -> Bool {
        if candidate == base {
            return true
        }
        var queue = symbols.directSupertypes(for: candidate)
        var visited: Set<SymbolID> = [candidate]
        while !queue.isEmpty {
            let next = queue.removeFirst()
            if next == base {
                return true
            }
            if visited.insert(next).inserted {
                queue.append(contentsOf: symbols.directSupertypes(for: next))
            }
        }
        return false
    }
}

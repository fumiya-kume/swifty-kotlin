import Foundation

extension TypeCheckSemaPassPhase {
    func inferExpr(
        _ id: ExprID,
        ctx: TypeInferenceContext,
        locals: inout [InternedString: (type: TypeID, symbol: SymbolID, isMutable: Bool, isInitialized: Bool)],
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
        let longType = sema.types.make(.primitive(.long, .nonNull))
        let floatType = sema.types.make(.primitive(.float, .nonNull))
        let doubleType = sema.types.make(.primitive(.double, .nonNull))
        let charType = sema.types.make(.primitive(.char, .nonNull))
        let stringType = sema.types.make(.primitive(.string, .nonNull))

        switch expr {
        case .intLiteral:
            sema.bindings.bindExprType(id, type: intType)
            return intType

        case .longLiteral:
            sema.bindings.bindExprType(id, type: longType)
            return longType

        case .floatLiteral:
            sema.bindings.bindExprType(id, type: floatType)
            return floatType

        case .doubleLiteral:
            sema.bindings.bindExprType(id, type: doubleType)
            return doubleType

        case .charLiteral:
            sema.bindings.bindExprType(id, type: charType)
            return charType

        case .boolLiteral:
            sema.bindings.bindExprType(id, type: boolType)
            return boolType

        case .stringLiteral:
            sema.bindings.bindExprType(id, type: stringType)
            return stringType

        case .stringTemplate(let parts, _):
            for part in parts {
                if case .expression(let exprID) = part {
                    _ = inferExpr(exprID, ctx: ctx, locals: &locals)
                }
            }
            sema.bindings.bindExprType(id, type: stringType)
            return stringType

        case .nameRef(let name, let nameRange):
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
                if !local.isInitialized {
                    ctx.semaCtx.diagnostics.error(
                        "KSWIFTK-SEMA-0031",
                        "Variable '\(interner.resolve(name))' must be initialized before use.",
                        range: nameRange
                    )
                }
                sema.bindings.bindIdentifier(id, symbol: local.symbol)
                sema.bindings.bindExprType(id, type: local.type)
                return local.type
            }
            let allCandidateIDs = scope.lookup(name)
            let (visibleIDs, invisibleSyms) = ctx.filterByVisibility(allCandidateIDs)
            let candidates = visibleIDs.compactMap { sema.symbols.symbol($0) }
            if candidates.isEmpty {
                if let firstInvisible = invisibleSyms.first {
                    let visLabel = firstInvisible.visibility == .protected ? "protected" : "private"
                    let code = firstInvisible.visibility == .protected ? "KSWIFTK-SEMA-0041" : "KSWIFTK-SEMA-0040"
                    ctx.semaCtx.diagnostics.error(
                        code,
                        "Cannot access '\(interner.resolve(name))': it is \(visLabel).",
                        range: nameRange
                    )
                } else {
                    ctx.semaCtx.diagnostics.error(
                        "KSWIFTK-SEMA-0022",
                        "Unresolved reference '\(interner.resolve(name))'.",
                        range: nameRange
                    )
                }
                sema.bindings.bindExprType(id, type: sema.types.errorType)
                return sema.types.errorType
            }
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
            return inferForExpr(id, loopVariable: loopVariable, iterableExpr: iterableExpr, bodyExpr: bodyExpr, range: range, ctx: ctx, locals: &locals)

        case .whileExpr(let conditionExpr, let bodyExpr, let range):
            return inferWhileExpr(id, conditionExpr: conditionExpr, bodyExpr: bodyExpr, range: range, ctx: ctx, locals: &locals)

        case .doWhileExpr(let bodyExpr, let conditionExpr, let range):
            return inferDoWhileExpr(id, bodyExpr: bodyExpr, conditionExpr: conditionExpr, range: range, ctx: ctx, locals: &locals)

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

        case .localDecl(let name, let isMutable, let typeAnnotation, let initializer, let range):
            return inferLocalDeclExpr(id, name: name, isMutable: isMutable, typeAnnotation: typeAnnotation, initializer: initializer, range: range, ctx: ctx, locals: &locals)

        case .localAssign(let name, let value, let range):
            return inferLocalAssignExpr(id, name: name, value: value, range: range, ctx: ctx, locals: &locals)

        case .arrayAccess(let arrayExpr, let indexExpr, let range):
            return inferArrayAccessExpr(id, arrayExpr: arrayExpr, indexExpr: indexExpr, range: range, ctx: ctx, locals: &locals)

        case .arrayAssign(let arrayExpr, let indexExpr, let valueExpr, let range):
            return inferArrayAssignExpr(id, arrayExpr: arrayExpr, indexExpr: indexExpr, valueExpr: valueExpr, range: range, ctx: ctx, locals: &locals)

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
            return inferIfExpr(id, condition: condition, thenExpr: thenExpr, elseExpr: elseExpr, ctx: ctx, locals: &locals, expectedType: expectedType)

        case .tryExpr(let body, let catchClauses, let finallyExpr, _):
            return inferTryExpr(id, body: body, catchClauses: catchClauses, finallyExpr: finallyExpr, ctx: ctx, locals: &locals, expectedType: expectedType)

        case .binary(let op, let lhsID, let rhsID, let range):
            return inferBinaryExpr(id, op: op, lhsID: lhsID, rhsID: rhsID, range: range, ctx: ctx, locals: &locals, expectedType: expectedType)

        case .call(let calleeID, let typeArgRefs, let args, let range):
            let explicitTypeArgs = resolveExplicitTypeArgs(typeArgRefs, ast: ast, sema: sema, interner: interner, diagnostics: ctx.semaCtx.diagnostics)
            return inferCallExpr(id, calleeID: calleeID, args: args, range: range, ctx: ctx, locals: &locals, expectedType: expectedType, explicitTypeArgs: explicitTypeArgs)

        case .memberCall(let receiverID, let calleeName, let typeArgRefs, let args, let range):
            let explicitTypeArgs = resolveExplicitTypeArgs(typeArgRefs, ast: ast, sema: sema, interner: interner, diagnostics: ctx.semaCtx.diagnostics)
            return inferMemberCallExpr(id, receiverID: receiverID, calleeName: calleeName, args: args, range: range, ctx: ctx, locals: &locals, expectedType: expectedType, explicitTypeArgs: explicitTypeArgs)

        case .unaryExpr(let op, let operandID, let range):
            let operandType = inferExpr(operandID, ctx: ctx, locals: &locals)
            let type: TypeID
            switch op {
            case .not:
                emitSubtypeConstraint(
                    left: operandType, right: boolType,
                    range: ast.arena.exprRange(operandID) ?? range,
                    solver: ConstraintSolver(), sema: sema,
                    diagnostics: ctx.semaCtx.diagnostics
                )
                type = boolType
            case .unaryPlus, .unaryMinus:
                type = operandType
            }
            sema.bindings.bindExprType(id, type: type)
            return type

        case .isCheck(let exprID, _, let negated, let range):
            _ = inferExpr(exprID, ctx: ctx, locals: &locals)
            let _ = negated
            let _ = range
            sema.bindings.bindExprType(id, type: boolType)
            return boolType

        case .asCast(let exprID, let typeRefID, let isSafe, _):
            _ = inferExpr(exprID, ctx: ctx, locals: &locals)
            let targetType = resolveTypeRef(typeRefID, ast: ast, sema: sema, interner: interner, diagnostics: ctx.semaCtx.diagnostics)
            let type: TypeID
            if isSafe {
                type = makeNullable(targetType, types: sema.types)
            } else {
                type = targetType
            }
            sema.bindings.bindExprType(id, type: type)
            return type

        case .nullAssert(let exprID, _):
            let operandType = inferExpr(exprID, ctx: ctx, locals: &locals)
            let type = makeNonNullable(operandType, types: sema.types)
            sema.bindings.bindExprType(id, type: type)
            return type

        case .safeMemberCall(let receiverID, let calleeName, let typeArgRefs, let args, let range):
            let explicitTypeArgs = resolveExplicitTypeArgs(typeArgRefs, ast: ast, sema: sema, interner: interner, diagnostics: ctx.semaCtx.diagnostics)
            return inferSafeMemberCallExpr(id, receiverID: receiverID, calleeName: calleeName, args: args, range: range, ctx: ctx, locals: &locals, expectedType: expectedType, explicitTypeArgs: explicitTypeArgs)

        case .compoundAssign(let op, let name, let valueExpr, let range):
            return inferCompoundAssignExpr(id, op: op, name: name, valueExpr: valueExpr, range: range, ctx: ctx, locals: &locals)

        case .whenExpr(let subjectID, let branches, let elseExpr, let range):
            return inferWhenExpr(id, subjectID: subjectID, branches: branches, elseExpr: elseExpr, range: range, ctx: ctx, locals: &locals, expectedType: expectedType)

        case .throwExpr(let value, _):
            _ = inferExpr(value, ctx: ctx, locals: &locals, expectedType: nil)
            sema.bindings.bindExprType(id, type: sema.types.nothingType)
            return sema.types.nothingType

        case .lambdaLiteral(let params, let body, _):
            let expectedFunctionType: FunctionType?
            if let expectedType,
               case .functionType(let functionType) = sema.types.kind(of: expectedType) {
                expectedFunctionType = functionType
            } else {
                expectedFunctionType = nil
            }

            var lambdaLocals = locals
            let outerSymbols = Set(locals.values.map { $0.symbol })
            let parameterTypes: [TypeID]
            if let expectedFunctionType, expectedFunctionType.params.count == params.count {
                parameterTypes = expectedFunctionType.params
            } else {
                parameterTypes = Array(repeating: sema.types.anyType, count: params.count)
            }
            for (offset, param) in params.enumerated() {
                let syntheticSymbol = SymbolID(rawValue: Int32(clamping: Int64(-1_000_000) - Int64(id.rawValue) * 256 - Int64(offset)))
                let parameterType = offset < parameterTypes.count ? parameterTypes[offset] : sema.types.anyType
                lambdaLocals[param] = (
                    type: parameterType,
                    symbol: syntheticSymbol,
                    isMutable: false,
                    isInitialized: true
                )
            }

            let inferredBodyType = inferExpr(
                body,
                ctx: ctx,
                locals: &lambdaLocals,
                expectedType: expectedFunctionType?.returnType
            )
            let captures = collectCapturedOuterSymbols(
                in: body,
                ast: ast,
                sema: sema,
                outerSymbols: outerSymbols
            )
            sema.bindings.bindCaptureSymbols(id, symbols: captures)

            if let expectedType, let expectedFunctionType {
                emitSubtypeConstraint(
                    left: inferredBodyType,
                    right: expectedFunctionType.returnType,
                    range: ast.arena.exprRange(body),
                    solver: ConstraintSolver(),
                    sema: sema,
                    diagnostics: ctx.semaCtx.diagnostics
                )
                sema.bindings.bindExprType(id, type: expectedType)
                return expectedType
            }

            let inferredFunctionType = sema.types.make(.functionType(FunctionType(
                params: parameterTypes,
                returnType: inferredBodyType,
                isSuspend: false,
                nullability: .nonNull
            )))
            sema.bindings.bindExprType(id, type: inferredFunctionType)
            return inferredFunctionType

        case .objectLiteral(let superTypes, _):
            let objectType = superTypes.first.map {
                resolveTypeRef($0, ast: ast, sema: sema, interner: interner, diagnostics: ctx.semaCtx.diagnostics)
            } ?? sema.types.anyType
            sema.bindings.bindExprType(id, type: objectType)
            return objectType

        case .callableRef(let receiver, let member, let range):
            let outerSymbols = Set(locals.values.map { $0.symbol })

            let receiverType: TypeID?
            if let receiver {
                receiverType = inferExpr(receiver, ctx: ctx, locals: &locals, expectedType: nil)
            } else {
                receiverType = nil
            }

            var candidates: [SymbolID] = []
            if let receiverType {
                let nonNullReceiver = makeNonNullable(receiverType, types: sema.types)
                let memberCandidates = collectMemberFunctionCandidates(
                    named: member,
                    receiverType: nonNullReceiver,
                    sema: sema
                )
                if !memberCandidates.isEmpty {
                    candidates = memberCandidates
                } else {
                    candidates = scope.lookup(member).filter { symbolID in
                        guard let symbol = sema.symbols.symbol(symbolID),
                              symbol.kind == .function,
                              let signature = sema.symbols.functionSignature(for: symbolID),
                              let declaredReceiver = signature.receiverType else {
                            return false
                        }
                        return sema.types.isSubtype(nonNullReceiver, declaredReceiver)
                    }
                }
            } else {
                candidates = scope.lookup(member).filter { symbolID in
                    guard let symbol = sema.symbols.symbol(symbolID) else {
                        return false
                    }
                    return symbol.kind == .function || symbol.kind == .constructor
                }
                if candidates.isEmpty,
                   let local = locals[member],
                   let localSymbol = sema.symbols.symbol(local.symbol),
                   localSymbol.kind == .function {
                    candidates = [local.symbol]
                }
            }

            let chosen = chooseCallableReferenceTarget(
                from: candidates,
                expectedType: expectedType,
                bindReceiver: receiver != nil,
                sema: sema
            )

            if let chosen,
               let signature = sema.symbols.functionSignature(for: chosen) {
                let inferredType = callableFunctionType(
                    for: signature,
                    bindReceiver: receiver != nil,
                    sema: sema
                )
                let resultType: TypeID
                if let expectedType,
                   case .functionType = sema.types.kind(of: expectedType) {
                    emitSubtypeConstraint(
                        left: inferredType,
                        right: expectedType,
                        range: range,
                        solver: ConstraintSolver(),
                        sema: sema,
                        diagnostics: ctx.semaCtx.diagnostics
                    )
                    resultType = expectedType
                } else {
                    resultType = inferredType
                }
                sema.bindings.bindIdentifier(id, symbol: chosen)
                sema.bindings.bindCallableTarget(id, target: .symbol(chosen))
                let captures = receiver.map { recv in
                    collectCapturedOuterSymbols(
                        in: recv,
                        ast: ast,
                        sema: sema,
                        outerSymbols: outerSymbols
                    )
                } ?? []
                sema.bindings.bindCaptureSymbols(id, symbols: captures)
                sema.bindings.bindExprType(id, type: resultType)
                return resultType
            }

            let fallbackType: TypeID
            if let expectedType,
               case .functionType = sema.types.kind(of: expectedType) {
                fallbackType = expectedType
            } else {
                fallbackType = sema.types.anyType
            }
            let fallbackCaptures = receiver.map { recv in
                collectCapturedOuterSymbols(
                    in: recv,
                    ast: ast,
                    sema: sema,
                    outerSymbols: outerSymbols
                )
            } ?? []
            sema.bindings.bindCaptureSymbols(id, symbols: fallbackCaptures)
            sema.bindings.bindExprType(id, type: fallbackType)
            return fallbackType

        case .blockExpr(let statements, let trailingExpr, _):
            var blockLocals = locals
            for stmt in statements {
                _ = inferExpr(stmt, ctx: ctx, locals: &blockLocals, expectedType: nil)
            }
            let resultType: TypeID
            if let trailingExpr {
                resultType = inferExpr(trailingExpr, ctx: ctx, locals: &blockLocals, expectedType: expectedType)
            } else {
                resultType = sema.types.unitType
            }
            // Propagate initialization state changes for outer-scope variables
            // back to the caller. New locals declared inside the block are not
            // propagated (they go out of scope), but if a variable that already
            // existed in `locals` was initialized inside the block, the updated
            // state should be visible to the caller.
            for (name, outerLocal) in locals {
                if let blockLocal = blockLocals[name],
                   blockLocal.symbol == outerLocal.symbol,
                   !outerLocal.isInitialized && blockLocal.isInitialized {
                    locals[name] = (outerLocal.type, outerLocal.symbol, outerLocal.isMutable, true)
                }
            }
            sema.bindings.bindExprType(id, type: resultType)
            return resultType

        case .localFunDecl(let name, let valueParams, let returnTypeRef, let body, let range):
            return inferLocalFunDeclExpr(id, name: name, valueParams: valueParams, returnTypeRef: returnTypeRef, body: body, range: range, ctx: ctx, locals: &locals)

        case .superRef(let range):
            guard let receiverType = ctx.implicitReceiverType else {
                ctx.semaCtx.diagnostics.error(
                    "KSWIFTK-SEMA-0050",
                    "'super' is not allowed outside of a class body.",
                    range: range
                )
                sema.bindings.bindExprType(id, type: sema.types.errorType)
                return sema.types.errorType
            }
            if let classSymbol = nominalSymbol(of: receiverType, types: sema.types) {
                let supertypes = sema.symbols.directSupertypes(for: classSymbol)
                let classSupertypes = supertypes.filter {
                    let kind = sema.symbols.symbol($0)?.kind
                    return kind == .class || kind == .enumClass
                }
                if let superclass = classSupertypes.first {
                    let superType = sema.types.make(.classType(ClassType(classSymbol: superclass)))
                    sema.bindings.bindExprType(id, type: superType)
                    return superType
                }
            }
            ctx.semaCtx.diagnostics.error(
                "KSWIFTK-SEMA-0052",
                "Class has no superclass.",
                range: range
            )
            sema.bindings.bindExprType(id, type: sema.types.errorType)
            return sema.types.errorType

        case .thisRef(let label, let range):
            guard let receiverType = ctx.implicitReceiverType else {
                ctx.semaCtx.diagnostics.error(
                    "KSWIFTK-SEMA-0051",
                    "'this' is not allowed in this context.",
                    range: range
                )
                sema.bindings.bindExprType(id, type: sema.types.errorType)
                return sema.types.errorType
            }
            if let label {
                if let qualifiedType = ctx.resolveQualifiedThis(label: label) {
                    sema.bindings.bindExprType(id, type: qualifiedType)
                    return qualifiedType
                }
                let labelStr = interner.resolve(label)
                ctx.semaCtx.diagnostics.error(
                    "KSWIFTK-SEMA-0053",
                    "Unresolved label '\(labelStr)' for qualified 'this'.",
                    range: range
                )
                sema.bindings.bindExprType(id, type: sema.types.errorType)
                return sema.types.errorType
            }
            sema.bindings.bindExprType(id, type: receiverType)
            return receiverType
        }
    }

    func applyFlowStateToLocals(
        _ state: DataFlowState,
        locals: inout [InternedString: (type: TypeID, symbol: SymbolID, isMutable: Bool, isInitialized: Bool)],
        sema: SemaModule
    ) {
        for (name, local) in locals {
            guard let varState = state.variables[local.symbol],
                  varState.possibleTypes.count == 1,
                  let narrowed = varState.possibleTypes.first else {
                continue
            }
            locals[name] = (narrowed, local.symbol, local.isMutable, local.isInitialized)
        }
    }
}

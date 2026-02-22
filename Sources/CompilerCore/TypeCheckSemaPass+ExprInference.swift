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

        case .call(let calleeID, _, let args, let range):
            return inferCallExpr(id, calleeID: calleeID, args: args, range: range, ctx: ctx, locals: &locals, expectedType: expectedType)

        case .memberCall(let receiverID, let calleeName, _, let args, let range):
            return inferMemberCallExpr(id, receiverID: receiverID, calleeName: calleeName, args: args, range: range, ctx: ctx, locals: &locals, expectedType: expectedType)

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

        case .safeMemberCall(let receiverID, let calleeName, _, let args, let range):
            return inferSafeMemberCallExpr(id, receiverID: receiverID, calleeName: calleeName, args: args, range: range, ctx: ctx, locals: &locals, expectedType: expectedType)

        case .compoundAssign(let op, let name, let valueExpr, let range):
            return inferCompoundAssignExpr(id, op: op, name: name, valueExpr: valueExpr, range: range, ctx: ctx, locals: &locals)

        case .whenExpr(let subjectID, let branches, let elseExpr, let range):
            return inferWhenExpr(id, subjectID: subjectID, branches: branches, elseExpr: elseExpr, range: range, ctx: ctx, locals: &locals, expectedType: expectedType)

        case .throwExpr(let value, _):
            _ = inferExpr(value, ctx: ctx, locals: &locals, expectedType: nil)
            sema.bindings.bindExprType(id, type: sema.types.nothingType)
            return sema.types.nothingType

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
            if label != nil {
                ctx.semaCtx.diagnostics.error(
                    "KSWIFTK-SEMA-0053",
                    "Qualified 'this@Label' is not yet supported.",
                    range: range
                )
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

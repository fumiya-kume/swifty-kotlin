import Foundation

/// Delegate class for KIR lowering: LambdaLowerer.
/// Holds an unowned reference to the driver for mutual recursion.

extension LambdaLowerer {
    func canCaptureSymbolForLambda(
        _ symbol: SymbolID,
        lambdaExprID: ExprID,
        lambdaParamCount: Int,
        sema: SemaModule
    ) -> Bool {
        if (0..<lambdaParamCount).contains(where: { index in
            symbol == syntheticLambdaParamSymbol(lambdaExprID: lambdaExprID, paramIndex: index)
        }) {
            return false
        }
        if driver.ctx.localValuesBySymbol[symbol] != nil {
            return true
        }
        if symbol == driver.ctx.currentImplicitReceiverSymbol,
           driver.ctx.currentImplicitReceiverExprID != nil {
            return true
        }
        guard let semanticSymbol = sema.symbols.symbol(symbol) else {
            return false
        }
        return semanticSymbol.kind == .valueParameter
    }

    func captureValueExpr(
        for symbol: SymbolID,
        sema: SemaModule,
        arena: KIRArena,
        emit instructions: inout KIRLoweringEmitContext
    ) -> KIRExprID? {
        return captureValueExpr(for: symbol, sema: sema, arena: arena, instructions: &instructions.instructions)
    }

    func uniqueSymbolsPreservingOrder(_ symbols: [SymbolID]) -> [SymbolID] {
        var seen: Set<SymbolID> = []
        var ordered: [SymbolID] = []
        ordered.reserveCapacity(symbols.count)
        for symbol in symbols where seen.insert(symbol).inserted {
            ordered.append(symbol)
        }
        return ordered
    }

    func collectBoundIdentifierSymbols(
        in exprID: ExprID,
        ast: ASTModule,
        sema: SemaModule,
        referenced: inout [SymbolID],
        seen: inout Set<SymbolID>
    ) {
        if let symbol = sema.bindings.identifierSymbols[exprID], seen.insert(symbol).inserted {
            referenced.append(symbol)
        }
        guard let expr = ast.arena.expr(exprID) else {
            return
        }

        switch expr {
        case .intLiteral,
             .longLiteral,
             .floatLiteral,
             .doubleLiteral,
             .charLiteral,
             .boolLiteral,
             .stringLiteral,
             .nameRef,
             .breakExpr,
             .continueExpr,
             .objectLiteral,
             .superRef,
             .thisRef:
            return

        case .stringTemplate(let parts, _):
            for part in parts {
                guard case .expression(let nestedExprID) = part else {
                    continue
                }
                collectBoundIdentifierSymbols(
                    in: nestedExprID,
                    ast: ast,
                    sema: sema,
                    referenced: &referenced,
                    seen: &seen
                )
            }

        case .forExpr(_, let iterableExpr, let bodyExpr, _, _):
            collectBoundIdentifierSymbols(in: iterableExpr, ast: ast, sema: sema, referenced: &referenced, seen: &seen)
            collectBoundIdentifierSymbols(in: bodyExpr, ast: ast, sema: sema, referenced: &referenced, seen: &seen)

        case .whileExpr(let conditionExpr, let bodyExpr, _, _):
            collectBoundIdentifierSymbols(in: conditionExpr, ast: ast, sema: sema, referenced: &referenced, seen: &seen)
            collectBoundIdentifierSymbols(in: bodyExpr, ast: ast, sema: sema, referenced: &referenced, seen: &seen)

        case .doWhileExpr(let bodyExpr, let conditionExpr, _, _):
            collectBoundIdentifierSymbols(in: bodyExpr, ast: ast, sema: sema, referenced: &referenced, seen: &seen)
            collectBoundIdentifierSymbols(in: conditionExpr, ast: ast, sema: sema, referenced: &referenced, seen: &seen)

        case .localDecl(_, _, _, let initializer, _):
            if let initializer {
                collectBoundIdentifierSymbols(in: initializer, ast: ast, sema: sema, referenced: &referenced, seen: &seen)
            }

        case .localAssign(_, let valueExpr, _):
            collectBoundIdentifierSymbols(in: valueExpr, ast: ast, sema: sema, referenced: &referenced, seen: &seen)

        case .indexedAssign(let receiverExpr, let indices, let valueExpr, _):
            collectBoundIdentifierSymbols(in: receiverExpr, ast: ast, sema: sema, referenced: &referenced, seen: &seen)
            for idx in indices { collectBoundIdentifierSymbols(in: idx, ast: ast, sema: sema, referenced: &referenced, seen: &seen) }
            collectBoundIdentifierSymbols(in: valueExpr, ast: ast, sema: sema, referenced: &referenced, seen: &seen)

        case .call(let calleeExpr, _, let args, _):
            collectBoundIdentifierSymbols(in: calleeExpr, ast: ast, sema: sema, referenced: &referenced, seen: &seen)
            for argument in args {
                collectBoundIdentifierSymbols(in: argument.expr, ast: ast, sema: sema, referenced: &referenced, seen: &seen)
            }

        case .memberCall(let receiverExpr, _, _, let args, _),
             .safeMemberCall(let receiverExpr, _, _, let args, _):
            collectBoundIdentifierSymbols(in: receiverExpr, ast: ast, sema: sema, referenced: &referenced, seen: &seen)
            for argument in args {
                collectBoundIdentifierSymbols(in: argument.expr, ast: ast, sema: sema, referenced: &referenced, seen: &seen)
            }

        case .indexedAccess(let receiverExpr, let indices, _):
            collectBoundIdentifierSymbols(in: receiverExpr, ast: ast, sema: sema, referenced: &referenced, seen: &seen)
            for idx in indices { collectBoundIdentifierSymbols(in: idx, ast: ast, sema: sema, referenced: &referenced, seen: &seen) }

        case .binary(_, let lhs, let rhs, _):
            collectBoundIdentifierSymbols(in: lhs, ast: ast, sema: sema, referenced: &referenced, seen: &seen)
            collectBoundIdentifierSymbols(in: rhs, ast: ast, sema: sema, referenced: &referenced, seen: &seen)

        case .whenExpr(let subjectExpr, let branches, let elseExpr, _):
            if let subjectExpr {
                collectBoundIdentifierSymbols(in: subjectExpr, ast: ast, sema: sema, referenced: &referenced, seen: &seen)
            }
            for branch in branches {
                for condition in branch.conditions {
                    collectBoundIdentifierSymbols(in: condition, ast: ast, sema: sema, referenced: &referenced, seen: &seen)
                }
                collectBoundIdentifierSymbols(in: branch.body, ast: ast, sema: sema, referenced: &referenced, seen: &seen)
            }
            if let elseExpr {
                collectBoundIdentifierSymbols(in: elseExpr, ast: ast, sema: sema, referenced: &referenced, seen: &seen)
            }

        case .returnExpr(let value, _, _):
            if let value {
                collectBoundIdentifierSymbols(in: value, ast: ast, sema: sema, referenced: &referenced, seen: &seen)
            }

        case .ifExpr(let condition, let thenExpr, let elseExpr, _):
            collectBoundIdentifierSymbols(in: condition, ast: ast, sema: sema, referenced: &referenced, seen: &seen)
            collectBoundIdentifierSymbols(in: thenExpr, ast: ast, sema: sema, referenced: &referenced, seen: &seen)
            if let elseExpr {
                collectBoundIdentifierSymbols(in: elseExpr, ast: ast, sema: sema, referenced: &referenced, seen: &seen)
            }

        case .tryExpr(let bodyExpr, let catchClauses, let finallyExpr, _):
            collectBoundIdentifierSymbols(in: bodyExpr, ast: ast, sema: sema, referenced: &referenced, seen: &seen)
            for catchClause in catchClauses {
                collectBoundIdentifierSymbols(in: catchClause.body, ast: ast, sema: sema, referenced: &referenced, seen: &seen)
            }
            if let finallyExpr {
                collectBoundIdentifierSymbols(in: finallyExpr, ast: ast, sema: sema, referenced: &referenced, seen: &seen)
            }

        case .unaryExpr(_, let operandExpr, _),
             .isCheck(let operandExpr, _, _, _),
             .asCast(let operandExpr, _, _, _),
             .nullAssert(let operandExpr, _),
             .throwExpr(let operandExpr, _):
            collectBoundIdentifierSymbols(in: operandExpr, ast: ast, sema: sema, referenced: &referenced, seen: &seen)

        case .compoundAssign(_, _, let valueExpr, _):
            collectBoundIdentifierSymbols(in: valueExpr, ast: ast, sema: sema, referenced: &referenced, seen: &seen)

        case .indexedCompoundAssign(_, let receiverExpr, let indices, let valueExpr, _):
            collectBoundIdentifierSymbols(in: receiverExpr, ast: ast, sema: sema, referenced: &referenced, seen: &seen)
            for idx in indices { collectBoundIdentifierSymbols(in: idx, ast: ast, sema: sema, referenced: &referenced, seen: &seen) }
            collectBoundIdentifierSymbols(in: valueExpr, ast: ast, sema: sema, referenced: &referenced, seen: &seen)

        case .lambdaLiteral(_, let bodyExpr, _, _):
            collectBoundIdentifierSymbols(in: bodyExpr, ast: ast, sema: sema, referenced: &referenced, seen: &seen)

        case .callableRef(let receiverExpr, _, _):
            if let receiverExpr {
                collectBoundIdentifierSymbols(in: receiverExpr, ast: ast, sema: sema, referenced: &referenced, seen: &seen)
            }

        case .localFunDecl(_, _, _, let functionBody, _):
            switch functionBody {
            case .block(let exprIDs, _):
                for nestedExpr in exprIDs {
                    collectBoundIdentifierSymbols(in: nestedExpr, ast: ast, sema: sema, referenced: &referenced, seen: &seen)
                }
            case .expr(let nestedExpr, _):
                collectBoundIdentifierSymbols(in: nestedExpr, ast: ast, sema: sema, referenced: &referenced, seen: &seen)
            case .unit:
                break
            }

        case .blockExpr(let statements, let trailingExpr, _):
            for statement in statements {
                collectBoundIdentifierSymbols(in: statement, ast: ast, sema: sema, referenced: &referenced, seen: &seen)
            }
            if let trailingExpr {
                collectBoundIdentifierSymbols(in: trailingExpr, ast: ast, sema: sema, referenced: &referenced, seen: &seen)
            }

        case .inExpr(let lhsExpr, let rhsExpr, _),
             .notInExpr(let lhsExpr, let rhsExpr, _):
            collectBoundIdentifierSymbols(in: lhsExpr, ast: ast, sema: sema, referenced: &referenced, seen: &seen)
            collectBoundIdentifierSymbols(in: rhsExpr, ast: ast, sema: sema, referenced: &referenced, seen: &seen)

        case .destructuringDecl(_, _, let initializer, _):
            collectBoundIdentifierSymbols(in: initializer, ast: ast, sema: sema, referenced: &referenced, seen: &seen)

        case .forDestructuringExpr(_, let iterable, let body, _):
            collectBoundIdentifierSymbols(in: iterable, ast: ast, sema: sema, referenced: &referenced, seen: &seen)
            collectBoundIdentifierSymbols(in: body, ast: ast, sema: sema, referenced: &referenced, seen: &seen)

        case .memberAssign(let receiverExpr, _, let valueExpr, _):
            collectBoundIdentifierSymbols(in: receiverExpr, ast: ast, sema: sema, referenced: &referenced, seen: &seen)
            collectBoundIdentifierSymbols(in: valueExpr, ast: ast, sema: sema, referenced: &referenced, seen: &seen)
        }
    }

    func containsImplicitReceiverReference(in exprID: ExprID, ast: ASTModule) -> Bool {
        guard let expr = ast.arena.expr(exprID) else {
            return false
        }
        switch expr {
        case .thisRef, .superRef:
            return true

        case .intLiteral,
             .longLiteral,
             .floatLiteral,
             .doubleLiteral,
             .charLiteral,
             .boolLiteral,
             .stringLiteral,
             .nameRef,
             .breakExpr,
             .continueExpr,
             .objectLiteral:
            return false

        case .stringTemplate(let parts, _):
            for part in parts {
                guard case .expression(let nestedExprID) = part else {
                    continue
                }
                if containsImplicitReceiverReference(in: nestedExprID, ast: ast) {
                    return true
                }
            }
            return false

        case .forExpr(_, let iterableExpr, let bodyExpr, _, _):
            return containsImplicitReceiverReference(in: iterableExpr, ast: ast)
                || containsImplicitReceiverReference(in: bodyExpr, ast: ast)

        case .whileExpr(let conditionExpr, let bodyExpr, _, _):
            return containsImplicitReceiverReference(in: conditionExpr, ast: ast)
                || containsImplicitReceiverReference(in: bodyExpr, ast: ast)

        case .doWhileExpr(let bodyExpr, let conditionExpr, _, _):
            return containsImplicitReceiverReference(in: bodyExpr, ast: ast)
                || containsImplicitReceiverReference(in: conditionExpr, ast: ast)

        case .localDecl(_, _, _, let initializer, _):
            guard let initializer else {
                return false
            }
            return containsImplicitReceiverReference(in: initializer, ast: ast)

        case .localAssign(_, let valueExpr, _):
            return containsImplicitReceiverReference(in: valueExpr, ast: ast)

        case .indexedAssign(let receiverExpr, let indices, let valueExpr, _):
            if containsImplicitReceiverReference(in: receiverExpr, ast: ast) { return true }
            for idx in indices { if containsImplicitReceiverReference(in: idx, ast: ast) { return true } }
            return containsImplicitReceiverReference(in: valueExpr, ast: ast)

        case .call(let calleeExpr, _, let args, _):
            if containsImplicitReceiverReference(in: calleeExpr, ast: ast) {
                return true
            }
            return args.contains { containsImplicitReceiverReference(in: $0.expr, ast: ast) }

        case .memberCall(let receiverExpr, _, _, let args, _),
             .safeMemberCall(let receiverExpr, _, _, let args, _):
            if containsImplicitReceiverReference(in: receiverExpr, ast: ast) {
                return true
            }
            return args.contains { containsImplicitReceiverReference(in: $0.expr, ast: ast) }

        case .indexedAccess(let receiverExpr, let indices, _):
            if containsImplicitReceiverReference(in: receiverExpr, ast: ast) { return true }
            return indices.contains { containsImplicitReceiverReference(in: $0, ast: ast) }

        case .binary(_, let lhsExpr, let rhsExpr, _):
            return containsImplicitReceiverReference(in: lhsExpr, ast: ast)
                || containsImplicitReceiverReference(in: rhsExpr, ast: ast)

        case .whenExpr(let subjectExpr, let branches, let elseExpr, _):
            if let subjectExpr,
               containsImplicitReceiverReference(in: subjectExpr, ast: ast) {
                return true
            }
            for branch in branches {
                for condition in branch.conditions {
                    if containsImplicitReceiverReference(in: condition, ast: ast) {
                        return true
                    }
                }
                if containsImplicitReceiverReference(in: branch.body, ast: ast) {
                    return true
                }
            }
            if let elseExpr,
               containsImplicitReceiverReference(in: elseExpr, ast: ast) {
                return true
            }
            return false

        case .returnExpr(let value, _, _):
            guard let value else {
                return false
            }
            return containsImplicitReceiverReference(in: value, ast: ast)

        case .ifExpr(let conditionExpr, let thenExpr, let elseExpr, _):
            if containsImplicitReceiverReference(in: conditionExpr, ast: ast)
                || containsImplicitReceiverReference(in: thenExpr, ast: ast) {
                return true
            }
            if let elseExpr {
                return containsImplicitReceiverReference(in: elseExpr, ast: ast)
            }
            return false

        case .tryExpr(let bodyExpr, let catchClauses, let finallyExpr, _):
            if containsImplicitReceiverReference(in: bodyExpr, ast: ast) {
                return true
            }
            for catchClause in catchClauses where containsImplicitReceiverReference(in: catchClause.body, ast: ast) {
                return true
            }
            if let finallyExpr {
                return containsImplicitReceiverReference(in: finallyExpr, ast: ast)
            }
            return false

        case .unaryExpr(_, let operandExpr, _),
             .isCheck(let operandExpr, _, _, _),
             .asCast(let operandExpr, _, _, _),
             .nullAssert(let operandExpr, _),
             .compoundAssign(_, _, let operandExpr, _),
             .throwExpr(let operandExpr, _):
            return containsImplicitReceiverReference(in: operandExpr, ast: ast)

        case .indexedCompoundAssign(_, let receiverExpr, let indices, let valueExpr, _):
            if containsImplicitReceiverReference(in: receiverExpr, ast: ast) { return true }
            for idx in indices { if containsImplicitReceiverReference(in: idx, ast: ast) { return true } }
            return containsImplicitReceiverReference(in: valueExpr, ast: ast)

        case .lambdaLiteral(_, let bodyExpr, _, _):
            return containsImplicitReceiverReference(in: bodyExpr, ast: ast)

        case .callableRef(let receiverExpr, _, _):
            guard let receiverExpr else {
                return false
            }
            return containsImplicitReceiverReference(in: receiverExpr, ast: ast)

        case .localFunDecl(_, _, _, let functionBody, _):
            switch functionBody {
            case .block(let exprIDs, _):
                return exprIDs.contains { containsImplicitReceiverReference(in: $0, ast: ast) }
            case .expr(let nestedExprID, _):
                return containsImplicitReceiverReference(in: nestedExprID, ast: ast)
            case .unit:
                return false
            }

        case .blockExpr(let statements, let trailingExpr, _):
            if statements.contains(where: { containsImplicitReceiverReference(in: $0, ast: ast) }) {
                return true
            }
            if let trailingExpr {
                return containsImplicitReceiverReference(in: trailingExpr, ast: ast)
            }
            return false

        case .inExpr(let lhsExpr, let rhsExpr, _),
             .notInExpr(let lhsExpr, let rhsExpr, _):
            return containsImplicitReceiverReference(in: lhsExpr, ast: ast)
                || containsImplicitReceiverReference(in: rhsExpr, ast: ast)

        case .destructuringDecl(_, _, let initializer, _):
            return containsImplicitReceiverReference(in: initializer, ast: ast)

        case .forDestructuringExpr(_, let iterable, let body, _):
            return containsImplicitReceiverReference(in: iterable, ast: ast)
                || containsImplicitReceiverReference(in: body, ast: ast)

        case .memberAssign(let receiverExpr, _, let valueExpr, _):
            return containsImplicitReceiverReference(in: receiverExpr, ast: ast)
                || containsImplicitReceiverReference(in: valueExpr, ast: ast)
        }
    }
}

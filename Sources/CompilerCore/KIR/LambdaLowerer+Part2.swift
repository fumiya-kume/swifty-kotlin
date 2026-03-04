import Foundation

// Delegate class for KIR lowering: LambdaLowerer.
// Holds an unowned reference to the driver for mutual recursion.

extension LambdaLowerer {
    func canCaptureSymbolForLambda(
        _ symbol: SymbolID,
        lambdaExprID: ExprID,
        lambdaParamCount: Int,
        sema: SemaModule
    ) -> Bool {
        if (0 ..< lambdaParamCount).contains(where: { index in
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
        captureValueExpr(for: symbol, sema: sema, arena: arena, instructions: &instructions.instructions)
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

        case let .stringTemplate(parts, _):
            for part in parts {
                guard case let .expression(nestedExprID) = part else {
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

        case let .forExpr(_, iterableExpr, bodyExpr, _, _):
            collectBoundIdentifierSymbols(in: iterableExpr, ast: ast, sema: sema, referenced: &referenced, seen: &seen)
            collectBoundIdentifierSymbols(in: bodyExpr, ast: ast, sema: sema, referenced: &referenced, seen: &seen)

        case let .whileExpr(conditionExpr, bodyExpr, _, _):
            collectBoundIdentifierSymbols(in: conditionExpr, ast: ast, sema: sema, referenced: &referenced, seen: &seen)
            collectBoundIdentifierSymbols(in: bodyExpr, ast: ast, sema: sema, referenced: &referenced, seen: &seen)

        case let .doWhileExpr(bodyExpr, conditionExpr, _, _):
            collectBoundIdentifierSymbols(in: bodyExpr, ast: ast, sema: sema, referenced: &referenced, seen: &seen)
            collectBoundIdentifierSymbols(in: conditionExpr, ast: ast, sema: sema, referenced: &referenced, seen: &seen)

        case let .localDecl(_, _, _, initializer, _):
            if let initializer {
                collectBoundIdentifierSymbols(in: initializer, ast: ast, sema: sema, referenced: &referenced, seen: &seen)
            }

        case let .localAssign(_, valueExpr, _):
            collectBoundIdentifierSymbols(in: valueExpr, ast: ast, sema: sema, referenced: &referenced, seen: &seen)

        case let .indexedAssign(receiverExpr, indices, valueExpr, _):
            collectBoundIdentifierSymbols(in: receiverExpr, ast: ast, sema: sema, referenced: &referenced, seen: &seen)
            for idx in indices {
                collectBoundIdentifierSymbols(in: idx, ast: ast, sema: sema, referenced: &referenced, seen: &seen)
            }
            collectBoundIdentifierSymbols(in: valueExpr, ast: ast, sema: sema, referenced: &referenced, seen: &seen)

        case let .call(calleeExpr, _, args, _):
            collectBoundIdentifierSymbols(in: calleeExpr, ast: ast, sema: sema, referenced: &referenced, seen: &seen)
            for argument in args {
                collectBoundIdentifierSymbols(in: argument.expr, ast: ast, sema: sema, referenced: &referenced, seen: &seen)
            }

        case let .memberCall(receiverExpr, _, _, args, _),
             let .safeMemberCall(receiverExpr, _, _, args, _):
            collectBoundIdentifierSymbols(in: receiverExpr, ast: ast, sema: sema, referenced: &referenced, seen: &seen)
            for argument in args {
                collectBoundIdentifierSymbols(in: argument.expr, ast: ast, sema: sema, referenced: &referenced, seen: &seen)
            }

        case let .indexedAccess(receiverExpr, indices, _):
            collectBoundIdentifierSymbols(in: receiverExpr, ast: ast, sema: sema, referenced: &referenced, seen: &seen)
            for idx in indices {
                collectBoundIdentifierSymbols(in: idx, ast: ast, sema: sema, referenced: &referenced, seen: &seen)
            }

        case let .binary(_, lhs, rhs, _):
            collectBoundIdentifierSymbols(in: lhs, ast: ast, sema: sema, referenced: &referenced, seen: &seen)
            collectBoundIdentifierSymbols(in: rhs, ast: ast, sema: sema, referenced: &referenced, seen: &seen)

        case let .whenExpr(subjectExpr, branches, elseExpr, _):
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

        case let .returnExpr(value, _, _):
            if let value {
                collectBoundIdentifierSymbols(in: value, ast: ast, sema: sema, referenced: &referenced, seen: &seen)
            }

        case let .ifExpr(condition, thenExpr, elseExpr, _):
            collectBoundIdentifierSymbols(in: condition, ast: ast, sema: sema, referenced: &referenced, seen: &seen)
            collectBoundIdentifierSymbols(in: thenExpr, ast: ast, sema: sema, referenced: &referenced, seen: &seen)
            if let elseExpr {
                collectBoundIdentifierSymbols(in: elseExpr, ast: ast, sema: sema, referenced: &referenced, seen: &seen)
            }

        case let .tryExpr(bodyExpr, catchClauses, finallyExpr, _):
            collectBoundIdentifierSymbols(in: bodyExpr, ast: ast, sema: sema, referenced: &referenced, seen: &seen)
            for catchClause in catchClauses {
                collectBoundIdentifierSymbols(in: catchClause.body, ast: ast, sema: sema, referenced: &referenced, seen: &seen)
            }
            if let finallyExpr {
                collectBoundIdentifierSymbols(in: finallyExpr, ast: ast, sema: sema, referenced: &referenced, seen: &seen)
            }

        case let .unaryExpr(_, operandExpr, _),
             let .isCheck(operandExpr, _, _, _),
             let .asCast(operandExpr, _, _, _),
             let .nullAssert(operandExpr, _),
             let .throwExpr(operandExpr, _):
            collectBoundIdentifierSymbols(in: operandExpr, ast: ast, sema: sema, referenced: &referenced, seen: &seen)

        case let .compoundAssign(_, _, valueExpr, _):
            collectBoundIdentifierSymbols(in: valueExpr, ast: ast, sema: sema, referenced: &referenced, seen: &seen)

        case let .indexedCompoundAssign(_, receiverExpr, indices, valueExpr, _):
            collectBoundIdentifierSymbols(in: receiverExpr, ast: ast, sema: sema, referenced: &referenced, seen: &seen)
            for idx in indices {
                collectBoundIdentifierSymbols(in: idx, ast: ast, sema: sema, referenced: &referenced, seen: &seen)
            }
            collectBoundIdentifierSymbols(in: valueExpr, ast: ast, sema: sema, referenced: &referenced, seen: &seen)

        case let .lambdaLiteral(_, bodyExpr, _, _):
            collectBoundIdentifierSymbols(in: bodyExpr, ast: ast, sema: sema, referenced: &referenced, seen: &seen)

        case let .callableRef(receiverExpr, _, _):
            if let receiverExpr {
                collectBoundIdentifierSymbols(in: receiverExpr, ast: ast, sema: sema, referenced: &referenced, seen: &seen)
            }

        case let .localFunDecl(_, _, _, functionBody, _):
            switch functionBody {
            case let .block(exprIDs, _):
                for nestedExpr in exprIDs {
                    collectBoundIdentifierSymbols(in: nestedExpr, ast: ast, sema: sema, referenced: &referenced, seen: &seen)
                }
            case let .expr(nestedExpr, _):
                collectBoundIdentifierSymbols(in: nestedExpr, ast: ast, sema: sema, referenced: &referenced, seen: &seen)
            case .unit:
                break
            }

        case let .blockExpr(statements, trailingExpr, _):
            for statement in statements {
                collectBoundIdentifierSymbols(in: statement, ast: ast, sema: sema, referenced: &referenced, seen: &seen)
            }
            if let trailingExpr {
                collectBoundIdentifierSymbols(in: trailingExpr, ast: ast, sema: sema, referenced: &referenced, seen: &seen)
            }

        case let .inExpr(lhsExpr, rhsExpr, _),
             let .notInExpr(lhsExpr, rhsExpr, _):
            collectBoundIdentifierSymbols(in: lhsExpr, ast: ast, sema: sema, referenced: &referenced, seen: &seen)
            collectBoundIdentifierSymbols(in: rhsExpr, ast: ast, sema: sema, referenced: &referenced, seen: &seen)

        case let .destructuringDecl(_, _, initializer, _):
            collectBoundIdentifierSymbols(in: initializer, ast: ast, sema: sema, referenced: &referenced, seen: &seen)

        case let .forDestructuringExpr(_, iterable, body, _):
            collectBoundIdentifierSymbols(in: iterable, ast: ast, sema: sema, referenced: &referenced, seen: &seen)
            collectBoundIdentifierSymbols(in: body, ast: ast, sema: sema, referenced: &referenced, seen: &seen)

        case let .memberAssign(receiverExpr, _, valueExpr, _):
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

        case let .stringTemplate(parts, _):
            for part in parts {
                guard case let .expression(nestedExprID) = part else {
                    continue
                }
                if containsImplicitReceiverReference(in: nestedExprID, ast: ast) {
                    return true
                }
            }
            return false

        case let .forExpr(_, iterableExpr, bodyExpr, _, _):
            return containsImplicitReceiverReference(in: iterableExpr, ast: ast)
                || containsImplicitReceiverReference(in: bodyExpr, ast: ast)

        case let .whileExpr(conditionExpr, bodyExpr, _, _):
            return containsImplicitReceiverReference(in: conditionExpr, ast: ast)
                || containsImplicitReceiverReference(in: bodyExpr, ast: ast)

        case let .doWhileExpr(bodyExpr, conditionExpr, _, _):
            return containsImplicitReceiverReference(in: bodyExpr, ast: ast)
                || containsImplicitReceiverReference(in: conditionExpr, ast: ast)

        case let .localDecl(_, _, _, initializer, _):
            guard let initializer else {
                return false
            }
            return containsImplicitReceiverReference(in: initializer, ast: ast)

        case let .localAssign(_, valueExpr, _):
            return containsImplicitReceiverReference(in: valueExpr, ast: ast)

        case let .indexedAssign(receiverExpr, indices, valueExpr, _):
            if containsImplicitReceiverReference(in: receiverExpr, ast: ast) { return true }
            for idx in indices where containsImplicitReceiverReference(in: idx, ast: ast) {
                return true
            }
            return containsImplicitReceiverReference(in: valueExpr, ast: ast)

        case let .call(calleeExpr, _, args, _):
            if containsImplicitReceiverReference(in: calleeExpr, ast: ast) {
                return true
            }
            return args.contains { containsImplicitReceiverReference(in: $0.expr, ast: ast) }

        case let .memberCall(receiverExpr, _, _, args, _),
             let .safeMemberCall(receiverExpr, _, _, args, _):
            if containsImplicitReceiverReference(in: receiverExpr, ast: ast) {
                return true
            }
            return args.contains { containsImplicitReceiverReference(in: $0.expr, ast: ast) }

        case let .indexedAccess(receiverExpr, indices, _):
            if containsImplicitReceiverReference(in: receiverExpr, ast: ast) { return true }
            return indices.contains { containsImplicitReceiverReference(in: $0, ast: ast) }

        case let .binary(_, lhsExpr, rhsExpr, _):
            return containsImplicitReceiverReference(in: lhsExpr, ast: ast)
                || containsImplicitReceiverReference(in: rhsExpr, ast: ast)

        case let .whenExpr(subjectExpr, branches, elseExpr, _):
            if let subjectExpr,
               containsImplicitReceiverReference(in: subjectExpr, ast: ast) {
                return true
            }
            for branch in branches {
                for condition in branch.conditions where containsImplicitReceiverReference(in: condition, ast: ast) {
                    return true
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

        case let .returnExpr(value, _, _):
            guard let value else {
                return false
            }
            return containsImplicitReceiverReference(in: value, ast: ast)

        case let .ifExpr(conditionExpr, thenExpr, elseExpr, _):
            if containsImplicitReceiverReference(in: conditionExpr, ast: ast)
                || containsImplicitReceiverReference(in: thenExpr, ast: ast) {
                return true
            }
            if let elseExpr {
                return containsImplicitReceiverReference(in: elseExpr, ast: ast)
            }
            return false

        case let .tryExpr(bodyExpr, catchClauses, finallyExpr, _):
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

        case let .unaryExpr(_, operandExpr, _),
             let .isCheck(operandExpr, _, _, _),
             let .asCast(operandExpr, _, _, _),
             let .nullAssert(operandExpr, _),
             let .compoundAssign(_, _, operandExpr, _),
             let .throwExpr(operandExpr, _):
            return containsImplicitReceiverReference(in: operandExpr, ast: ast)

        case let .indexedCompoundAssign(_, receiverExpr, indices, valueExpr, _):
            if containsImplicitReceiverReference(in: receiverExpr, ast: ast) { return true }
            for idx in indices where containsImplicitReceiverReference(in: idx, ast: ast) {
                return true
            }
            return containsImplicitReceiverReference(in: valueExpr, ast: ast)

        case let .lambdaLiteral(_, bodyExpr, _, _):
            return containsImplicitReceiverReference(in: bodyExpr, ast: ast)

        case let .callableRef(receiverExpr, _, _):
            guard let receiverExpr else {
                return false
            }
            return containsImplicitReceiverReference(in: receiverExpr, ast: ast)

        case let .localFunDecl(_, _, _, functionBody, _):
            switch functionBody {
            case let .block(exprIDs, _):
                return exprIDs.contains { containsImplicitReceiverReference(in: $0, ast: ast) }
            case let .expr(nestedExprID, _):
                return containsImplicitReceiverReference(in: nestedExprID, ast: ast)
            case .unit:
                return false
            }

        case let .blockExpr(statements, trailingExpr, _):
            if statements.contains(where: { containsImplicitReceiverReference(in: $0, ast: ast) }) {
                return true
            }
            if let trailingExpr {
                return containsImplicitReceiverReference(in: trailingExpr, ast: ast)
            }
            return false

        case let .inExpr(lhsExpr, rhsExpr, _),
             let .notInExpr(lhsExpr, rhsExpr, _):
            return containsImplicitReceiverReference(in: lhsExpr, ast: ast)
                || containsImplicitReceiverReference(in: rhsExpr, ast: ast)

        case let .destructuringDecl(_, _, initializer, _):
            return containsImplicitReceiverReference(in: initializer, ast: ast)

        case let .forDestructuringExpr(_, iterable, body, _):
            return containsImplicitReceiverReference(in: iterable, ast: ast)
                || containsImplicitReceiverReference(in: body, ast: ast)

        case let .memberAssign(receiverExpr, _, valueExpr, _):
            return containsImplicitReceiverReference(in: receiverExpr, ast: ast)
                || containsImplicitReceiverReference(in: valueExpr, ast: ast)
        }
    }
}

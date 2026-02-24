import Foundation

/// Stateless utility for analyzing captured outer symbols in closures and local functions.
/// Derived from TypeCheckSemaPass+CaptureAnalysis.swift.
struct CaptureAnalyzer {
    func collectCapturedOuterSymbols(
        in exprID: ExprID,
        ast: ASTModule,
        sema: SemaModule,
        outerSymbols: Set<SymbolID>,
        skipNestedClosures: Bool = true
    ) -> [SymbolID] {
        guard !outerSymbols.isEmpty else {
            return []
        }

        var captured: Set<SymbolID> = []

        func recordCapture(for targetExprID: ExprID) {
            guard let symbol = sema.bindings.identifierSymbol(for: targetExprID),
                  outerSymbols.contains(symbol) else {
                return
            }
            captured.insert(symbol)
        }

        func visitBody(_ body: FunctionBody) {
            switch body {
            case .block(let exprs, _):
                for expr in exprs {
                    visit(expr)
                }
            case .expr(let expr, _):
                visit(expr)
            case .unit:
                break
            }
        }

        func visit(_ currentExprID: ExprID) {
            guard let expr = ast.arena.expr(currentExprID) else {
                return
            }
            switch expr {
            case .nameRef:
                recordCapture(for: currentExprID)

            case .forExpr(_, let iterable, let body, _):
                visit(iterable)
                visit(body)

            case .whileExpr(let condition, let body, _):
                visit(condition)
                visit(body)

            case .doWhileExpr(let body, let condition, _):
                visit(body)
                visit(condition)

            case .localDecl(_, _, _, let initializer, _):
                if let initializer {
                    visit(initializer)
                }

            case .localAssign(_, let value, _):
                visit(value)

            case .indexedAssign(let receiver, let indices, let value, _):
                visit(receiver)
                for idx in indices { visit(idx) }
                visit(value)

            case .call(let callee, _, let args, _):
                visit(callee)
                for arg in args {
                    visit(arg.expr)
                }

            case .memberCall(let receiver, _, _, let args, _):
                visit(receiver)
                for arg in args {
                    visit(arg.expr)
                }

            case .indexedAccess(let receiver, let indices, _):
                visit(receiver)
                for idx in indices { visit(idx) }

            case .binary(_, let lhs, let rhs, _):
                visit(lhs)
                visit(rhs)

            case .whenExpr(let subject, let branches, let elseExpr, _):
                if let subject {
                    visit(subject)
                }
                for branch in branches {
                    for condition in branch.conditions {
                        visit(condition)
                    }
                    visit(branch.body)
                }
                if let elseExpr {
                    visit(elseExpr)
                }

            case .returnExpr(let value, _):
                if let value {
                    visit(value)
                }

            case .ifExpr(let condition, let thenExpr, let elseExpr, _):
                visit(condition)
                visit(thenExpr)
                if let elseExpr {
                    visit(elseExpr)
                }

            case .tryExpr(let body, let catchClauses, let finallyExpr, _):
                visit(body)
                for catchClause in catchClauses {
                    visit(catchClause.body)
                }
                if let finallyExpr {
                    visit(finallyExpr)
                }

            case .unaryExpr(_, let operand, _):
                visit(operand)

            case .isCheck(let value, _, _, _):
                visit(value)

            case .asCast(let value, _, _, _):
                visit(value)

            case .nullAssert(let value, _):
                visit(value)

            case .safeMemberCall(let receiver, _, _, let args, _):
                visit(receiver)
                for arg in args {
                    visit(arg.expr)
                }

            case .compoundAssign(_, _, let value, _):
                visit(value)

            case .indexedCompoundAssign(_, let receiver, let indices, let value, _):
                visit(receiver)
                for idx in indices { visit(idx) }
                visit(value)

            case .throwExpr(let value, _):
                visit(value)

            case .lambdaLiteral(_, let body, _):
                if !skipNestedClosures {
                    visit(body)
                }

            case .callableRef(let receiver, _, _):
                if let receiver {
                    visit(receiver)
                }

            case .localFunDecl(_, _, _, let body, _):
                if !skipNestedClosures {
                    visitBody(body)
                }

            case .blockExpr(let statements, let trailingExpr, _):
                for statement in statements {
                    visit(statement)
                }
                if let trailingExpr {
                    visit(trailingExpr)
                }

            case .stringTemplate(let parts, _):
                for part in parts {
                    if case .expression(let expr) = part {
                        visit(expr)
                    }
                }

            case .inExpr(let lhs, let rhs, _),
                 .notInExpr(let lhs, let rhs, _):
                visit(lhs)
                visit(rhs)

            case .intLiteral, .longLiteral, .floatLiteral, .doubleLiteral,
                 .charLiteral, .boolLiteral, .stringLiteral, .breakExpr,
                 .continueExpr, .objectLiteral, .superRef, .thisRef:
                break
            }
        }

        visit(exprID)
        return captured.sorted(by: { $0.rawValue < $1.rawValue })
    }
}

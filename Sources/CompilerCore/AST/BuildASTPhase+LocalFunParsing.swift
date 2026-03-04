import Foundation

extension BuildASTPhase {
    func parseLocalFunDeclExpr(
        from statementTokens: [Token],
        interner: StringInterner,
        astArena: ASTArena
    ) -> ExprID? {
        guard let head = statementTokens.first,
              case .keyword(.fun) = head.kind
        else {
            return nil
        }

        guard let nameToken = statementTokens.dropFirst().first(where: { token in
            isTypeLikeNameToken(token.kind)
        }),
            let name = internedIdentifier(from: nameToken, interner: interner)
        else {
            return nil
        }

        guard let lParenIndex = statementTokens.firstIndex(where: { $0.kind == .symbol(.lParen) }) else {
            return nil
        }

        var valueParams: [ValueParamDecl] = []
        var depth = BracketDepth()
        var paramTokens: [Token] = []
        var index = lParenIndex + 1
        while index < statementTokens.count {
            let token = statementTokens[index]
            if token.kind == .symbol(.rParen), depth.paren == 0 {
                break
            }
            depth.track(token.kind)
            if token.kind == .symbol(.comma), depth.isAtTopLevel {
                appendValueParameter(from: paramTokens, into: &valueParams, interner: interner, astArena: astArena)
                paramTokens.removeAll(keepingCapacity: true)
            } else {
                paramTokens.append(token)
            }
            index += 1
        }
        if !paramTokens.isEmpty {
            appendValueParameter(from: paramTokens, into: &valueParams, interner: interner, astArena: astArena)
        }

        guard index < statementTokens.count, statementTokens[index].kind == .symbol(.rParen) else {
            return nil
        }
        index += 1

        var returnType: TypeRefID?
        if index < statementTokens.count, statementTokens[index].kind == .symbol(.colon) {
            index += 1
            var typeTokens: [Token] = []
            var typeDepth = BracketDepth()
            while index < statementTokens.count {
                let token = statementTokens[index]
                if typeDepth.isAtTopLevel {
                    if token.kind == .symbol(.lBrace) || token.kind == .symbol(.assign) {
                        break
                    }
                }
                typeDepth.track(token.kind)
                typeTokens.append(token)
                index += 1
            }
            returnType = parseTypeRef(from: typeTokens, interner: interner, astArena: astArena)
        }

        let body: FunctionBody
        if index < statementTokens.count, statementTokens[index].kind == .symbol(.assign) {
            index += 1
            let exprTokens = Array(statementTokens[index...]).filter { $0.kind != .symbol(.semicolon) }
            let parser = ExpressionParser(tokens: exprTokens, interner: interner, astArena: astArena)
            if let exprID = parser.parse(), let exprRange = astArena.exprRange(exprID) {
                body = .expr(exprID, exprRange)
            } else {
                body = .unit
            }
        } else if index < statementTokens.count, statementTokens[index].kind == .symbol(.lBrace) {
            var braceDepth = 0
            var bodyTokens: [Token] = []
            let braceStart = index
            while index < statementTokens.count {
                let token = statementTokens[index]
                if token.kind == .symbol(.lBrace) {
                    braceDepth += 1
                } else if token.kind == .symbol(.rBrace) {
                    braceDepth -= 1
                    if braceDepth == 0 {
                        index += 1
                        break
                    }
                }
                if braceDepth >= 1, !(braceDepth == 1 && token.kind == .symbol(.lBrace)) {
                    bodyTokens.append(token)
                }
                index += 1
            }
            if !bodyTokens.isEmpty {
                let stmtGroups = splitTokensIntoStatements(bodyTokens)
                var blockExprs: [ExprID] = []
                for stmtTokens in stmtGroups {
                    let filtered = stmtTokens.filter { $0.kind != .symbol(.semicolon) }
                    guard !filtered.isEmpty else { continue }
                    if let localFun = parseLocalFunDeclExpr(from: stmtTokens, interner: interner, astArena: astArena) {
                        blockExprs.append(localFun)
                    } else if let localDecl = parseLocalDeclarationExpr(from: filtered, interner: interner, astArena: astArena) {
                        blockExprs.append(localDecl)
                    } else if let localAssign = parseLocalAssignmentExpr(from: filtered, interner: interner, astArena: astArena) {
                        blockExprs.append(localAssign)
                    } else {
                        let parser = ExpressionParser(tokens: filtered, interner: interner, astArena: astArena)
                        if let exprID = parser.parse() {
                            blockExprs.append(exprID)
                        }
                    }
                }
                if !blockExprs.isEmpty,
                   let firstRange = astArena.exprRange(blockExprs.first!),
                   let lastRange = astArena.exprRange(blockExprs.last!) {
                    let bodyRange = SourceRange(start: firstRange.start, end: lastRange.end)
                    body = .block(blockExprs, bodyRange)
                } else {
                    let bodyRange = SourceRange(
                        start: statementTokens[braceStart].range.start,
                        end: statementTokens[min(index, statementTokens.count - 1)].range.end
                    )
                    body = .block([], bodyRange)
                }
            } else {
                let bodyRange = SourceRange(
                    start: statementTokens[braceStart].range.start,
                    end: statementTokens[min(index, statementTokens.count - 1)].range.end
                )
                body = .block([], bodyRange)
            }
        } else {
            body = .unit
        }

        let end: SourceLocation = switch body {
        case let .block(_, range):
            range.end
        case let .expr(_, range):
            range.end
        case .unit:
            statementTokens.last?.range.end ?? head.range.end
        }
        let range = SourceRange(start: head.range.start, end: end)
        return astArena.appendExpr(.localFunDecl(
            name: name,
            valueParams: valueParams,
            returnType: returnType,
            body: body,
            range: range
        ))
    }
}

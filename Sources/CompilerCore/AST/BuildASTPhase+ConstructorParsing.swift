import Foundation

extension BuildASTPhase {
    internal func declarationInitBlocks(
        from nodeID: NodeID,
        in arena: SyntaxArena,
        interner: StringInterner,
        astArena: ASTArena
    ) -> [FunctionBody] {
        var result: [FunctionBody] = []
        for child in arena.children(of: nodeID) {
            guard case .node(let bodyBlockID) = child,
                  arena.node(bodyBlockID).kind == .block else {
                continue
            }
            for bodyChild in arena.children(of: bodyBlockID) {
                guard case .node(let statementID) = bodyChild,
                      isStatementLikeKind(arena.node(statementID).kind) else {
                    continue
                }
                let headerTokens = collectDirectTokens(from: statementID, in: arena).filter { token in
                    token.kind != .symbol(.semicolon)
                }
                guard let firstToken = headerTokens.first,
                      firstToken.kind == .softKeyword(.`init`) else {
                    continue
                }

                if let nestedBlockID = arena.children(of: statementID).compactMap({ inner -> NodeID? in
                    guard case .node(let nodeID) = inner,
                          arena.node(nodeID).kind == .block else {
                        return nil
                    }
                    return nodeID
                }).first {
                    let exprs = blockExpressions(
                        from: nestedBlockID,
                        in: arena,
                        interner: interner,
                        astArena: astArena
                    )
                    result.append(.block(exprs, arena.node(nestedBlockID).range))
                    continue
                }

                if headerTokens.count > 1 {
                    let parser = ExpressionParser(
                        tokens: Array(headerTokens.dropFirst()),
                        interner: interner,
                        astArena: astArena
                    )
                    if let exprID = parser.parse(),
                       let range = astArena.exprRange(exprID) {
                        result.append(.expr(exprID, range))
                        continue
                    }
                }
                result.append(.unit)
            }
        }
        return result
    }

    internal func declarationSecondaryConstructors(
        from nodeID: NodeID,
        in arena: SyntaxArena,
        interner: StringInterner,
        astArena: ASTArena
    ) -> [ConstructorDecl] {
        var result: [ConstructorDecl] = []
        for child in arena.children(of: nodeID) {
            guard case .node(let bodyBlockID) = child,
                  arena.node(bodyBlockID).kind == .block else {
                continue
            }
            for bodyChild in arena.children(of: bodyBlockID) {
                guard case .node(let ctorNodeID) = bodyChild,
                      arena.node(ctorNodeID).kind == .constructorDecl else {
                    continue
                }
                let ctorNode = arena.node(ctorNodeID)
                let params = declarationValueParameters(from: ctorNodeID, in: arena, interner: interner, astArena: astArena)
                let delegationCall = extractDelegationCall(from: ctorNodeID, in: arena, interner: interner, astArena: astArena)
                let body: FunctionBody
                if let blockID = arena.children(of: ctorNodeID).compactMap({ child -> NodeID? in
                    guard case .node(let id) = child, arena.node(id).kind == .block else { return nil }
                    return id
                }).first {
                    let exprs = blockExpressions(from: blockID, in: arena, interner: interner, astArena: astArena)
                    body = .block(exprs, arena.node(blockID).range)
                } else {
                    body = .unit
                }
                result.append(ConstructorDecl(
                    range: ctorNode.range,
                    modifiers: declarationModifiers(from: ctorNodeID, in: arena),
                    valueParams: params,
                    delegationCall: delegationCall,
                    body: body
                ))
            }
        }
        return result
    }

    internal func extractDelegationCall(
        from nodeID: NodeID,
        in arena: SyntaxArena,
        interner: StringInterner,
        astArena: ASTArena
    ) -> ConstructorDelegationCall? {
        let tokens = collectTokens(from: nodeID, in: arena)
        var index = 0
        var parenDepth = 0
        var foundFirstParens = false
        while index < tokens.count {
            let token = tokens[index]
            if token.kind == .symbol(.lParen) {
                parenDepth += 1
                if !foundFirstParens {
                    foundFirstParens = true
                }
            }
            if token.kind == .symbol(.rParen) {
                parenDepth -= 1
                if parenDepth == 0 && foundFirstParens {
                    index += 1
                    break
                }
            }
            index += 1
        }

        guard index < tokens.count else { return nil }

        if tokens[index].kind == .symbol(.colon) {
            index += 1
        }

        guard index < tokens.count else { return nil }

        let kind: ConstructorDelegationKind
        if tokens[index].kind == .keyword(.this) {
            kind = .this
            index += 1
        } else if tokens[index].kind == .keyword(.super) {
            kind = .super_
            index += 1
        } else {
            return nil
        }

        let range = tokens[index - 1].range

        var args: [CallArgument] = []
        if index < tokens.count, tokens[index].kind == .symbol(.lParen) {
            index += 1
            var argTokens: [Token] = []
            var depth = 0
            while index < tokens.count {
                let t = tokens[index]
                if t.kind == .symbol(.lParen) { depth += 1 }
                if t.kind == .symbol(.rParen) {
                    if depth == 0 { index += 1; break }
                    depth -= 1
                }
                if t.kind == .symbol(.comma) && depth == 0 {
                    if !argTokens.isEmpty {
                        let parser = ExpressionParser(tokens: argTokens, interner: interner, astArena: astArena)
                        if let exprID = parser.parse() {
                            args.append(CallArgument(expr: exprID))
                        }
                        argTokens.removeAll(keepingCapacity: true)
                    }
                } else {
                    argTokens.append(t)
                }
                index += 1
            }
            if !argTokens.isEmpty {
                let parser = ExpressionParser(tokens: argTokens, interner: interner, astArena: astArena)
                if let exprID = parser.parse() {
                    args.append(CallArgument(expr: exprID))
                }
            }
        }

        return ConstructorDelegationCall(kind: kind, args: args, range: range)
    }
}

import Foundation

extension BuildASTPhase {
    func declarationIsVar(from nodeID: NodeID, in arena: SyntaxArena) -> Bool {
        for child in arena.children(of: nodeID) {
            if case .token(let tokenID) = child,
               let token = resolveToken(tokenID, in: arena),
               token.kind == .keyword(.var) {
                return true
            }
        }
        return false
    }

    func declarationPropertyInitializer(
        from nodeID: NodeID,
        in arena: SyntaxArena,
        interner: StringInterner,
        astArena: ASTArena
    ) -> ExprID? {
        let tokens = propertyHeadTokens(from: nodeID, in: arena)
        guard !tokens.isEmpty else {
            return nil
        }

        var assignIndex: Int?
        var depth = BracketDepth()
        for (index, token) in tokens.enumerated() {
            if case .softKeyword(.by) = token.kind, depth.isAtTopLevel {
                return nil
            }
            if token.kind == .symbol(.assign) && depth.isAtTopLevel {
                assignIndex = index
                break
            }
            depth.track(token.kind)
        }

        guard let assignIndex else {
            return nil
        }
        let start = assignIndex + 1
        guard start < tokens.count else {
            return nil
        }
        let exprTokens = tokens[start...].filter { $0.kind != .symbol(.semicolon) }
        guard !exprTokens.isEmpty else {
            return nil
        }
        let parser = ExpressionParser(tokens: Array(exprTokens), interner: interner, astArena: astArena)
        return parser.parse()
    }

    func declarationPropertyAccessors(
        from nodeID: NodeID,
        in arena: SyntaxArena,
        interner: StringInterner,
        astArena: ASTArena
    ) -> (getter: PropertyAccessorDecl?, setter: PropertyAccessorDecl?) {
        var getter: PropertyAccessorDecl?
        var setter: PropertyAccessorDecl?

        guard let accessorBlockID = arena.children(of: nodeID).compactMap({ child -> NodeID? in
            guard case .node(let childID) = child,
                  arena.node(childID).kind == .block else {
                return nil
            }
            return childID
        }).first else {
            return (nil, nil)
        }

        for child in arena.children(of: accessorBlockID) {
            guard case .node(let statementID) = child,
                  arena.node(statementID).kind == .statement else {
                continue
            }

            let headerTokens = collectDirectTokens(from: statementID, in: arena).filter { token in
                token.kind != .symbol(.semicolon)
            }
            guard let firstToken = headerTokens.first else {
                continue
            }

            let kind: PropertyAccessorKind
            switch firstToken.kind {
            case .softKeyword(.get):
                kind = .getter
            case .softKeyword(.set):
                kind = .setter
            default:
                continue
            }

            let parameterName: InternedString?
            if kind == .setter {
                parameterName = setterParameterName(from: headerTokens, interner: interner)
            } else {
                parameterName = nil
            }

            let body = accessorBody(
                statementID: statementID,
                headerTokens: headerTokens,
                in: arena,
                interner: interner,
                astArena: astArena
            )
            let accessor = PropertyAccessorDecl(
                range: arena.node(statementID).range,
                kind: kind,
                parameterName: parameterName,
                body: body
            )
            switch kind {
            case .getter:
                if getter == nil {
                    getter = accessor
                }
            case .setter:
                if setter == nil {
                    setter = accessor
                }
            }
        }

        return (getter, setter)
    }

    func declarationInitBlocks(
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
                      arena.node(statementID).kind == .statement else {
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

    func setterParameterName(
        from headerTokens: [Token],
        interner: StringInterner
    ) -> InternedString? {
        guard let openParenIndex = headerTokens.firstIndex(where: { $0.kind == .symbol(.lParen) }) else {
            return nil
        }
        for token in headerTokens[(openParenIndex + 1)...] {
            if token.kind == .symbol(.rParen) {
                break
            }
            if let name = internedIdentifier(from: token, interner: interner),
               isTypeLikeNameToken(token.kind) {
                return name
            }
        }
        return nil
    }

    func accessorBody(
        statementID: NodeID,
        headerTokens: [Token],
        in arena: SyntaxArena,
        interner: StringInterner,
        astArena: ASTArena
    ) -> FunctionBody {
        if let nestedBlockID = arena.children(of: statementID).compactMap({ child -> NodeID? in
            guard case .node(let nodeID) = child,
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
            return .block(exprs, arena.node(nestedBlockID).range)
        }

        guard let assignIndex = headerTokens.firstIndex(where: { $0.kind == .symbol(.assign) }) else {
            return .unit
        }
        let exprTokens = headerTokens[(assignIndex + 1)...].filter { token in
            token.kind != .symbol(.semicolon)
        }
        guard !exprTokens.isEmpty else {
            return .unit
        }
        let parser = ExpressionParser(tokens: Array(exprTokens), interner: interner, astArena: astArena)
        guard let exprID = parser.parse(),
              let range = astArena.exprRange(exprID) else {
            return .unit
        }
        return .expr(exprID, range)
    }


    func declarationBody(
        from nodeID: NodeID,
        in arena: SyntaxArena,
        interner: StringInterner,
        astArena: ASTArena
    ) -> FunctionBody {
        for child in arena.children(of: nodeID) {
            if case .node(let childID) = child, arena.node(childID).kind == .block {
                let exprs = blockExpressions(from: childID, in: arena, interner: interner, astArena: astArena)
                return .block(exprs, arena.node(childID).range)
            }
        }

        let tokens = collectTokens(from: nodeID, in: arena)
        guard let assignIndex = tokens.firstIndex(where: { token in
            if case .symbol(.assign) = token.kind {
                return true
            }
            return false
        }) else {
            return .unit
        }

        let bodyStartIndex = assignIndex + 1
        if bodyStartIndex >= tokens.count {
            return .unit
        }
        let exprTokens = Array(tokens[bodyStartIndex...])
        let parser = ExpressionParser(tokens: exprTokens, interner: interner, astArena: astArena)
        guard let exprID = parser.parse() else {
            return .unit
        }
        guard let range = astArena.exprRange(exprID) else {
            return .unit
        }
        return .expr(exprID, range)
    }

    func blockExpressions(
        from blockNodeID: NodeID,
        in arena: SyntaxArena,
        interner: StringInterner,
        astArena: ASTArena
    ) -> [ExprID] {
        var result: [ExprID] = []
        for child in arena.children(of: blockNodeID) {
            guard case .node(let nodeID) = child else {
                continue
            }
            let node = arena.node(nodeID)
            guard node.kind == .statement else {
                continue
            }
            let statementTokens = collectTokens(from: nodeID, in: arena).filter { token in
                token.kind != .symbol(.semicolon)
            }
            guard !statementTokens.isEmpty else {
                continue
            }
            let parser = ExpressionParser(tokens: statementTokens, interner: interner, astArena: astArena)
            if let exprID = parser.parse() {
                result.append(exprID)
            }
        }
        return result
    }

    func skipBalancedBracket(
        in tokens: [Token],
        from startIndex: Int,
        open: TokenKind,
        close: TokenKind
    ) -> Int {
        guard startIndex < tokens.count, tokens[startIndex].kind == open else {
            return startIndex
        }
        var depth = 0
        var index = startIndex
        while index < tokens.count {
            let kind = tokens[index].kind
            if kind == open {
                depth += 1
            } else if kind == close {
                depth -= 1
                if depth == 0 {
                    return index + 1
                }
            }
            index += 1
        }
        return index
    }

    func resolveToken(_ tokenID: TokenID, in arena: SyntaxArena) -> Token? {
        let index = Int(tokenID.rawValue)
        guard index >= 0 && index < arena.tokens.count else {
            return nil
        }
        return arena.tokens[index]
    }

    func collectTokens(from nodeID: NodeID, in arena: SyntaxArena) -> [Token] {
        var tokens: [Token] = []
        for child in arena.children(of: nodeID) {
            switch child {
            case .token(let tokenID):
                if let token = resolveToken(tokenID, in: arena) {
                    tokens.append(token)
                }
            case .node(let childID):
                tokens.append(contentsOf: collectTokens(from: childID, in: arena))
            }
        }
        return tokens
    }

    func collectDirectTokens(from nodeID: NodeID, in arena: SyntaxArena) -> [Token] {
        var tokens: [Token] = []
        for child in arena.children(of: nodeID) {
            guard case .token(let tokenID) = child,
                  let token = resolveToken(tokenID, in: arena) else {
                continue
            }
            tokens.append(token)
        }
        return tokens
    }

}

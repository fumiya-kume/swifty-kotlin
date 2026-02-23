import Foundation

extension BuildASTPhase {
    internal func declarationIsVar(from nodeID: NodeID, in arena: SyntaxArena) -> Bool {
        for child in arena.children(of: nodeID) {
            if case .token(let tokenID) = child,
               let token = resolveToken(tokenID, in: arena),
               token.kind == .keyword(.var) {
                return true
            }
        }
        return false
    }

    internal func declarationPropertyInitializer(
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
        let parser = ExpressionParser(tokens: exprTokens[...], interner: interner, astArena: astArena)
        return parser.parse()
    }

    internal func declarationPropertyAccessors(
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
                  isStatementLikeKind(arena.node(statementID).kind) else {
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

    internal func setterParameterName(
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

    internal func accessorBody(
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
        let parser = ExpressionParser(tokens: ArraySlice(exprTokens), interner: interner, astArena: astArena)
        guard let exprID = parser.parse(),
              let range = astArena.exprRange(exprID) else {
            return .unit
        }
        return .expr(exprID, range)
    }
}

import Foundation

extension BuildASTPhase {
    func declarationIsVar(from nodeID: NodeID, in arena: SyntaxArena) -> Bool {
        for child in arena.children(of: nodeID) {
            if case let .token(tokenID) = child,
               let token = resolveToken(tokenID, in: arena),
               token.kind == .keyword(.var)
            {
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
            if token.kind == .symbol(.assign), depth.isAtTopLevel {
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
        let parser = ExpressionParser(
            tokens: exprTokens[...],
            interner: interner,
            astArena: astArena,
            diagnostics: diagnostics
        )
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

        // First, try to find accessors inside a block child (e.g. `val x: T { get() = ... }`).
        if let accessorBlockID = arena.children(of: nodeID).compactMap({ child -> NodeID? in
            guard case let .node(childID) = child,
                  arena.node(childID).kind == .block
            else {
                return nil
            }
            return childID
        }).first {
            for child in arena.children(of: accessorBlockID) {
                guard case let .node(statementID) = child,
                      isStatementLikeKind(arena.node(statementID).kind)
                else {
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

                let parameterName: InternedString? = if kind == .setter {
                    setterParameterName(from: headerTokens, interner: interner)
                } else {
                    nil
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

        // Fallback: detect inline accessor syntax from flat tokens.
        // Handles `val x: T get() = expr` where get()/set() appear as flat
        // tokens of the property node without a wrapping block.
        let allTokens = collectTokens(from: nodeID, in: arena)
        return parseInlineAccessors(from: allTokens, nodeRange: arena.node(nodeID).range, interner: interner, astArena: astArena)
    }

    /// Find the index where an inline `get`/`set` accessor keyword starts in
    /// a flat token list.  Returns `nil` when no accessor keyword is present.
    func inlineAccessorStartIndex(in tokens: [Token]) -> Int? {
        for (index, token) in tokens.enumerated() {
            let isAccessorKeyword = switch token.kind {
            case .softKeyword(.get), .softKeyword(.set):
                true
            default:
                false
            }
            guard isAccessorKeyword else { continue }
            // Require `(` immediately after to distinguish from identifiers.
            if index + 1 < tokens.count,
               tokens[index + 1].kind == .symbol(.lParen)
            {
                return index
            }
        }
        return nil
    }

    /// Parse inline `get()/set()` accessor declarations from a flat token
    /// stream.  For `val x: T get() = expr`, the tokens after the type
    /// annotation contain `get ( ) = expr` without a wrapping block node.
    private func parseInlineAccessors(
        from allTokens: [Token],
        nodeRange: SourceRange,
        interner: StringInterner,
        astArena: ASTArena
    ) -> (getter: PropertyAccessorDecl?, setter: PropertyAccessorDecl?) {
        var getter: PropertyAccessorDecl?
        var setter: PropertyAccessorDecl?
        var remaining = allTokens[...]

        while let startIdx = remaining.firstIndex(where: { token in
            switch token.kind {
            case .softKeyword(.get), .softKeyword(.set):
                true
            default:
                false
            }
        }) {
            let token = remaining[startIdx]
            let kind: PropertyAccessorKind
            switch token.kind {
            case .softKeyword(.get): kind = .getter
            case .softKeyword(.set): kind = .setter
            default:
                remaining = remaining[(startIdx + 1)...]
                continue
            }

            // Require `(` immediately after the keyword.
            guard startIdx + 1 < remaining.endIndex,
                  remaining[startIdx + 1].kind == .symbol(.lParen)
            else {
                remaining = remaining[(startIdx + 1)...]
                continue
            }

            // Find matching `)` after `(`.
            var closeParenIdx = startIdx + 2
            var depth = 1
            while closeParenIdx < remaining.endIndex {
                if remaining[closeParenIdx].kind == .symbol(.lParen) { depth += 1 }
                if remaining[closeParenIdx].kind == .symbol(.rParen) {
                    depth -= 1
                    if depth == 0 { break }
                }
                closeParenIdx += 1
            }
            guard closeParenIdx < remaining.endIndex else {
                remaining = remaining[(startIdx + 1)...]
                continue
            }

            let parameterName: InternedString?
            if kind == .setter {
                let parenTokens = Array(remaining[(startIdx + 1) ... closeParenIdx])
                parameterName = setterParameterName(from: parenTokens, interner: interner)
            } else {
                parameterName = nil
            }

            // Determine accessor body: either `= expr` or `{ block }`.
            let afterParen = closeParenIdx + 1
            let body: FunctionBody
            if afterParen < remaining.endIndex,
               remaining[afterParen].kind == .symbol(.assign)
            {
                // Find extent of body expression: up to the next get/set keyword or end.
                let exprStart = afterParen + 1
                var exprEnd = remaining.endIndex
                for i in exprStart ..< remaining.endIndex {
                    switch remaining[i].kind {
                    case .softKeyword(.get), .softKeyword(.set):
                        // Check if it's followed by `(` to confirm it's an accessor keyword.
                        if i + 1 < remaining.endIndex,
                           remaining[i + 1].kind == .symbol(.lParen)
                        {
                            exprEnd = i
                        }
                    default:
                        break
                    }
                    if exprEnd != remaining.endIndex { break }
                }
                let exprTokens = remaining[exprStart ..< exprEnd].filter { $0.kind != .symbol(.semicolon) }
                if !exprTokens.isEmpty {
                    let parser = ExpressionParser(
                        tokens: ArraySlice(exprTokens),
                        interner: interner,
                        astArena: astArena,
                        diagnostics: diagnostics
                    )
                    if let exprID = parser.parse(),
                       let range = astArena.exprRange(exprID)
                    {
                        body = .expr(exprID, range)
                    } else {
                        body = .unit
                    }
                } else {
                    body = .unit
                }
                remaining = remaining[exprEnd...]
            } else {
                body = .unit
                remaining = remaining[afterParen...]
            }

            let accessor = PropertyAccessorDecl(
                range: nodeRange,
                kind: kind,
                parameterName: parameterName,
                body: body
            )
            switch kind {
            case .getter:
                if getter == nil { getter = accessor }
            case .setter:
                if setter == nil { setter = accessor }
            }
        }

        return (getter, setter)
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
               isTypeLikeNameToken(token.kind)
            {
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
            guard case let .node(nodeID) = child,
                  arena.node(nodeID).kind == .block
            else {
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
        let parser = ExpressionParser(
            tokens: ArraySlice(exprTokens),
            interner: interner,
            astArena: astArena,
            diagnostics: diagnostics
        )
        guard let exprID = parser.parse(),
              let range = astArena.exprRange(exprID)
        else {
            return .unit
        }
        return .expr(exprID, range)
    }
}

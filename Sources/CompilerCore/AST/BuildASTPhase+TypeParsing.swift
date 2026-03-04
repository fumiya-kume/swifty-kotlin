import Foundation

extension BuildASTPhase {
    func isTypeLikeNameToken(_ kind: TokenKind) -> Bool {
        TypeRefParserCore.isTypeLikeNameToken(kind)
    }

    func stripDefaultValue(_ tokens: [Token]) -> [Token] {
        splitDefaultValue(tokens).withoutDefault
    }

    func splitDefaultValue(_ tokens: [Token]) -> (withoutDefault: [Token], defaultTokens: [Token]?) {
        var depth = BracketDepth()
        for (index, token) in tokens.enumerated() {
            if token.kind == .symbol(.assign), depth.isAtTopLevel {
                let defaultStart = tokens.index(after: index)
                let trailing = defaultStart < tokens.endIndex ? Array(tokens[defaultStart...]) : []
                return (Array(tokens[..<index]), trailing)
            }
            depth.track(token.kind)
        }
        return (tokens, nil)
    }

    func declarationFunctionName(
        from nodeID: NodeID,
        in arena: SyntaxArena,
        interner: StringInterner
    ) -> InternedString {
        let tokens = collectTokens(from: nodeID, in: arena)
        guard let paramsOpenIndex = tokens.firstIndex(where: { $0.kind == .symbol(.lParen) }) else {
            return declarationName(from: nodeID, in: arena, interner: interner)
        }
        if paramsOpenIndex == 0 {
            return declarationName(from: nodeID, in: arena, interner: interner)
        }

        for index in stride(from: paramsOpenIndex - 1, through: 0, by: -1) {
            let token = tokens[index]
            if !isTypeLikeNameToken(token.kind) {
                continue
            }
            if let name = internedIdentifier(from: token, interner: interner) {
                return name
            }
        }
        return declarationName(from: nodeID, in: arena, interner: interner)
    }

    func declarationReceiverType(
        from nodeID: NodeID,
        in arena: SyntaxArena,
        interner: StringInterner,
        astArena: ASTArena
    ) -> TypeRefID? {
        let tokens = collectTokens(from: nodeID, in: arena)
        guard let paramsOpenIndex = tokens.firstIndex(where: { $0.kind == .symbol(.lParen) }),
              paramsOpenIndex > 0
        else {
            return nil
        }

        var nameIndex: Int?
        for index in stride(from: paramsOpenIndex - 1, through: 0, by: -1) where isTypeLikeNameToken(tokens[index].kind) {
            nameIndex = index
            break
        }
        guard let nameIndex else {
            return nil
        }

        var receiverSeparatorIndex: Int?
        var receiverSeparatorToken: Token?
        var depth = BracketDepth()
        for index in 0 ..< nameIndex {
            let token = tokens[index]
            depth.track(token.kind)
            if depth.angle == 0,
               token.kind == .symbol(.dot) || token.kind == .symbol(.questionDot)
            {
                receiverSeparatorIndex = index
                receiverSeparatorToken = token
            }
        }
        guard let receiverSeparatorIndex else {
            return nil
        }

        guard let funIndex = tokens.firstIndex(where: { $0.kind == .keyword(.fun) }) else {
            return nil
        }

        let receiverStart = skipBalancedBracket(
            in: tokens, from: funIndex + 1,
            open: .symbol(.lessThan), close: .symbol(.greaterThan)
        )

        if receiverStart >= receiverSeparatorIndex {
            return nil
        }

        var receiverTokens = Array(tokens[receiverStart ..< receiverSeparatorIndex])
        if receiverSeparatorToken?.kind == .symbol(.questionDot),
           let separatorRange = receiverSeparatorToken?.range
        {
            receiverTokens.append(Token(kind: .symbol(.question), range: separatorRange))
        }
        return parseTypeRef(from: receiverTokens, interner: interner, astArena: astArena)
    }

    func declarationReturnType(
        from nodeID: NodeID,
        in arena: SyntaxArena,
        interner: StringInterner,
        astArena: ASTArena
    ) -> TypeRefID? {
        let tokens = collectTokens(from: nodeID, in: arena)
        guard let closeParenIndex = firstFunctionParameterCloseParen(in: tokens) else {
            return nil
        }

        var index = closeParenIndex + 1
        while index < tokens.count {
            let token = tokens[index]
            if token.kind == .symbol(.assign) || token.kind == .symbol(.lBrace) {
                return nil
            }
            if token.kind == .symbol(.colon) {
                index += 1
                break
            }
            index += 1
        }

        guard index < tokens.count else {
            return nil
        }

        var typeTokens: [Token] = []
        var depth = BracketDepth()
        while index < tokens.count {
            let token = tokens[index]
            if depth.angle == 0 {
                if token.kind == .symbol(.assign) || token.kind == .symbol(.lBrace) {
                    break
                }
                if case .softKeyword(.where) = token.kind {
                    break
                }
            }
            depth.track(token.kind)
            typeTokens.append(token)
            index += 1
        }

        return parseTypeRef(from: typeTokens, interner: interner, astArena: astArena)
    }

    /// Extracts the receiver type for extension properties (e.g. `val String.firstChar: Char`).
    /// Returns the TypeRefID for `String`, or `nil` for regular properties.
    func declarationPropertyReceiverType(
        from nodeID: NodeID,
        in arena: SyntaxArena,
        interner: StringInterner,
        astArena: ASTArena
    ) -> TypeRefID? {
        let tokens = propertyHeadTokens(from: nodeID, in: arena)

        // Find the val/var keyword index.
        guard let valVarIndex = tokens.firstIndex(where: {
            $0.kind == .keyword(.val) || $0.kind == .keyword(.var)
        }) else {
            return nil
        }

        // Look for the last top-level dot after the val/var keyword, skipping angle brackets
        // for generic receiver types (e.g. `val List<Int>.head`). This handles qualified
        // receiver types like `val kotlin.String.firstChar: Char` correctly.
        var lastDotIndex: Int?
        var depth = BracketDepth()
        for index in (valVarIndex + 1) ..< tokens.count {
            let token = tokens[index]
            depth.track(token.kind)
            if depth.angle == 0 {
                if token.kind == .symbol(.dot) {
                    lastDotIndex = index
                } else if token.kind == .symbol(.colon)
                    || token.kind == .symbol(.assign)
                    || token.kind == .symbol(.lBrace)
                {
                    break
                }
            }
        }
        guard let dotIndex = lastDotIndex else {
            return nil
        }

        // The receiver type tokens are between val/var and the dot.
        let receiverTokens = Array(tokens[(valVarIndex + 1) ..< dotIndex])
        guard !receiverTokens.isEmpty else {
            return nil
        }
        return parseTypeRef(from: receiverTokens, interner: interner, astArena: astArena)
    }

    /// Extracts the property name after the dot for extension properties
    /// (e.g. returns "firstChar" for `val String.firstChar: Char`).
    func declarationPropertyNameAfterDot(
        from nodeID: NodeID,
        in arena: SyntaxArena,
        interner: StringInterner
    ) -> InternedString {
        let tokens = propertyHeadTokens(from: nodeID, in: arena)

        // Find the val/var keyword index.
        guard let valVarIndex = tokens.firstIndex(where: {
            $0.kind == .keyword(.val) || $0.kind == .keyword(.var)
        }) else {
            return declarationName(from: nodeID, in: arena, interner: interner)
        }

        // Find the last top-level dot before `:`, `=`, or `{`.
        // This handles qualified receiver types like `val kotlin.String.firstChar: Char`.
        var depth = BracketDepth()
        var lastDotIndex: Int?
        for index in (valVarIndex + 1) ..< tokens.count {
            let token = tokens[index]
            depth.track(token.kind)
            if depth.angle == 0 {
                if token.kind == .symbol(.dot) {
                    lastDotIndex = index
                } else if token.kind == .symbol(.colon)
                    || token.kind == .symbol(.assign)
                    || token.kind == .symbol(.lBrace)
                {
                    break
                }
            }
        }
        guard let dotIndex = lastDotIndex, dotIndex + 1 < tokens.count else {
            return declarationName(from: nodeID, in: arena, interner: interner)
        }

        // The property name is the identifier right after the dot.
        let nameToken = tokens[dotIndex + 1]
        if let name = internedIdentifier(from: nameToken, interner: interner) {
            return name
        }
        return declarationName(from: nodeID, in: arena, interner: interner)
    }

    func declarationPropertyType(
        from nodeID: NodeID,
        in arena: SyntaxArena,
        interner: StringInterner,
        astArena: ASTArena
    ) -> TypeRefID? {
        let tokens = propertyHeadTokens(from: nodeID, in: arena)
        var sawName = false
        var colonIndex: Int?
        for (index, token) in tokens.enumerated() {
            if !sawName {
                switch token.kind {
                case .keyword(.val), .keyword(.var):
                    continue
                default:
                    if isTypeLikeNameToken(token.kind) {
                        sawName = true
                    }
                    continue
                }
            }

            if token.kind == .symbol(.colon) {
                colonIndex = index
                break
            }
            if token.kind == .symbol(.assign) || token.kind == .symbol(.lBrace) || token.kind == .symbol(.semicolon) {
                return nil
            }
            if case .softKeyword(.by) = token.kind {
                return nil
            }
        }

        guard let colonIndex else {
            return nil
        }

        var typeTokens: [Token] = []
        var depth = BracketDepth()
        var index = colonIndex + 1
        while index < tokens.count {
            let token = tokens[index]
            if depth.angle == 0 {
                if token.kind == .symbol(.assign) || token.kind == .symbol(.lBrace) || token.kind == .symbol(.semicolon) {
                    break
                }
                if case .softKeyword(.by) = token.kind {
                    break
                }
            }
            depth.track(token.kind)
            typeTokens.append(token)
            index += 1
        }

        return parseTypeRef(from: typeTokens, interner: interner, astArena: astArena)
    }

    func propertyHeadTokens(
        from nodeID: NodeID,
        in arena: SyntaxArena
    ) -> [Token] {
        var tokens: [Token] = []
        for child in arena.children(of: nodeID) {
            switch child {
            case let .token(tokenID):
                if let token = resolveToken(tokenID, in: arena) {
                    // Stop before inline `get(`/`set(` accessor keywords so that
                    // type and initializer parsing don't consume accessor tokens.
                    switch token.kind {
                    case .softKeyword(.get), .softKeyword(.set):
                        if let idx = inlineAccessorStartIndex(in: tokens + [token]) {
                            return Array(tokens.prefix(idx))
                        }
                    default:
                        break
                    }
                    tokens.append(token)
                }
            case let .node(childID):
                if arena.node(childID).kind == .block {
                    return tokens
                }
            }
        }
        // Final check: scan collected tokens for inline accessor start.
        if let idx = inlineAccessorStartIndex(in: tokens) {
            return Array(tokens.prefix(idx))
        }
        return tokens
    }

    func firstFunctionParameterCloseParen(in tokens: [Token]) -> Int? {
        guard let openIndex = tokens.firstIndex(where: { $0.kind == .symbol(.lParen) }) else {
            return nil
        }
        let afterClose = skipBalancedBracket(in: tokens, from: openIndex, open: .symbol(.lParen), close: .symbol(.rParen))
        guard afterClose > openIndex else {
            return nil
        }
        return afterClose - 1
    }

    func parseTypeRef(
        from tokens: [Token],
        interner: StringInterner,
        astArena: ASTArena
    ) -> TypeRefID? {
        guard !tokens.isEmpty else {
            return nil
        }
        let options = TypeRefParserCore.Options.declaration
        guard let parsed = TypeRefParserCore.parseTypeRefPrefix(
            tokens[...],
            interner: interner,
            astArena: astArena,
            options: options
        ) else {
            return nil
        }
        return parsed.consumed == tokens.count ? parsed.ref : nil
    }

    func isParameterModifierToken(_ token: Token) -> Bool {
        guard case let .keyword(keyword) = token.kind else {
            return false
        }
        switch keyword {
        case .vararg, .crossinline, .noinline:
            return true
        default:
            return false
        }
    }
}

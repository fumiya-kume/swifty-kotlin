import Foundation

extension BuildASTPhase {
    internal func parseLocalDeclarationExpr(
        from statementTokens: [Token],
        interner: StringInterner,
        astArena: ASTArena
    ) -> ExprID? {
        guard !statementTokens.isEmpty else {
            return nil
        }
        var startIndex = 0
        while startIndex < statementTokens.count,
              case .keyword(let kw) = statementTokens[startIndex].kind,
              KotlinParser.isDeclarationModifierKeyword(kw) {
            startIndex += 1
        }
        guard startIndex < statementTokens.count else {
            return nil
        }
        let head = statementTokens[startIndex]
        let isMutable: Bool
        switch head.kind {
        case .keyword(.val):
            isMutable = false
        case .keyword(.var):
            isMutable = true
        default:
            return nil
        }

        // Check for destructuring declaration: val (a, b) = expr
        if let destructuringResult = parseDestructuringDeclarationExpr(
            from: statementTokens,
            startIndex: startIndex,
            isMutable: isMutable,
            interner: interner,
            astArena: astArena
        ) {
            return destructuringResult
        }

        let context = LocalStatementCoreContext(
            interner: interner,
            astArena: astArena,
            parseExpression: { tokens in
                ExpressionParser(tokens: tokens, interner: interner, astArena: astArena).parse()
            },
            parseTypeReference: { typeTokens in
                self.parseTypeRef(from: typeTokens, interner: interner, astArena: astArena)
            },
            resolveDeclarationName: { token, interner in
                guard self.isTypeLikeNameToken(token.kind) else {
                    return nil
                }
                return self.internedIdentifier(from: token, interner: interner)
            }
        )
        return LocalStatementCore.parseLocalDeclaration(
            from: statementTokens,
            context: context,
            options: .declaration
        )
    }

    internal func parseLocalAssignmentExpr(
        from statementTokens: [Token],
        interner: StringInterner,
        astArena: ASTArena
    ) -> ExprID? {
        let context = LocalStatementCoreContext(
            interner: interner,
            astArena: astArena,
            parseExpression: { tokens in
                ExpressionParser(tokens: tokens, interner: interner, astArena: astArena).parse()
            },
            parseTypeReference: { _ in nil },
            resolveDeclarationName: { _, _ in nil }
        )
        return LocalStatementCore.parseLocalAssignment(
            from: statementTokens,
            context: context,
            options: .declaration
        )
    }

    /// Parse destructuring declaration: `val (a, b, _) = expr`
    /// Returns nil if the tokens don't match the destructuring pattern.
    internal func parseDestructuringDeclarationExpr(
        from statementTokens: [Token],
        startIndex: Int,
        isMutable: Bool,
        interner: StringInterner,
        astArena: ASTArena
    ) -> ExprID? {
        // After val/var keyword, expect `(` — but the CST parser may insert
        // a `missing(identifier)` token before it when it expects a property name.
        var afterKeyword = startIndex + 1
        // Skip any missing tokens inserted by the CST parser
        while afterKeyword < statementTokens.count,
              case .missing = statementTokens[afterKeyword].kind {
            afterKeyword += 1
        }
        guard afterKeyword < statementTokens.count,
              statementTokens[afterKeyword].kind == .symbol(.lParen) else {
            return nil
        }

        // Find the matching closing paren
        var depth = 0
        var closeParenIndex: Int?
        for i in afterKeyword..<statementTokens.count {
            switch statementTokens[i].kind {
            case .symbol(.lParen):
                depth += 1
            case .symbol(.rParen):
                depth -= 1
                if depth == 0 {
                    closeParenIndex = i
                    break
                }
            default:
                break
            }
            if closeParenIndex != nil { break }
        }
        guard let closeParenIndex else {
            return nil
        }

        // Parse names between parens, separated by commas
        // Supports: identifiers and `_` (underscore)
        let innerTokens = Array(statementTokens[(afterKeyword + 1)..<closeParenIndex])
        var names: [InternedString?] = []
        var idx = 0
        while idx < innerTokens.count {
            let token = innerTokens[idx]
            switch token.kind {
            case .symbol(.comma):
                idx += 1
                continue
            case .identifier(let name):
                let nameStr = interner.resolve(name)
                if nameStr == "_" {
                    names.append(nil)
                } else {
                    names.append(name)
                }
                idx += 1
            case .backtickedIdentifier(let name):
                names.append(name)
                idx += 1
            default:
                // Skip type annotations (`: Type`) after variable names
                if token.kind == .symbol(.colon) {
                    idx += 1
                    // Skip type tokens until comma or end
                    var typeDepth = BracketDepth()
                    while idx < innerTokens.count {
                        let t = innerTokens[idx]
                        if typeDepth.isAtTopLevel && t.kind == .symbol(.comma) {
                            break
                        }
                        typeDepth.track(t.kind)
                        idx += 1
                    }
                    continue
                }
                idx += 1
            }
        }

        guard !names.isEmpty else {
            return nil
        }

        // After closing paren, expect `=`
        var assignIndex: Int?
        for i in (closeParenIndex + 1)..<statementTokens.count {
            if statementTokens[i].kind == .symbol(.assign) {
                assignIndex = i
                break
            }
        }
        guard let assignIndex else {
            return nil
        }

        // Parse the initializer expression
        let initializerTokens = statementTokens[(assignIndex + 1)...].filter { token in
            token.kind != .symbol(.semicolon)
        }
        guard !initializerTokens.isEmpty else {
            return nil
        }
        let parser = ExpressionParser(tokens: initializerTokens[...], interner: interner, astArena: astArena)
        guard let initializerExpr = parser.parse() else {
            return nil
        }

        let rangeStart = statementTokens[0].range.start
        let end = astArena.exprRange(initializerExpr)?.end ?? statementTokens.last?.range.end ?? statementTokens[startIndex].range.end
        let range = SourceRange(start: rangeStart, end: end)

        return astArena.appendExpr(.destructuringDecl(
            names: names,
            isMutable: isMutable,
            initializer: initializerExpr,
            range: range
        ))
    }
}

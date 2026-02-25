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

        guard let nameToken = statementTokens.dropFirst(startIndex + 1).first(where: { token in
            isTypeLikeNameToken(token.kind)
        }),
              let name = internedIdentifier(from: nameToken, interner: interner) else {
            return nil
        }

        let nameIndex = statementTokens.firstIndex(where: { token in
            if let n = internedIdentifier(from: token, interner: interner), n == name, isTypeLikeNameToken(token.kind) {
                return true
            }
            return false
        }) ?? 1

        var typeAnnotation: TypeRefID?
        var colonIndex: Int?
        for i in (nameIndex + 1)..<statementTokens.count {
            let token = statementTokens[i]
            if token.kind == .symbol(.colon) {
                colonIndex = i
                break
            }
            if token.kind == .symbol(.assign) || token.kind == .symbol(.semicolon) {
                break
            }
        }
        if let colonIndex {
            var typeTokens: [Token] = []
            var depth = BracketDepth()
            var idx = colonIndex + 1
            while idx < statementTokens.count {
                let token = statementTokens[idx]
                if depth.isAtTopLevel {
                    if token.kind == .symbol(.assign) || token.kind == .symbol(.semicolon) {
                        break
                    }
                }
                depth.track(token.kind)
                typeTokens.append(token)
                idx += 1
            }
            typeAnnotation = parseTypeRef(from: typeTokens, interner: interner, astArena: astArena)
        }

        var assignIndex: Int?
        var depth = BracketDepth()
        for (index, token) in statementTokens.enumerated() {
            if token.kind == .symbol(.assign) && depth.isAtTopLevel {
                assignIndex = index
                break
            }
            depth.track(token.kind)
        }

        var initializerExpr: ExprID?
        if let assignIndex {
            let initializerTokens = statementTokens[(assignIndex + 1)...].filter { token in
                token.kind != .symbol(.semicolon)
            }
            guard !initializerTokens.isEmpty else {
                return nil
            }
            let parser = ExpressionParser(tokens: initializerTokens[...], interner: interner, astArena: astArena)
            guard let parsedInitializer = parser.parse() else {
                return nil
            }
            initializerExpr = parsedInitializer
        }

        if typeAnnotation == nil && initializerExpr == nil {
            return nil
        }

        let end: SourceLocation
        if let initializerExpr {
            end = astArena.exprRange(initializerExpr)?.end ?? statementTokens.last?.range.end ?? head.range.end
        } else {
            end = statementTokens.last?.range.end ?? head.range.end
        }
        let rangeStart = statementTokens[0].range.start
        let range = SourceRange(start: rangeStart, end: end)
        return astArena.appendExpr(.localDecl(
            name: name,
            isMutable: isMutable,
            typeAnnotation: typeAnnotation,
            initializer: initializerExpr,
            range: range
        ))
    }

    internal func parseLocalAssignmentExpr(
        from statementTokens: [Token],
        interner: StringInterner,
        astArena: ASTArena
    ) -> ExprID? {
        if let compoundExpr = parseCompoundAssignmentExpr(
            from: statementTokens, interner: interner, astArena: astArena
        ) {
            return compoundExpr
        }

        var assignIndex: Int?
        var depth = BracketDepth()
        for (index, token) in statementTokens.enumerated() {
            if token.kind == .symbol(.assign) && depth.isAtTopLevel {
                assignIndex = index
                break
            }
            depth.track(token.kind)
        }
        guard let assignIndex, assignIndex > 0 else {
            return nil
        }

        let lhsTokens = statementTokens[..<assignIndex].filter { token in
            token.kind != .symbol(.semicolon)
        }
        guard !lhsTokens.isEmpty else {
            return nil
        }

        let valueTokens = statementTokens[(assignIndex + 1)...].filter { token in
            token.kind != .symbol(.semicolon)
        }
        guard !valueTokens.isEmpty else {
            return nil
        }

        let lhsParser = ExpressionParser(tokens: lhsTokens[...], interner: interner, astArena: astArena)
        guard let lhsExpr = lhsParser.parse() else {
            return nil
        }
        let parser = ExpressionParser(tokens: valueTokens[...], interner: interner, astArena: astArena)
        guard let valueExpr = parser.parse() else {
            return nil
        }
        guard let lhs = astArena.expr(lhsExpr),
              let lhsRange = astArena.exprRange(lhsExpr) else {
            return nil
        }
        let end = astArena.exprRange(valueExpr)?.end ?? statementTokens.last?.range.end ?? lhsRange.end
        let range = SourceRange(start: lhsRange.start, end: end)

        switch lhs {
        case .nameRef(let name, _):
            let nameText = interner.resolve(name)
            if nameText == "val" || nameText == "var" {
                return nil
            }
            return astArena.appendExpr(.localAssign(name: name, value: valueExpr, range: range))

        case .memberCall(let receiver, let member, _, let args, _) where args.isEmpty:
            return astArena.appendExpr(.memberAssign(receiver: receiver, member: member, value: valueExpr, range: range))

        case .indexedAccess(let receiver, let indices, _):
            return astArena.appendExpr(.indexedAssign(receiver: receiver, indices: indices, value: valueExpr, range: range))

        default:
            return nil
        }
    }

    internal func parseCompoundAssignmentExpr(
        from statementTokens: [Token],
        interner: StringInterner,
        astArena: ASTArena
    ) -> ExprID? {
        let compoundOps: [(TokenKind, CompoundAssignOp)] = [
            (.symbol(.plusAssign), .plusAssign),
            (.symbol(.minusAssign), .minusAssign),
            (.symbol(.starAssign), .timesAssign),
            (.symbol(.slashAssign), .divAssign),
            (.symbol(.percentAssign), .modAssign),
        ]

        var foundIndex: Int?
        var foundOp: CompoundAssignOp?
        var depth = BracketDepth()
        for (index, token) in statementTokens.enumerated() {
            for (kind, op) in compoundOps {
                if token.kind == kind && depth.isAtTopLevel {
                    foundIndex = index
                    foundOp = op
                    break
                }
            }
            if foundIndex != nil { break }
            depth.track(token.kind)
        }

        guard let assignIndex = foundIndex, let op = foundOp, assignIndex > 0 else {
            return nil
        }

        let lhsTokens = statementTokens[..<assignIndex].filter { $0.kind != .symbol(.semicolon) }
        guard !lhsTokens.isEmpty else { return nil }

        let valueTokens = statementTokens[(assignIndex + 1)...].filter { $0.kind != .symbol(.semicolon) }
        guard !valueTokens.isEmpty else { return nil }

        let lhsParser = ExpressionParser(tokens: lhsTokens[...], interner: interner, astArena: astArena)
        guard let lhsExpr = lhsParser.parse(),
              let lhs = astArena.expr(lhsExpr),
              let lhsRange = astArena.exprRange(lhsExpr) else {
            return nil
        }

        let parser = ExpressionParser(tokens: valueTokens[...], interner: interner, astArena: astArena)
        guard let valueExpr = parser.parse() else { return nil }

        let end = astArena.exprRange(valueExpr)?.end ?? statementTokens.last?.range.end ?? lhsRange.end
        let range = SourceRange(start: lhsRange.start, end: end)
        switch lhs {
        case .nameRef(let name, _):
            return astArena.appendExpr(.compoundAssign(op: op, name: name, value: valueExpr, range: range))
        case .indexedAccess(let receiver, let indices, _):
            return astArena.appendExpr(.indexedCompoundAssign(op: op, receiver: receiver, indices: indices, value: valueExpr, range: range))
        default:
            return nil
        }
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

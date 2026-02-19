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
            let parser = ExpressionParser(tokens: Array(initializerTokens), interner: interner, astArena: astArena)
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

        let lhsParser = ExpressionParser(tokens: Array(lhsTokens), interner: interner, astArena: astArena)
        guard let lhsExpr = lhsParser.parse() else {
            return nil
        }
        let parser = ExpressionParser(tokens: Array(valueTokens), interner: interner, astArena: astArena)
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

        case .arrayAccess(let array, let index, _):
            return astArena.appendExpr(.arrayAssign(array: array, index: index, value: valueExpr, range: range))

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

        let lhsParser = ExpressionParser(tokens: Array(lhsTokens), interner: interner, astArena: astArena)
        guard let lhsExpr = lhsParser.parse(),
              let lhs = astArena.expr(lhsExpr),
              case .nameRef(let name, _) = lhs,
              let lhsRange = astArena.exprRange(lhsExpr) else {
            return nil
        }

        let parser = ExpressionParser(tokens: Array(valueTokens), interner: interner, astArena: astArena)
        guard let valueExpr = parser.parse() else { return nil }

        let end = astArena.exprRange(valueExpr)?.end ?? statementTokens.last?.range.end ?? lhsRange.end
        let range = SourceRange(start: lhsRange.start, end: end)
        return astArena.appendExpr(.compoundAssign(op: op, name: name, value: valueExpr, range: range))
    }
}

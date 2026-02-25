import Foundation

extension BuildASTPhase.ExpressionParser {
    func parseBlockExpression() -> ExprID? {
        guard let openBrace = consume() else {
            return nil
        }
        var depth = 1
        var blockTokens: [Token] = []
        var end = openBrace.range.end

        while let token = current() {
            _ = consume()
            switch token.kind {
            case .symbol(.lBrace):
                depth += 1
                blockTokens.append(token)
            case .symbol(.rBrace):
                depth -= 1
                if depth == 0 {
                    end = token.range.end
                    break
                }
                blockTokens.append(token)
            default:
                blockTokens.append(token)
            }
            if depth == 0 {
                break
            }
        }

        let ranges = splitBlockTokensIntoStatementRanges(blockTokens)
        if ranges.isEmpty {
            let range = SourceRange(start: openBrace.range.start, end: end)
            return astArena.appendExpr(.blockExpr(statements: [], trailingExpr: nil, range: range))
        }

        var statements: [ExprID] = []
        let allTokens = blockTokens[...]
        for (start, rangeEnd) in ranges {
            let group = allTokens[start..<rangeEnd]
            guard !group.isEmpty else { continue }
            if let localDecl = parseLocalDeclFromSlice(group) {
                statements.append(localDecl)
            } else if let localAssign = parseLocalAssignFromSlice(group) {
                statements.append(localAssign)
            } else if let expr = BuildASTPhase.ExpressionParser(tokens: group, interner: interner, astArena: astArena).parse() {
                statements.append(expr)
            }
        }

        var trailingExpr: ExprID?
        if let lastID = statements.last, let lastExpr = astArena.expr(lastID) {
            switch lastExpr {
            case .localDecl, .localAssign, .indexedAssign, .compoundAssign, .indexedCompoundAssign, .localFunDecl:
                break
            default:
                trailingExpr = statements.removeLast()
            }
        }

        let range = SourceRange(start: openBrace.range.start, end: end)
        return astArena.appendExpr(.blockExpr(statements: statements, trailingExpr: trailingExpr, range: range))
    }

    /// Returns statement boundary ranges as `(startIndex, endIndex)` pairs into `tokens`.
    func splitBlockTokensIntoStatementRanges(_ tokens: [Token]) -> [(Int, Int)] {
        var ranges: [(Int, Int)] = []
        var groupStart = 0
        var lastTokenIndex = -1
        var parenDepth = 0
        var bracketDepth = 0
        var braceDepth = 0
        for (idx, token) in tokens.enumerated() {
            let isTopLevel = parenDepth == 0 && bracketDepth == 0 && braceDepth == 0
            if isTopLevel {
                if token.kind == .symbol(.semicolon) {
                    if lastTokenIndex >= groupStart {
                        ranges.append((groupStart, lastTokenIndex + 1))
                    }
                    groupStart = idx + 1
                    switch token.kind {
                    case .symbol(.lParen):    parenDepth += 1
                    case .symbol(.rParen):    parenDepth = max(0, parenDepth - 1)
                    case .symbol(.lBracket):  bracketDepth += 1
                    case .symbol(.rBracket):  bracketDepth = max(0, bracketDepth - 1)
                    case .symbol(.lBrace):    braceDepth += 1
                    case .symbol(.rBrace):    braceDepth = max(0, braceDepth - 1)
                    default: break
                    }
                    continue
                }
                let hasNewline = token.leadingTrivia.contains { piece in
                    if case .newline = piece { return true }
                    return false
                }
                if hasNewline && lastTokenIndex >= groupStart {
                    let lastKind = tokens[lastTokenIndex].kind
                    let lastIsContinuation = isBinaryOperatorTokenKind(lastKind)
                    let nextIsContinuation = isBinaryOperatorTokenKind(token.kind)
                    if !lastIsContinuation && !nextIsContinuation {
                        ranges.append((groupStart, lastTokenIndex + 1))
                        groupStart = idx
                    }
                }
            }
            switch token.kind {
            case .symbol(.lParen):    parenDepth += 1
            case .symbol(.rParen):    parenDepth = max(0, parenDepth - 1)
            case .symbol(.lBracket):  bracketDepth += 1
            case .symbol(.rBracket):  bracketDepth = max(0, bracketDepth - 1)
            case .symbol(.lBrace):    braceDepth += 1
            case .symbol(.rBrace):    braceDepth = max(0, braceDepth - 1)
            default: break
            }
            lastTokenIndex = idx
        }
        if lastTokenIndex >= groupStart {
            ranges.append((groupStart, lastTokenIndex + 1))
        }
        return ranges
    }

    func isBinaryOperatorTokenKind(_ kind: TokenKind) -> Bool {
        switch kind {
        case .symbol(.plus), .symbol(.minus), .symbol(.star), .symbol(.slash), .symbol(.percent),
             .symbol(.ampAmp), .symbol(.barBar),
             .symbol(.equalEqual), .symbol(.bangEqual),
             .symbol(.lessThan), .symbol(.lessOrEqual), .symbol(.greaterThan), .symbol(.greaterOrEqual),
             .symbol(.assign), .symbol(.plusAssign), .symbol(.minusAssign),
             .symbol(.starAssign), .symbol(.slashAssign), .symbol(.percentAssign),
             .symbol(.dotDot), .symbol(.dotDotLt),
             .symbol(.questionQuestion), .symbol(.questionColon),
             .symbol(.dot), .symbol(.questionDot),
             .symbol(.doubleColon),
             .symbol(.arrow), .symbol(.fatArrow),
             .keyword(.as), .keyword(.is), .keyword(.in),
             .keyword(.else), .keyword(.catch), .keyword(.finally):
            return true
        default:
            return false
        }
    }

    func isLocalDeclarationTokens(_ tokens: [Token]) -> Bool {
        guard !tokens.isEmpty else { return false }
        var i = 0
        while i < tokens.count {
            if case .keyword(let kw) = tokens[i].kind,
               KotlinParser.isDeclarationModifierKeyword(kw) {
                i += 1
                continue
            }
            break
        }
        guard i < tokens.count else { return false }
        switch tokens[i].kind {
        case .keyword(.val), .keyword(.var):
            return true
        default:
            return false
        }
    }

    func isLocalAssignmentTokens(_ tokens: [Token]) -> Bool {
        guard tokens.count >= 3 else { return false }
        let assignOps: [TokenKind] = [
            .symbol(.assign),
            .symbol(.plusAssign), .symbol(.minusAssign),
            .symbol(.starAssign), .symbol(.slashAssign), .symbol(.percentAssign),
        ]
        var depth = BuildASTPhase.BracketDepth()
        for token in tokens {
            if assignOps.contains(token.kind) && depth.isAtTopLevel {
                return true
            }
            depth.track(token.kind)
        }
        return false
    }

    func parseLocalDeclFromTokens(_ tokens: [Token]) -> ExprID? {
        parseLocalDeclFromSlice(tokens[...])
    }

    func parseLocalDeclFromSlice(_ tokens: ArraySlice<Token>) -> ExprID? {
        guard !tokens.isEmpty else { return nil }
        var si = tokens.startIndex
        while si < tokens.endIndex {
            if case .keyword(let kw) = tokens[si].kind,
               KotlinParser.isDeclarationModifierKeyword(kw) {
                si += 1
                continue
            }
            break
        }
        guard si < tokens.endIndex else { return nil }
        let head = tokens[si]
        let isMutable: Bool
        switch head.kind {
        case .keyword(.val):
            isMutable = false
        case .keyword(.var):
            isMutable = true
        default:
            return nil
        }

        let nameToken = tokens[(si + 1)...].first(where: { token in
            switch token.kind {
            case .identifier, .backtickedIdentifier:
                return true
            default:
                return false
            }
        })
        guard let nameToken, let name = tokenText(nameToken) else {
            return nil
        }

        let nameIndex = tokens.firstIndex(where: { $0.range.start == nameToken.range.start }) ?? (si + 1)

        var typeAnnotation: TypeRefID?
        var colonIndex: Int?
        for i in (nameIndex + 1)..<tokens.endIndex {
            let token = tokens[i]
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
            var typeDepth = BuildASTPhase.BracketDepth()
            var idx = colonIndex + 1
            while idx < tokens.endIndex {
                let token = tokens[idx]
                if typeDepth.isAtTopLevel {
                    if token.kind == .symbol(.assign) || token.kind == .symbol(.semicolon) {
                        break
                    }
                }
                typeDepth.track(token.kind)
                typeTokens.append(token)
                idx += 1
            }
            if !typeTokens.isEmpty {
                let typeParser = BuildASTPhase.ExpressionParser(
                    tokens: typeTokens, interner: interner, astArena: astArena
                )
                let fallbackRange = typeTokens[0].range
                typeAnnotation = typeParser.parseTypeReference(fallbackRange)
            }
        }

        var assignIndex: Int?
        var depth = BuildASTPhase.BracketDepth()
        for i in tokens.startIndex..<tokens.endIndex {
            let token = tokens[i]
            if token.kind == .symbol(.assign) && depth.isAtTopLevel {
                assignIndex = i
                break
            }
            depth.track(token.kind)
        }

        var initializerExpr: ExprID?
        if let assignIndex {
            let initSlice = tokens[(assignIndex + 1)...]
            if !initSlice.isEmpty {
                let parser = BuildASTPhase.ExpressionParser(tokens: initSlice, interner: interner, astArena: astArena)
                initializerExpr = parser.parse()
            }
        }

        if typeAnnotation == nil && initializerExpr == nil {
            return nil
        }

        let rangeEnd: SourceLocation
        if let initializerExpr {
            rangeEnd = astArena.exprRange(initializerExpr)?.end ?? tokens.last?.range.end ?? head.range.end
        } else {
            rangeEnd = tokens.last?.range.end ?? head.range.end
        }
        let range = SourceRange(start: tokens[tokens.startIndex].range.start, end: rangeEnd)
        return astArena.appendExpr(.localDecl(
            name: name,
            isMutable: isMutable,
            typeAnnotation: typeAnnotation,
            initializer: initializerExpr,
            range: range
        ))
    }

    func parseLocalAssignFromTokens(_ tokens: [Token]) -> ExprID? {
        parseLocalAssignFromSlice(tokens[...])
    }

    func parseLocalAssignFromSlice(_ tokens: ArraySlice<Token>) -> ExprID? {
        guard tokens.count >= 3 else { return nil }

        let compoundOps: [(TokenKind, CompoundAssignOp)] = [
            (.symbol(.plusAssign), .plusAssign),
            (.symbol(.minusAssign), .minusAssign),
            (.symbol(.starAssign), .timesAssign),
            (.symbol(.slashAssign), .divAssign),
            (.symbol(.percentAssign), .modAssign),
        ]
        var compoundIndex: Int?
        var compoundOp: CompoundAssignOp?
        var compoundDepth = BuildASTPhase.BracketDepth()
        for i in tokens.startIndex..<tokens.endIndex {
            let token = tokens[i]
            for (kind, op) in compoundOps {
                if token.kind == kind && compoundDepth.isAtTopLevel {
                    compoundIndex = i
                    compoundOp = op
                    break
                }
            }
            if compoundIndex != nil { break }
            compoundDepth.track(token.kind)
        }
        if let compoundIndex, let op = compoundOp, compoundIndex > tokens.startIndex {
            let lhsSlice = tokens[tokens.startIndex..<compoundIndex]
            guard !lhsSlice.isEmpty else { return nil }
            let lhsParser = BuildASTPhase.ExpressionParser(tokens: lhsSlice, interner: interner, astArena: astArena)
            guard let lhsExpr = lhsParser.parse(),
                  let lhs = astArena.expr(lhsExpr),
                  let lhsRange = astArena.exprRange(lhsExpr) else {
                return nil
            }
            let valueSlice = tokens[(compoundIndex + 1)...]
            guard !valueSlice.isEmpty else { return nil }
            let parser = BuildASTPhase.ExpressionParser(tokens: valueSlice, interner: interner, astArena: astArena)
            guard let valueExpr = parser.parse() else { return nil }
            let rangeEnd = astArena.exprRange(valueExpr)?.end ?? tokens.last?.range.end ?? lhsRange.end
            let range = SourceRange(start: tokens[tokens.startIndex].range.start, end: rangeEnd)
            switch lhs {
            case .nameRef(let name, _):
                return astArena.appendExpr(.compoundAssign(op: op, name: name, value: valueExpr, range: range))
            case .indexedAccess(let receiver, let indices, _):
                return astArena.appendExpr(.indexedCompoundAssign(op: op, receiver: receiver, indices: indices, value: valueExpr, range: range))
            default:
                return nil
            }
        }

        var assignIndex: Int?
        var depth = BuildASTPhase.BracketDepth()
        for i in tokens.startIndex..<tokens.endIndex {
            let token = tokens[i]
            if token.kind == .symbol(.assign) && depth.isAtTopLevel {
                assignIndex = i
                break
            }
            depth.track(token.kind)
        }
        guard let assignIndex, assignIndex > tokens.startIndex else { return nil }
        let lhsSlice = tokens[tokens.startIndex..<assignIndex]
        guard !lhsSlice.isEmpty else { return nil }
        let valueSlice = tokens[(assignIndex + 1)...]
        guard !valueSlice.isEmpty else { return nil }
        let lhsParser = BuildASTPhase.ExpressionParser(tokens: lhsSlice, interner: interner, astArena: astArena)
        guard let lhsExpr = lhsParser.parse() else { return nil }
        let parser = BuildASTPhase.ExpressionParser(tokens: valueSlice, interner: interner, astArena: astArena)
        guard let valueExpr = parser.parse() else { return nil }
        guard let lhs = astArena.expr(lhsExpr),
              let lhsRange = astArena.exprRange(lhsExpr) else {
            return nil
        }
        let rangeEnd = astArena.exprRange(valueExpr)?.end ?? tokens.last?.range.end ?? lhsRange.end
        let range = SourceRange(start: lhsRange.start, end: rangeEnd)
        switch lhs {
        case .nameRef(let name, _):
            return astArena.appendExpr(.localAssign(name: name, value: valueExpr, range: range))
        case .indexedAccess(let receiver, let indices, _):
            return astArena.appendExpr(.indexedAssign(receiver: receiver, indices: indices, value: valueExpr, range: range))
        default:
            return nil
        }
    }

    func skipBalancedParenthesisIfNeeded() {
        guard matches(.symbol(.lParen)) else {
            return
        }
        _ = consume()
        var depth = 1
        while let token = current(), depth > 0 {
            _ = consume()
            switch token.kind {
            case .symbol(.lParen):
                depth += 1
            case .symbol(.rParen):
                depth -= 1
            default:
                continue
            }
        }
    }
}

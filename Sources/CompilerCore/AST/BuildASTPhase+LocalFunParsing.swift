import Foundation

extension BuildASTPhase {
    func parseLocalFunDeclExpr(
        from statementTokens: [Token],
        interner: StringInterner,
        astArena: ASTArena
    ) -> ExprID? {
        guard !statementTokens.isEmpty else {
            return nil
        }

        var startIndex = 0
        var isSuspend = false
        while startIndex < statementTokens.count,
              case let .keyword(keyword) = statementTokens[startIndex].kind,
              KotlinParser.isDeclarationModifierKeyword(keyword)
        {
            if keyword == .suspend {
                isSuspend = true
            }
            startIndex += 1
        }

        guard startIndex < statementTokens.count else {
            return nil
        }

        let head = statementTokens[startIndex]
        guard case .keyword(.fun) = head.kind
        else {
            return nil
        }

        let funTokens = Array(statementTokens[startIndex...])

        var angleDepth = 0
        let nameToken = statementTokens.dropFirst().first(where: { token in
            switch token.kind {
            case .symbol(.lessThan):
                angleDepth += 1
                return false
            case .symbol(.greaterThan):
                angleDepth = max(0, angleDepth - 1)
                return false
            default:
                return angleDepth == 0 && isTypeLikeNameToken(token.kind)
            }
        })
        guard let nameToken,
              let name = internedIdentifier(from: nameToken, interner: interner)
        else {
            return nil
        }

        guard let lParenIndex = funTokens.firstIndex(where: { $0.kind == .symbol(.lParen) }) else {
            return nil
        }
        let nameIndex = statementTokens.firstIndex(where: { $0.range.start == nameToken.range.start && $0.range.end == nameToken.range.end }) ?? 1
        let rawTypeParams = parseLocalTypeParams(
            from: Array(statementTokens[1 ..< nameIndex]),
            interner: interner,
            astArena: astArena
        )
        let whereClauses = parseLocalWhereClauses(
            from: statementTokens,
            interner: interner,
            astArena: astArena
        )
        let typeParams = applyLocalWhereClauses(rawTypeParams, whereClauses: whereClauses)

        var valueParams: [ValueParamDecl] = []
        var depth = BracketDepth()
        var paramTokens: [Token] = []
        var index = lParenIndex + 1
        while index < funTokens.count {
            let token = funTokens[index]
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

        guard index < funTokens.count, funTokens[index].kind == .symbol(.rParen) else {
            return nil
        }
        index += 1

        let returnType = parseReturnTypeAnnotation(
            from: funTokens, index: &index, interner: interner, astArena: astArena
        )

        let body: FunctionBody
        if index < funTokens.count, funTokens[index].kind == .symbol(.assign) {
            index += 1
            let exprTokens = Array(funTokens[index...]).filter { $0.kind != .symbol(.semicolon) }
            let parser = ExpressionParser(tokens: exprTokens, interner: interner, astArena: astArena)
            if let exprID = parser.parse(), let exprRange = astArena.exprRange(exprID) {
                body = .expr(exprID, exprRange)
            } else {
                body = .unit
            }
        } else if index < funTokens.count, funTokens[index].kind == .symbol(.lBrace) {
            body = parseBraceBody(
                from: funTokens, index: &index, interner: interner, astArena: astArena
            )
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
            typeParams: typeParams,
            valueParams: valueParams,
            returnType: returnType,
            body: body,
            isSuspend: isSuspend,
            range: range
        ))
    }

    // MARK: - Local Fun Parsing Helpers

    private func parseReturnTypeAnnotation(
        from statementTokens: [Token],
        index: inout Int,
        interner: StringInterner,
        astArena: ASTArena
    ) -> TypeRefID? {
        guard index < statementTokens.count, statementTokens[index].kind == .symbol(.colon) else {
            return nil
        }
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
        return parseTypeRef(from: typeTokens, interner: interner, astArena: astArena)
    }

    private func parseBraceBody(
        from statementTokens: [Token],
        index: inout Int,
        interner: StringInterner,
        astArena: ASTArena
    ) -> FunctionBody {
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
               let lastRange = astArena.exprRange(blockExprs.last!)
            {
                let bodyRange = SourceRange(start: firstRange.start, end: lastRange.end)
                return .block(blockExprs, bodyRange)
            } else {
                let bodyRange = SourceRange(
                    start: statementTokens[braceStart].range.start,
                    end: statementTokens[min(index, statementTokens.count - 1)].range.end
                )
                return .block([], bodyRange)
            }
        } else {
            let bodyRange = SourceRange(
                start: statementTokens[braceStart].range.start,
                end: statementTokens[min(index, statementTokens.count - 1)].range.end
            )
            return .block([], bodyRange)
        }
    }

    private func parseLocalTypeParams(
        from tokens: [Token],
        interner: StringInterner,
        astArena: ASTArena
    ) -> [TypeParamDecl] {
        guard tokens.contains(where: { $0.kind == .symbol(.lessThan) }) else {
            return []
        }
        var result: [TypeParamDecl] = []
        var angleDepth = 0
        var pendingVariance: TypeVariance = .invariant
        var pendingReified = false
        var tokenIndex = 0
        while tokenIndex < tokens.count {
            let token = tokens[tokenIndex]
            switch token.kind {
            case .symbol(.lessThan):
                angleDepth += 1
                tokenIndex += 1
                continue
            case .symbol(.greaterThan):
                angleDepth = max(0, angleDepth - 1)
                pendingVariance = .invariant
                pendingReified = false
                tokenIndex += 1
                continue
            case .symbol(.comma):
                pendingVariance = .invariant
                pendingReified = false
                tokenIndex += 1
                continue
            case .softKeyword(.out):
                pendingVariance = .out
                tokenIndex += 1
                continue
            case .keyword(.in):
                pendingVariance = .in
                tokenIndex += 1
                continue
            case .keyword(.reified):
                pendingReified = true
                tokenIndex += 1
                continue
            default:
                break
            }
            guard angleDepth == 1,
                  isTypeLikeNameToken(token.kind),
                  let paramName = internedIdentifier(from: token, interner: interner)
            else {
                tokenIndex += 1
                continue
            }
            tokenIndex += 1
            let upperBound = parseLocalInlineUpperBound(
                tokens: tokens,
                tokenIndex: &tokenIndex,
                interner: interner,
                astArena: astArena
            )
            result.append(TypeParamDecl(
                name: paramName,
                variance: pendingVariance,
                isReified: pendingReified,
                upperBound: upperBound
            ))
            pendingVariance = .invariant
            pendingReified = false
        }
        return result
    }

    private func parseLocalInlineUpperBound(
        tokens: [Token],
        tokenIndex: inout Int,
        interner: StringInterner,
        astArena: ASTArena
    ) -> TypeRefID? {
        guard tokenIndex < tokens.count,
              tokens[tokenIndex].kind == .symbol(.colon)
        else {
            return nil
        }
        tokenIndex += 1
        var boundTokens: [Token] = []
        var innerDepth = BracketDepth()
        while tokenIndex < tokens.count {
            let token = tokens[tokenIndex]
            if innerDepth.isAtTopLevel,
               (token.kind == .symbol(.comma) || token.kind == .symbol(.greaterThan))
            {
                break
            }
            innerDepth.track(token.kind)
            boundTokens.append(token)
            tokenIndex += 1
        }
        return parseTypeRef(from: boundTokens, interner: interner, astArena: astArena)
    }

    private func parseLocalWhereClauses(
        from tokens: [Token],
        interner: StringInterner,
        astArena: ASTArena
    ) -> [(name: InternedString, bound: TypeRefID)] {
        var depth = BracketDepth()
        guard let startIndex = tokens.enumerated().first(where: { index, token in
            depth.track(token.kind)
            return depth.isAtTopLevel && {
                if case .softKeyword(.where) = token.kind { return true }
                return false
            }()
        })?.offset else {
            return []
        }
        var result: [(name: InternedString, bound: TypeRefID)] = []
        var index = startIndex + 1
        while index < tokens.count {
            let token = tokens[index]
            if token.kind == .symbol(.lBrace) || token.kind == .symbol(.semicolon) || token.kind == .symbol(.assign) {
                break
            }
            guard isTypeLikeNameToken(token.kind),
                  let paramName = internedIdentifier(from: token, interner: interner)
            else {
                index += 1
                continue
            }
            index += 1
            guard index < tokens.count, tokens[index].kind == .symbol(.colon) else {
                continue
            }
            index += 1
            var boundTokens: [Token] = []
            var innerDepth = BracketDepth()
            while index < tokens.count {
                let boundToken = tokens[index]
                if innerDepth.isAtTopLevel,
                   (boundToken.kind == .symbol(.comma)
                    || boundToken.kind == .symbol(.lBrace)
                    || boundToken.kind == .symbol(.semicolon)
                    || boundToken.kind == .symbol(.assign))
                {
                    break
                }
                innerDepth.track(boundToken.kind)
                boundTokens.append(boundToken)
                index += 1
            }
            if let boundRef = parseTypeRef(from: boundTokens, interner: interner, astArena: astArena) {
                result.append((name: paramName, bound: boundRef))
            }
            if index < tokens.count, tokens[index].kind == .symbol(.comma) {
                index += 1
            }
        }
        return result
    }

    private func applyLocalWhereClauses(
        _ typeParams: [TypeParamDecl],
        whereClauses: [(name: InternedString, bound: TypeRefID)]
    ) -> [TypeParamDecl] {
        guard !whereClauses.isEmpty else { return typeParams }
        let clausesByName = Dictionary(grouping: whereClauses, by: \.name)
        return typeParams.map { typeParam in
            let extraBounds = clausesByName[typeParam.name]?.map(\.bound) ?? []
            guard !extraBounds.isEmpty else { return typeParam }
            return TypeParamDecl(
                name: typeParam.name,
                variance: typeParam.variance,
                isReified: typeParam.isReified,
                upperBounds: typeParam.upperBounds + extraBounds
            )
        }
    }
}

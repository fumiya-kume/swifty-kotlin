import Foundation

extension BuildASTPhase {
    func declarationTypeParameters(
        from nodeID: NodeID,
        in arena: SyntaxArena,
        interner: StringInterner,
        astArena: ASTArena? = nil
    ) -> [TypeParamDecl] {
        for child in arena.children(of: nodeID) {
            if case let .node(childID) = child,
               arena.node(childID).kind == .typeArgs
            {
                let tokens = collectTokens(from: childID, in: arena)
                return parseTypeParamTokens(tokens, interner: interner, astArena: astArena)
            }
        }
        return []
    }

    // MARK: - Type parameter token parsing helpers

    private func parseTypeParamTokens(
        _ tokens: [Token],
        interner: StringInterner,
        astArena: ASTArena?
    ) -> [TypeParamDecl] {
        var result: [TypeParamDecl] = []
        var angleDepth = 0
        var pendingVariance: TypeVariance = .invariant
        var pendingReified = false
        var tokenIndex = 0

        while tokenIndex < tokens.count {
            let token = tokens[tokenIndex]
            if handleAngleBracketToken(token.kind, angleDepth: &angleDepth,
                                       pendingVariance: &pendingVariance, pendingReified: &pendingReified)
            {
                tokenIndex += 1
                continue
            }
            guard angleDepth == 1 else {
                tokenIndex += 1
                continue
            }
            if handleVarianceToken(token.kind, pendingVariance: &pendingVariance, pendingReified: &pendingReified) {
                tokenIndex += 1
                continue
            }
            guard isTypeLikeNameToken(token.kind),
                  let name = internedIdentifier(from: token, interner: interner)
            else {
                tokenIndex += 1
                continue
            }
            if case let .keyword(keyword) = token.kind, isLeadingDeclarationKeyword(keyword) {
                tokenIndex += 1
                continue
            }
            tokenIndex += 1
            let upperBound = parseInlineUpperBound(tokens: tokens, tokenIndex: &tokenIndex,
                                                   interner: interner, astArena: astArena)
            result.append(TypeParamDecl(
                name: name, variance: pendingVariance, isReified: pendingReified, upperBound: upperBound
            ))
            pendingVariance = .invariant
            pendingReified = false
        }
        return result
    }

    private func handleAngleBracketToken(
        _ kind: TokenKind, angleDepth: inout Int,
        pendingVariance: inout TypeVariance, pendingReified: inout Bool
    ) -> Bool {
        switch kind {
        case .symbol(.lessThan):
            angleDepth += 1
            return true
        case .symbol(.greaterThan):
            angleDepth = max(0, angleDepth - 1)
            pendingVariance = .invariant
            pendingReified = false
            return true
        case .symbol(.comma):
            pendingVariance = .invariant
            pendingReified = false
            return true
        default:
            return false
        }
    }

    private func handleVarianceToken(
        _ kind: TokenKind, pendingVariance: inout TypeVariance, pendingReified: inout Bool
    ) -> Bool {
        switch kind {
        case .softKeyword(.out):
            pendingVariance = .out
            return true
        case .keyword(.in):
            pendingVariance = .in
            return true
        case .keyword(.reified):
            pendingReified = true
            return true
        default:
            return false
        }
    }

    private func parseInlineUpperBound(
        tokens: [Token], tokenIndex: inout Int,
        interner: StringInterner, astArena: ASTArena?
    ) -> TypeRefID? {
        guard tokenIndex < tokens.count,
              tokens[tokenIndex].kind == .symbol(.colon)
        else { return nil }
        tokenIndex += 1
        var boundTokens: [Token] = []
        var innerDepth = BracketDepth()
        while tokenIndex < tokens.count {
            let tokenItem = tokens[tokenIndex]
            if innerDepth.isAtTopLevel {
                if tokenItem.kind == .symbol(.comma) || tokenItem.kind == .symbol(.greaterThan) {
                    break
                }
            }
            innerDepth.track(tokenItem.kind)
            boundTokens.append(tokenItem)
            tokenIndex += 1
        }
        guard let astArena else { return nil }
        return parseTypeRef(from: boundTokens, interner: interner, astArena: astArena)
    }

    func declarationWhereClauses(
        from nodeID: NodeID,
        in arena: SyntaxArena,
        interner: StringInterner,
        astArena: ASTArena
    ) -> [(name: InternedString, bound: TypeRefID)] {
        let tokens = collectTokens(from: nodeID, in: arena)
        guard let startIndex = findWhereKeywordIndex(in: tokens) else {
            return []
        }
        return parseWhereClauseEntries(tokens: tokens, startIndex: startIndex,
                                       interner: interner, astArena: astArena)
    }

    // MARK: - Where clause helpers

    private func findWhereKeywordIndex(in tokens: [Token]) -> Int? {
        var depth = BracketDepth()
        for (index, token) in tokens.enumerated() {
            depth.track(token.kind)
            if depth.isAtTopLevel, case .softKeyword(.where) = token.kind {
                return index
            }
        }
        return nil
    }

    private func parseWhereClauseEntries(
        tokens: [Token], startIndex: Int,
        interner: StringInterner, astArena: ASTArena
    ) -> [(name: InternedString, bound: TypeRefID)] {
        var result: [(name: InternedString, bound: TypeRefID)] = []
        var index = startIndex + 1
        while index < tokens.count {
            let token = tokens[index]
            if token.kind == .symbol(.lBrace) || token.kind == .symbol(.semicolon) {
                break
            }
            guard isTypeLikeNameToken(token.kind),
                  let name = internedIdentifier(from: token, interner: interner)
            else {
                index += 1
                continue
            }
            index += 1
            guard index < tokens.count, tokens[index].kind == .symbol(.colon) else {
                continue
            }
            index += 1
            let boundTokens = collectBoundTokens(tokens: tokens, index: &index)
            if let boundRef = parseTypeRef(from: boundTokens, interner: interner, astArena: astArena) {
                result.append((name: name, bound: boundRef))
            }
            if index < tokens.count, tokens[index].kind == .symbol(.comma) {
                index += 1
            }
        }
        return result
    }

    private func collectBoundTokens(tokens: [Token], index: inout Int) -> [Token] {
        var boundTokens: [Token] = []
        var innerDepth = BracketDepth()
        while index < tokens.count {
            let tokenItem = tokens[index]
            if innerDepth.isAtTopLevel {
                let kind = tokenItem.kind
                let shouldBreak = kind == .symbol(.comma)
                    || kind == .symbol(.lBrace)
                    || kind == .symbol(.semicolon)
                    || kind == .symbol(.assign)
                if shouldBreak {
                    break
                }
            }
            innerDepth.track(tokenItem.kind)
            boundTokens.append(tokenItem)
            index += 1
        }
        return boundTokens
    }

    func applyWhereClauses(
        _ typeParams: [TypeParamDecl],
        whereClauses: [(name: InternedString, bound: TypeRefID)]
    ) -> [TypeParamDecl] {
        guard !whereClauses.isEmpty else { return typeParams }
        let clausesByName = Dictionary(grouping: whereClauses, by: \.name)
        return typeParams.map { param in
            let paramClauses = clausesByName[param.name] ?? []
            guard !paramClauses.isEmpty else {
                return param
            }
            let mergedBounds = param.upperBounds + paramClauses.map(\.bound)
            return TypeParamDecl(
                name: param.name,
                variance: param.variance,
                isReified: param.isReified,
                upperBounds: mergedBounds
            )
        }
    }
}

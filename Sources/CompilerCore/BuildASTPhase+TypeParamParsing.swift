import Foundation

extension BuildASTPhase {
    func declarationTypeParameters(
        from nodeID: NodeID,
        in arena: SyntaxArena,
        interner: StringInterner,
        astArena: ASTArena? = nil
    ) -> [TypeParamDecl] {
        for child in arena.children(of: nodeID) {
            if case .node(let childID) = child,
               arena.node(childID).kind == .typeArgs {
                let tokens = collectTokens(from: childID, in: arena)
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
                        if angleDepth == 1 {
                            pendingVariance = .invariant
                            pendingReified = false
                        }
                        tokenIndex += 1
                        continue
                    default:
                        break
                    }

                    guard angleDepth == 1 else {
                        tokenIndex += 1
                        continue
                    }

                    switch token.kind {
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

                    guard isTypeLikeNameToken(token.kind),
                          let name = internedIdentifier(from: token, interner: interner) else {
                        tokenIndex += 1
                        continue
                    }
                    if case .keyword(let keyword) = token.kind, isLeadingDeclarationKeyword(keyword) {
                        tokenIndex += 1
                        continue
                    }

                    tokenIndex += 1

                    var upperBound: TypeRefID? = nil
                    if tokenIndex < tokens.count,
                       tokens[tokenIndex].kind == .symbol(.colon) {
                        tokenIndex += 1
                        var boundTokens: [Token] = []
                        var innerDepth = BracketDepth()
                        while tokenIndex < tokens.count {
                            let t = tokens[tokenIndex]
                            if innerDepth.isAtTopLevel {
                                if t.kind == .symbol(.comma) || t.kind == .symbol(.greaterThan) {
                                    break
                                }
                            }
                            innerDepth.track(t.kind)
                            boundTokens.append(t)
                            tokenIndex += 1
                        }
                        if let astArena {
                            upperBound = parseTypeRef(from: boundTokens, interner: interner, astArena: astArena)
                        }
                    }

                    result.append(TypeParamDecl(name: name, variance: pendingVariance, isReified: pendingReified, upperBound: upperBound))
                    pendingVariance = .invariant
                    pendingReified = false
                }
                return result
            }
        }
        return []
    }

    func declarationWhereClauses(
        from nodeID: NodeID,
        in arena: SyntaxArena,
        interner: StringInterner,
        astArena: ASTArena
    ) -> [(name: InternedString, bound: TypeRefID)] {
        let tokens = collectTokens(from: nodeID, in: arena)
        var whereIndex: Int? = nil
        var depth = BracketDepth()
        for (index, token) in tokens.enumerated() {
            depth.track(token.kind)
            if depth.isAtTopLevel, case .softKeyword(.where) = token.kind {
                whereIndex = index
                break
            }
        }
        guard let startIndex = whereIndex else {
            return []
        }

        var result: [(name: InternedString, bound: TypeRefID)] = []
        var index = startIndex + 1
        while index < tokens.count {
            let token = tokens[index]
            if token.kind == .symbol(.lBrace) || token.kind == .symbol(.semicolon) {
                break
            }
            guard isTypeLikeNameToken(token.kind),
                  let name = internedIdentifier(from: token, interner: interner) else {
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
                let t = tokens[index]
                if innerDepth.isAtTopLevel {
                    if t.kind == .symbol(.comma) || t.kind == .symbol(.lBrace) || t.kind == .symbol(.semicolon) {
                        break
                    }
                }
                innerDepth.track(t.kind)
                boundTokens.append(t)
                index += 1
            }
            if let boundRef = parseTypeRef(from: boundTokens, interner: interner, astArena: astArena) {
                result.append((name: name, bound: boundRef))
            }
            if index < tokens.count, tokens[index].kind == .symbol(.comma) {
                index += 1
            }
        }
        return result
    }

    func applyWhereClauses(
        _ typeParams: [TypeParamDecl],
        whereClauses: [(name: InternedString, bound: TypeRefID)]
    ) -> [TypeParamDecl] {
        guard !whereClauses.isEmpty else { return typeParams }
        return typeParams.map { param in
            if param.upperBound != nil { return param }
            guard let clause = whereClauses.first(where: { $0.name == param.name }) else {
                return param
            }
            return TypeParamDecl(
                name: param.name,
                variance: param.variance,
                isReified: param.isReified,
                upperBound: clause.bound
            )
        }
    }
}

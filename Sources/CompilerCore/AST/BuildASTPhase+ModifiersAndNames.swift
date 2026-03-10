import Foundation

extension BuildASTPhase {
    private static let keywordModifierMap: [Keyword: Modifiers.Element] = [
        .public: .public, .private: .private, .internal: .internal, .protected: .protected,
        .final: .final, .open: .open, .abstract: .abstract, .sealed: .sealed,
        .data: .data, .annotation: .annotationClass, .inline: .inline, .suspend: .suspend,
        .tailrec: .tailrec, .operator: .operator, .infix: .infix,
        .crossinline: .crossinline, .noinline: .noinline, .vararg: .vararg,
        .external: .external, .expect: .expect, .actual: .actual, .value: .value,
        .enum: .enumModifier, .inner: .inner, .companion: .companion,
        .const: .const, .override: .override, .fun: .funModifier, .lateinit: .lateinit,
    ]

    func modifier(from token: Token) -> Modifiers.Element? {
        guard case let .keyword(keyword) = token.kind else {
            return nil
        }
        return Self.keywordModifierMap[keyword]
    }

    func declarationModifiers(from nodeID: NodeID, in arena: SyntaxArena) -> Modifiers {
        var modifiers: Modifiers = []
        let children = arena.children(of: nodeID)
        var index = children.startIndex
        while index < children.endIndex {
            let child = children[index]
            if case let .token(tokenID) = child,
               let token = resolveToken(tokenID, in: arena)
            {
                if case let .keyword(keyword) = token.kind {
                    switch keyword {
                    case .fun:
                        let nextKeyword: Keyword? = if children.index(after: index) < children.endIndex {
                            children[children.index(after: index)...].compactMap { child -> Keyword? in
                                guard case let .token(nextTokenID) = child,
                                      let nextToken = resolveToken(nextTokenID, in: arena),
                                      case let .keyword(nextKeyword) = nextToken.kind
                                else {
                                    return nil
                                }
                                return nextKeyword
                            }.first
                        } else {
                            nil
                        }
                        if nextKeyword == .interface {
                            modifiers.insert(.funModifier)
                            index = children.index(after: index)
                            continue
                        }
                        return modifiers
                    case .class, .object, .interface, .val, .var, .typealias:
                        return modifiers
                    default:
                        break
                    }
                }
                if let modifier = modifier(from: token) {
                    modifiers.insert(modifier)
                    index = children.index(after: index)
                    continue
                }
                index = children.index(after: index)
                continue
            }
            index = children.index(after: index)
        }
        return modifiers
    }

    func extractQualifiedPath(
        from nodeID: NodeID,
        in arena: SyntaxArena,
        interner: StringInterner,
        isPackageHeader: Bool
    ) -> [InternedString] {
        var names: [InternedString] = []
        let children = arena.children(of: nodeID)
        let targetKeyword: TokenKind = isPackageHeader ? .keyword(.package) : .keyword(.import)
        
        var startIndex = 0
        if let idx = children.firstIndex(where: { child in
            guard case let .token(tokenID) = child, let token = resolveToken(tokenID, in: arena) else { return false }
            return token.kind == targetKeyword
        }) {
            startIndex = idx + 1
        }

        for child in children[startIndex...] {
            guard case let .token(tokenID) = child,
                  let token = resolveToken(tokenID, in: arena)
            else {
                continue
            }
            if case .symbol(.star) = token.kind {
                continue
            }
            if !isPackageHeader, case .keyword(.as) = token.kind {
                break
            }
            if let name = internedIdentifier(from: token, interner: interner) {
                names.append(name)
            }
        }
        return names
    }

    func extractImportAlias(
        from nodeID: NodeID,
        in arena: SyntaxArena,
        interner: StringInterner
    ) -> InternedString? {
        var foundAs = false
        for child in arena.children(of: nodeID) {
            guard case let .token(tokenID) = child,
                  let token = resolveToken(tokenID, in: arena)
            else {
                continue
            }
            if foundAs {
                if case .missing = token.kind {
                    return interner.intern("")
                }
                return internedIdentifier(from: token, interner: interner)
            }
            if case .keyword(.as) = token.kind {
                foundAs = true
            }
        }
        if foundAs {
            return interner.intern("")
        }
        return nil
    }

    func internedIdentifier(from token: Token, interner: StringInterner) -> InternedString? {
        switch token.kind {
        case let .identifier(interned):
            interned
        case let .backtickedIdentifier(interned):
            interned
        case let .keyword(keyword):
            interner.intern(keyword.rawValue)
        case let .softKeyword(soft):
            interner.intern(soft.rawValue)
        default:
            nil
        }
    }

    func isLeadingDeclarationKeyword(_ keyword: Keyword) -> Bool {
        switch keyword {
        case .class, .object, .interface, .fun, .val, .var, .typealias, .enum, .import, .package, .companion:
            true
        case .public, .private, .internal, .protected, .open, .abstract, .sealed, .data, .annotation,
             .inner, .expect, .actual, .const, .lateinit, .override, .final,
             .crossinline, .noinline, .tailrec, .inline, .suspend, .operator, .infix, .external, .value:
            true
        default:
            false
        }
    }
}

import Foundation

extension BuildASTPhase {
    func modifier(from token: Token) -> Modifiers.Element? {
        switch token.kind {
        case .keyword(.public):
            .public
        case .keyword(.private):
            .private
        case .keyword(.internal):
            .internal
        case .keyword(.protected):
            .protected
        case .keyword(.final):
            .final
        case .keyword(.open):
            .open
        case .keyword(.abstract):
            .abstract
        case .keyword(.sealed):
            .sealed
        case .keyword(.data):
            .data
        case .keyword(.annotation):
            .annotationClass
        case .keyword(.inline):
            .inline
        case .keyword(.suspend):
            .suspend
        case .keyword(.tailrec):
            .tailrec
        case .keyword(.operator):
            .operator
        case .keyword(.infix):
            .infix
        case .keyword(.crossinline):
            .crossinline
        case .keyword(.noinline):
            .noinline
        case .keyword(.vararg):
            .vararg
        case .keyword(.external):
            .external
        case .keyword(.expect):
            .expect
        case .keyword(.actual):
            .actual
        case .keyword(.value):
            .value
        case .keyword(.enum):
            .enumModifier
        case .keyword(.inner):
            .inner
        case .keyword(.companion):
            .companion
        case .keyword(.const):
            .const
        case .keyword(.override):
            .override
        case .keyword(.fun):
            .funModifier
        case .keyword(.lateinit):
            .lateinit
        default:
            nil
        }
    }

    func declarationModifiers(from nodeID: NodeID, in arena: SyntaxArena) -> Modifiers {
        var modifiers: Modifiers = []
        for child in arena.children(of: nodeID) {
            if case let .token(tokenID) = child,
               let token = resolveToken(tokenID, in: arena)
            {
                if let modifier = modifier(from: token) {
                    modifiers.insert(modifier)
                    continue
                }
                continue
            }
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
        for child in arena.children(of: nodeID) {
            guard case let .token(tokenID) = child,
                  let token = resolveToken(tokenID, in: arena)
            else {
                continue
            }
            if case .symbol(.star) = token.kind {
                continue
            }
            if isPackageHeader, case .keyword(.package) = token.kind {
                continue
            }
            if !isPackageHeader, case .keyword(.import) = token.kind {
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

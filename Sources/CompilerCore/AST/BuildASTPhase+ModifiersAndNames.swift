import Foundation

extension BuildASTPhase {
    func declarationModifiers(from nodeID: NodeID, in arena: SyntaxArena) -> Modifiers {
        var modifiers: Modifiers = []
        for child in arena.children(of: nodeID) {
            if case .token(let tokenID) = child,
               let token = resolveToken(tokenID, in: arena) {
                switch token.kind {
                case .keyword(.public):
                    modifiers.insert(.public)
                case .keyword(.private):
                    modifiers.insert(.private)
                case .keyword(.internal):
                    modifiers.insert(.internal)
                case .keyword(.protected):
                    modifiers.insert(.protected)
                case .keyword(.final):
                    modifiers.insert(.final)
                case .keyword(.open):
                    modifiers.insert(.open)
                case .keyword(.abstract):
                    modifiers.insert(.abstract)
                case .keyword(.sealed):
                    modifiers.insert(.sealed)
                case .keyword(.data):
                    modifiers.insert(.data)
                case .keyword(.annotation):
                    modifiers.insert(.annotationClass)
                case .keyword(.inline):
                    modifiers.insert(.inline)
                case .keyword(.suspend):
                    modifiers.insert(.suspend)
                case .keyword(.tailrec):
                    modifiers.insert(.tailrec)
                case .keyword(.operator):
                    modifiers.insert(.operator)
                case .keyword(.infix):
                    modifiers.insert(.infix)
                case .keyword(.crossinline):
                    modifiers.insert(.crossinline)
                case .keyword(.noinline):
                    modifiers.insert(.noinline)
                case .keyword(.vararg):
                    modifiers.insert(.vararg)
                case .keyword(.external):
                    modifiers.insert(.external)
                case .keyword(.expect):
                    modifiers.insert(.expect)
                case .keyword(.actual):
                    modifiers.insert(.actual)
                case .keyword(.value):
                    modifiers.insert(.value)
                case .keyword(.enum):
                    modifiers.insert(.enumModifier)
                case .keyword(.inner):
                    modifiers.insert(.inner)
                default:
                    continue
                }
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
            guard case .token(let tokenID) = child,
                  let token = resolveToken(tokenID, in: arena) else {
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
            guard case .token(let tokenID) = child,
                  let token = resolveToken(tokenID, in: arena) else {
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
        case .identifier(let interned):
            return interned
        case .backtickedIdentifier(let interned):
            return interned
        case .keyword(let keyword):
            return interner.intern(keyword.rawValue)
        case .softKeyword(let soft):
            return interner.intern(soft.rawValue)
        default:
            return nil
        }
    }

    func isLeadingDeclarationKeyword(_ keyword: Keyword) -> Bool {
        switch keyword {
        case .class, .object, .interface, .fun, .val, .var, .typealias, .enum, .import, .package, .companion:
            return true
        case .public, .private, .internal, .protected, .open, .abstract, .sealed, .data, .annotation,
             .inner, .expect, .actual, .const, .lateinit, .override, .final,
             .crossinline, .noinline, .tailrec, .inline, .suspend, .operator, .infix, .external, .value:
            return true
        default:
            return false
        }
    }

}

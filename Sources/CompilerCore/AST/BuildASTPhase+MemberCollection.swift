import Foundation

extension BuildASTPhase {
    func declarationEnumEntries(
        from nodeID: NodeID,
        in arena: SyntaxArena,
        interner: StringInterner
    ) -> [EnumEntryDecl] {
        var entries: [EnumEntryDecl] = []
        var stack: [NodeID] = [nodeID]
        while let current = stack.popLast() {
            for child in arena.children(of: current) {
                guard case .node(let childID) = child else {
                    continue
                }
                let childNode = arena.node(childID)
                if childNode.kind == .enumEntry {
                    entries.append(makeEnumEntryDecl(from: childID, in: arena, interner: interner))
                } else {
                    stack.append(childID)
                }
            }
        }
        return entries
    }

    func declarationNestedTypeAliases(
        from nodeID: NodeID,
        in arena: SyntaxArena,
        interner: StringInterner,
        astArena: ASTArena
    ) -> [TypeAliasDecl] {
        guard let bodyBlockID = arena.children(of: nodeID).compactMap({ child -> NodeID? in
            guard case .node(let childID) = child,
                  arena.node(childID).kind == .block else {
                return nil
            }
            return childID
        }).first else {
            return []
        }

        var aliases: [TypeAliasDecl] = []
        for child in arena.children(of: bodyBlockID) {
            guard case .node(let childID) = child,
                  arena.node(childID).kind == .typeAliasDecl else {
                continue
            }
            aliases.append(makeTypeAliasDecl(from: childID, in: arena, interner: interner, astArena: astArena))
        }
        return aliases
    }

    func declarationSuperTypes(
        from nodeID: NodeID,
        in arena: SyntaxArena,
        interner: StringInterner,
        astArena: ASTArena
    ) -> [TypeRefID] {
        let tokens = collectTokens(from: nodeID, in: arena)
        guard !tokens.isEmpty else {
            return []
        }
        let declName = declarationName(from: nodeID, in: arena, interner: interner)
        guard let nameIndex = tokens.firstIndex(where: { token in
            guard let name = internedIdentifier(from: token, interner: interner) else {
                return false
            }
            if case .keyword(let keyword) = token.kind, isLeadingDeclarationKeyword(keyword) {
                return false
            }
            return name == declName
        }) else {
            return []
        }

        var index = nameIndex + 1
        index = skipBalancedBracket(in: tokens, from: index, open: .symbol(.lessThan), close: .symbol(.greaterThan))
        index = skipBalancedBracket(in: tokens, from: index, open: .symbol(.lParen), close: .symbol(.rParen))
        guard index < tokens.count, tokens[index].kind == .symbol(.colon) else {
            return []
        }
        index += 1

        var refs: [TypeRefID] = []
        var current: [Token] = []
        var depth = BracketDepth()
        while index < tokens.count {
            let token = tokens[index]
            if depth.isAngleParenTopLevel {
                if token.kind == .symbol(.lBrace) || token.kind == .symbol(.semicolon) {
                    break
                }
                if case .softKeyword(.where) = token.kind {
                    break
                }
                if token.kind == .symbol(.comma) {
                    if let ref = parseTypeRef(
                        from: stripSuperTypeInvocation(from: current),
                        interner: interner,
                        astArena: astArena
                    ) {
                        refs.append(ref)
                    }
                    current.removeAll(keepingCapacity: true)
                    index += 1
                    continue
                }
            }

            depth.track(token.kind)
            current.append(token)
            index += 1
        }
        if let ref = parseTypeRef(
            from: stripSuperTypeInvocation(from: current),
            interner: interner,
            astArena: astArena
        ) {
            refs.append(ref)
        }
        return refs
    }

    func stripSuperTypeInvocation(from tokens: [Token]) -> [Token] {
        var result: [Token] = []
        var depth = BracketDepth()
        for token in tokens {
            if depth.angle == 0 && token.kind == .symbol(.lParen) {
                break
            }
            depth.track(token.kind)
            result.append(token)
        }
        return result
    }

    func declarationMemberDecls(
        from nodeID: NodeID,
        in arena: SyntaxArena,
        interner: StringInterner,
        astArena: ASTArena
    ) -> (functions: [DeclID], properties: [DeclID], nestedClasses: [DeclID], nestedObjects: [DeclID]) {
        guard let bodyBlockID = arena.children(of: nodeID).compactMap({ child -> NodeID? in
            guard case .node(let childID) = child,
                  arena.node(childID).kind == .block else {
                return nil
            }
            return childID
        }).first else {
            return ([], [], [], [])
        }

        var functions: [DeclID] = []
        var properties: [DeclID] = []
        var nestedClasses: [DeclID] = []
        var nestedObjects: [DeclID] = []

        for child in arena.children(of: bodyBlockID) {
            guard case .node(let childID) = child else {
                continue
            }
            let childNode = arena.node(childID)
            switch childNode.kind {
            case .funDecl:
                let funDecl = makeFunDecl(from: childID, in: arena, interner: interner, astArena: astArena)
                let declID = astArena.appendDecl(.funDecl(funDecl))
                functions.append(declID)
            case .propertyDecl:
                let propDecl = makePropertyDecl(from: childID, in: arena, interner: interner, astArena: astArena)
                let declID = astArena.appendDecl(.propertyDecl(propDecl))
                properties.append(declID)
            case .classDecl:
                let classDecl = makeClassDecl(from: childID, in: arena, interner: interner, astArena: astArena)
                let declID = astArena.appendDecl(.classDecl(classDecl))
                nestedClasses.append(declID)
            case .interfaceDecl:
                let interfaceDecl = makeInterfaceDecl(from: childID, in: arena, interner: interner, astArena: astArena)
                let declID = astArena.appendDecl(.interfaceDecl(interfaceDecl))
                nestedClasses.append(declID)
            case .objectDecl:
                let objectDecl = makeObjectDecl(from: childID, in: arena, interner: interner, astArena: astArena)
                let declID = astArena.appendDecl(.objectDecl(objectDecl))
                nestedObjects.append(declID)
            default:
                continue
            }
        }

        return (functions, properties, nestedClasses, nestedObjects)
    }

    func declarationDelegateExpression(
        from nodeID: NodeID,
        in arena: SyntaxArena,
        interner: StringInterner,
        astArena: ASTArena
    ) -> ExprID? {
        let tokens = propertyHeadTokens(from: nodeID, in: arena)
        guard !tokens.isEmpty else {
            return nil
        }

        var byIndex: Int?
        var depth = BracketDepth()
        for (index, token) in tokens.enumerated() {
            if case .softKeyword(.by) = token.kind, depth.isAtTopLevel {
                byIndex = index
                break
            }
            depth.track(token.kind)
        }

        guard let byIndex else {
            return nil
        }
        let start = byIndex + 1
        guard start < tokens.count else {
            return nil
        }
        let exprTokens = tokens[start...].filter { $0.kind != .symbol(.semicolon) }
        guard !exprTokens.isEmpty else {
            return nil
        }
        let parser = ExpressionParser(tokens: Array(exprTokens), interner: interner, astArena: astArena)
        return parser.parse()
    }
}

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
                guard case let .node(childID) = child else {
                    continue
                }
                let childNode = arena.node(childID)
                if childNode.kind == .enumEntry {
                    let expanded = declarationEnumEntries(
                        fromEnumEntryNode: childID,
                        in: arena,
                        interner: interner
                    )
                    if expanded.isEmpty {
                        entries.append(makeEnumEntryDecl(from: childID, in: arena, interner: interner))
                    } else {
                        entries.append(contentsOf: expanded)
                    }
                } else {
                    stack.append(childID)
                }
            }
        }
        return entries
    }

    private func declarationEnumEntries(
        fromEnumEntryNode nodeID: NodeID,
        in arena: SyntaxArena,
        interner: StringInterner
    ) -> [EnumEntryDecl] {
        let tokens = collectTokens(from: nodeID, in: arena)
        guard !tokens.isEmpty else {
            return []
        }

        var segments: [[Token]] = []
        var current: [Token] = []
        var depth = BracketDepth()

        for token in tokens {
            if depth.isAtTopLevel,
               token.kind == .symbol(.comma) || token.kind == .symbol(.semicolon)
            {
                if !current.isEmpty {
                    segments.append(current)
                    current.removeAll(keepingCapacity: true)
                }
                continue
            }
            depth.track(token.kind)
            current.append(token)
        }
        if !current.isEmpty {
            segments.append(current)
        }

        var entries: [EnumEntryDecl] = []
        entries.reserveCapacity(segments.count)
        for segment in segments {
            guard let nameToken = segment.first(where: { token in
                internedIdentifier(from: token, interner: interner) != nil
            }), let name = internedIdentifier(from: nameToken, interner: interner) else {
                continue
            }
            let end = segment.last?.range.end ?? nameToken.range.end
            entries.append(EnumEntryDecl(
                range: SourceRange(start: nameToken.range.start, end: end),
                name: name
            ))
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
            guard case let .node(childID) = child,
                  arena.node(childID).kind == .block
            else {
                return nil
            }
            return childID
        }).first else {
            return []
        }

        var aliases: [TypeAliasDecl] = []
        for child in arena.children(of: bodyBlockID) {
            guard case let .node(childID) = child,
                  arena.node(childID).kind == .typeAliasDecl
            else {
                continue
            }
            aliases.append(makeTypeAliasDecl(from: childID, in: arena, interner: interner, astArena: astArena))
        }
        return aliases
    }

    /// Parses supertype entries for class declarations, including optional
    /// `by expr` delegation (e.g. `class Foo(impl: Printer) : Printer by impl`).
    /// Returns `[SuperTypeEntry]`; use `declarationSuperTypes` for interface/object.
    func declarationSuperTypeEntries(
        from nodeID: NodeID,
        in arena: SyntaxArena,
        interner: StringInterner,
        astArena: ASTArena
    ) -> [SuperTypeEntry] {
        let tokens = collectTokens(from: nodeID, in: arena)
        guard !tokens.isEmpty else {
            return []
        }
        let declName = declarationName(from: nodeID, in: arena, interner: interner)
        guard let nameIndex = tokens.firstIndex(where: { token in
            guard let name = internedIdentifier(from: token, interner: interner) else {
                return false
            }
            if case let .keyword(keyword) = token.kind, isLeadingDeclarationKeyword(keyword) {
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

        var entries: [SuperTypeEntry] = []
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
                    if let entry = parseSuperTypeEntry(from: current, interner: interner, astArena: astArena) {
                        entries.append(entry)
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
        if let entry = parseSuperTypeEntry(from: current, interner: interner, astArena: astArena) {
            entries.append(entry)
        }
        return entries
    }

    /// Parses a single supertype chunk, optionally with `by expr` (class delegation).
    private func parseSuperTypeEntry(
        from tokens: [Token],
        interner: StringInterner,
        astArena: ASTArena
    ) -> SuperTypeEntry? {
        let stripped = stripSuperTypeInvocation(from: tokens)
        guard !stripped.isEmpty else { return nil }

        var byIndex: Int?
        var depth = BracketDepth()
        for (index, token) in stripped.enumerated() {
            if case .softKeyword(.by) = token.kind, depth.isAtTopLevel {
                byIndex = index
                break
            }
            depth.track(token.kind)
        }

        let typeTokens: [Token]
        let exprTokens: ArraySlice<Token>
        if let byIndex {
            typeTokens = Array(stripped[..<byIndex])
            exprTokens = stripped[(byIndex + 1)...].filter { $0.kind != .symbol(.semicolon) }
        } else {
            typeTokens = stripped
            exprTokens = [][...]
        }

        guard let typeRef = parseTypeRef(from: typeTokens, interner: interner, astArena: astArena) else {
            return nil
        }

        let delegateExpr: ExprID?
        if exprTokens.isEmpty {
            delegateExpr = nil
        } else {
            let parser = ExpressionParser(tokens: exprTokens, interner: interner, astArena: astArena)
            delegateExpr = parser.parse()
        }

        return SuperTypeEntry(typeRef: typeRef, delegateExpression: delegateExpr)
    }

    func declarationSuperTypes(
        from nodeID: NodeID,
        in arena: SyntaxArena,
        interner: StringInterner,
        astArena: ASTArena
    ) -> [TypeRefID] {
        let entries = declarationSuperTypeEntries(from: nodeID, in: arena, interner: interner, astArena: astArena)
        return entries.map(\.typeRef)
    }

    func stripSuperTypeInvocation(from tokens: [Token]) -> [Token] {
        var result: [Token] = []
        var depth = BracketDepth()
        for token in tokens {
            if depth.angle == 0, token.kind == .symbol(.lParen) {
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
    ) -> (functions: [DeclID], properties: [DeclID], nestedClasses: [DeclID], nestedObjects: [DeclID], companionObject: DeclID?) {
        guard let bodyBlockID = arena.children(of: nodeID).compactMap({ child -> NodeID? in
            guard case let .node(childID) = child,
                  arena.node(childID).kind == .block
            else {
                return nil
            }
            return childID
        }).first else {
            return ([], [], [], [], nil)
        }

        var functions: [DeclID] = []
        var properties: [DeclID] = []
        var nestedClasses: [DeclID] = []
        var nestedObjects: [DeclID] = []
        var companionObject: DeclID?

        for child in arena.children(of: bodyBlockID) {
            guard case let .node(childID) = child else { continue }
            processMemberChild(
                childID,
                in: arena, interner: interner, astArena: astArena,
                functions: &functions, properties: &properties,
                nestedClasses: &nestedClasses, nestedObjects: &nestedObjects,
                companionObject: &companionObject
            )
        }

        return (functions, properties, nestedClasses, nestedObjects, companionObject)
    }

    private func processMemberChild(
        _ childID: NodeID,
        in arena: SyntaxArena,
        interner: StringInterner,
        astArena: ASTArena,
        functions: inout [DeclID],
        properties: inout [DeclID],
        nestedClasses: inout [DeclID],
        nestedObjects: inout [DeclID],
        companionObject: inout DeclID?
    ) {
        let childNode = arena.node(childID)
        switch childNode.kind {
        case .funDecl:
            let funDecl = makeFunDecl(from: childID, in: arena, interner: interner, astArena: astArena)
            functions.append(astArena.appendDecl(.funDecl(funDecl)))
        case .propertyDecl:
            let propDecl = makePropertyDecl(from: childID, in: arena, interner: interner, astArena: astArena)
            properties.append(astArena.appendDecl(.propertyDecl(propDecl)))
        case .classDecl:
            let classDecl = makeClassDecl(from: childID, in: arena, interner: interner, astArena: astArena)
            nestedClasses.append(astArena.appendDecl(.classDecl(classDecl)))
        case .interfaceDecl:
            let interfaceDecl = makeInterfaceDecl(from: childID, in: arena, interner: interner, astArena: astArena)
            nestedClasses.append(astArena.appendDecl(.interfaceDecl(interfaceDecl)))
        case .objectDecl:
            let objectDecl = makeObjectDecl(from: childID, in: arena, interner: interner, astArena: astArena)
            let declID = astArena.appendDecl(.objectDecl(objectDecl))
            if objectDecl.modifiers.contains(.companion) {
                companionObject = declID
            } else {
                nestedObjects.append(declID)
            }
        default:
            break
        }
    }

    /// Walks the class body block and records the declaration-order sequence
    /// of property initializers and `init { }` blocks.  The returned array
    /// contains `.property(i)` / `.initBlock(j)` entries whose indices
    /// correspond to the positions in `ClassDecl.memberProperties` and
    /// `ClassDecl.initBlocks` respectively.
    func declarationClassBodyInitOrder(
        from nodeID: NodeID,
        in arena: SyntaxArena,
        interner _: StringInterner
    ) -> [ClassBodyInitMember] {
        guard let bodyBlockID = arena.children(of: nodeID).compactMap({ child -> NodeID? in
            guard case let .node(childID) = child,
                  arena.node(childID).kind == .block
            else {
                return nil
            }
            return childID
        }).first else {
            return []
        }

        var order: [ClassBodyInitMember] = []
        var propertyIndex = 0
        var initBlockIndex = 0

        for child in arena.children(of: bodyBlockID) {
            guard case let .node(childID) = child else {
                continue
            }
            let childNode = arena.node(childID)

            if childNode.kind == .propertyDecl {
                order.append(.property(propertyIndex))
                propertyIndex += 1
                continue
            }

            // Init blocks appear as statement-like nodes whose first direct
            // token is the `init` soft keyword (same logic used by
            // `declarationInitBlocks`).
            if isStatementLikeKind(childNode.kind) {
                let headerTokens = collectDirectTokens(from: childID, in: arena).filter { token in
                    token.kind != .symbol(.semicolon)
                }
                if let firstToken = headerTokens.first {
                    if firstToken.kind == .softKeyword(.`init`) {
                        order.append(.initBlock(initBlockIndex))
                        initBlockIndex += 1
                    }
                }
            }
        }
        return order
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
        let parser = ExpressionParser(tokens: ArraySlice(exprTokens), interner: interner, astArena: astArena)
        return parser.parse()
    }
}

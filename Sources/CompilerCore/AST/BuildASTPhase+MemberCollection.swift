
private func isConstructorVisibilityModifier(_ kind: TokenKind) -> Bool {
    guard case .keyword(let keyword) = kind else {
        return false
    }
    switch keyword {
    case .internal, .private, .public, .protected, .external:
        return true
    default:
        return false
    }
}

extension BuildASTPhase {
    func declarationEnumEntries(
        from nodeID: NodeID,
        in arena: SyntaxArena,
        interner: StringInterner,
        astArena: ASTArena,
        diagnostics: DiagnosticEngine?
    ) -> [EnumEntryDecl] {
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

        let tokens = collectTokens(from: bodyBlockID, in: arena)
        guard !tokens.isEmpty else {
            return []
        }

        var segments: [[Token]] = []
        var current: [Token] = []
        var depth = BracketDepth()
        var seenOpeningBrace = false

        for token in tokens {
            if !seenOpeningBrace {
                if token.kind == .symbol(.lBrace) {
                    seenOpeningBrace = true
                }
                continue
            }

            if depth.isAtTopLevel,
               token.kind == .symbol(.rBrace)
            {
                if !current.isEmpty {
                    segments.append(current)
                    current.removeAll(keepingCapacity: true)
                }
                break
            }

            if depth.isAtTopLevel,
               token.kind == .symbol(.semicolon)
            {
                if !current.isEmpty {
                    segments.append(current)
                    current.removeAll(keepingCapacity: true)
                }
                break
            }

            if depth.isAtTopLevel,
               token.kind == .symbol(.comma)
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
            // Skip segments that contain declaration keywords — these are class member
            // declarations that appear in non-enum class bodies, not enum entries.
            let hasDeclKeyword = segment.contains(where: { token in
                switch token.kind {
                case .keyword(.val), .keyword(.var), .keyword(.fun),
                     .keyword(.class), .keyword(.object), .keyword(.interface),
                     .keyword(.typealias), .keyword(.constructor), .softKeyword(.constructor):
                    return true
                default:
                    return false
                }
            })
            if hasDeclKeyword { continue }

            var annotations: [AnnotationNode] = []
            var annotIndex = 0
            while annotIndex < segment.count, segment[annotIndex].kind == .symbol(.at) {
                if let parsed = AnnotationParsingSupport.parseAnnotation(
                    from: segment, start: annotIndex, interner: interner, allowUseSiteTarget: false
                ) {
                    // Skip annotations that had an invalid (property) use-site target —
                    // those belong to property declarations, not enum entries.
                    if parsed.invalidUseSiteTargetRange == nil {
                        annotations.append(parsed.annotation)
                    }
                    annotIndex = parsed.nextIndex
                } else {
                    annotIndex += 1
                }
            }
            guard let nameIndex = segment[annotIndex...].firstIndex(where: { token in
                internedIdentifier(from: token, interner: interner) != nil
            }), let name = internedIdentifier(from: segment[nameIndex], interner: interner) else {
                continue
            }
            let nameToken = segment[nameIndex]
            var constructorArgs: [CallArgument] = []
            if let parenIndex = segment[nameIndex...].dropFirst().firstIndex(where: { $0.kind == .symbol(.lParen) }) {
                let afterParen = skipBalancedBracket(in: segment, from: parenIndex, open: .symbol(.lParen), close: .symbol(.rParen))
                let argTokens = Array(segment[(parenIndex + 1)..<afterParen])
                let parser = ExpressionParser(
                    tokens: argTokens,
                    interner: interner,
                    astArena: astArena,
                    diagnostics: diagnostics
                )
                constructorArgs = parser.parseCallArguments()
            }
            let end = segment.last?.range.end ?? nameToken.range.end
            entries.append(EnumEntryDecl(
                range: SourceRange(start: nameToken.range.start, end: end),
                name: name,
                annotations: annotations,
                constructorArgs: constructorArgs
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
        let declarationKeyword: Keyword
        switch arena.node(nodeID).kind {
        case .classDecl:
            declarationKeyword = .class
        case .objectDecl:
            declarationKeyword = .object
        case .interfaceDecl:
            declarationKeyword = .interface
        default:
            return []
        }
        guard let introducerIndex = firstTopLevelKeywordIndex(in: tokens, matching: [declarationKeyword]),
              introducerIndex + 1 < tokens.count,
              let name = internedIdentifier(from: tokens[introducerIndex + 1], interner: interner),
              name == declName
        else {
            return []
        }
        let nameIndex = introducerIndex + 1

        var index = nameIndex + 1
        index = skipBalancedBracket(in: tokens, from: index, open: .symbol(.lessThan), close: .symbol(.greaterThan))
        index = skipBalancedBracket(in: tokens, from: index, open: .symbol(.lParen), close: .symbol(.rParen))
        // Primary constructors may use the explicit `constructor` keyword with an
        // optional visibility modifier and/or annotations; skip them before
        // looking for the supertype colon.
        while index < tokens.count {
            let token = tokens[index]
            if token.kind == .symbol(.at) {
                if let parsed = AnnotationParsingSupport.parseAnnotation(
                    from: tokens, start: index, interner: interner, allowUseSiteTarget: false
                ) {
                    index = parsed.nextIndex
                    continue
                }
                break
            }
            if isConstructorVisibilityModifier(token.kind) {
                index += 1
                continue
            }
            break
        }
        if index < tokens.count,
           tokens[index].kind == .keyword(.constructor) || tokens[index].kind == .softKeyword(.constructor) {
            index += 1
            index = skipBalancedBracket(in: tokens, from: index, open: .symbol(.lParen), close: .symbol(.rParen))
        }
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
        guard !tokens.isEmpty else { return nil }

        var byIndex: Int?
        var depth = BracketDepth()
        for (index, token) in tokens.enumerated() {
            if case .softKeyword(.by) = token.kind, depth.isAtTopLevel {
                byIndex = index
                break
            }
            depth.track(token.kind)
        }

        let typeTokens: [Token]
        let exprTokens: [Token]
        if let byIndex {
            typeTokens = Array(tokens[..<byIndex])
            exprTokens = Array(tokens[(byIndex + 1)...]).filter { $0.kind != .symbol(.semicolon) }
        } else {
            typeTokens = tokens
            exprTokens = []
        }

        guard let parsedSuperType = parseSuperTypeTypeRef(from: typeTokens, interner: interner, astArena: astArena) else {
            return nil
        }

        let delegateExpr: ExprID?
        if exprTokens.isEmpty {
            delegateExpr = nil
        } else {
            let parser = ExpressionParser(tokens: exprTokens, interner: interner, astArena: astArena)
            delegateExpr = parser.parse()
        }

        return SuperTypeEntry(
            typeRef: parsedSuperType.ref,
            delegateExpression: delegateExpr,
            constructorArgs: parsedSuperType.constructorArgs
        )
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

    /// A supertype reference together with the arguments of its optional
    /// trailing constructor invocation.
    private struct ParsedSuperType {
        let ref: TypeRefID
        let constructorArgs: [CallArgument]
    }

    /// Parses a supertype type reference plus an optional trailing constructor
    /// invocation `(args)`, while still allowing function type literals such as
    /// `() -> V` and receiver function types such as `String.() -> Unit`.
    private func parseSuperTypeTypeRef(
        from tokens: [Token],
        interner: StringInterner,
        astArena: ASTArena
    ) -> ParsedSuperType? {
        guard !tokens.isEmpty else { return nil }

        let options = TypeRefParserCore.Options.declaration
        guard let parsed = TypeRefParserCore.parseTypeRefPrefix(
            tokens[...],
            interner: interner,
            astArena: astArena,
            options: options,
            diagnostics: diagnostics
        ) else {
            return nil
        }

        let remainingStart = parsed.consumed
        guard remainingStart < tokens.count else {
            return ParsedSuperType(ref: parsed.ref, constructorArgs: [])
        }

        // A named supertype may be followed by a constructor invocation `(...)`.
        guard tokens[remainingStart].kind == .symbol(.lParen) else {
            return nil
        }

        var parenDepth = 0
        var index = remainingStart
        while index < tokens.count {
            let kind = tokens[index].kind
            if kind == .symbol(.lParen) {
                parenDepth += 1
            } else if kind == .symbol(.rParen) {
                parenDepth -= 1
                if parenDepth == 0 {
                    index += 1
                    break
                }
            }
            index += 1
        }

        guard parenDepth == 0 else { return nil }
        let trailing = tokens[index...]
        guard trailing.allSatisfy({ $0.kind == .symbol(.semicolon) }) else { return nil }

        let args = parseSuperTypeConstructorArgs(
            Array(tokens[(remainingStart + 1) ..< (index - 1)]),
            interner: interner,
            astArena: astArena
        )
        return ParsedSuperType(ref: parsed.ref, constructorArgs: args)
    }

    /// Splits the token run between the parentheses of a superclass constructor
    /// invocation on top-level commas and parses each chunk as an expression.
    private func parseSuperTypeConstructorArgs(
        _ tokens: [Token],
        interner: StringInterner,
        astArena: ASTArena
    ) -> [CallArgument] {
        var args: [CallArgument] = []
        var current: [Token] = []
        var depth = BracketDepth()

        func flush() {
            guard !current.isEmpty else { return }
            let parser = ExpressionParser(tokens: current, interner: interner, astArena: astArena)
            if let exprID = parser.parse() {
                args.append(CallArgument(expr: exprID))
            }
            current.removeAll(keepingCapacity: true)
        }

        for token in tokens {
            if token.kind == .symbol(.comma), depth.isAtTopLevel {
                flush()
                continue
            }
            depth.track(token.kind)
            current.append(token)
        }
        flush()
        return args
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
    ///
    /// `ClassDecl.memberProperties` is `constructorProperties + members.properties`
    /// (primary-constructor `val`/`var` params first, then body-declared
    /// properties — see `makeClassDecl`), so `propertyIndex` must start at
    /// `constructorPropertyCount` rather than 0. Otherwise the `.property(i)`
    /// entries this function emits — which are indexed relative to the body
    /// block alone — end up pointing at the wrong `memberProperties` entry
    /// (or a constructor-parameter property with no body initializer) as soon
    /// as the class has both kinds of property, and body property initializers
    /// silently stop running. `ObjectDecl.memberProperties` has no constructor
    /// properties prepended, so its callers pass 0 (the default).
    func declarationClassBodyInitOrder(
        from nodeID: NodeID,
        in arena: SyntaxArena,
        interner _: StringInterner,
        constructorPropertyCount: Int = 0
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
        var propertyIndex = constructorPropertyCount
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
        // A delegate expression follows the same call grammar as any other
        // initializer.  In particular, a trailing lambda is the final call
        // argument and must participate in overload resolution and inference.
        let tokens = propertyHeadTokens(
            from: nodeID,
            in: arena,
            includingTrailingLambdaTokens: true
        )
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
        // The trailing lambda is included in these tokens so that it
        // participates in ordinary call parsing, overload resolution, and
        // type inference. Remove only declaration-level semicolons; semicolons
        // in the lambda body must remain available to the block parser.
        let exprTokens = filterTopLevelSemicolons(tokens[start...])
        guard !exprTokens.isEmpty else {
            return nil
        }
        let parser = ExpressionParser(tokens: ArraySlice(exprTokens), interner: interner, astArena: astArena)
        return parser.parse()
    }
}

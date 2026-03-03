extension KotlinParser {
    // swiftlint:disable:next cyclomatic_complexity function_body_length
    func parseDeclaration() -> NodeID {
        var modifierChildren: [SyntaxChild] = []
        var modifierRange = RangeAccumulator()
        while case let .keyword(keyword) = stream.peek().kind, Self.isDeclarationModifierKeyword(keyword) {
            _ = consumeToken(into: &modifierChildren, range: &modifierRange)
        }
        let token = stream.peek()
        switch token.kind {
        case .keyword(.class):
            return parseNamedDeclaration(
                kind: .classDecl,
                leadingChildren: modifierChildren,
                leadingRange: modifierRange.value
            )
        case .keyword(.object):
            return parseNamedDeclaration(
                kind: .objectDecl,
                leadingChildren: modifierChildren,
                leadingRange: modifierRange.value
            )
        case .keyword(.interface):
            return parseNamedDeclaration(
                kind: .interfaceDecl,
                leadingChildren: modifierChildren,
                leadingRange: modifierRange.value
            )
        case .keyword(.fun):
            // `fun interface` — consume `fun` as a modifier and parse as interface decl
            if stream.peek(1).kind == .keyword(.interface) {
                _ = consumeToken(into: &modifierChildren, range: &modifierRange)
                return parseNamedDeclaration(
                    kind: .interfaceDecl,
                    leadingChildren: modifierChildren,
                    leadingRange: modifierRange.value
                )
            }
            return parseFunctionDeclaration(leadingChildren: modifierChildren, leadingRange: modifierRange.value)
        case .keyword(.val), .keyword(.var):
            return parsePropertyDeclaration(leadingChildren: modifierChildren, leadingRange: modifierRange.value)
        case .keyword(.typealias):
            return parseTypeAliasDeclaration(leadingChildren: modifierChildren, leadingRange: modifierRange.value)
        case .keyword(.enum):
            return parseEnumDeclaration(leadingChildren: modifierChildren, leadingRange: modifierRange.value)
        case .keyword(.package):
            return parsePackageHeader(leadingChildren: modifierChildren, leadingRange: modifierRange.value)
        case .keyword(.import):
            return parseImportHeader(leadingChildren: modifierChildren, leadingRange: modifierRange.value)
        case .keyword(.companion):
            _ = consumeToken(into: &modifierChildren, range: &modifierRange)
            if case .keyword(.object) = stream.peek().kind {
                return parseNamedDeclaration(
                    kind: .objectDecl,
                    leadingChildren: modifierChildren,
                    leadingRange: modifierRange.value
                )
            }
            return parseDeclaration()
        default:
            return parseStatement(inBlock: false)
        }
    }

    func parsePackageHeader(leadingChildren: [SyntaxChild] = [], leadingRange: SourceRange? = nil) -> NodeID {
        parseHeaderDeclaration(keyword: .keyword(.package), kind: .packageHeader, allowWildcard: false, leadingChildren: leadingChildren, leadingRange: leadingRange)
    }

    func parseImportHeader(leadingChildren: [SyntaxChild] = [], leadingRange: SourceRange? = nil) -> NodeID {
        parseHeaderDeclaration(keyword: .keyword(.import), kind: .importHeader, allowWildcard: true, allowAlias: true, leadingChildren: leadingChildren, leadingRange: leadingRange)
    }

    func parseHeaderDeclaration(
        keyword: TokenKind,
        kind: SyntaxKind,
        allowWildcard: Bool,
        allowAlias: Bool = false,
        leadingChildren: [SyntaxChild],
        leadingRange: SourceRange?
    ) -> NodeID {
        var range = RangeAccumulator(value: leadingRange)
        var children: [SyntaxChild] = leadingChildren
        consumeIf(expected: keyword, into: &children, range: &range, code: "KSWIFTK-PARSE-0001")
        parseQualifiedPath(into: &children, range: &range, allowImportWildcard: allowWildcard, stopAtAs: allowAlias)
        if allowAlias, case .keyword(.as) = stream.peek().kind {
            _ = consumeToken(into: &children, range: &range)
            if isIdentifierLike(stream.peek().kind) {
                _ = consumeToken(into: &children, range: &range)
            } else {
                insertMissingToken(expected: .identifier(.invalid), into: &children, range: &range, code: "KSWIFTK-PARSE-0005", message: "Expected alias name after 'as'.")
            }
        }
        appendOptionalTerminator(into: &children, range: &range)
        return arena.appendNode(kind: kind, range: range.value ?? invalidRange, children)
    }

    func parseNamedDeclaration(
        kind: SyntaxKind,
        leadingChildren: [SyntaxChild] = [],
        leadingRange: SourceRange? = nil
    ) -> NodeID {
        var children: [SyntaxChild] = leadingChildren
        var range = RangeAccumulator(value: leadingRange)
        let supportsTypeParameters = kind == .classDecl || kind == .interfaceDecl

        // Detect companion object: leading modifiers contain the `companion` keyword
        let isCompanionObject = kind == .objectDecl && leadingChildren.contains(where: { child in
            if case let .token(tokenID) = child,
               let token = arena.token(tokenID),
               case .keyword(.companion) = token.kind
            {
                return true
            }
            return false
        })

        _ = consumeToken(into: &children, range: &range)
        if isIdentifierLike(stream.peek().kind) {
            _ = consumeToken(into: &children, range: &range)
        } else if !isCompanionObject {
            // Companion objects may omit the name (defaults to "Companion"),
            // so only emit a diagnostic for non-companion declarations.
            insertMissingToken(expected: .identifier(.invalid), into: &children, range: &range, code: "KSWIFTK-PARSE-0002", message: "Expected declaration name.")
        }
        if supportsTypeParameters, canStartTypeArgumentsInternal(hasAnchorToken: lastConsumedToken != nil) {
            children.append(.node(parseTypeArguments()))
            if let last = children.last {
                range.append(childRange(last))
            }
        }
        parsePostDeclarationTail(
            into: &children,
            range: &range,
            includeBlock: kind == .classDecl || kind == .interfaceDecl || kind == .objectDecl
        )

        return arena.appendNode(
            kind: kind,
            range: range.value ?? invalidRange, children
        )
    }

    func parseFunctionDeclaration(
        leadingChildren: [SyntaxChild] = [],
        leadingRange: SourceRange? = nil
    ) -> NodeID {
        var children: [SyntaxChild] = leadingChildren
        var range = RangeAccumulator(value: leadingRange)

        _ = consumeToken(into: &children, range: &range)
        if canStartTypeArgumentsInternal(hasAnchorToken: lastConsumedToken != nil) {
            children.append(.node(parseTypeArguments()))
            if let last = children.last {
                range.append(childRange(last))
            }
        }
        if isIdentifierLike(stream.peek().kind) {
            _ = consumeToken(into: &children, range: &range)
        } else {
            insertMissingToken(expected: .identifier(.invalid), into: &children, range: &range, code: "KSWIFTK-PARSE-0002", message: "Expected function name.")
        }

        if case .symbol(.lParen) = stream.peek().kind {
            children.append(.node(parseBalancedGroup(opening: .lParen, closing: .rParen)))
        }

        if case .symbol(.lBrace) = stream.peek().kind {
            children.append(.node(parseBlock()))
        } else {
            parseTail(inBlock: false, into: &children, range: &range)
        }

        return arena.appendNode(
            kind: .funDecl,
            range: range.value ?? invalidRange, children
        )
    }

    func parsePropertyDeclaration(
        leadingChildren: [SyntaxChild] = [],
        leadingRange: SourceRange? = nil
    ) -> NodeID {
        var children: [SyntaxChild] = leadingChildren
        var range = RangeAccumulator(value: leadingRange)

        _ = consumeToken(into: &children, range: &range)
        if isIdentifierLike(stream.peek().kind) {
            _ = consumeToken(into: &children, range: &range)
        } else {
            insertMissingToken(expected: .identifier(.invalid), into: &children, range: &range, code: "KSWIFTK-PARSE-0002", message: "Expected property name.")
        }

        if case .symbol(.lBrace) = stream.peek().kind {
            children.append(.node(parseBlock()))
        } else {
            parseTail(inBlock: false, into: &children, range: &range)
        }

        return arena.appendNode(
            kind: .propertyDecl,
            range: range.value ?? invalidRange, children
        )
    }

    func parseTypeAliasDeclaration(
        leadingChildren: [SyntaxChild] = [],
        leadingRange: SourceRange? = nil
    ) -> NodeID {
        var children: [SyntaxChild] = leadingChildren
        var range = RangeAccumulator(value: leadingRange)

        _ = consumeToken(into: &children, range: &range)
        if isIdentifierLike(stream.peek().kind) {
            _ = consumeToken(into: &children, range: &range)
        } else {
            insertMissingToken(expected: .identifier(.invalid), into: &children, range: &range, code: "KSWIFTK-PARSE-0002", message: "Expected typealias name.")
        }
        if canStartTypeArgumentsInternal(hasAnchorToken: lastConsumedToken != nil) {
            children.append(.node(parseTypeArguments()))
            if let last = children.last {
                range.append(childRange(last))
            }
        }
        parseTail(inBlock: false, into: &children, range: &range)

        return arena.appendNode(
            kind: .typeAliasDecl,
            range: range.value ?? invalidRange, children
        )
    }

    func parseEnumDeclaration(
        leadingChildren: [SyntaxChild] = [],
        leadingRange: SourceRange? = nil
    ) -> NodeID {
        var children: [SyntaxChild] = leadingChildren
        var range = RangeAccumulator(value: leadingRange)

        _ = consumeToken(into: &children, range: &range)
        if case .keyword(.class) = stream.peek().kind {
            _ = consumeToken(into: &children, range: &range)
        }
        if isIdentifierLike(stream.peek().kind) {
            _ = consumeToken(into: &children, range: &range)
        } else {
            insertMissingToken(expected: .identifier(.invalid), into: &children, range: &range, code: "KSWIFTK-PARSE-0002", message: "Expected enum name.")
        }

        if case .symbol(.lBrace) = stream.peek().kind {
            children.append(.node(parseEnumBody()))
        } else {
            parseTail(inBlock: false, into: &children, range: &range)
        }

        return arena.appendNode(
            kind: .classDecl,
            range: range.value ?? invalidRange, children
        )
    }

    func parseEnumBody() -> NodeID {
        var children: [SyntaxChild] = []
        var range = RangeAccumulator()
        guard consumeIfSymbol(.lBrace, into: &children, range: &range) else {
            return arena.appendNode(kind: .block, range: range.value ?? invalidRange, children)
        }

        while !stream.atEOF() {
            let token = stream.peek()
            if case .symbol(.rBrace) = token.kind {
                _ = consumeToken(into: &children, range: &range)
                break
            }

            if isIdentifierLike(token.kind) {
                children.append(.node(parseEnumEntryDeclaration()))
                continue
            }
            if isDeclarationStart(token.kind) {
                children.append(.node(parseDeclaration()))
                continue
            }
            if token.kind == .symbol(.comma) || token.kind == .symbol(.semicolon) {
                _ = consumeToken(into: &children, range: &range)
                continue
            }
            children.append(.node(parseStatement(inBlock: true)))
        }

        return arena.appendNode(kind: .block, range: range.value ?? invalidRange, children)
    }

    func parseEnumEntryDeclaration() -> NodeID {
        var children: [SyntaxChild] = []
        var range = RangeAccumulator()

        if isIdentifierLike(stream.peek().kind) {
            _ = consumeToken(into: &children, range: &range)
        }
        if case .symbol(.lParen) = stream.peek().kind {
            children.append(.node(parseBalancedGroup(opening: .lParen, closing: .rParen)))
        }
        parseTail(inBlock: true, into: &children, range: &range)

        return arena.appendNode(
            kind: .enumEntry,
            range: range.value ?? invalidRange, children
        )
    }

    func parseConstructorDeclaration() -> NodeID {
        var children: [SyntaxChild] = []
        var range = RangeAccumulator()

        _ = consumeToken(into: &children, range: &range)

        if case .symbol(.lParen) = stream.peek().kind {
            children.append(.node(parseBalancedGroup(opening: .lParen, closing: .rParen)))
            if let last = children.last {
                range.append(childRange(last))
            }
        }

        var parenDepth = 0
        while !stream.atEOF() {
            let token = stream.peek()
            if token.kind == .eof { break }
            if case .symbol(.rBrace) = token.kind, parenDepth == 0 { break }
            if case .symbol(.lBrace) = token.kind, parenDepth == 0 { break }
            if hasLeadingNewline(token), parenDepth == 0, !children.isEmpty, token.kind != .symbol(.colon), token.kind != .keyword(.this), token.kind != .keyword(.super) { break }
            if case .symbol(.semicolon) = token.kind {
                _ = consumeToken(into: &children, range: &range)
                break
            }
            _ = consumeToken(into: &children, range: &range)
            if case .symbol(.lParen) = token.kind { parenDepth += 1 }
            if case .symbol(.rParen) = token.kind { parenDepth = max(0, parenDepth - 1) }
        }

        if case .symbol(.lBrace) = stream.peek().kind {
            children.append(.node(parseBlock()))
            if let last = children.last {
                range.append(childRange(last))
            }
        }

        return arena.appendNode(kind: .constructorDecl, range: range.value ?? invalidRange, children)
    }

    func parsePostDeclarationTail(into children: inout [SyntaxChild], range: inout RangeAccumulator, includeBlock: Bool) {
        if case .symbol(.lBrace) = stream.peek().kind {
            if includeBlock {
                children.append(.node(parseBlock()))
            } else {
                _ = consumeToken(into: &children, range: &range)
            }
            return
        }
        parseTail(inBlock: false, into: &children, range: &range)
    }
}

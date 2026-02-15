public final class KotlinParser {
    private let stream: TokenStream
    private let interner: StringInterner
    private let diagnostics: DiagnosticEngine
    private let arena: SyntaxArena
    private var lastConsumedToken: Token?

    public init(tokens: [Token], interner: StringInterner, diagnostics: DiagnosticEngine) {
        self.stream = TokenStream(tokens)
        self.interner = interner
        self.diagnostics = diagnostics
        self.arena = SyntaxArena()
    }

    public func parseFile() -> (arena: SyntaxArena, root: NodeID) {
        var children: [SyntaxChild] = []
        var range = RangeAccumulator()
        var sawTopLevelStatement = false
        var sawTopLevelDeclOrHeader = false

        while !stream.atEOF() {
            let token = stream.peek()
            if token.kind == .eof {
                break
            }

            let node: NodeID
            switch token.kind {
            case .keyword(.package):
                node = parsePackageHeader()
                sawTopLevelDeclOrHeader = true
            case .keyword(.import):
                node = parseImportHeader()
                sawTopLevelDeclOrHeader = true
            case .keyword(let keyword) where isDeclarationKeyword(keyword):
                node = parseDeclaration()
                sawTopLevelDeclOrHeader = true
            default:
                node = parseStatement(inBlock: false)
                sawTopLevelStatement = true
            }

            children.append(.node(node))
            range.append(arena.node(node).range)
        }

        let rootKind: SyntaxKind
        if sawTopLevelStatement && !sawTopLevelDeclOrHeader {
            rootKind = .script
        } else {
            rootKind = .kotlinFile
        }

        return (
            arena: arena,
            root: arena.makeNode(
                kind: rootKind,
                range: range.value ?? invalidRange, children)
        )
    }

    private func parseDeclaration() -> NodeID {
        var modifierChildren: [SyntaxChild] = []
        var modifierRange = RangeAccumulator()
        while case .keyword(let keyword) = stream.peek().kind, isDeclarationModifierKeyword(keyword) {
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

    private func parsePackageHeader(leadingChildren: [SyntaxChild] = [], leadingRange: SourceRange? = nil) -> NodeID {
        parseHeaderDeclaration(keyword: .keyword(.package), kind: .packageHeader, allowWildcard: false, leadingChildren: leadingChildren, leadingRange: leadingRange)
    }

    private func parseImportHeader(leadingChildren: [SyntaxChild] = [], leadingRange: SourceRange? = nil) -> NodeID {
        parseHeaderDeclaration(keyword: .keyword(.import), kind: .importHeader, allowWildcard: true, leadingChildren: leadingChildren, leadingRange: leadingRange)
    }

    private func parseHeaderDeclaration(
        keyword: TokenKind,
        kind: SyntaxKind,
        allowWildcard: Bool,
        leadingChildren: [SyntaxChild],
        leadingRange: SourceRange?
    ) -> NodeID {
        var range = RangeAccumulator(value: leadingRange)
        var children: [SyntaxChild] = leadingChildren
        consumeIf(expected: keyword, into: &children, range: &range, code: "KSWIFTK-PARSE-0001")
        parseQualifiedPath(into: &children, range: &range, allowImportWildcard: allowWildcard)
        appendOptionalTerminator(into: &children, range: &range)
        return arena.makeNode(kind: kind, range: range.value ?? invalidRange, children)
    }

    private func parseNamedDeclaration(
        kind: SyntaxKind,
        leadingChildren: [SyntaxChild] = [],
        leadingRange: SourceRange? = nil
    ) -> NodeID {
        var children: [SyntaxChild] = leadingChildren
        var range = RangeAccumulator(value: leadingRange)

        _ = consumeToken(into: &children, range: &range)
        if canStartTypeArgumentsInternal(after: lastConsumedToken) {
            children.append(.node(parseTypeArguments()))
            if let last = children.last {
                range.append(childRange(last))
            }
        }

        if isIdentifierLike(stream.peek().kind) {
            _ = consumeToken(into: &children, range: &range)
        } else {
            diagnoseMissing("KSWIFTK-PARSE-0002", "Expected declaration name.")
        }
        parsePostDeclarationTail(
            into: &children,
            range: &range,
            includeBlock: kind == .classDecl || kind == .interfaceDecl || kind == .objectDecl
        )

        return arena.makeNode(
            kind: kind,
            range: range.value ?? invalidRange, children)
    }

    private func parseFunctionDeclaration(
        leadingChildren: [SyntaxChild] = [],
        leadingRange: SourceRange? = nil
    ) -> NodeID {
        var children: [SyntaxChild] = leadingChildren
        var range = RangeAccumulator(value: leadingRange)

        _ = consumeToken(into: &children, range: &range)
        if canStartTypeArgumentsInternal(after: lastConsumedToken) {
            children.append(.node(parseTypeArguments()))
            if let last = children.last {
                range.append(childRange(last))
            }
        }
        if isIdentifierLike(stream.peek().kind) {
            _ = consumeToken(into: &children, range: &range)
        } else {
            diagnoseMissing("KSWIFTK-PARSE-0002", "Expected function name.")
        }

        if case .symbol(.lParen) = stream.peek().kind {
            children.append(.node(parseBalancedGroup(opening: .lParen, closing: .rParen)))
        }

        if case .symbol(.lBrace) = stream.peek().kind {
            children.append(.node(parseBlock()))
        } else {
            parseTail(inBlock: false, into: &children, range: &range)
        }

        return arena.makeNode(
            kind: .funDecl,
            range: range.value ?? invalidRange, children)
    }

    private func parsePropertyDeclaration(
        leadingChildren: [SyntaxChild] = [],
        leadingRange: SourceRange? = nil
    ) -> NodeID {
        var children: [SyntaxChild] = leadingChildren
        var range = RangeAccumulator(value: leadingRange)

        _ = consumeToken(into: &children, range: &range)
        if isIdentifierLike(stream.peek().kind) {
            _ = consumeToken(into: &children, range: &range)
        } else {
            diagnoseMissing("KSWIFTK-PARSE-0002", "Expected property name.")
        }

        if case .symbol(.lBrace) = stream.peek().kind {
            children.append(.node(parseBlock()))
        } else {
            parseTail(inBlock: false, into: &children, range: &range)
        }

        return arena.makeNode(
            kind: .propertyDecl,
            range: range.value ?? invalidRange, children)
    }

    private func parseTypeAliasDeclaration(
        leadingChildren: [SyntaxChild] = [],
        leadingRange: SourceRange? = nil
    ) -> NodeID {
        var children: [SyntaxChild] = leadingChildren
        var range = RangeAccumulator(value: leadingRange)

        _ = consumeToken(into: &children, range: &range)
        if isIdentifierLike(stream.peek().kind) {
            _ = consumeToken(into: &children, range: &range)
        } else {
            diagnoseMissing("KSWIFTK-PARSE-0002", "Expected typealias name.")
        }
        parseTail(inBlock: false, into: &children, range: &range)

        return arena.makeNode(
            kind: .typeAliasDecl,
            range: range.value ?? invalidRange, children)
    }

    private func parseEnumDeclaration(
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
            diagnoseMissing("KSWIFTK-PARSE-0002", "Expected enum name.")
        }

        if case .symbol(.lBrace) = stream.peek().kind {
            children.append(.node(parseEnumBody()))
        } else {
            parseTail(inBlock: false, into: &children, range: &range)
        }

        return arena.makeNode(
            kind: .classDecl,
            range: range.value ?? invalidRange, children)
    }

    private func parseEnumBody() -> NodeID {
        var children: [SyntaxChild] = []
        var range = RangeAccumulator()
        guard consumeIfSymbol(.lBrace, into: &children, range: &range) else {
            return arena.makeNode(kind: .block, range: range.value ?? invalidRange, children)
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

        return arena.makeNode(kind: .block, range: range.value ?? invalidRange, children)
    }

    private func parseEnumEntryDeclaration() -> NodeID {
        var children: [SyntaxChild] = []
        var range = RangeAccumulator()

        if isIdentifierLike(stream.peek().kind) {
            _ = consumeToken(into: &children, range: &range)
        }
        if case .symbol(.lParen) = stream.peek().kind {
            children.append(.node(parseBalancedGroup(opening: .lParen, closing: .rParen)))
        }
        parseTail(inBlock: true, into: &children, range: &range)

        return arena.makeNode(
            kind: .enumEntry,
            range: range.value ?? invalidRange, children)
    }

    private func parsePostDeclarationTail(into children: inout [SyntaxChild], range: inout RangeAccumulator, includeBlock: Bool) {
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

    private func parseBlock() -> NodeID {
        var children: [SyntaxChild] = []
        var range = RangeAccumulator()
        guard consumeIfSymbol(.lBrace, into: &children, range: &range) else {
            return arena.makeNode(kind: .block, range: range.value ?? invalidRange, children)
        }

        while !stream.atEOF() {
            let token = stream.peek()
            if case .symbol(.rBrace) = token.kind {
                _ = consumeToken(into: &children, range: &range)
                break
            }
            if isDeclarationStart(token.kind) && hasLeadingNewline(token) {
                children.append(.node(parseDeclaration()))
            } else if parseStatementTail(inBlock: true) == .canContinue {
                children.append(.node(parseStatement(inBlock: true)))
            } else {
                _ = consumeToken(into: &children, range: &range)
            }
        }

        return arena.makeNode(kind: .block, range: range.value ?? invalidRange, children)
    }

    private func parseStatement(inBlock: Bool) -> NodeID {
        let startCount = stream.index
        var children: [SyntaxChild] = []
        var range = RangeAccumulator()

        while !stream.atEOF() {
            let token = stream.peek()
            if shouldStopStatementBefore(token, inBlock: inBlock) {
                break
            }
            if case .symbol(.lBrace) = token.kind, inBlock {
                children.append(.node(parseBlock()))
                continue
            }

            _ = consumeToken(into: &children, range: &range)
            if case .symbol(.semicolon) = token.kind {
                break
            }
            if !inBlock, hasLeadingNewline(stream.peek()) {
                break
            }
        }

        if stream.index == startCount, !shouldStopStatementBefore(stream.peek(), inBlock: inBlock) {
            _ = consumeToken(into: &children, range: &range)
        }

        return arena.makeNode(
            kind: .statement,
            range: range.value ?? invalidRange, children)
    }

    private enum StatementTailStatus {
        case noProgress
        case canContinue
    }

    private func parseStatementTail(inBlock: Bool) -> StatementTailStatus {
        let token = stream.peek()
        if shouldStopStatementBefore(token, inBlock: inBlock) {
            return .noProgress
        }
        if case .symbol(.semicolon) = token.kind {
            return .canContinue
        }
        return .canContinue
    }

    private func parseTail(inBlock: Bool, into children: inout [SyntaxChild], range: inout RangeAccumulator) {
        var progress = false
        while !stream.atEOF() {
            let token = stream.peek()
            if shouldStopStatementBefore(token, inBlock: inBlock) {
                break
            }
            if case .symbol(.lBrace) = token.kind, inBlock {
                children.append(.node(parseBlock()))
                progress = true
                continue
            }
            if case .symbol(.lBrace) = token.kind {
                children.append(.node(parseBlock()))
                break
            }
            _ = consumeToken(into: &children, range: &range)
            progress = true
            if case .symbol(.semicolon) = token.kind {
                break
            }
            if !inBlock, hasLeadingNewline(stream.peek()) {
                break
            }
        }
        if !progress, !shouldStopStatementBefore(stream.peek(), inBlock: inBlock) {
            _ = consumeToken(into: &children, range: &range)
        }
    }

    private func parseBalancedGroup(opening: Symbol, closing: Symbol) -> NodeID {
        var children: [SyntaxChild] = []
        var range = RangeAccumulator()

        guard consumeIfSymbol(opening, into: &children, range: &range) else {
            return arena.makeNode(kind: .statement, range: invalidRange, [])
        }

        var depth = 1
        while !stream.atEOF() && depth > 0 {
            let token = stream.peek()
            if case .symbol(let symbol) = token.kind, symbol == closing && depth == 1 {
                _ = consumeToken(into: &children, range: &range)
                return arena.makeNode(kind: .statement, range: range.value ?? invalidRange, children)
            }
            if depth == 1 && hasLeadingNewline(token) && isLikelyTopLevelDeclarationStart(token) {
                break
            }

            _ = consumeToken(into: &children, range: &range)
            if case .symbol(opening) = token.kind {
                depth += 1
            } else if case .symbol(closing) = token.kind {
                depth -= 1
            }
        }

        diagnostics.warning(
            "KSWIFTK-PARSE-0004",
            "Unterminated '\(opening.rawValue)' group.",
            range: stream.peek().rangeIfAvailable
        )
        return arena.makeNode(kind: .statement, range: range.value ?? invalidRange, children)
    }

    private func parseQualifiedPath(into children: inout [SyntaxChild], range: inout RangeAccumulator, allowImportWildcard: Bool) {
        var consumed = false
        while !stream.atEOF() {
            let token = stream.peek()
            if shouldStopStatementBefore(token, inBlock: false) {
                break
            }
            if case .symbol(.dot) = token.kind {
                _ = consumeToken(into: &children, range: &range)
                consumed = true
                continue
            }
            if isIdentifierLike(token.kind) {
                _ = consumeToken(into: &children, range: &range)
                consumed = true
                continue
            }
            if allowImportWildcard, case .symbol(.star) = token.kind {
                _ = consumeToken(into: &children, range: &range)
                consumed = true
                continue
            }
            if hasLeadingNewline(token) && consumed {
                break
            }
            break
        }
        if !consumed {
            diagnoseMissing("KSWIFTK-PARSE-0003", "Expected name in package/import path.")
        }
    }

    private func consumeIf(expected: TokenKind, into children: inout [SyntaxChild], range: inout RangeAccumulator, code: String) {
        if stream.peek().kind == expected {
            _ = consumeToken(into: &children, range: &range)
            return
        }
        diagnostics.warning(code, "Expected \(expected).", range: stream.peek().rangeIfAvailable)
    }

    private func consumeIfSymbol(_ symbol: Symbol, into children: inout [SyntaxChild], range: inout RangeAccumulator) -> Bool {
        if case .symbol(symbol) = stream.peek().kind {
            _ = consumeToken(into: &children, range: &range)
            return true
        }
        return false
    }

    private func consumeToken(into children: inout [SyntaxChild], range: inout RangeAccumulator) -> Token {
        let token = stream.advance()
        let tokenID = arena.appendToken(token)
        let child: SyntaxChild = .token(tokenID)
        children.append(child)
        range.append(token.range)
        if token.kind != .eof {
            lastConsumedToken = token
        }
        return token
    }

    private func childRange(_ child: SyntaxChild) -> SourceRange {
        switch child {
        case .token(let tokenID):
            let index = Int(tokenID.rawValue)
            guard index >= 0 && index < arena.tokens.count else { return invalidRange }
            return arena.tokens[index].range
        case .node(let nodeID):
            return arena.node(nodeID).range
        }
    }

    private func shouldStopStatementBefore(_ token: Token, inBlock: Bool) -> Bool {
        if token.kind == .eof {
            return true
        }
        switch token.kind {
        case .symbol(.rBrace):
            return true
        case .keyword(.else), .keyword(.catch), .keyword(.finally):
            return inBlock
        case .keyword(.class), .keyword(.object), .keyword(.interface), .keyword(.fun),
             .keyword(.val), .keyword(.var), .keyword(.typealias), .keyword(.enum),
             .keyword(.package), .keyword(.import):
            return !inBlock && hasLeadingNewline(token)
        default:
            return false
        }
    }

    private func isDeclarationModifierKeyword(_ keyword: Keyword) -> Bool {
        switch keyword {
        case .public, .private, .internal, .protected, .open, .abstract, .sealed, .data, .annotation,
             .inner, .expect, .actual, .const, .lateinit, .override, .final, .crossinline, .noinline, .tailrec,
             .inline, .suspend, .operator, .infix, .external, .value:
            return true
        default:
            return false
        }
    }

    private func isDeclarationKeyword(_ keyword: Keyword) -> Bool {
        if isDeclarationModifierKeyword(keyword) {
            return true
        }
        switch keyword {
        case .class, .object, .interface, .fun, .val, .var, .typealias, .enum, .package, .import, .companion:
            return true
        default:
            return false
        }
    }

    private func isDeclarationStart(_ kind: TokenKind) -> Bool {
        if case .keyword(let keyword) = kind, isDeclarationKeyword(keyword) {
            return true
        }
        return false
    }

    private func isIdentifierLike(_ kind: TokenKind) -> Bool {
        switch kind {
        case .identifier, .backtickedIdentifier, .keyword, .softKeyword:
            return true
        default:
            return false
        }
    }

    private func hasLeadingNewline(_ token: Token) -> Bool {
        return token.leadingTrivia.contains(.newline)
    }

    private func appendOptionalTerminator(into children: inout [SyntaxChild], range: inout RangeAccumulator) {
        if !stream.atEOF(), case .symbol(.semicolon) = stream.peek().kind {
            _ = consumeToken(into: &children, range: &range)
        }
    }

    private func diagnoseMissing(_ code: String, _ message: String) {
        diagnostics.warning(code, message, range: stream.peek().rangeIfAvailable)
    }

    private func parseTypeArguments() -> NodeID {
        var children: [SyntaxChild] = []
        var range = RangeAccumulator()
        var depth = 1

        guard consumeIfSymbol(.lessThan, into: &children, range: &range) else {
            return arena.makeNode(
                kind: .typeArgs,
                range: range.value ?? invalidRange,
                []
            )
        }

        while !stream.atEOF() && depth > 0 {
            let next = stream.peek()
            if depth == 1 && hasLeadingNewline(next) && isLikelyTopLevelDeclarationStart(next) {
                break
            }

            let token = consumeToken(into: &children, range: &range)
            if token.kind == .eof {
                break
            }

            switch token.kind {
            case .symbol(.lessThan):
                depth += 1
            case .symbol(.greaterThan):
                depth -= 1
                if depth == 0 {
                    return arena.makeNode(kind: .typeArgs, range: range.value ?? invalidRange, children)
                }
            default:
                break
            }
        }

        diagnostics.warning(
            "KSWIFTK-PARSE-0005",
            "Unterminated '<' type argument list.",
            range: stream.peek().rangeIfAvailable
        )
        return arena.makeNode(
            kind: .typeArgs,
            range: range.value ?? invalidRange,
            children
        )
    }

    private func canStartTypeArgumentsInternal(after token: Token?) -> Bool {
        guard token != nil else { return false }
        guard case .symbol(.lessThan) = stream.peek().kind else { return false }

        var depth = 1
        var projectionExpected = true
        var sawProjection = false

        for lookahead in 1...32 {
            let token = stream.peek(lookahead)
            switch token.kind {
            case .eof:
                return depth == 1 && sawProjection && !projectionExpected
            case .symbol(.lessThan):
                depth += 1
            case .symbol(.greaterThan):
                depth -= 1
                if depth == 0 {
                    if projectionExpected { return false }
                    return followsTypeArgs(stream.peek(lookahead + 1))
                }
            case .symbol(.comma):
                if depth == 1 {
                    if !sawProjection { return false }
                    projectionExpected = true
                }
            case .identifier, .backtickedIdentifier:
                if depth == 1 {
                    sawProjection = true
                    projectionExpected = false
                } else { return false }
            case .symbol(.star):
                if depth == 1 {
                    sawProjection = true
                    projectionExpected = false
                } else { return false }
            case .keyword(.in), .softKeyword(.out):
                if depth == 1 && projectionExpected {
                    break
                }
                if depth == 1 {
                    projectionExpected = true
                } else if depth < 1 {
                    return false
                }
            case .symbol(.dot), .symbol(.question), .symbol(.questionDot),
                 .symbol(.doubleColon), .symbol(.colon):
                if depth == 1 && projectionExpected {
                    return false
                }
            default:
                if depth == 0 {
                    return false
                }
            }
        }

        return false
    }

    private func followsTypeArgs(_ token: Token) -> Bool {
        switch token.kind {
        case .symbol(.lParen), .symbol(.dot), .symbol(.questionDot), .symbol(.bangBang),
             .symbol(.doubleColon), .symbol(.lessThan), .symbol(.colon), .symbol(.comma),
             .symbol(.lBrace), .symbol(.rParen), .symbol(.rBrace), .symbol(.question),
             .symbol(.assign):
            return true
        case .identifier, .backtickedIdentifier, .keyword, .softKeyword:
            return true
        case .eof:
            return true
        default:
            return false
        }
    }

    public func canStartTypeArguments(after token: Token) -> Bool {
        return canStartTypeArgumentsInternal(after: token)
    }

    public func canStartTypeArguments(after node: NodeID) -> Bool {
        guard Int(node.rawValue) >= 0 && Int(node.rawValue) < arena.nodes.count else { return false }
        let nodeKind = arena.node(node).kind
        if case .typeArgs = nodeKind {
            return false
        }
        return canStartTypeArgumentsInternal(after: lastConsumedToken)
    }

    private func isLikelyTopLevelDeclarationStart(_ token: Token) -> Bool {
        if isDeclarationStart(token.kind) {
            return true
        }
        if case .keyword(let keyword) = token.kind {
            return isDeclarationModifierKeyword(keyword) || keyword == .companion
        }
        return false
    }

    private var invalidRange: SourceRange {
        SourceRange(
            start: SourceLocation(file: FileID.invalid, offset: 0),
            end: SourceLocation(file: FileID.invalid, offset: 0)
        )
    }
}

private extension Token {
    var rangeIfAvailable: SourceRange {
        return range
    }
}

private struct RangeAccumulator {
    var value: SourceRange?

    mutating func append(_ range: SourceRange) {
        if let current = value {
            value = SourceRange(start: current.start, end: range.end)
        } else {
            value = range
        }
    }
}

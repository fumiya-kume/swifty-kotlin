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
        var sawNonPropertyDecl = false

        var pendingImports: [SyntaxChild] = []
        var importRange = RangeAccumulator()

        while !stream.atEOF() {
            let token = stream.peek()
            if token.kind == .eof {
                break
            }

            var node: NodeID
            switch token.kind {
            case .keyword(.package):
                node = parsePackageHeader()
            case .keyword(.import):
                node = parseImportHeader()
                pendingImports.append(.node(node))
                importRange.append(arena.node(node).range)
                range.append(arena.node(node).range)
                continue
            case .keyword(let keyword) where isDeclarationKeyword(keyword):
                node = parseDeclaration()
                if arena.node(node).kind != .propertyDecl {
                    sawNonPropertyDecl = true
                }
            default:
                let before = stream.index
                node = parseStatement(inBlock: false)
                if stream.index == before {
                    var skipChildren: [SyntaxChild] = []
                    var skipRange = RangeAccumulator()
                    skipToSynchronizationPoint(inBlock: false, into: &skipChildren, range: &skipRange)
                    if stream.index == before, !stream.atEOF() {
                        _ = consumeToken(into: &skipChildren, range: &skipRange)
                    }
                    node = arena.appendNode(kind: .statement, range: skipRange.value ?? invalidRange, skipChildren)
                }
                sawTopLevelStatement = true
            }

            if !pendingImports.isEmpty {
                let importListNode = arena.appendNode(
                    kind: .importList,
                    range: importRange.value ?? invalidRange,
                    pendingImports
                )
                children.append(.node(importListNode))
                pendingImports.removeAll(keepingCapacity: true)
                importRange = RangeAccumulator()
            }

            children.append(.node(node))
            range.append(arena.node(node).range)
        }

        if !pendingImports.isEmpty {
            let importListNode = arena.appendNode(
                kind: .importList,
                range: importRange.value ?? invalidRange,
                pendingImports
            )
            children.append(.node(importListNode))
        }

        let rootKind: SyntaxKind
        if sawTopLevelStatement && !sawNonPropertyDecl {
            rootKind = .script
        } else {
            rootKind = .kotlinFile
        }

        return (
            arena: arena,
            root: arena.appendNode(
                kind: rootKind,
                range: range.value ?? invalidRange, children)
        )
    }

    private func parseDeclaration() -> NodeID {
        var modifierChildren: [SyntaxChild] = []
        var modifierRange = RangeAccumulator()
        while case .keyword(let keyword) = stream.peek().kind, Self.isDeclarationModifierKeyword(keyword) {
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
        return arena.appendNode(kind: kind, range: range.value ?? invalidRange, children)
    }

    private func parseNamedDeclaration(
        kind: SyntaxKind,
        leadingChildren: [SyntaxChild] = [],
        leadingRange: SourceRange? = nil
    ) -> NodeID {
        var children: [SyntaxChild] = leadingChildren
        var range = RangeAccumulator(value: leadingRange)
        let supportsTypeParameters = kind == .classDecl || kind == .interfaceDecl

        _ = consumeToken(into: &children, range: &range)
        if isIdentifierLike(stream.peek().kind) {
            _ = consumeToken(into: &children, range: &range)
        } else {
            insertMissingToken(expected: .identifier(.invalid), into: &children, range: &range, code: "KSWIFTK-PARSE-0002", message: "Expected declaration name.")
        }
        if supportsTypeParameters && canStartTypeArgumentsInternal(after: lastConsumedToken) {
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
            insertMissingToken(expected: .identifier(.invalid), into: &children, range: &range, code: "KSWIFTK-PARSE-0002", message: "Expected property name.")
        }

        if case .symbol(.lBrace) = stream.peek().kind {
            children.append(.node(parseBlock()))
        } else {
            parseTail(inBlock: false, into: &children, range: &range)
        }

        return arena.appendNode(
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
            insertMissingToken(expected: .identifier(.invalid), into: &children, range: &range, code: "KSWIFTK-PARSE-0002", message: "Expected typealias name.")
        }
        parseTail(inBlock: false, into: &children, range: &range)

        return arena.appendNode(
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
            insertMissingToken(expected: .identifier(.invalid), into: &children, range: &range, code: "KSWIFTK-PARSE-0002", message: "Expected enum name.")
        }

        if case .symbol(.lBrace) = stream.peek().kind {
            children.append(.node(parseEnumBody()))
        } else {
            parseTail(inBlock: false, into: &children, range: &range)
        }

        return arena.appendNode(
            kind: .classDecl,
            range: range.value ?? invalidRange, children)
    }

    private func parseEnumBody() -> NodeID {
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

        return arena.appendNode(
            kind: .enumEntry,
            range: range.value ?? invalidRange, children)
    }

    private func parseConstructorDeclaration() -> NodeID {
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
            return arena.appendNode(kind: .block, range: range.value ?? invalidRange, children)
        }

        while !stream.atEOF() {
            let token = stream.peek()
            if case .symbol(.rBrace) = token.kind {
                _ = consumeToken(into: &children, range: &range)
                break
            }
            if case .keyword(.constructor) = token.kind {
                children.append(.node(parseConstructorDeclaration()))
                continue
            }
            if case .softKeyword(.constructor) = token.kind {
                children.append(.node(parseConstructorDeclaration()))
                continue
            }
            if isDeclarationStart(token.kind) && hasLeadingNewline(token) {
                children.append(.node(parseDeclaration()))
            } else if parseStatementTail(inBlock: true) == .canContinue {
                children.append(.node(parseStatement(inBlock: true)))
            } else {
                let before = stream.index
                skipToSynchronizationPoint(inBlock: true, into: &children, range: &range)
                if stream.index == before, !stream.atEOF() {
                    _ = consumeToken(into: &children, range: &range)
                }
            }
        }

        return arena.appendNode(kind: .block, range: range.value ?? invalidRange, children)
    }

    private func parseStatement(inBlock: Bool) -> NodeID {
        if isLoopStart(stream.peek().kind) {
            return parseLoopStatement(inBlock: inBlock)
        }

        let leadingKind = classifyStatementLeadingToken(stream.peek())

        let startCount = stream.index
        var children: [SyntaxChild] = []
        var range = RangeAccumulator()
        var parenDepth = 0
        var bracketDepth = 0

        while !stream.atEOF() {
            let token = stream.peek()
            if inBlock,
               !children.isEmpty,
               parenDepth == 0,
               bracketDepth == 0,
               hasLeadingNewline(token),
               shouldSplitStatementOnNewline(token.kind) {
                break
            }
            if shouldStopStatementBefore(token, inBlock: inBlock) {
                break
            }
            if case .symbol(.lBrace) = token.kind, inBlock {
                children.append(.node(parseBlock()))
                continue
            }

            _ = consumeToken(into: &children, range: &range)
            switch token.kind {
            case .symbol(.lParen):
                parenDepth += 1
            case .symbol(.rParen):
                parenDepth = max(0, parenDepth - 1)
            case .symbol(.lBracket):
                bracketDepth += 1
            case .symbol(.rBracket):
                bracketDepth = max(0, bracketDepth - 1)
            default:
                break
            }
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

        let nodeKind = resolveStatementKind(leadingKind, children: children)

        return arena.appendNode(
            kind: nodeKind,
            range: range.value ?? invalidRange, children)
    }

    private func classifyStatementLeadingToken(_ token: Token) -> SyntaxKind {
        switch token.kind {
        case .keyword(.if):
            return .ifExpr
        case .keyword(.when):
            return .whenExpr
        case .keyword(.try):
            return .tryExpr
        case .identifier, .backtickedIdentifier:
            return .callExpr
        case .softKeyword:
            return .callExpr
        default:
            return .statement
        }
    }

    private func resolveStatementKind(_ candidate: SyntaxKind, children: [SyntaxChild]) -> SyntaxKind {
        switch candidate {
        case .ifExpr, .whenExpr, .tryExpr:
            return candidate
        case .callExpr:
            for child in children {
                if case .node(let childID) = child,
                   arena.node(childID).kind == .block {
                    return .callExpr
                }
                if case .token(let tokenID) = child {
                    let index = Int(tokenID.rawValue)
                    if index >= 0 && index < arena.tokens.count {
                        let token = arena.tokens[index]
                        if token.kind == .symbol(.lParen) {
                            return .callExpr
                        }
                    }
                }
            }
            return .statement
        default:
            return .statement
        }
    }

    private func parseLoopStatement(inBlock: Bool) -> NodeID {
        _ = inBlock
        var children: [SyntaxChild] = []
        var range = RangeAccumulator()

        let loopToken = consumeToken(into: &children, range: &range)

        switch loopToken.kind {
        case .keyword(.for), .keyword(.while):
            if case .symbol(.lParen) = stream.peek().kind {
                let header = parseBalancedGroup(opening: .lParen, closing: .rParen)
                children.append(.node(header))
                range.append(arena.node(header).range)
            }
            appendLoopBody(into: &children, range: &range)

        case .keyword(.do):
            appendLoopBody(into: &children, range: &range)
            if case .keyword(.while) = stream.peek().kind {
                _ = consumeToken(into: &children, range: &range)
                if case .symbol(.lParen) = stream.peek().kind {
                    let condition = parseBalancedGroup(opening: .lParen, closing: .rParen)
                    children.append(.node(condition))
                    range.append(arena.node(condition).range)
                }
            }

        default:
            break
        }

        return arena.appendNode(kind: .loopStmt, range: range.value ?? invalidRange, children)
    }

    private func appendLoopBody(into children: inout [SyntaxChild], range: inout RangeAccumulator) {
        if case .symbol(.lBrace) = stream.peek().kind {
            let block = parseBlock()
            children.append(.node(block))
            range.append(arena.node(block).range)
            return
        }
        let before = stream.index
        let body = parseStatement(inBlock: true)
        children.append(.node(body))
        range.append(arena.node(body).range)
        if stream.index == before, !stream.atEOF() {
            _ = consumeToken(into: &children, range: &range)
        }
    }

    private func shouldSplitStatementOnNewline(_ kind: TokenKind) -> Bool {
        switch kind {
        case .symbol(.dot), .symbol(.comma), .symbol(.questionDot), .symbol(.questionQuestion),
             .symbol(.plus), .symbol(.minus), .symbol(.star), .symbol(.slash),
             .symbol(.equalEqual), .symbol(.assign), .symbol(.arrow),
             .symbol(.rParen), .symbol(.rBracket), .symbol(.rBrace):
            return false
        default:
            return true
        }
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
            return arena.appendNode(kind: .statement, range: invalidRange, [])
        }

        var depth = 1
        while !stream.atEOF() && depth > 0 {
            let token = stream.peek()
            if case .symbol(let symbol) = token.kind, symbol == closing && depth == 1 {
                _ = consumeToken(into: &children, range: &range)
                return arena.appendNode(kind: .statement, range: range.value ?? invalidRange, children)
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
        return arena.appendNode(kind: .statement, range: range.value ?? invalidRange, children)
    }

    private func parseQualifiedPath(into children: inout [SyntaxChild], range: inout RangeAccumulator, allowImportWildcard: Bool) {
        var consumed = false
        while !stream.atEOF() {
            let token = stream.peek()
            if shouldStopStatementBefore(token, inBlock: false) {
                break
            }
            // Package/import paths must not consume declaration starts on the next line.
            if consumed && hasLeadingNewline(token) {
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
            break
        }
        if !consumed {
            insertMissingToken(expected: .identifier(.invalid), into: &children, range: &range, code: "KSWIFTK-PARSE-0003", message: "Expected name in package/import path.")
        }
    }

    private func consumeIf(expected: TokenKind, into children: inout [SyntaxChild], range: inout RangeAccumulator, code: String) {
        if stream.peek().kind == expected {
            _ = consumeToken(into: &children, range: &range)
            return
        }
        insertMissingToken(expected: expected, into: &children, range: &range, code: code, message: "Expected \(expected).")
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
        case .keyword(.class), .keyword(.object), .keyword(.interface), .keyword(.fun),
             .keyword(.val), .keyword(.var), .keyword(.typealias), .keyword(.enum),
             .keyword(.package), .keyword(.import):
            return !inBlock && hasLeadingNewline(token)
        default:
            return false
        }
    }

    static func isDeclarationModifierKeyword(_ keyword: Keyword) -> Bool {
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
        if Self.isDeclarationModifierKeyword(keyword) {
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

    private func isLoopStart(_ kind: TokenKind) -> Bool {
        switch kind {
        case .keyword(.for), .keyword(.while), .keyword(.do):
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

    private func zeroWidthRange(at token: Token) -> SourceRange {
        let loc = token.range.start
        return SourceRange(start: loc, end: loc)
    }

    private func insertMissingToken(
        expected: TokenKind,
        into children: inout [SyntaxChild],
        range: inout RangeAccumulator,
        code: String,
        message: String
    ) {
        let missingRange = zeroWidthRange(at: stream.peek())
        diagnostics.warning(code, message, range: missingRange)
        let missingToken = Token(kind: .missing(expected: expected), range: missingRange)
        let tokenID = arena.appendToken(missingToken)
        children.append(.token(tokenID))
        range.append(missingRange)
    }

    private func isSynchronizationPoint(_ token: Token, inBlock: Bool) -> Bool {
        switch token.kind {
        case .eof:
            return true
        case .symbol(.rBrace):
            return true
        case .keyword(.class), .keyword(.fun), .keyword(.val), .keyword(.var),
             .keyword(.object), .keyword(.interface), .keyword(.typealias),
             .keyword(.import), .keyword(.package):
            return true
        default:
            break
        }
        if inBlock {
            switch token.kind {
            case .symbol(.semicolon):
                return true
            case .keyword(.catch), .keyword(.finally), .keyword(.else):
                return true
            default:
                if hasLeadingNewline(token) {
                    return true
                }
            }
        }
        return false
    }

    private func skipToSynchronizationPoint(
        inBlock: Bool,
        into children: inout [SyntaxChild],
        range: inout RangeAccumulator
    ) {
        let skippedStart = stream.peek().range
        var skippedCount = 0
        while !stream.atEOF() {
            let token = stream.peek()
            if isSynchronizationPoint(token, inBlock: inBlock) {
                break
            }
            _ = consumeToken(into: &children, range: &range)
            skippedCount += 1
        }
        if skippedCount > 0 {
            diagnostics.error(
                "KSWIFTK-PARSE-0006",
                "Skipped \(skippedCount) unexpected token(s).",
                range: skippedStart
            )
        }
    }

    private func parseTypeArguments() -> NodeID {
        var children: [SyntaxChild] = []
        var range = RangeAccumulator()
        var depth = 1

        guard consumeIfSymbol(.lessThan, into: &children, range: &range) else {
            return arena.appendNode(
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
                    return arena.appendNode(kind: .typeArgs, range: range.value ?? invalidRange, children)
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
        return arena.appendNode(
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
            return Self.isDeclarationModifierKeyword(keyword) || keyword == .companion
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

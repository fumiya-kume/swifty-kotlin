public final class KotlinParser {
    internal let stream: TokenStream
    internal let interner: StringInterner
    internal let diagnostics: DiagnosticEngine
    internal let arena: SyntaxArena
    internal var lastConsumedToken: Token?

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
        func flushPendingImportsIfNeeded() {
            guard !pendingImports.isEmpty else {
                return
            }
            let importListNode = arena.appendNode(
                kind: .importList,
                range: importRange.value ?? invalidRange,
                pendingImports
            )
            children.append(.node(importListNode))
            pendingImports.removeAll(keepingCapacity: true)
            importRange = RangeAccumulator()
        }

        while !stream.atEOF() {
            let token = stream.peek()
            if token.kind == .eof {
                break
            }

            var node: NodeID
            switch token.kind {
            case .keyword(.package):
                node = parsePackageHeader()
                sawNonPropertyDecl = true
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

            flushPendingImportsIfNeeded()

            children.append(.node(node))
            range.append(arena.node(node).range)
        }

        flushPendingImportsIfNeeded()

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
}

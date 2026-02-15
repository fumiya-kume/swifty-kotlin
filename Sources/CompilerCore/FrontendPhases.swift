import Foundation

public final class LoadSourcesPhase: CompilerPhase {
    public static let name = "LoadSources"

    public init() {}

    public func run(_ ctx: CompilationContext) throws {
        if ctx.options.inputs.isEmpty {
            ctx.diagnostics.error(
                "KSWIFTK-SOURCE-0001",
                "No input files were specified.",
                range: nil
            )
            throw CompilerPipelineError.loadError
        }

        for path in ctx.options.inputs {
            do {
                _ = try ctx.sourceManager.addFile(path: path)
            } catch {
                ctx.diagnostics.error(
                    "KSWIFTK-SOURCE-0002",
                    "Cannot read input file: \(path)",
                    range: nil
                )
                throw CompilerPipelineError.loadError
            }
        }
    }
}

public final class LexPhase: CompilerPhase {
    public static let name = "Lex"

    public init() {}

    public func run(_ ctx: CompilationContext) throws {
        var tokens: [Token] = []
        for fileID in ctx.sourceManager.fileIDs().sorted(by: { $0.rawValue < $1.rawValue }) {
            let contents = ctx.sourceManager.contents(of: fileID)
            let lexer = KotlinLexer(
                file: fileID,
                source: contents,
                interner: ctx.interner,
                diagnostics: ctx.diagnostics
            )
            let fileTokens = lexer.lexAll()
            if let last = fileTokens.last, case .eof = last.kind {
                tokens.append(contentsOf: fileTokens.dropLast())
            } else {
                tokens.append(contentsOf: fileTokens)
            }
        }
        ctx.tokens = tokens
    }
}

public final class ParsePhase: CompilerPhase {
    public static let name = "Parse"

    public init() {}

    public func run(_ ctx: CompilationContext) throws {
        let parser = KotlinParser(
            tokens: ctx.tokens,
            interner: ctx.interner,
            diagnostics: ctx.diagnostics
        )
        let parsed = parser.parseFile()
        ctx.cst = parsed.arena
        ctx.cstRoot = parsed.root
    }
}

public final class BuildASTPhase: CompilerPhase {
    public static let name = "BuildAST"

    public init() {}

    public func run(_ ctx: CompilationContext) throws {
        guard let cst = ctx.cst else {
            throw CompilerPipelineError.invalidInput("Parse phase did not run.")
        }

        let arena = ASTArena()
        var declarations: [DeclID] = []
        var packageByFile: [Int32: [InternedString]] = [:]
        var importsByFile: [Int32: [ImportDecl]] = [:]
        var declarationsByFile: [Int32: [DeclID]] = [:]

        for child in cst.children(of: ctx.cstRoot) {
            guard case .node(let nodeID) = child else {
                continue
            }
            let node = cst.node(nodeID)
            let fileRawID = node.range.start.file.rawValue

            switch node.kind {
            case .packageHeader:
                packageByFile[fileRawID] = extractQualifiedPath(from: nodeID, in: cst, interner: ctx.interner, isPackageHeader: true)

            case .importHeader:
                let path = extractQualifiedPath(from: nodeID, in: cst, interner: ctx.interner, isPackageHeader: false)
                importsByFile[fileRawID, default: []].append(ImportDecl(range: node.range, path: path))

            case .classDecl:
                let id = arena.appendDecl(.classDecl(makeClassDecl(from: nodeID, in: cst, interner: ctx.interner)))
                declarations.append(id)
                declarationsByFile[fileRawID, default: []].append(id)

            case .objectDecl:
                let id = arena.appendDecl(.objectDecl(makeObjectDecl(from: nodeID, in: cst, interner: ctx.interner)))
                declarations.append(id)
                declarationsByFile[fileRawID, default: []].append(id)

            case .interfaceDecl:
                let id = arena.appendDecl(.classDecl(makeClassDecl(from: nodeID, in: cst, interner: ctx.interner)))
                declarations.append(id)
                declarationsByFile[fileRawID, default: []].append(id)

            case .funDecl:
                let id = arena.appendDecl(.funDecl(makeFunDecl(from: nodeID, in: cst, interner: ctx.interner)))
                declarations.append(id)
                declarationsByFile[fileRawID, default: []].append(id)

            case .propertyDecl:
                let id = arena.appendDecl(.propertyDecl(makePropertyDecl(from: nodeID, in: cst, interner: ctx.interner)))
                declarations.append(id)
                declarationsByFile[fileRawID, default: []].append(id)

            case .typeAliasDecl:
                let id = arena.appendDecl(.typeAliasDecl(makeTypeAliasDecl(from: nodeID, in: cst, interner: ctx.interner)))
                declarations.append(id)
                declarationsByFile[fileRawID, default: []].append(id)

            case .enumEntry:
                let id = arena.appendDecl(.enumEntry(makeEnumEntryDecl(from: nodeID, in: cst, interner: ctx.interner)))
                declarations.append(id)
                declarationsByFile[fileRawID, default: []].append(id)

            default:
                continue
            }
        }

        let tokenFileIDs = Set(ctx.tokens.map { $0.range.start.file.rawValue })
        let fileIDs = tokenFileIDs.filter { $0 != invalidID }.sorted()
        let files: [ASTFile] = fileIDs.map { rawID in
            ASTFile(
                fileID: FileID(rawValue: rawID),
                packageFQName: packageByFile[rawID] ?? [],
                imports: importsByFile[rawID] ?? [],
                topLevelDecls: declarationsByFile[rawID] ?? []
            )
        }

        ctx.ast = ASTModule(files: files, arena: arena, declarationCount: declarations.count, tokenCount: ctx.tokens.count)
    }

    private func makeClassDecl(from nodeID: NodeID, in arena: SyntaxArena, interner: StringInterner) -> ClassDecl {
        let node = arena.node(nodeID)
        return ClassDecl(
            range: node.range,
            name: declarationName(from: nodeID, in: arena, interner: interner),
            modifiers: declarationModifiers(from: nodeID, in: arena),
            typeParams: declarationTypeParameters(from: nodeID, in: arena, interner: interner),
            primaryConstructorParams: declarationValueParameters(from: nodeID, in: arena, interner: interner)
        )
    }

    private func makeObjectDecl(from nodeID: NodeID, in arena: SyntaxArena, interner: StringInterner) -> ObjectDecl {
        let node = arena.node(nodeID)
        let modifiers = declarationModifiers(from: nodeID, in: arena)
        return ObjectDecl(
            range: node.range,
            name: declarationName(from: nodeID, in: arena, interner: interner),
            modifiers: modifiers
        )
    }

    private func makeFunDecl(from nodeID: NodeID, in arena: SyntaxArena, interner: StringInterner) -> FunDecl {
        let node = arena.node(nodeID)
        let modifiers = declarationModifiers(from: nodeID, in: arena)
        let isSuspend = modifiers.contains(.suspend)
        let isInline = modifiers.contains(.inline)
        let valueParams = declarationValueParameters(from: nodeID, in: arena, interner: interner)
        let body = declarationBody(from: nodeID, in: arena)
        return FunDecl(
            range: node.range,
            name: declarationName(from: nodeID, in: arena, interner: interner),
            modifiers: modifiers,
            typeParams: declarationTypeParameters(from: nodeID, in: arena, interner: interner),
            receiverType: nil,
            valueParams: valueParams,
            returnType: nil,
            body: body,
            isSuspend: isSuspend,
            isInline: isInline
        )
    }

    private func makePropertyDecl(from nodeID: NodeID, in arena: SyntaxArena, interner: StringInterner) -> PropertyDecl {
        let node = arena.node(nodeID)
        return PropertyDecl(
            range: node.range,
            name: declarationName(from: nodeID, in: arena, interner: interner),
            modifiers: declarationModifiers(from: nodeID, in: arena),
            type: nil
        )
    }

    private func makeTypeAliasDecl(from nodeID: NodeID, in arena: SyntaxArena, interner: StringInterner) -> TypeAliasDecl {
        let node = arena.node(nodeID)
        return TypeAliasDecl(
            range: node.range,
            name: declarationName(from: nodeID, in: arena, interner: interner),
            modifiers: declarationModifiers(from: nodeID, in: arena)
        )
    }

    private func makeEnumEntryDecl(from nodeID: NodeID, in arena: SyntaxArena, interner: StringInterner) -> EnumEntryDecl {
        let node = arena.node(nodeID)
        return EnumEntryDecl(
            range: node.range,
            name: declarationName(from: nodeID, in: arena, interner: interner)
        )
    }

    private func declarationName(from nodeID: NodeID, in arena: SyntaxArena, interner: StringInterner) -> InternedString {
        for child in arena.children(of: nodeID) {
            if case .token(let tokenID) = child {
                let index = Int(tokenID.rawValue)
                if index < 0 || index >= arena.tokens.count {
                    continue
                }
                let token = arena.tokens[index]
                guard let name = internedIdentifier(from: token, interner: interner) else {
                    continue
                }
                if case .keyword(let keyword) = token.kind, isLeadingDeclarationKeyword(keyword) {
                    continue
                }
                return name
            }
        }
        return interner.intern("")
    }

    private func declarationTypeParameters(
        from nodeID: NodeID,
        in arena: SyntaxArena,
        interner: StringInterner
    ) -> [TypeParamDecl] {
        for child in arena.children(of: nodeID) {
            if case .node(let childID) = child,
               arena.node(childID).kind == .typeArgs {
                let tokens = collectTokens(from: childID, in: arena)
                return tokens
                    .compactMap { token in
                        if !isTypeLikeNameToken(token.kind) {
                            return nil
                        }
                        guard let name = internedIdentifier(from: token, interner: interner) else {
                            return nil
                        }
                        if case .keyword(let keyword) = token.kind, isLeadingDeclarationKeyword(keyword) {
                            return nil
                        }
                        return TypeParamDecl(name: name)
                    }
            }
        }
        return []
    }

    private func declarationValueParameters(
        from nodeID: NodeID,
        in arena: SyntaxArena,
        interner: StringInterner
    ) -> [ValueParamDecl] {
        let tokens = collectTokens(from: nodeID, in: arena)
        guard let startIndex = tokens.firstIndex(where: { token in
            if case .symbol(.lParen) = token.kind {
                return true
            }
            return false
        }) else {
            return []
        }

        var depth = 0
        var arguments: [ValueParamDecl] = []
        var paramTokens: [Token] = []
        var index = startIndex + 1
        while index < tokens.count {
            let token = tokens[index]
            if token.kind == .symbol(.lParen) {
                depth += 1
                if depth > 0 {
                    paramTokens.append(token)
                }
            } else if token.kind == .symbol(.rParen) {
                if depth == 0 {
                    break
                }
                depth -= 1
                if depth >= 0 {
                    paramTokens.append(token)
                }
            } else if token.kind == .symbol(.comma) && depth == 0 {
                appendValueParameter(from: paramTokens, into: &arguments, interner: interner)
                paramTokens.removeAll(keepingCapacity: true)
            } else {
                if token.kind == .symbol(.lBrace) {
                    // Stop at block start for simple tail-recognition in function declarations.
                    break
                }
                paramTokens.append(token)
            }
            index += 1
        }
        if !paramTokens.isEmpty {
            appendValueParameter(from: paramTokens, into: &arguments, interner: interner)
        }
        return arguments
    }

    private func appendValueParameter(
        from tokens: [Token],
        into parameters: inout [ValueParamDecl],
        interner: StringInterner
    ) {
        let sanitized = tokens.filter { token in
            return isTypeLikeNameToken(token.kind)
        }

        guard let nameToken = sanitized.first(where: { token in
            isTypeLikeNameToken(token.kind)
        }) else {
            return
        }

        guard let name = internedIdentifier(from: nameToken, interner: interner) else {
            return
        }
        if case .keyword(let keyword) = nameToken.kind, isLeadingDeclarationKeyword(keyword) {
            return
        }
                parameters.append(ValueParamDecl(name: name, type: nil))
    }

    private func isTypeLikeNameToken(_ kind: TokenKind) -> Bool {
        switch kind {
        case .identifier, .backtickedIdentifier:
            return true
        case .keyword(.in):
            return false
        case .keyword:
            return true
        case .softKeyword(.out):
            return false
        case .softKeyword:
            return true
        default:
            return false
        }
    }

    private func declarationBody(from nodeID: NodeID, in arena: SyntaxArena) -> FunctionBody {
        for child in arena.children(of: nodeID) {
            if case .node(let childID) = child, arena.node(childID).kind == .block {
                return .block(arena.node(childID).range)
            }
        }

        let tokens = collectTokens(from: nodeID, in: arena)
        guard let assignIndex = tokens.firstIndex(where: { token in
            if case .symbol(.assign) = token.kind {
                return true
            }
            return false
        }) else {
            return .unit
        }

        let bodyStartIndex = assignIndex + 1
        if bodyStartIndex >= tokens.count {
            return .unit
        }
        let start = tokens[bodyStartIndex].range.start
        let end = tokens.last?.range.end ?? tokens[bodyStartIndex].range.end
        return .expr(SourceRange(start: start, end: end))
    }

    private func collectTokens(from nodeID: NodeID, in arena: SyntaxArena) -> [Token] {
        var tokens: [Token] = []
        for child in arena.children(of: nodeID) {
            switch child {
            case .token(let tokenID):
                let index = Int(tokenID.rawValue)
                if index < 0 || index >= arena.tokens.count {
                    continue
                }
                tokens.append(arena.tokens[index])
            case .node(let childID):
                tokens.append(contentsOf: collectTokens(from: childID, in: arena))
            }
        }
        return tokens
    }

    private func declarationModifiers(from nodeID: NodeID, in arena: SyntaxArena) -> Modifiers {
        var modifiers: Modifiers = []
        for child in arena.children(of: nodeID) {
            if case .token(let tokenID) = child {
                let index = Int(tokenID.rawValue)
                if index < 0 || index >= arena.tokens.count {
                    continue
                }
                switch arena.tokens[index].kind {
                case .keyword(.public):
                    modifiers.insert(.publicModifier)
                case .keyword(.private):
                    modifiers.insert(.privateModifier)
                case .keyword(.internal):
                    modifiers.insert(.internalModifier)
                case .keyword(.protected):
                    modifiers.insert(.protectedModifier)
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
                default:
                    continue
                }
            }
        }
        return modifiers
    }

    private func extractQualifiedPath(
        from nodeID: NodeID,
        in arena: SyntaxArena,
        interner: StringInterner,
        isPackageHeader: Bool
    ) -> [InternedString] {
        var names: [InternedString] = []
        for child in arena.children(of: nodeID) {
            if case .token(let tokenID) = child {
                let index = Int(tokenID.rawValue)
                if index < 0 || index >= arena.tokens.count {
                    continue
                }
                let token = arena.tokens[index]
                if case .symbol(.star) = token.kind {
                    continue
                }
                if isPackageHeader, case .keyword(.package) = token.kind {
                    continue
                }
                if !isPackageHeader, case .keyword(.import) = token.kind {
                    continue
                }
                if let name = internedIdentifier(from: token, interner: interner) {
                    names.append(name)
                }
            }
        }
        return names
    }

    private func internedIdentifier(from token: Token, interner: StringInterner) -> InternedString? {
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

    private func isLeadingDeclarationKeyword(_ keyword: Keyword) -> Bool {
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

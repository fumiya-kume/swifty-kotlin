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
                let id = arena.appendDecl(.classDecl(makeClassDecl(from: nodeID, in: cst, interner: ctx.interner, astArena: arena)))
                declarations.append(id)
                declarationsByFile[fileRawID, default: []].append(id)

            case .objectDecl:
                let id = arena.appendDecl(.objectDecl(makeObjectDecl(from: nodeID, in: cst, interner: ctx.interner, astArena: arena)))
                declarations.append(id)
                declarationsByFile[fileRawID, default: []].append(id)

            case .interfaceDecl:
                let id = arena.appendDecl(.classDecl(makeClassDecl(from: nodeID, in: cst, interner: ctx.interner, astArena: arena)))
                declarations.append(id)
                declarationsByFile[fileRawID, default: []].append(id)

            case .funDecl:
                let id = arena.appendDecl(.funDecl(makeFunDecl(from: nodeID, in: cst, interner: ctx.interner, astArena: arena)))
                declarations.append(id)
                declarationsByFile[fileRawID, default: []].append(id)

            case .propertyDecl:
                let id = arena.appendDecl(.propertyDecl(makePropertyDecl(from: nodeID, in: cst, interner: ctx.interner, astArena: arena)))
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

    private func makeClassDecl(from nodeID: NodeID, in arena: SyntaxArena, interner: StringInterner, astArena: ASTArena) -> ClassDecl {
        let node = arena.node(nodeID)
        return ClassDecl(
            range: node.range,
            name: declarationName(from: nodeID, in: arena, interner: interner),
            modifiers: declarationModifiers(from: nodeID, in: arena),
            typeParams: declarationTypeParameters(from: nodeID, in: arena, interner: interner),
            primaryConstructorParams: declarationValueParameters(from: nodeID, in: arena, interner: interner, astArena: astArena),
            superTypes: declarationSuperTypes(from: nodeID, in: arena, interner: interner, astArena: astArena),
            enumEntries: declarationEnumEntries(from: nodeID, in: arena, interner: interner)
        )
    }

    private func makeObjectDecl(from nodeID: NodeID, in arena: SyntaxArena, interner: StringInterner, astArena: ASTArena) -> ObjectDecl {
        let node = arena.node(nodeID)
        let modifiers = declarationModifiers(from: nodeID, in: arena)
        return ObjectDecl(
            range: node.range,
            name: declarationName(from: nodeID, in: arena, interner: interner),
            modifiers: modifiers,
            superTypes: declarationSuperTypes(from: nodeID, in: arena, interner: interner, astArena: astArena)
        )
    }

    private func makeFunDecl(from nodeID: NodeID, in arena: SyntaxArena, interner: StringInterner, astArena: ASTArena) -> FunDecl {
        let node = arena.node(nodeID)
        let modifiers = declarationModifiers(from: nodeID, in: arena)
        let isSuspend = modifiers.contains(.suspend)
        let isInline = modifiers.contains(.inline)
        let functionName = declarationFunctionName(from: nodeID, in: arena, interner: interner)
        let valueParams = declarationValueParameters(from: nodeID, in: arena, interner: interner, astArena: astArena)
        let receiverType = declarationReceiverType(from: nodeID, in: arena, interner: interner, astArena: astArena)
        let returnType = declarationReturnType(from: nodeID, in: arena, interner: interner, astArena: astArena)
        let body = declarationBody(from: nodeID, in: arena, interner: interner, astArena: astArena)
        return FunDecl(
            range: node.range,
            name: functionName,
            modifiers: modifiers,
            typeParams: declarationTypeParameters(from: nodeID, in: arena, interner: interner),
            receiverType: receiverType,
            valueParams: valueParams,
            returnType: returnType,
            body: body,
            isSuspend: isSuspend,
            isInline: isInline
        )
    }

    private func makePropertyDecl(from nodeID: NodeID, in arena: SyntaxArena, interner: StringInterner, astArena: ASTArena) -> PropertyDecl {
        let node = arena.node(nodeID)
        return PropertyDecl(
            range: node.range,
            name: declarationName(from: nodeID, in: arena, interner: interner),
            modifiers: declarationModifiers(from: nodeID, in: arena),
            type: declarationPropertyType(from: nodeID, in: arena, interner: interner, astArena: astArena)
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
        interner: StringInterner,
        astArena: ASTArena
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
                appendValueParameter(from: paramTokens, into: &arguments, interner: interner, astArena: astArena)
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
            appendValueParameter(from: paramTokens, into: &arguments, interner: interner, astArena: astArena)
        }
        return arguments
    }

    private func declarationEnumEntries(
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

    private func declarationSuperTypes(
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
        if index < tokens.count, tokens[index].kind == .symbol(.lessThan) {
            var depth = 0
            while index < tokens.count {
                let token = tokens[index]
                if token.kind == .symbol(.lessThan) {
                    depth += 1
                } else if token.kind == .symbol(.greaterThan) {
                    depth -= 1
                    if depth == 0 {
                        index += 1
                        break
                    }
                }
                index += 1
            }
        }
        if index < tokens.count, tokens[index].kind == .symbol(.lParen) {
            var depth = 0
            while index < tokens.count {
                let token = tokens[index]
                if token.kind == .symbol(.lParen) {
                    depth += 1
                } else if token.kind == .symbol(.rParen) {
                    depth -= 1
                    if depth == 0 {
                        index += 1
                        break
                    }
                }
                index += 1
            }
        }
        guard index < tokens.count, tokens[index].kind == .symbol(.colon) else {
            return []
        }
        index += 1

        var refs: [TypeRefID] = []
        var current: [Token] = []
        var angleDepth = 0
        var parenDepth = 0
        while index < tokens.count {
            let token = tokens[index]
            let atTopLevel = angleDepth == 0 && parenDepth == 0
            if atTopLevel {
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

            if token.kind == .symbol(.lessThan) {
                angleDepth += 1
            } else if token.kind == .symbol(.greaterThan) {
                angleDepth = max(0, angleDepth - 1)
            } else if token.kind == .symbol(.lParen) {
                parenDepth += 1
            } else if token.kind == .symbol(.rParen) {
                parenDepth = max(0, parenDepth - 1)
            }
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

    private func stripSuperTypeInvocation(from tokens: [Token]) -> [Token] {
        var result: [Token] = []
        var angleDepth = 0
        for token in tokens {
            if token.kind == .symbol(.lessThan) {
                angleDepth += 1
            } else if token.kind == .symbol(.greaterThan) {
                angleDepth = max(0, angleDepth - 1)
            } else if angleDepth == 0 && token.kind == .symbol(.lParen) {
                break
            }
            result.append(token)
        }
        return result
    }

    private func appendValueParameter(
        from tokens: [Token],
        into parameters: inout [ValueParamDecl],
        interner: StringInterner,
        astArena: ASTArena
    ) {
        let withoutDefault = stripDefaultValue(tokens)
        let hasDefaultValue = withoutDefault.count != tokens.count
        guard !withoutDefault.isEmpty else {
            return
        }

        let colonIndex = withoutDefault.firstIndex(where: { token in
            if case .symbol(.colon) = token.kind {
                return true
            }
            return false
        })

        let nameSearchTokens: ArraySlice<Token>
        if let colonIndex {
            nameSearchTokens = withoutDefault[..<colonIndex]
        } else {
            nameSearchTokens = withoutDefault[...]
        }

        guard let nameToken = nameSearchTokens.last(where: { token in
            if isParameterModifierToken(token) {
                return false
            }
            return isTypeLikeNameToken(token.kind)
        }) else {
            return
        }
        guard let name = internedIdentifier(from: nameToken, interner: interner) else {
            return
        }
        if case .keyword(let keyword) = nameToken.kind, isLeadingDeclarationKeyword(keyword) {
            return
        }

        let typeRef: TypeRefID?
        if let colonIndex {
            let typeTokens = Array(withoutDefault[(colonIndex + 1)...])
            typeRef = parseTypeRef(from: typeTokens, interner: interner, astArena: astArena)
        } else {
            typeRef = nil
        }

        let isVararg = withoutDefault.contains(where: { token in
            if case .keyword(.vararg) = token.kind {
                return true
            }
            return false
        })
        parameters.append(ValueParamDecl(
            name: name,
            type: typeRef,
            hasDefaultValue: hasDefaultValue,
            isVararg: isVararg
        ))
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

    private func stripDefaultValue(_ tokens: [Token]) -> [Token] {
        var angleDepth = 0
        var parenDepth = 0
        var bracketDepth = 0
        var braceDepth = 0

        for (index, token) in tokens.enumerated() {
            switch token.kind {
            case .symbol(.lessThan):
                angleDepth += 1
            case .symbol(.greaterThan):
                angleDepth = max(0, angleDepth - 1)
            case .symbol(.lParen):
                parenDepth += 1
            case .symbol(.rParen):
                parenDepth = max(0, parenDepth - 1)
            case .symbol(.lBracket):
                bracketDepth += 1
            case .symbol(.rBracket):
                bracketDepth = max(0, bracketDepth - 1)
            case .symbol(.lBrace):
                braceDepth += 1
            case .symbol(.rBrace):
                braceDepth = max(0, braceDepth - 1)
            case .symbol(.assign):
                if angleDepth == 0 && parenDepth == 0 && bracketDepth == 0 && braceDepth == 0 {
                    return Array(tokens[..<index])
                }
            default:
                continue
            }
        }
        return tokens
    }

    private func declarationFunctionName(
        from nodeID: NodeID,
        in arena: SyntaxArena,
        interner: StringInterner
    ) -> InternedString {
        let tokens = collectTokens(from: nodeID, in: arena)
        guard let paramsOpenIndex = tokens.firstIndex(where: { $0.kind == .symbol(.lParen) }) else {
            return declarationName(from: nodeID, in: arena, interner: interner)
        }
        if paramsOpenIndex == 0 {
            return declarationName(from: nodeID, in: arena, interner: interner)
        }

        for index in stride(from: paramsOpenIndex - 1, through: 0, by: -1) {
            let token = tokens[index]
            if !isTypeLikeNameToken(token.kind) {
                continue
            }
            if let name = internedIdentifier(from: token, interner: interner) {
                return name
            }
        }
        return declarationName(from: nodeID, in: arena, interner: interner)
    }

    private func declarationReceiverType(
        from nodeID: NodeID,
        in arena: SyntaxArena,
        interner: StringInterner,
        astArena: ASTArena
    ) -> TypeRefID? {
        let tokens = collectTokens(from: nodeID, in: arena)
        guard let paramsOpenIndex = tokens.firstIndex(where: { $0.kind == .symbol(.lParen) }),
              paramsOpenIndex > 0 else {
            return nil
        }

        var nameIndex: Int?
        for index in stride(from: paramsOpenIndex - 1, through: 0, by: -1) {
            if isTypeLikeNameToken(tokens[index].kind) {
                nameIndex = index
                break
            }
        }
        guard let nameIndex else {
            return nil
        }

        var dotIndex: Int?
        var angleDepth = 0
        for index in 0..<nameIndex {
            let token = tokens[index]
            if token.kind == .symbol(.lessThan) {
                angleDepth += 1
            } else if token.kind == .symbol(.greaterThan) {
                angleDepth = max(0, angleDepth - 1)
            }
            if angleDepth == 0, token.kind == .symbol(.dot) {
                dotIndex = index
            }
        }
        guard let dotIndex else {
            return nil
        }

        guard let funIndex = tokens.firstIndex(where: { $0.kind == .keyword(.fun) }) else {
            return nil
        }

        var receiverStart = funIndex + 1
        if receiverStart < tokens.count, tokens[receiverStart].kind == .symbol(.lessThan) {
            var genericDepth = 0
            while receiverStart < tokens.count {
                let token = tokens[receiverStart]
                if token.kind == .symbol(.lessThan) {
                    genericDepth += 1
                } else if token.kind == .symbol(.greaterThan) {
                    genericDepth -= 1
                    if genericDepth == 0 {
                        receiverStart += 1
                        break
                    }
                }
                receiverStart += 1
            }
        }

        if receiverStart >= dotIndex {
            return nil
        }

        let receiverTokens = Array(tokens[receiverStart..<dotIndex])
        return parseTypeRef(from: receiverTokens, interner: interner, astArena: astArena)
    }

    private func declarationReturnType(
        from nodeID: NodeID,
        in arena: SyntaxArena,
        interner: StringInterner,
        astArena: ASTArena
    ) -> TypeRefID? {
        let tokens = collectTokens(from: nodeID, in: arena)
        guard let closeParenIndex = firstFunctionParameterCloseParen(in: tokens) else {
            return nil
        }

        var index = closeParenIndex + 1
        while index < tokens.count {
            let token = tokens[index]
            if token.kind == .symbol(.assign) || token.kind == .symbol(.lBrace) {
                return nil
            }
            if token.kind == .symbol(.colon) {
                index += 1
                break
            }
            index += 1
        }

        guard index < tokens.count else {
            return nil
        }

        var typeTokens: [Token] = []
        var angleDepth = 0
        while index < tokens.count {
            let token = tokens[index]
            if angleDepth == 0 {
                if token.kind == .symbol(.assign) || token.kind == .symbol(.lBrace) {
                    break
                }
                if case .softKeyword(.where) = token.kind {
                    break
                }
            }

            if token.kind == .symbol(.lessThan) {
                angleDepth += 1
            } else if token.kind == .symbol(.greaterThan) {
                angleDepth = max(0, angleDepth - 1)
            }

            typeTokens.append(token)
            index += 1
        }

        return parseTypeRef(from: typeTokens, interner: interner, astArena: astArena)
    }

    private func declarationPropertyType(
        from nodeID: NodeID,
        in arena: SyntaxArena,
        interner: StringInterner,
        astArena: ASTArena
    ) -> TypeRefID? {
        let tokens = collectTokens(from: nodeID, in: arena)
        var sawName = false
        var colonIndex: Int?
        for (index, token) in tokens.enumerated() {
            if !sawName {
                switch token.kind {
                case .keyword(.val), .keyword(.var):
                    continue
                default:
                    if isTypeLikeNameToken(token.kind) {
                        sawName = true
                    }
                    continue
                }
            }

            if token.kind == .symbol(.colon) {
                colonIndex = index
                break
            }
            if token.kind == .symbol(.assign) || token.kind == .symbol(.lBrace) || token.kind == .symbol(.semicolon) {
                return nil
            }
            if case .softKeyword(.by) = token.kind {
                return nil
            }
        }

        guard let colonIndex else {
            return nil
        }

        var typeTokens: [Token] = []
        var angleDepth = 0
        var index = colonIndex + 1
        while index < tokens.count {
            let token = tokens[index]
            if angleDepth == 0 {
                if token.kind == .symbol(.assign) || token.kind == .symbol(.lBrace) || token.kind == .symbol(.semicolon) {
                    break
                }
                if case .softKeyword(.by) = token.kind {
                    break
                }
            }

            if token.kind == .symbol(.lessThan) {
                angleDepth += 1
            } else if token.kind == .symbol(.greaterThan) {
                angleDepth = max(0, angleDepth - 1)
            }

            typeTokens.append(token)
            index += 1
        }

        return parseTypeRef(from: typeTokens, interner: interner, astArena: astArena)
    }

    private func firstFunctionParameterCloseParen(in tokens: [Token]) -> Int? {
        guard let openIndex = tokens.firstIndex(where: { $0.kind == .symbol(.lParen) }) else {
            return nil
        }
        var depth = 0
        for index in openIndex..<tokens.count {
            let token = tokens[index]
            if token.kind == .symbol(.lParen) {
                depth += 1
            } else if token.kind == .symbol(.rParen) {
                depth -= 1
                if depth == 0 {
                    return index
                }
            }
        }
        return nil
    }

    private func parseTypeRef(
        from tokens: [Token],
        interner: StringInterner,
        astArena: ASTArena
    ) -> TypeRefID? {
        if tokens.isEmpty {
            return nil
        }

        var path: [InternedString] = []
        var nullable = false
        var angleDepth = 0

        for token in tokens {
            switch token.kind {
            case .symbol(.lessThan):
                angleDepth += 1
            case .symbol(.greaterThan):
                angleDepth = max(0, angleDepth - 1)
            case .symbol(.question):
                if angleDepth == 0 {
                    nullable = true
                }
            case .symbol(.dot):
                continue
            default:
                if angleDepth > 0 {
                    continue
                }
                if let name = internedIdentifier(from: token, interner: interner),
                   isTypeLikeNameToken(token.kind) {
                    path.append(name)
                }
            }
        }

        guard !path.isEmpty else {
            return nil
        }
        return astArena.appendTypeRef(.named(path: path, nullable: nullable))
    }

    private func isParameterModifierToken(_ token: Token) -> Bool {
        guard case .keyword(let keyword) = token.kind else {
            return false
        }
        switch keyword {
        case .vararg, .crossinline, .noinline:
            return true
        default:
            return false
        }
    }

    private func declarationBody(
        from nodeID: NodeID,
        in arena: SyntaxArena,
        interner: StringInterner,
        astArena: ASTArena
    ) -> FunctionBody {
        for child in arena.children(of: nodeID) {
            if case .node(let childID) = child, arena.node(childID).kind == .block {
                let exprs = blockExpressions(from: childID, in: arena, interner: interner, astArena: astArena)
                return .block(exprs, arena.node(childID).range)
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
        let exprTokens = Array(tokens[bodyStartIndex...])
        let parser = ExpressionParser(tokens: exprTokens, interner: interner, astArena: astArena)
        guard let exprID = parser.parse() else {
            return .unit
        }
        guard let range = astArena.exprRange(exprID) else {
            return .unit
        }
        return .expr(exprID, range)
    }

    private func blockExpressions(
        from blockNodeID: NodeID,
        in arena: SyntaxArena,
        interner: StringInterner,
        astArena: ASTArena
    ) -> [ExprID] {
        var result: [ExprID] = []
        for child in arena.children(of: blockNodeID) {
            guard case .node(let nodeID) = child else {
                continue
            }
            let node = arena.node(nodeID)
            guard node.kind == .statement else {
                continue
            }
            let statementTokens = collectTokens(from: nodeID, in: arena).filter { token in
                token.kind != .symbol(.semicolon)
            }
            guard !statementTokens.isEmpty else {
                continue
            }
            let parser = ExpressionParser(tokens: statementTokens, interner: interner, astArena: astArena)
            if let exprID = parser.parse() {
                result.append(exprID)
            }
        }
        return result
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
                case .keyword(.enum):
                    modifiers.insert(.enumModifier)
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

    private final class ExpressionParser {
        private let tokens: [Token]
        private let interner: StringInterner
        private let astArena: ASTArena
        private var index: Int = 0

        init(tokens: [Token], interner: StringInterner, astArena: ASTArena) {
            self.tokens = tokens
            self.interner = interner
            self.astArena = astArena
        }

        func parse() -> ExprID? {
            parseExpression(minPrecedence: 0)
        }

        private func parseExpression(minPrecedence: Int) -> ExprID? {
            guard var lhs = parsePostfixOrPrimary() else {
                return nil
            }

            while let op = binaryOperator(at: current()), precedence(of: op) >= minPrecedence {
                guard let opToken = consume() else { break }
                let nextMin = precedence(of: op) + 1
                guard let rhs = parseExpression(minPrecedence: nextMin) else { break }
                let range = mergeRanges(astArena.exprRange(lhs), astArena.exprRange(rhs), fallback: opToken.range)
                lhs = astArena.appendExpr(.binary(op: op, lhs: lhs, rhs: rhs, range: range))
            }
            return lhs
        }

        private func parsePostfixOrPrimary() -> ExprID? {
            guard var expr = parsePrimary() else {
                return nil
            }
            while matches(.symbol(.lParen)) {
                guard let open = consume() else { break }
                var args: [ExprID] = []
                if !matches(.symbol(.rParen)) {
                    while true {
                        if let arg = parseExpression(minPrecedence: 0) {
                            args.append(arg)
                        }
                        if matches(.symbol(.comma)) {
                            _ = consume()
                            continue
                        }
                        break
                    }
                }
                let close = consumeIf(.symbol(.rParen))
                let fallbackEnd = close?.range.end ?? open.range.end
                let endRange = SourceRange(start: fallbackEnd, end: fallbackEnd)
                let range = mergeRanges(astArena.exprRange(expr), close?.range ?? endRange, fallback: open.range)
                expr = astArena.appendExpr(.call(callee: expr, args: args, range: range))
            }
            return expr
        }

        private func parsePrimary() -> ExprID? {
            guard let token = current() else {
                return nil
            }

            switch token.kind {
            case .intLiteral(let text), .longLiteral(let text):
                _ = consume()
                let value = Int64(text.filter { $0.isNumber }) ?? 0
                return astArena.appendExpr(.intLiteral(value, token.range))

            case .keyword(.true):
                _ = consume()
                return astArena.appendExpr(.boolLiteral(true, token.range))

            case .keyword(.false):
                _ = consume()
                return astArena.appendExpr(.boolLiteral(false, token.range))

            case .identifier(let name), .backtickedIdentifier(let name):
                _ = consume()
                return astArena.appendExpr(.nameRef(name, token.range))

            case .keyword(.when):
                return parseWhenExpression()

            case .keyword(let keyword):
                _ = consume()
                return astArena.appendExpr(.nameRef(interner.intern(keyword.rawValue), token.range))

            case .softKeyword(let keyword):
                _ = consume()
                return astArena.appendExpr(.nameRef(interner.intern(keyword.rawValue), token.range))

            case .stringQuote, .rawStringQuote:
                return parseStringLiteral()

            case .symbol(.lParen):
                _ = consume()
                let expr = parseExpression(minPrecedence: 0)
                _ = consumeIf(.symbol(.rParen))
                return expr

            default:
                return nil
            }
        }

        private func parseStringLiteral() -> ExprID? {
            guard let open = consume() else { return nil }
            var pieces: [String] = []
            var end = open.range.end
            let closingKind = open.kind

            while let token = current() {
                if token.kind == closingKind {
                    _ = consume()
                    end = token.range.end
                    break
                }
                if case .stringSegment(let segment) = token.kind {
                    pieces.append(interner.resolve(segment))
                }
                end = token.range.end
                _ = consume()
            }

            let literal = pieces.joined()
            let id = interner.intern(literal)
            let range = SourceRange(start: open.range.start, end: end)
            return astArena.appendExpr(.stringLiteral(id, range))
        }

        private func parseWhenExpression() -> ExprID? {
            guard let whenToken = consume() else {
                return nil
            }
            guard consumeIf(.symbol(.lParen)) != nil else {
                return nil
            }
            guard let subject = parseExpression(minPrecedence: 0) else {
                return nil
            }
            _ = consumeIf(.symbol(.rParen))
            guard consumeIf(.symbol(.lBrace)) != nil else {
                return nil
            }

            var branches: [WhenBranch] = []
            var elseExpr: ExprID?
            var end = whenToken.range.end

            while let token = current() {
                if token.kind == .symbol(.rBrace) {
                    end = token.range.end
                    _ = consume()
                    break
                }

                let branchStart = token.range.start
                var condition: ExprID?
                if token.kind == .keyword(.else) {
                    _ = consume()
                } else {
                    condition = parseExpression(minPrecedence: 0)
                }

                _ = consumeIf(.symbol(.arrow))
                let body = parseExpression(minPrecedence: 0)
                while matches(.symbol(.semicolon)) || matches(.symbol(.comma)) {
                    _ = consume()
                }

                if let body {
                    let branchRange = SourceRange(start: branchStart, end: astArena.exprRange(body)?.end ?? branchStart)
                    let branch = WhenBranch(condition: condition, body: body, range: branchRange)
                    if condition == nil {
                        elseExpr = body
                    } else {
                        branches.append(branch)
                    }
                    end = branchRange.end
                }
            }

            let range = SourceRange(start: whenToken.range.start, end: end)
            return astArena.appendExpr(.whenExpr(subject: subject, branches: branches, elseExpr: elseExpr, range: range))
        }

        private func mergeRanges(_ lhs: SourceRange?, _ rhs: SourceRange?, fallback: SourceRange) -> SourceRange {
            switch (lhs, rhs) {
            case let (lhs?, rhs?):
                return SourceRange(start: lhs.start, end: rhs.end)
            case let (lhs?, nil):
                return lhs
            case let (nil, rhs?):
                return rhs
            default:
                return fallback
            }
        }

        private func binaryOperator(at token: Token?) -> BinaryOp? {
            guard let token else { return nil }
            switch token.kind {
            case .symbol(.plus):
                return .add
            case .symbol(.minus):
                return .subtract
            case .symbol(.star):
                return .multiply
            case .symbol(.slash):
                return .divide
            case .symbol(.equalEqual):
                return .equal
            default:
                return nil
            }
        }

        private func precedence(of op: BinaryOp) -> Int {
            switch op {
            case .multiply, .divide:
                return 20
            case .add, .subtract:
                return 10
            case .equal:
                return 5
            }
        }

        private func current() -> Token? {
            if index >= 0 && index < tokens.count {
                return tokens[index]
            }
            return nil
        }

        private func consume() -> Token? {
            guard let token = current() else {
                return nil
            }
            index += 1
            return token
        }

        private func matches(_ kind: TokenKind) -> Bool {
            current()?.kind == kind
        }

        private func consumeIf(_ kind: TokenKind) -> Token? {
            guard matches(kind) else {
                return nil
            }
            return consume()
        }
    }
}

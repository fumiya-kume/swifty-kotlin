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

            case .classDecl, .interfaceDecl:
                let decl = Decl.classDecl(makeClassDecl(from: nodeID, in: cst, interner: ctx.interner, astArena: arena))
                appendDecl(decl, to: arena, declarations: &declarations, fileDecls: &declarationsByFile, fileRawID: fileRawID)

            case .objectDecl:
                let decl = Decl.objectDecl(makeObjectDecl(from: nodeID, in: cst, interner: ctx.interner, astArena: arena))
                appendDecl(decl, to: arena, declarations: &declarations, fileDecls: &declarationsByFile, fileRawID: fileRawID)

            case .funDecl:
                let decl = Decl.funDecl(makeFunDecl(from: nodeID, in: cst, interner: ctx.interner, astArena: arena))
                appendDecl(decl, to: arena, declarations: &declarations, fileDecls: &declarationsByFile, fileRawID: fileRawID)

            case .propertyDecl:
                let decl = Decl.propertyDecl(makePropertyDecl(from: nodeID, in: cst, interner: ctx.interner, astArena: arena))
                appendDecl(decl, to: arena, declarations: &declarations, fileDecls: &declarationsByFile, fileRawID: fileRawID)

            case .typeAliasDecl:
                let decl = Decl.typeAliasDecl(makeTypeAliasDecl(from: nodeID, in: cst, interner: ctx.interner))
                appendDecl(decl, to: arena, declarations: &declarations, fileDecls: &declarationsByFile, fileRawID: fileRawID)

            case .enumEntry:
                let decl = Decl.enumEntry(makeEnumEntryDecl(from: nodeID, in: cst, interner: ctx.interner))
                appendDecl(decl, to: arena, declarations: &declarations, fileDecls: &declarationsByFile, fileRawID: fileRawID)

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

    private func appendDecl(
        _ decl: Decl,
        to arena: ASTArena,
        declarations: inout [DeclID],
        fileDecls: inout [Int32: [DeclID]],
        fileRawID: Int32
    ) {
        let id = arena.appendDecl(decl)
        declarations.append(id)
        fileDecls[fileRawID, default: []].append(id)
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
            enumEntries: declarationEnumEntries(from: nodeID, in: arena, interner: interner),
            initBlocks: declarationInitBlocks(from: nodeID, in: arena, interner: interner, astArena: astArena)
        )
    }

    private func makeObjectDecl(from nodeID: NodeID, in arena: SyntaxArena, interner: StringInterner, astArena: ASTArena) -> ObjectDecl {
        let node = arena.node(nodeID)
        let modifiers = declarationModifiers(from: nodeID, in: arena)
        return ObjectDecl(
            range: node.range,
            name: declarationName(from: nodeID, in: arena, interner: interner),
            modifiers: modifiers,
            superTypes: declarationSuperTypes(from: nodeID, in: arena, interner: interner, astArena: astArena),
            initBlocks: declarationInitBlocks(from: nodeID, in: arena, interner: interner, astArena: astArena)
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
        let accessors = declarationPropertyAccessors(from: nodeID, in: arena, interner: interner, astArena: astArena)
        return PropertyDecl(
            range: node.range,
            name: declarationName(from: nodeID, in: arena, interner: interner),
            modifiers: declarationModifiers(from: nodeID, in: arena),
            type: declarationPropertyType(from: nodeID, in: arena, interner: interner, astArena: astArena),
            isVar: declarationIsVar(from: nodeID, in: arena),
            initializer: declarationPropertyInitializer(from: nodeID, in: arena, interner: interner, astArena: astArena),
            getter: accessors.getter,
            setter: accessors.setter
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
            if case .token(let tokenID) = child,
               let token = resolveToken(tokenID, in: arena),
               let name = internedIdentifier(from: token, interner: interner) {
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

    private func stripSuperTypeInvocation(from tokens: [Token]) -> [Token] {
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
        var depth = BracketDepth()
        for (index, token) in tokens.enumerated() {
            if token.kind == .symbol(.assign) && depth.isAtTopLevel {
                return Array(tokens[..<index])
            }
            depth.track(token.kind)
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
        var depth = BracketDepth()
        for index in 0..<nameIndex {
            let token = tokens[index]
            depth.track(token.kind)
            if depth.angle == 0, token.kind == .symbol(.dot) {
                dotIndex = index
            }
        }
        guard let dotIndex else {
            return nil
        }

        guard let funIndex = tokens.firstIndex(where: { $0.kind == .keyword(.fun) }) else {
            return nil
        }

        let receiverStart = skipBalancedBracket(
            in: tokens, from: funIndex + 1,
            open: .symbol(.lessThan), close: .symbol(.greaterThan)
        )

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
        var depth = BracketDepth()
        while index < tokens.count {
            let token = tokens[index]
            if depth.angle == 0 {
                if token.kind == .symbol(.assign) || token.kind == .symbol(.lBrace) {
                    break
                }
                if case .softKeyword(.where) = token.kind {
                    break
                }
            }
            depth.track(token.kind)
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
        let tokens = propertyHeadTokens(from: nodeID, in: arena)
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
        var depth = BracketDepth()
        var index = colonIndex + 1
        while index < tokens.count {
            let token = tokens[index]
            if depth.angle == 0 {
                if token.kind == .symbol(.assign) || token.kind == .symbol(.lBrace) || token.kind == .symbol(.semicolon) {
                    break
                }
                if case .softKeyword(.by) = token.kind {
                    break
                }
            }
            depth.track(token.kind)
            typeTokens.append(token)
            index += 1
        }

        return parseTypeRef(from: typeTokens, interner: interner, astArena: astArena)
    }

    private func declarationIsVar(from nodeID: NodeID, in arena: SyntaxArena) -> Bool {
        for child in arena.children(of: nodeID) {
            if case .token(let tokenID) = child,
               let token = resolveToken(tokenID, in: arena),
               token.kind == .keyword(.var) {
                return true
            }
        }
        return false
    }

    private func declarationPropertyInitializer(
        from nodeID: NodeID,
        in arena: SyntaxArena,
        interner: StringInterner,
        astArena: ASTArena
    ) -> ExprID? {
        let tokens = propertyHeadTokens(from: nodeID, in: arena)
        guard !tokens.isEmpty else {
            return nil
        }

        var assignIndex: Int?
        var depth = BracketDepth()
        for (index, token) in tokens.enumerated() {
            if case .softKeyword(.by) = token.kind, depth.isAtTopLevel {
                return nil
            }
            if token.kind == .symbol(.assign) && depth.isAtTopLevel {
                assignIndex = index
                break
            }
            depth.track(token.kind)
        }

        guard let assignIndex else {
            return nil
        }
        let start = assignIndex + 1
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

    private func declarationPropertyAccessors(
        from nodeID: NodeID,
        in arena: SyntaxArena,
        interner: StringInterner,
        astArena: ASTArena
    ) -> (getter: PropertyAccessorDecl?, setter: PropertyAccessorDecl?) {
        var getter: PropertyAccessorDecl?
        var setter: PropertyAccessorDecl?

        guard let accessorBlockID = arena.children(of: nodeID).compactMap({ child -> NodeID? in
            guard case .node(let childID) = child,
                  arena.node(childID).kind == .block else {
                return nil
            }
            return childID
        }).first else {
            return (nil, nil)
        }

        for child in arena.children(of: accessorBlockID) {
            guard case .node(let statementID) = child,
                  arena.node(statementID).kind == .statement else {
                continue
            }

            let headerTokens = collectDirectTokens(from: statementID, in: arena).filter { token in
                token.kind != .symbol(.semicolon)
            }
            guard let firstToken = headerTokens.first else {
                continue
            }

            let kind: PropertyAccessorKind
            switch firstToken.kind {
            case .softKeyword(.get):
                kind = .getter
            case .softKeyword(.set):
                kind = .setter
            default:
                continue
            }

            let parameterName: InternedString?
            if kind == .setter {
                parameterName = setterParameterName(from: headerTokens, interner: interner)
            } else {
                parameterName = nil
            }

            let body = accessorBody(
                statementID: statementID,
                headerTokens: headerTokens,
                in: arena,
                interner: interner,
                astArena: astArena
            )
            let accessor = PropertyAccessorDecl(
                range: arena.node(statementID).range,
                kind: kind,
                parameterName: parameterName,
                body: body
            )
            switch kind {
            case .getter:
                if getter == nil {
                    getter = accessor
                }
            case .setter:
                if setter == nil {
                    setter = accessor
                }
            }
        }

        return (getter, setter)
    }

    private func declarationInitBlocks(
        from nodeID: NodeID,
        in arena: SyntaxArena,
        interner: StringInterner,
        astArena: ASTArena
    ) -> [FunctionBody] {
        var result: [FunctionBody] = []
        for child in arena.children(of: nodeID) {
            guard case .node(let bodyBlockID) = child,
                  arena.node(bodyBlockID).kind == .block else {
                continue
            }
            for bodyChild in arena.children(of: bodyBlockID) {
                guard case .node(let statementID) = bodyChild,
                      arena.node(statementID).kind == .statement else {
                    continue
                }
                let headerTokens = collectDirectTokens(from: statementID, in: arena).filter { token in
                    token.kind != .symbol(.semicolon)
                }
                guard let firstToken = headerTokens.first,
                      firstToken.kind == .softKeyword(.`init`) else {
                    continue
                }

                if let nestedBlockID = arena.children(of: statementID).compactMap({ inner -> NodeID? in
                    guard case .node(let nodeID) = inner,
                          arena.node(nodeID).kind == .block else {
                        return nil
                    }
                    return nodeID
                }).first {
                    let exprs = blockExpressions(
                        from: nestedBlockID,
                        in: arena,
                        interner: interner,
                        astArena: astArena
                    )
                    result.append(.block(exprs, arena.node(nestedBlockID).range))
                    continue
                }

                if headerTokens.count > 1 {
                    let parser = ExpressionParser(
                        tokens: Array(headerTokens.dropFirst()),
                        interner: interner,
                        astArena: astArena
                    )
                    if let exprID = parser.parse(),
                       let range = astArena.exprRange(exprID) {
                        result.append(.expr(exprID, range))
                        continue
                    }
                }
                result.append(.unit)
            }
        }
        return result
    }

    private func setterParameterName(
        from headerTokens: [Token],
        interner: StringInterner
    ) -> InternedString? {
        guard let openParenIndex = headerTokens.firstIndex(where: { $0.kind == .symbol(.lParen) }) else {
            return nil
        }
        for token in headerTokens[(openParenIndex + 1)...] {
            if token.kind == .symbol(.rParen) {
                break
            }
            if let name = internedIdentifier(from: token, interner: interner),
               isTypeLikeNameToken(token.kind) {
                return name
            }
        }
        return nil
    }

    private func accessorBody(
        statementID: NodeID,
        headerTokens: [Token],
        in arena: SyntaxArena,
        interner: StringInterner,
        astArena: ASTArena
    ) -> FunctionBody {
        if let nestedBlockID = arena.children(of: statementID).compactMap({ child -> NodeID? in
            guard case .node(let nodeID) = child,
                  arena.node(nodeID).kind == .block else {
                return nil
            }
            return nodeID
        }).first {
            let exprs = blockExpressions(
                from: nestedBlockID,
                in: arena,
                interner: interner,
                astArena: astArena
            )
            return .block(exprs, arena.node(nestedBlockID).range)
        }

        guard let assignIndex = headerTokens.firstIndex(where: { $0.kind == .symbol(.assign) }) else {
            return .unit
        }
        let exprTokens = headerTokens[(assignIndex + 1)...].filter { token in
            token.kind != .symbol(.semicolon)
        }
        guard !exprTokens.isEmpty else {
            return .unit
        }
        let parser = ExpressionParser(tokens: Array(exprTokens), interner: interner, astArena: astArena)
        guard let exprID = parser.parse(),
              let range = astArena.exprRange(exprID) else {
            return .unit
        }
        return .expr(exprID, range)
    }

    private func propertyHeadTokens(
        from nodeID: NodeID,
        in arena: SyntaxArena
    ) -> [Token] {
        var tokens: [Token] = []
        for child in arena.children(of: nodeID) {
            switch child {
            case .token(let tokenID):
                if let token = resolveToken(tokenID, in: arena) {
                    tokens.append(token)
                }
            case .node(let childID):
                if arena.node(childID).kind == .block {
                    return tokens
                }
            }
        }
        return tokens
    }

    private func firstFunctionParameterCloseParen(in tokens: [Token]) -> Int? {
        guard let openIndex = tokens.firstIndex(where: { $0.kind == .symbol(.lParen) }) else {
            return nil
        }
        let afterClose = skipBalancedBracket(in: tokens, from: openIndex, open: .symbol(.lParen), close: .symbol(.rParen))
        guard afterClose > openIndex else {
            return nil
        }
        return afterClose - 1
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
        var depth = BracketDepth()

        for token in tokens {
            depth.track(token.kind)
            if depth.angle > 0 {
                continue
            }
            switch token.kind {
            case .symbol(.question):
                nullable = true
            case .symbol(.dot), .symbol(.greaterThan):
                continue
            default:
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

    private struct BracketDepth {
        var angle: Int = 0
        var paren: Int = 0
        var bracket: Int = 0
        var brace: Int = 0

        var isAtTopLevel: Bool {
            angle == 0 && paren == 0 && bracket == 0 && brace == 0
        }

        var isAngleParenTopLevel: Bool {
            angle == 0 && paren == 0
        }

        mutating func track(_ kind: TokenKind) {
            switch kind {
            case .symbol(.lessThan):    angle += 1
            case .symbol(.greaterThan): angle = max(0, angle - 1)
            case .symbol(.lParen):      paren += 1
            case .symbol(.rParen):      paren = max(0, paren - 1)
            case .symbol(.lBracket):    bracket += 1
            case .symbol(.rBracket):    bracket = max(0, bracket - 1)
            case .symbol(.lBrace):      brace += 1
            case .symbol(.rBrace):      brace = max(0, brace - 1)
            default: break
            }
        }
    }

    private func skipBalancedBracket(
        in tokens: [Token],
        from startIndex: Int,
        open: TokenKind,
        close: TokenKind
    ) -> Int {
        guard startIndex < tokens.count, tokens[startIndex].kind == open else {
            return startIndex
        }
        var depth = 0
        var index = startIndex
        while index < tokens.count {
            let kind = tokens[index].kind
            if kind == open {
                depth += 1
            } else if kind == close {
                depth -= 1
                if depth == 0 {
                    return index + 1
                }
            }
            index += 1
        }
        return index
    }

    private func resolveToken(_ tokenID: TokenID, in arena: SyntaxArena) -> Token? {
        let index = Int(tokenID.rawValue)
        guard index >= 0 && index < arena.tokens.count else {
            return nil
        }
        return arena.tokens[index]
    }

    private func collectTokens(from nodeID: NodeID, in arena: SyntaxArena) -> [Token] {
        var tokens: [Token] = []
        for child in arena.children(of: nodeID) {
            switch child {
            case .token(let tokenID):
                if let token = resolveToken(tokenID, in: arena) {
                    tokens.append(token)
                }
            case .node(let childID):
                tokens.append(contentsOf: collectTokens(from: childID, in: arena))
            }
        }
        return tokens
    }

    private func collectDirectTokens(from nodeID: NodeID, in arena: SyntaxArena) -> [Token] {
        var tokens: [Token] = []
        for child in arena.children(of: nodeID) {
            guard case .token(let tokenID) = child,
                  let token = resolveToken(tokenID, in: arena) else {
                continue
            }
            tokens.append(token)
        }
        return tokens
    }

    private func declarationModifiers(from nodeID: NodeID, in arena: SyntaxArena) -> Modifiers {
        var modifiers: Modifiers = []
        for child in arena.children(of: nodeID) {
            if case .token(let tokenID) = child,
               let token = resolveToken(tokenID, in: arena) {
                switch token.kind {
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
            if let name = internedIdentifier(from: token, interner: interner) {
                names.append(name)
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
                var args: [CallArgument] = []
                if !matches(.symbol(.rParen)) {
                    while true {
                        if let argument = parseCallArgument() {
                            args.append(argument)
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

        private func parseCallArgument() -> CallArgument? {
            var isSpread = false
            if matches(.symbol(.star)) {
                _ = consume()
                isSpread = true
            }

            var label: InternedString?
            if let first = current(),
               let second = peek(1),
               isArgumentLabelToken(first.kind),
               second.kind == .symbol(.assign) {
                label = tokenText(first)
                _ = consume()
                _ = consume()
            }

            guard let expr = parseExpression(minPrecedence: 0) else {
                return nil
            }
            return CallArgument(label: label, isSpread: isSpread, expr: expr)
        }

        private func isArgumentLabelToken(_ kind: TokenKind) -> Bool {
            switch kind {
            case .identifier, .backtickedIdentifier, .keyword, .softKeyword:
                return true
            default:
                return false
            }
        }

        private func tokenText(_ token: Token) -> InternedString? {
            switch token.kind {
            case .identifier(let name), .backtickedIdentifier(let name):
                return name
            case .keyword(let keyword):
                return interner.intern(keyword.rawValue)
            case .softKeyword(let keyword):
                return interner.intern(keyword.rawValue)
            default:
                return nil
            }
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

        private func peek(_ offset: Int) -> Token? {
            let target = index + offset
            if target >= 0 && target < tokens.count {
                return tokens[target]
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

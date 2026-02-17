import Foundation

extension BuildASTPhase {
    func appendDecl(
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

    func makeClassDecl(from nodeID: NodeID, in arena: SyntaxArena, interner: StringInterner, astArena: ASTArena) -> ClassDecl {
        let node = arena.node(nodeID)
        let members = declarationMemberDecls(from: nodeID, in: arena, interner: interner, astArena: astArena)
        let rawTypeParams = declarationTypeParameters(from: nodeID, in: arena, interner: interner, astArena: astArena)
        let whereClauses = declarationWhereClauses(from: nodeID, in: arena, interner: interner, astArena: astArena)
        let typeParams = applyWhereClauses(rawTypeParams, whereClauses: whereClauses)
        return ClassDecl(
            range: node.range,
            name: declarationName(from: nodeID, in: arena, interner: interner),
            modifiers: declarationModifiers(from: nodeID, in: arena),
            typeParams: typeParams,
            primaryConstructorParams: declarationValueParameters(from: nodeID, in: arena, interner: interner, astArena: astArena),
            superTypes: declarationSuperTypes(from: nodeID, in: arena, interner: interner, astArena: astArena),
            nestedTypeAliases: declarationNestedTypeAliases(from: nodeID, in: arena, interner: interner, astArena: astArena),
            enumEntries: declarationEnumEntries(from: nodeID, in: arena, interner: interner),
            initBlocks: declarationInitBlocks(from: nodeID, in: arena, interner: interner, astArena: astArena),
            secondaryConstructors: declarationSecondaryConstructors(from: nodeID, in: arena, interner: interner, astArena: astArena),
            memberFunctions: members.functions,
            memberProperties: members.properties,
            nestedClasses: members.nestedClasses,
            nestedObjects: members.nestedObjects
        )
    }

    func makeInterfaceDecl(from nodeID: NodeID, in arena: SyntaxArena, interner: StringInterner, astArena: ASTArena) -> InterfaceDecl {
        let node = arena.node(nodeID)
        let rawTypeParams = declarationTypeParameters(from: nodeID, in: arena, interner: interner, astArena: astArena)
        let whereClauses = declarationWhereClauses(from: nodeID, in: arena, interner: interner, astArena: astArena)
        let typeParams = applyWhereClauses(rawTypeParams, whereClauses: whereClauses)
        return InterfaceDecl(
            range: node.range,
            name: declarationName(from: nodeID, in: arena, interner: interner),
            modifiers: declarationModifiers(from: nodeID, in: arena),
            typeParams: typeParams,
            superTypes: declarationSuperTypes(from: nodeID, in: arena, interner: interner, astArena: astArena),
            nestedTypeAliases: declarationNestedTypeAliases(from: nodeID, in: arena, interner: interner, astArena: astArena)
        )
    }

    func makeObjectDecl(from nodeID: NodeID, in arena: SyntaxArena, interner: StringInterner, astArena: ASTArena) -> ObjectDecl {
        let node = arena.node(nodeID)
        let modifiers = declarationModifiers(from: nodeID, in: arena)
        let members = declarationMemberDecls(from: nodeID, in: arena, interner: interner, astArena: astArena)
        return ObjectDecl(
            range: node.range,
            name: declarationName(from: nodeID, in: arena, interner: interner),
            modifiers: modifiers,
            superTypes: declarationSuperTypes(from: nodeID, in: arena, interner: interner, astArena: astArena),
            nestedTypeAliases: declarationNestedTypeAliases(from: nodeID, in: arena, interner: interner, astArena: astArena),
            initBlocks: declarationInitBlocks(from: nodeID, in: arena, interner: interner, astArena: astArena),
            memberFunctions: members.functions,
            memberProperties: members.properties,
            nestedClasses: members.nestedClasses,
            nestedObjects: members.nestedObjects
        )
    }

    func makeFunDecl(from nodeID: NodeID, in arena: SyntaxArena, interner: StringInterner, astArena: ASTArena) -> FunDecl {
        let node = arena.node(nodeID)
        let modifiers = declarationModifiers(from: nodeID, in: arena)
        let isSuspend = modifiers.contains(.suspend)
        let isInline = modifiers.contains(.inline)
        let functionName = declarationFunctionName(from: nodeID, in: arena, interner: interner)
        let valueParams = declarationValueParameters(from: nodeID, in: arena, interner: interner, astArena: astArena)
        let receiverType = declarationReceiverType(from: nodeID, in: arena, interner: interner, astArena: astArena)
        let returnType = declarationReturnType(from: nodeID, in: arena, interner: interner, astArena: astArena)
        let body = declarationBody(from: nodeID, in: arena, interner: interner, astArena: astArena)
        let rawTypeParams = declarationTypeParameters(from: nodeID, in: arena, interner: interner, astArena: astArena)
        let whereClauses = declarationWhereClauses(from: nodeID, in: arena, interner: interner, astArena: astArena)
        let typeParams = applyWhereClauses(rawTypeParams, whereClauses: whereClauses)
        return FunDecl(
            range: node.range,
            name: functionName,
            modifiers: modifiers,
            typeParams: typeParams,
            receiverType: receiverType,
            valueParams: valueParams,
            returnType: returnType,
            body: body,
            isSuspend: isSuspend,
            isInline: isInline
        )
    }

    func makePropertyDecl(from nodeID: NodeID, in arena: SyntaxArena, interner: StringInterner, astArena: ASTArena) -> PropertyDecl {
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
            setter: accessors.setter,
            delegateExpression: declarationDelegateExpression(from: nodeID, in: arena, interner: interner, astArena: astArena)
        )
    }

    func makeTypeAliasDecl(from nodeID: NodeID, in arena: SyntaxArena, interner: StringInterner, astArena: ASTArena) -> TypeAliasDecl {
        let node = arena.node(nodeID)
        let rawTypeParams = declarationTypeParameters(from: nodeID, in: arena, interner: interner, astArena: astArena)
        let whereClauses = declarationWhereClauses(from: nodeID, in: arena, interner: interner, astArena: astArena)
        let typeParams = applyWhereClauses(rawTypeParams, whereClauses: whereClauses)
        return TypeAliasDecl(
            range: node.range,
            name: declarationName(from: nodeID, in: arena, interner: interner),
            modifiers: declarationModifiers(from: nodeID, in: arena),
            typeParams: typeParams,
            underlyingType: declarationTypeAliasRHS(from: nodeID, in: arena, interner: interner, astArena: astArena)
        )
    }

    func declarationTypeAliasRHS(
        from nodeID: NodeID,
        in arena: SyntaxArena,
        interner: StringInterner,
        astArena: ASTArena
    ) -> TypeRefID? {
        let tokens = collectTokens(from: nodeID, in: arena)
        guard let assignIndex = tokens.firstIndex(where: { $0.kind == .symbol(.assign) }) else {
            return nil
        }
        let rhsTokens = Array(tokens[(assignIndex + 1)...]).filter { $0.kind != .symbol(.semicolon) }
        return parseTypeRef(from: rhsTokens, interner: interner, astArena: astArena)
    }

    func makeEnumEntryDecl(from nodeID: NodeID, in arena: SyntaxArena, interner: StringInterner) -> EnumEntryDecl {
        let node = arena.node(nodeID)
        return EnumEntryDecl(
            range: node.range,
            name: declarationName(from: nodeID, in: arena, interner: interner)
        )
    }

    func declarationName(from nodeID: NodeID, in arena: SyntaxArena, interner: StringInterner) -> InternedString {
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

    func declarationTypeParameters(
        from nodeID: NodeID,
        in arena: SyntaxArena,
        interner: StringInterner,
        astArena: ASTArena? = nil
    ) -> [TypeParamDecl] {
        for child in arena.children(of: nodeID) {
            if case .node(let childID) = child,
               arena.node(childID).kind == .typeArgs {
                let tokens = collectTokens(from: childID, in: arena)
                var result: [TypeParamDecl] = []
                var angleDepth = 0
                var pendingVariance: TypeVariance = .invariant
                var pendingReified = false
                var tokenIndex = 0

                while tokenIndex < tokens.count {
                    let token = tokens[tokenIndex]
                    switch token.kind {
                    case .symbol(.lessThan):
                        angleDepth += 1
                        tokenIndex += 1
                        continue
                    case .symbol(.greaterThan):
                        angleDepth = max(0, angleDepth - 1)
                        pendingVariance = .invariant
                        pendingReified = false
                        tokenIndex += 1
                        continue
                    case .symbol(.comma):
                        if angleDepth == 1 {
                            pendingVariance = .invariant
                            pendingReified = false
                        }
                        tokenIndex += 1
                        continue
                    default:
                        break
                    }

                    guard angleDepth == 1 else {
                        tokenIndex += 1
                        continue
                    }

                    switch token.kind {
                    case .softKeyword(.out):
                        pendingVariance = .out
                        tokenIndex += 1
                        continue
                    case .keyword(.in):
                        pendingVariance = .in
                        tokenIndex += 1
                        continue
                    case .keyword(.reified):
                        pendingReified = true
                        tokenIndex += 1
                        continue
                    default:
                        break
                    }

                    guard isTypeLikeNameToken(token.kind),
                          let name = internedIdentifier(from: token, interner: interner) else {
                        tokenIndex += 1
                        continue
                    }
                    if case .keyword(let keyword) = token.kind, isLeadingDeclarationKeyword(keyword) {
                        tokenIndex += 1
                        continue
                    }

                    tokenIndex += 1

                    var upperBound: TypeRefID? = nil
                    if let astArena,
                       tokenIndex < tokens.count,
                       tokens[tokenIndex].kind == .symbol(.colon) {
                        tokenIndex += 1
                        var boundTokens: [Token] = []
                        var innerDepth = BracketDepth()
                        while tokenIndex < tokens.count {
                            let t = tokens[tokenIndex]
                            if innerDepth.isAtTopLevel {
                                if t.kind == .symbol(.comma) || t.kind == .symbol(.greaterThan) {
                                    break
                                }
                            }
                            innerDepth.track(t.kind)
                            boundTokens.append(t)
                            tokenIndex += 1
                        }
                        upperBound = parseTypeRef(from: boundTokens, interner: interner, astArena: astArena)
                    }

                    result.append(TypeParamDecl(name: name, variance: pendingVariance, isReified: pendingReified, upperBound: upperBound))
                    pendingVariance = .invariant
                    pendingReified = false
                }
                return result
            }
        }
        return []
    }

    func declarationWhereClauses(
        from nodeID: NodeID,
        in arena: SyntaxArena,
        interner: StringInterner,
        astArena: ASTArena
    ) -> [(name: InternedString, bound: TypeRefID)] {
        let tokens = collectTokens(from: nodeID, in: arena)
        var whereIndex: Int? = nil
        var depth = BracketDepth()
        for (index, token) in tokens.enumerated() {
            depth.track(token.kind)
            if depth.isAtTopLevel, case .softKeyword(.where) = token.kind {
                whereIndex = index
                break
            }
        }
        guard let startIndex = whereIndex else {
            return []
        }

        var result: [(name: InternedString, bound: TypeRefID)] = []
        var index = startIndex + 1
        while index < tokens.count {
            let token = tokens[index]
            if token.kind == .symbol(.lBrace) || token.kind == .symbol(.semicolon) {
                break
            }
            guard isTypeLikeNameToken(token.kind),
                  let name = internedIdentifier(from: token, interner: interner) else {
                index += 1
                continue
            }
            index += 1
            guard index < tokens.count, tokens[index].kind == .symbol(.colon) else {
                continue
            }
            index += 1
            var boundTokens: [Token] = []
            var innerDepth = BracketDepth()
            while index < tokens.count {
                let t = tokens[index]
                if innerDepth.isAtTopLevel {
                    if t.kind == .symbol(.comma) || t.kind == .symbol(.lBrace) || t.kind == .symbol(.semicolon) {
                        break
                    }
                }
                innerDepth.track(t.kind)
                boundTokens.append(t)
                index += 1
            }
            if let boundRef = parseTypeRef(from: boundTokens, interner: interner, astArena: astArena) {
                result.append((name: name, bound: boundRef))
            }
            if index < tokens.count, tokens[index].kind == .symbol(.comma) {
                index += 1
            }
        }
        return result
    }

    func applyWhereClauses(
        _ typeParams: [TypeParamDecl],
        whereClauses: [(name: InternedString, bound: TypeRefID)]
    ) -> [TypeParamDecl] {
        guard !whereClauses.isEmpty else { return typeParams }
        return typeParams.map { param in
            if param.upperBound != nil { return param }
            guard let clause = whereClauses.first(where: { $0.name == param.name }) else {
                return param
            }
            return TypeParamDecl(
                name: param.name,
                variance: param.variance,
                isReified: param.isReified,
                upperBound: clause.bound
            )
        }
    }

    func declarationValueParameters(
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

    func appendValueParameter(
        from tokens: [Token],
        into parameters: inout [ValueParamDecl],
        interner: StringInterner,
        astArena: ASTArena
    ) {
        let split = splitDefaultValue(tokens)
        let withoutDefault = split.withoutDefault
        let hasDefaultValue = split.defaultTokens != nil
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
        let defaultValueExpr: ExprID?
        if let defaultTokens = split.defaultTokens?
            .filter({ $0.kind != .symbol(.semicolon) }),
           !defaultTokens.isEmpty {
            let parser = ExpressionParser(tokens: defaultTokens, interner: interner, astArena: astArena)
            defaultValueExpr = parser.parse()
        } else {
            defaultValueExpr = nil
        }
        parameters.append(ValueParamDecl(
            name: name,
            type: typeRef,
            hasDefaultValue: hasDefaultValue,
            isVararg: isVararg,
            defaultValue: defaultValueExpr
        ))
    }

}

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
        let members = declarationMemberDecls(from: nodeID, in: arena, interner: interner, astArena: astArena)
        return InterfaceDecl(
            range: node.range,
            name: declarationName(from: nodeID, in: arena, interner: interner),
            modifiers: declarationModifiers(from: nodeID, in: arena),
            typeParams: typeParams,
            superTypes: declarationSuperTypes(from: nodeID, in: arena, interner: interner, astArena: astArena),
            nestedTypeAliases: declarationNestedTypeAliases(from: nodeID, in: arena, interner: interner, astArena: astArena),
            memberFunctions: members.functions,
            memberProperties: members.properties,
            nestedClasses: members.nestedClasses,
            nestedObjects: members.nestedObjects
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


extension BuildASTPhase {
    /// Returns the index of the `class` keyword that introduces a class declaration,
    /// skipping `Foo::class` class-literal expressions that appear before the declaration.
    private func classDeclarationKeywordIndex(in tokens: [Token]) -> Int? {
        firstTopLevelKeywordIndex(in: tokens, matching: [.class]) { previousToken in
            previousToken.kind == .symbol(.doubleColon)
        }
    }

    private static let declarationIntroducerKeywords: Set<Keyword> = [
        .class, .object, .interface, .fun, .val, .var, .typealias, .enum, .package, .import,
    ]

    /// Scans `tokens` from the start, tracking balanced bracket depth, and
    /// returns the index of the first top-level keyword that matches one of
    /// `keywords`. This avoids treating keywords inside annotation arguments
    /// (e.g. `::class` in `@file:OptIn(...::class)`) as declaration introducers.
    /// `skippingIfPrecededBy`, when provided, rejects a match whose immediately
    /// preceding token satisfies it (e.g. `::` before `class`, to skip class-literal
    /// expressions like `Foo::class`) and keeps scanning for the next candidate.
    func firstTopLevelKeywordIndex(
        in tokens: [Token],
        matching keywords: Set<Keyword>,
        skippingIfPrecededBy isExcludedPredecessor: ((Token) -> Bool)? = nil
    ) -> Int? {
        var depth = BracketDepth()
        var previousToken: Token?
        for (index, token) in tokens.enumerated() {
            depth.track(token.kind)
            let isExcluded = previousToken.map { isExcludedPredecessor?($0) ?? false } ?? false
            if depth.isAtTopLevel,
               case let .keyword(keyword) = token.kind,
               keywords.contains(keyword),
               !isExcluded {
                return index
            }
            previousToken = token
        }
        return nil
    }

    /// Returns the index of the next top-level keyword after `startIndex`.
    func firstTopLevelKeywordIndex(
        in tokens: [Token],
        after startIndex: Int
    ) -> Int? {
        var depth = BracketDepth()
        for (index, token) in tokens.enumerated() {
            depth.track(token.kind)
            if index > startIndex,
               depth.isAtTopLevel,
               case .keyword = token.kind {
                return index
            }
        }
        return nil
    }

    func makeClassDecl(from nodeID: NodeID, in arena: SyntaxArena, interner: StringInterner, astArena: ASTArena) -> ClassDecl {
        let node = arena.node(nodeID)
        let primaryConstructorParams = declarationValueParameters(
            from: nodeID,
            in: arena,
            interner: interner,
            astArena: astArena
        )
        let members = declarationMemberDecls(from: nodeID, in: arena, interner: interner, astArena: astArena)
        let constructorProperties = primaryConstructorPropertyDecls(
            from: primaryConstructorParams,
            classRange: node.range,
            astArena: astArena,
            interner: interner
        )
        let rawTypeParams = declarationTypeParameters(from: nodeID, in: arena, interner: interner, astArena: astArena)
        let whereClauses = declarationWhereClauses(from: nodeID, in: arena, interner: interner, astArena: astArena)
        let typeParams = applyWhereClauses(rawTypeParams, whereClauses: whereClauses)
        let modifiers = declarationModifiers(from: nodeID, in: arena)
        let annotations = declarationAnnotations(from: nodeID, in: arena, interner: interner)
        return ClassDecl(
            range: node.range,
            name: declarationName(from: nodeID, in: arena, interner: interner),
            modifiers: modifiers,
            annotations: annotations,
            isInner: modifiers.contains(.inner),
            typeParams: typeParams,
            primaryConstructorParams: primaryConstructorParams,
            primaryConstructorModifiers: declarationPrimaryConstructorModifiers(
                from: nodeID, in: arena, interner: interner
            ),
            primaryConstructorAnnotations: declarationPrimaryConstructorAnnotations(from: nodeID, in: arena, interner: interner),
            hasPrimaryConstructorSyntax: declarationHasPrimaryConstructorSyntax(
                from: nodeID, in: arena, interner: interner
            ),
            superTypeEntries: declarationSuperTypeEntries(from: nodeID, in: arena, interner: interner, astArena: astArena),
            nestedTypeAliases: declarationNestedTypeAliases(from: nodeID, in: arena, interner: interner, astArena: astArena),
            enumEntries: declarationEnumEntries(from: nodeID, in: arena, interner: interner, astArena: astArena, diagnostics: diagnostics),
            initBlocks: declarationInitBlocks(from: nodeID, in: arena, interner: interner, astArena: astArena),
            classBodyInitOrder: declarationClassBodyInitOrder(
                from: nodeID, in: arena, interner: interner,
                constructorPropertyCount: constructorProperties.count
            ),
            secondaryConstructors: declarationSecondaryConstructors(from: nodeID, in: arena, interner: interner, astArena: astArena),
            memberFunctions: members.functions,
            memberProperties: constructorProperties + members.properties,
            nestedClasses: members.nestedClasses,
            nestedObjects: members.nestedObjects,
            companionObject: members.companionObject
        )
    }

    /// Scans the primary-constructor header of a class — from the class name up
    /// to `constructor`/`(`/`:`/`{` — collecting annotations and candidate modifier
    /// tokens along the way, so the two extractors below share one walk instead of
    /// each re-scanning the header independently.
    private struct PrimaryConstructorHeaderScan {
        var annotations: [AnnotationNode] = []
        var modifiers: Modifiers = []
        var sawConstructorKeyword = false
    }

    private func scanPrimaryConstructorHeader(
        classIndex: Int, in tokens: [Token], interner: StringInterner
    ) -> PrimaryConstructorHeaderScan {
        var scan = PrimaryConstructorHeaderScan()
        var index = classIndex + 1
        var sawClassName = false
        var depth = BracketDepth()
        while index < tokens.count {
            let token = tokens[index]
            if !sawClassName {
                if case .identifier = token.kind {
                    sawClassName = true
                } else if case .backtickedIdentifier = token.kind {
                    sawClassName = true
                }
                index += 1
                continue
            }
            if depth.isAtTopLevel {
                switch token.kind {
                case .keyword(.constructor), .softKeyword(.constructor):
                    scan.sawConstructorKeyword = true
                    return scan
                case .symbol(.lParen), .symbol(.colon), .symbol(.lBrace):
                    return scan
                case .symbol(.at):
                    if let parsed = AnnotationParsingSupport.parseAnnotation(
                        from: tokens, start: index, interner: interner, allowUseSiteTarget: false
                    ) {
                        scan.annotations.append(parsed.annotation)
                        index = parsed.nextIndex
                    } else {
                        index += 1
                    }
                    continue
                default:
                    break
                }
                if let modifier = modifier(from: token) {
                    scan.modifiers.insert(modifier)
                }
            }
            depth.track(token.kind)
            index += 1
        }
        return scan
    }

    /// Extracts annotations placed on the primary constructor in a class header,
    /// e.g. `class Foo @Inject constructor()`.
    private func declarationPrimaryConstructorAnnotations(
        from nodeID: NodeID, in arena: SyntaxArena, interner: StringInterner
    ) -> [AnnotationNode] {
        let tokens = collectTokens(from: nodeID, in: arena)
        guard let classIndex = classDeclarationKeywordIndex(in: tokens) else {
            return []
        }
        return scanPrimaryConstructorHeader(classIndex: classIndex, in: tokens, interner: interner).annotations
    }

    /// Extracts modifiers attached to the primary constructor declaration in a
    /// class header, e.g. `class Foo private constructor()`.
    private func declarationPrimaryConstructorModifiers(
        from nodeID: NodeID, in arena: SyntaxArena, interner: StringInterner
    ) -> Modifiers {
        let tokens = collectTokens(from: nodeID, in: arena)
        guard let classIndex = classDeclarationKeywordIndex(in: tokens) else {
            return []
        }
        let scan = scanPrimaryConstructorHeader(classIndex: classIndex, in: tokens, interner: interner)
        return scan.sawConstructorKeyword ? scan.modifiers : []
    }

    /// Detects whether the class header contains explicit constructor parentheses,
    /// distinguishing `class Foo()` from `class Foo`.
    private func declarationHasPrimaryConstructorSyntax(
        from nodeID: NodeID, in arena: SyntaxArena, interner: StringInterner
    ) -> Bool {
        let tokens = collectTokens(from: nodeID, in: arena)
        return classPrimaryConstructorOpenParenIndex(in: tokens, interner: interner) != nil
    }

    func makeInterfaceDecl(from nodeID: NodeID, in arena: SyntaxArena, interner: StringInterner, astArena: ASTArena) -> InterfaceDecl {
        let node = arena.node(nodeID)
        let rawTypeParams = declarationTypeParameters(from: nodeID, in: arena, interner: interner, astArena: astArena)
        let whereClauses = declarationWhereClauses(from: nodeID, in: arena, interner: interner, astArena: astArena)
        let typeParams = applyWhereClauses(rawTypeParams, whereClauses: whereClauses)
        let members = declarationMemberDecls(from: nodeID, in: arena, interner: interner, astArena: astArena)
        let modifiers = declarationModifiers(from: nodeID, in: arena)
        let annotations = declarationAnnotations(from: nodeID, in: arena, interner: interner)
        return InterfaceDecl(
            range: node.range,
            name: declarationName(from: nodeID, in: arena, interner: interner),
            modifiers: modifiers,
            annotations: annotations,
            isFunInterface: modifiers.contains(.funModifier),
            typeParams: typeParams,
            superTypes: declarationSuperTypes(from: nodeID, in: arena, interner: interner, astArena: astArena),
            nestedTypeAliases: declarationNestedTypeAliases(from: nodeID, in: arena, interner: interner, astArena: astArena),
            memberFunctions: members.functions,
            memberProperties: members.properties,
            nestedClasses: members.nestedClasses,
            nestedObjects: members.nestedObjects,
            companionObject: members.companionObject
        )
    }

    func makeObjectDecl(from nodeID: NodeID, in arena: SyntaxArena, interner: StringInterner, astArena: ASTArena) -> ObjectDecl {
        let node = arena.node(nodeID)
        let modifiers = declarationModifiers(from: nodeID, in: arena)
        let annotations = declarationAnnotations(from: nodeID, in: arena, interner: interner)
        let superTypeEntries = declarationSuperTypeEntries(
            from: nodeID,
            in: arena,
            interner: interner,
            astArena: astArena
        )
        let members = declarationMemberDecls(from: nodeID, in: arena, interner: interner, astArena: astArena)
        return ObjectDecl(
            range: node.range,
            name: declarationName(from: nodeID, in: arena, interner: interner),
            modifiers: modifiers,
            annotations: annotations,
            superTypes: superTypeEntries.map(\.typeRef),
            superTypeConstructorArgs: superTypeEntries.first { !$0.constructorArgs.isEmpty }?.constructorArgs ?? [],
            nestedTypeAliases: declarationNestedTypeAliases(from: nodeID, in: arena, interner: interner, astArena: astArena),
            initBlocks: declarationInitBlocks(from: nodeID, in: arena, interner: interner, astArena: astArena),
            classBodyInitOrder: declarationClassBodyInitOrder(from: nodeID, in: arena, interner: interner),
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
        let isTailrec = modifiers.contains(.tailrec)
        let functionName = declarationFunctionName(from: nodeID, in: arena, interner: interner)
        let valueParams = declarationValueParameters(from: nodeID, in: arena, interner: interner, astArena: astArena)
        let explicitReceiverType = declarationReceiverType(from: nodeID, in: arena, interner: interner, astArena: astArena)
        let contextReceiverTypes = declarationContextReceiverTypes(
            from: nodeID,
            in: arena,
            interner: interner,
            astArena: astArena
        )
        let receiverType = explicitReceiverType ?? contextReceiverTypes.first
        let returnType = declarationReturnType(from: nodeID, in: arena, interner: interner, astArena: astArena)
        let body = declarationBody(from: nodeID, in: arena, interner: interner, astArena: astArena)
        let rawTypeParams = declarationTypeParameters(from: nodeID, in: arena, interner: interner, astArena: astArena)
        let whereClauses = declarationWhereClauses(from: nodeID, in: arena, interner: interner, astArena: astArena)
        let typeParams = applyWhereClauses(rawTypeParams, whereClauses: whereClauses)
        let annotations = declarationAnnotations(from: nodeID, in: arena, interner: interner)
        return FunDecl(
            range: node.range,
            name: functionName,
            modifiers: modifiers,
            annotations: annotations,
            typeParams: typeParams,
            receiverType: receiverType,
            valueParams: valueParams,
            returnType: returnType,
            body: body,
            isSuspend: isSuspend,
            isInline: isInline,
            isTailrec: isTailrec
        )
    }

    func makePropertyDecl(from nodeID: NodeID, in arena: SyntaxArena, interner: StringInterner, astArena: ASTArena) -> PropertyDecl {
        let node = arena.node(nodeID)
        let accessors = declarationPropertyAccessors(from: nodeID, in: arena, interner: interner, astArena: astArena)
        let delegateExpr = declarationDelegateExpression(from: nodeID, in: arena, interner: interner, astArena: astArena)

        // When a delegate expression contains a trailing lambda, reuse its
        // parsed body here so KIR lowering can create the lambda function from
        // the same AST nodes as ordinary call-argument checking.
        var delegateBody: FunctionBody?
        var delegateBodyParams: [InternedString] = []
        if let delegateExpr {
            if let parsed = delegateLambda(from: delegateExpr, astArena: astArena) {
                // Reuse the lambda body already parsed as a call argument for KIR
                // lowering; reparsing the same block would create a second AST
                // copy whose bindings are not visible to the lowering path.
                delegateBodyParams = parsed.params
                delegateBody = parsed.body
            } else if let blockChildID = arena.children(of: nodeID).compactMap({ child -> NodeID? in
                guard case let .node(childID) = child, arena.node(childID).kind == .block else {
                    return nil
                }
                return childID
            }).first {
                // A parameterized trailing lambda (`{ prop, old, new -> ... }`)
                // cannot be recovered from the CST statement nodes: the
                // parameter list and the arrow form their own statement node
                // that the block-statement parser cannot make sense of. Re-parse
                // the block's tokens as a lambda literal so both the parameter
                // names and the real body statements survive.
                if let parsed = delegateLambdaFromBlockTokens(
                    blockNodeID: blockChildID, in: arena, interner: interner, astArena: astArena
                ) {
                    delegateBodyParams = parsed.params
                    delegateBody = parsed.body
                } else {
                    let exprs = blockExpressions(from: blockChildID, in: arena, interner: interner, astArena: astArena)
                    delegateBody = .block(exprs, arena.node(blockChildID).range)
                }
            }
        }

        let modifiers = declarationModifiers(from: nodeID, in: arena)
        let annotations = declarationAnnotations(from: nodeID, in: arena, interner: interner)
        let receiverType = declarationPropertyReceiverType(
            from: nodeID, in: arena, interner: interner, astArena: astArena
        )
        let propertyName: InternedString = if receiverType != nil {
            declarationPropertyNameAfterDot(from: nodeID, in: arena, interner: interner)
        } else {
            declarationPropertyName(from: nodeID, in: arena, interner: interner)
        }

        // Kotlin 2.0 explicit backing field: `field = expr` or `field: Type = expr`
        let explicitField = declarationExplicitBackingField(
            from: nodeID, in: arena, interner: interner, astArena: astArena
        )

        return PropertyDecl(
            range: node.range,
            name: propertyName,
            modifiers: modifiers,
            annotations: annotations,
            type: declarationPropertyType(from: nodeID, in: arena, interner: interner, astArena: astArena),
            isVar: declarationIsVar(from: nodeID, in: arena),
            initializer: declarationPropertyInitializer(from: nodeID, in: arena, interner: interner, astArena: astArena),
            getter: accessors.getter,
            setter: accessors.setter,
            delegateExpression: delegateExpr,
            delegateBody: delegateBody,
            delegateBodyParams: delegateBodyParams,
            receiverType: receiverType,
            explicitBackingField: explicitField
        )
    }

    /// Extracts the trailing lambda already parsed into a delegate call.
    /// Delegate lowering consumes `delegateBody`, so it must point at the same
    /// AST body that Sema checks as the call argument rather than a separately
    /// parsed copy.
    private func delegateLambda(
        from delegateExpr: ExprID,
        astArena: ASTArena
    ) -> (params: [InternedString], body: FunctionBody)? {
        let args: [CallArgument]
        switch astArena.expr(delegateExpr) {
        case let .call(_, _, callArgs, _):
            args = callArgs
        case let .memberCall(_, _, _, memberArgs, _):
            args = memberArgs
        default:
            return nil
        }

        guard let argument = args.last,
              case let .lambdaLiteral(params, bodyExprID, _, _) = astArena.expr(argument.expr)
        else {
            return nil
        }
        guard let bodyExpr = astArena.expr(bodyExprID) else { return nil }
        if case let .blockExpr(statements, trailingExpr, range) = bodyExpr {
            var expressions = statements
            if let trailingExpr {
                expressions.append(trailingExpr)
            }
            return (params, .block(expressions, range))
        }
        guard let range = astArena.exprRange(bodyExprID) else { return nil }
        return (params, .expr(bodyExprID, range))
    }

    /// Re-parses a delegate property's trailing-lambda block from its tokens so
    /// that a declared parameter list (`{ prop, old, new -> ... }`) is preserved.
    /// Returns `nil` for parameterless lambdas, which the CST statement nodes
    /// already describe correctly.
    private func delegateLambdaFromBlockTokens(
        blockNodeID: NodeID,
        in arena: SyntaxArena,
        interner: StringInterner,
        astArena: ASTArena
    ) -> (params: [InternedString], body: FunctionBody)? {
        let tokens = collectTokens(from: blockNodeID, in: arena)
        guard let last = tokens.last,
              tokens.contains(where: { $0.kind == .symbol(.arrow) })
        else {
            return nil
        }
        let eofRange = SourceRange(start: last.range.end, end: last.range.end)
        let parser = ExpressionParser(
            tokens: (tokens + [Token(kind: .eof, range: eofRange)])[...],
            interner: interner,
            astArena: astArena
        )
        guard let lambdaExprID = parser.parseLambdaLiteral(),
              let lambdaExpr = astArena.expr(lambdaExprID),
              case let .lambdaLiteral(params, bodyExprID, _, _) = lambdaExpr,
              !params.isEmpty,
              let bodyExpr = astArena.expr(bodyExprID)
        else {
            return nil
        }
        if case let .blockExpr(statements, trailingExpr, range) = bodyExpr {
            var exprs = statements
            if let trailingExpr {
                exprs.append(trailingExpr)
            }
            return (params, .block(exprs, range))
        }
        guard let range = astArena.exprRange(bodyExprID) else {
            return nil
        }
        return (params, .expr(bodyExprID, range))
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
            annotations: declarationAnnotations(from: nodeID, in: arena, interner: interner),
            typeParams: typeParams,
            underlyingType: declarationTypeAliasRHS(from: nodeID, in: arena, interner: interner, astArena: astArena)
        )
    }

    private func declarationTypeAliasRHS(
        from nodeID: NodeID,
        in arena: SyntaxArena,
        interner: StringInterner,
        astArena: ASTArena
    ) -> TypeRefID? {
        let tokens = collectTokens(from: nodeID, in: arena)
        guard let assignIndex = tokens.firstIndex(where: { $0.kind == .symbol(.assign) }) else {
            return nil
        }
        let rhsTokens = tokens[(assignIndex + 1)...].filter { $0.kind != .symbol(.semicolon) }
        return parseTypeRef(from: rhsTokens, interner: interner, astArena: astArena)
    }

    func declarationName(from nodeID: NodeID, in arena: SyntaxArena, interner: StringInterner) -> InternedString {
        let tokens = collectTokens(from: nodeID, in: arena)
        let searchTokens: ArraySlice<Token>
        if let introducerIndex = declarationIntroducerIndex(in: tokens) {
            var index = introducerIndex + 1
            if tokens[introducerIndex].kind == .keyword(.enum),
               index < tokens.count,
               tokens[index].kind == .keyword(.class)
            {
                index += 1
            }
            if tokens[introducerIndex].kind == .keyword(.fun),
               index < tokens.count,
               tokens[index].kind == .keyword(.interface)
            {
                index += 1
            }
            if tokens[introducerIndex].kind == .keyword(.fun),
               index < tokens.count,
               tokens[index].kind == .symbol(.lessThan)
            {
                index = skipBalancedBracket(
                    in: tokens,
                    from: index,
                    open: .symbol(.lessThan),
                    close: .symbol(.greaterThan)
                )
            }
            let boundaryIndex = tokens[index...].firstIndex(where: isDeclarationNameBoundaryToken) ?? tokens.count
            searchTokens = tokens[index..<boundaryIndex]
        } else {
            searchTokens = tokens[...]
        }
        return firstDeclarationName(in: searchTokens, interner: interner) ?? interner.intern("")
    }

    /// Terminators that end the name slot of a declaration header, e.g. the
    /// parameter list, class body, or delegate assignment that follows the name.
    private func isDeclarationNameBoundaryToken(_ token: Token) -> Bool {
        token.kind == .symbol(.lParen)
            || token.kind == .symbol(.lBrace)
            || token.kind == .symbol(.colon)
            || token.kind == .symbol(.assign)
            || token.kind == .symbol(.semicolon)
    }

    /// Returns the first identifier-like token in the declaration name slot.
    /// Modifier keywords are valid names once the declaration introducer has
    /// established that this is a name position.
    private func firstDeclarationName(
        in tokens: ArraySlice<Token>, interner: StringInterner
    ) -> InternedString? {
        for token in tokens {
            if let name = internedIdentifier(from: token, interner: interner) {
                return name
            }
        }
        return nil
    }

    func declarationValueParameters(
        from nodeID: NodeID,
        in arena: SyntaxArena,
        interner: StringInterner,
        astArena: ASTArena
    ) -> [ValueParamDecl] {
        let tokens = collectTokens(from: nodeID, in: arena)
        let nodeKind = arena.node(nodeID).kind
        // Only look for the opening `(` that occurs before any `{` (class body).
        // This prevents picking up `(` from member function declarations like
        // `class F { operator fun invoke(x: Int) }` as constructor parameters.
        guard let startIndex = declarationParameterOpenParenIndex(
            in: tokens, nodeKind: nodeKind, interner: interner
        ) else {
            return []
        }

        var depth = BracketDepth()
        var arguments: [ValueParamDecl] = []
        var paramTokens: [Token] = []
        var index = startIndex + 1
        while index < tokens.count {
            let token = tokens[index]
            if token.kind == .symbol(.rParen), depth.paren == 0 {
                break
            }
            depth.track(token.kind)
            if token.kind == .symbol(.comma), depth.isAtTopLevel {
                appendValueParameter(from: paramTokens, into: &arguments, interner: interner, astArena: astArena)
                paramTokens.removeAll(keepingCapacity: true)
            } else {
                paramTokens.append(token)
            }
            index += 1
        }
        if !paramTokens.isEmpty {
            appendValueParameter(from: paramTokens, into: &arguments, interner: interner, astArena: astArena)
        }
        return arguments
    }

    private func declarationIntroducerIndex(in tokens: [Token]) -> Int? {
        firstTopLevelKeywordIndex(in: tokens, matching: Self.declarationIntroducerKeywords)
    }

    private func declarationParameterOpenParenIndex(
        in tokens: [Token], nodeKind: SyntaxKind, interner: StringInterner
    ) -> Int? {
        switch nodeKind {
        case .funDecl:
            functionParameterOpenParenIndex(in: tokens)
        case .classDecl:
            classPrimaryConstructorOpenParenIndex(in: tokens, interner: interner)
        case .constructorDecl:
            constructorParameterOpenParenIndex(in: tokens)
        default:
            tokens.firstIndex(where: { token in
                token.kind == .symbol(.lParen)
            })
        }
    }

    private func classPrimaryConstructorOpenParenIndex(
        in tokens: [Token], interner: StringInterner
    ) -> Int? {
        guard let classIndex = classDeclarationKeywordIndex(in: tokens) else {
            return nil
        }
        var index = classIndex + 1
        if index < tokens.count, TypeRefParserCore.isTypeLikeNameToken(tokens[index].kind) {
            index += 1
        }
        if index < tokens.count, tokens[index].kind == .symbol(.lessThan) {
            index = skipBalancedBracket(
                in: tokens,
                from: index,
                open: .symbol(.lessThan),
                close: .symbol(.greaterThan)
            )
        }
        var depth = BracketDepth()
        while index < tokens.count {
            let token = tokens[index]
            if depth.isAtTopLevel {
                let kind = token.kind
                if kind == .symbol(.lParen) {
                    return index
                }
                if kind == .symbol(.colon) || kind == .symbol(.lBrace) || kind == .symbol(.assign) {
                    return nil
                }
                if kind == .symbol(.at) {
                    if let parsed = AnnotationParsingSupport.parseAnnotation(
                        from: tokens, start: index, interner: interner, allowUseSiteTarget: false
                    ) {
                        index = parsed.nextIndex
                    } else {
                        index += 1
                    }
                    continue
                }
            }
            depth.track(token.kind)
            index += 1
        }
        return nil
    }

    private func constructorParameterOpenParenIndex(in tokens: [Token]) -> Int? {
        guard let ctorIndex = tokens.firstIndex(where: { token in
            token.kind == .keyword(.constructor) || token.kind == .softKeyword(.constructor)
        }) else {
            return tokens.firstIndex(where: { token in
                token.kind == .symbol(.lParen)
            })
        }
        var index = ctorIndex + 1
        while index < tokens.count {
            let kind = tokens[index].kind
            if kind == .symbol(.lParen) {
                return index
            }
            if kind == .symbol(.colon) || kind == .symbol(.lBrace) {
                return nil
            }
            index += 1
        }
        return nil
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

        // Parse leading annotations (e.g. @field:FieldMark, @Deprecated("msg"))
        // and skip past them so their colons are not confused with the name:type colon.
        var parsedAnnotations: [AnnotationNode] = []
        var annotationScanIndex = 0
        while annotationScanIndex < withoutDefault.count,
              withoutDefault[annotationScanIndex].kind == .symbol(.at) {
            if let parsed = AnnotationParsingSupport.parseAnnotation(
                from: withoutDefault, start: annotationScanIndex, interner: interner, allowUseSiteTarget: true
            ) {
                parsedAnnotations.append(parsed.annotation)
                annotationScanIndex = parsed.nextIndex
            } else {
                annotationScanIndex += 1
            }
        }
        let afterAnnotations = annotationScanIndex

        let colonIndex = withoutDefault[afterAnnotations...].firstIndex(where: { token in
            if case .symbol(.colon) = token.kind {
                return true
            }
            return false
        })

        let nameSearchTokens: ArraySlice<Token> = if let colonIndex {
            withoutDefault[..<colonIndex]
        } else {
            withoutDefault[...]
        }

        // A modifier keyword (`inner`, `sealed`, `vararg`, `override`, ...) is only
        // acting as a modifier when something else follows it in the name slot; when
        // it's the rightmost candidate before the colon, it IS the parameter name
        // (Kotlin modifier keywords are valid plain identifiers outside modifier
        // position). `lastIndex(where:)` already finds that rightmost candidate, so
        // no separate keyword-exclusion pass is needed here.
        guard let nameIndex = nameSearchTokens.lastIndex(where: { token in
            internedIdentifier(from: token, interner: interner) != nil
        }) else {
            return
        }
        let nameToken = nameSearchTokens[nameIndex]
        guard let name = internedIdentifier(from: nameToken, interner: interner) else {
            return
        }

        let typeRef: TypeRefID?
        if let colonIndex {
            let typeTokens = Array(withoutDefault[(colonIndex + 1)...])
            typeRef = parseTypeRef(from: typeTokens, interner: interner, astArena: astArena)
        } else {
            typeRef = nil
        }

        // Only the modifier-prefix zone (tokens strictly before the resolved name)
        // can carry real `vararg`/`crossinline`/`noinline`/`override`/`val`/`var`
        // modifiers; scanning the full token list would misfire when the parameter
        // is simply named one of these keywords (e.g. `val override: Int`).
        let modifierPrefixTokens = withoutDefault[..<nameIndex]
        var candidateModifiers: Modifiers = []
        for token in modifierPrefixTokens {
            if let candidate = modifier(from: token) {
                candidateModifiers.insert(candidate)
            }
        }
        let isVararg = candidateModifiers.contains(.vararg)
        let isCrossinline = candidateModifiers.contains(.crossinline)
        let isNoinline = candidateModifiers.contains(.noinline)
        let isOverrideProperty = candidateModifiers.contains(.override)
        let isValProperty = modifierPrefixTokens.contains(where: { $0.kind == .keyword(.val) })
        let isVarProperty = modifierPrefixTokens.contains(where: { $0.kind == .keyword(.var) })
        let defaultValueExpr: ExprID?
        if let defaultTokens = split.defaultTokens?
            .filter({ $0.kind != .symbol(.semicolon) }),
            !defaultTokens.isEmpty
        {
            let parser = ExpressionParser(tokens: defaultTokens, interner: interner, astArena: astArena)
            defaultValueExpr = parser.parse()
        } else {
            defaultValueExpr = nil
        }
        parameters.append(ValueParamDecl(
            name: name,
            type: typeRef,
            isProperty: isValProperty || isVarProperty,
            isMutableProperty: isVarProperty,
            isOverrideProperty: isOverrideProperty,
            hasDefaultValue: hasDefaultValue,
            isVararg: isVararg,
            isCrossinline: isCrossinline,
            isNoinline: isNoinline,
            defaultValue: defaultValueExpr,
            annotations: parsedAnnotations
        ))
    }

    private func primaryConstructorPropertyDecls(
        from params: [ValueParamDecl],
        classRange: SourceRange,
        astArena: ASTArena,
        interner: StringInterner
    ) -> [DeclID] {
        params.compactMap { param in
            guard param.isProperty else {
                return nil
            }
            // A vararg parameter is lowered as an element-typed parameter for
            // call resolution, but its constructor property is Array<out T>.
            let propertyType: TypeRefID? = if param.isVararg, let elementType = param.type {
                astArena.appendTypeRef(.named(
                    path: [interner.intern("Array")],
                    args: [.out(elementType)],
                    nullable: false
                ))
            } else {
                param.type
            }
            let property = PropertyDecl(
                range: classRange,
                name: param.name,
                modifiers: param.isOverrideProperty ? [.override] : [],
                type: propertyType,
                isVar: param.isMutableProperty,
                isSynthesizedPrimaryConstructorProperty: true
            )
            return astArena.appendDecl(.propertyDecl(property))
        }
    }
}

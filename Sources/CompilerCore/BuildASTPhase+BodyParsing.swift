import Foundation

extension BuildASTPhase {
    func declarationIsVar(from nodeID: NodeID, in arena: SyntaxArena) -> Bool {
        for child in arena.children(of: nodeID) {
            if case .token(let tokenID) = child,
               let token = resolveToken(tokenID, in: arena),
               token.kind == .keyword(.var) {
                return true
            }
        }
        return false
    }

    func declarationPropertyInitializer(
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

    func declarationPropertyAccessors(
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
                  isStatementLikeKind(arena.node(statementID).kind) else {
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

    func declarationInitBlocks(
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
                      isStatementLikeKind(arena.node(statementID).kind) else {
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

    func declarationSecondaryConstructors(
        from nodeID: NodeID,
        in arena: SyntaxArena,
        interner: StringInterner,
        astArena: ASTArena
    ) -> [ConstructorDecl] {
        var result: [ConstructorDecl] = []
        for child in arena.children(of: nodeID) {
            guard case .node(let bodyBlockID) = child,
                  arena.node(bodyBlockID).kind == .block else {
                continue
            }
            for bodyChild in arena.children(of: bodyBlockID) {
                guard case .node(let ctorNodeID) = bodyChild,
                      arena.node(ctorNodeID).kind == .constructorDecl else {
                    continue
                }
                let ctorNode = arena.node(ctorNodeID)
                let params = declarationValueParameters(from: ctorNodeID, in: arena, interner: interner, astArena: astArena)
                let delegationCall = extractDelegationCall(from: ctorNodeID, in: arena, interner: interner, astArena: astArena)
                let body: FunctionBody
                if let blockID = arena.children(of: ctorNodeID).compactMap({ child -> NodeID? in
                    guard case .node(let id) = child, arena.node(id).kind == .block else { return nil }
                    return id
                }).first {
                    let exprs = blockExpressions(from: blockID, in: arena, interner: interner, astArena: astArena)
                    body = .block(exprs, arena.node(blockID).range)
                } else {
                    body = .unit
                }
                result.append(ConstructorDecl(
                    range: ctorNode.range,
                    modifiers: declarationModifiers(from: ctorNodeID, in: arena),
                    valueParams: params,
                    delegationCall: delegationCall,
                    body: body
                ))
            }
        }
        return result
    }

    func extractDelegationCall(
        from nodeID: NodeID,
        in arena: SyntaxArena,
        interner: StringInterner,
        astArena: ASTArena
    ) -> ConstructorDelegationCall? {
        let tokens = collectTokens(from: nodeID, in: arena)
        var index = 0
        var parenDepth = 0
        var foundFirstParens = false
        while index < tokens.count {
            let token = tokens[index]
            if token.kind == .symbol(.lParen) {
                parenDepth += 1
                if !foundFirstParens {
                    foundFirstParens = true
                }
            }
            if token.kind == .symbol(.rParen) {
                parenDepth -= 1
                if parenDepth == 0 && foundFirstParens {
                    index += 1
                    break
                }
            }
            index += 1
        }

        guard index < tokens.count else { return nil }

        if tokens[index].kind == .symbol(.colon) {
            index += 1
        }

        guard index < tokens.count else { return nil }

        let kind: ConstructorDelegationKind
        if tokens[index].kind == .keyword(.this) {
            kind = .this
            index += 1
        } else if tokens[index].kind == .keyword(.super) {
            kind = .super_
            index += 1
        } else {
            return nil
        }

        let range = tokens[index - 1].range

        var args: [CallArgument] = []
        if index < tokens.count, tokens[index].kind == .symbol(.lParen) {
            index += 1
            var argTokens: [Token] = []
            var depth = 0
            while index < tokens.count {
                let t = tokens[index]
                if t.kind == .symbol(.lParen) { depth += 1 }
                if t.kind == .symbol(.rParen) {
                    if depth == 0 { index += 1; break }
                    depth -= 1
                }
                if t.kind == .symbol(.comma) && depth == 0 {
                    if !argTokens.isEmpty {
                        let parser = ExpressionParser(tokens: argTokens, interner: interner, astArena: astArena)
                        if let exprID = parser.parse() {
                            args.append(CallArgument(expr: exprID))
                        }
                        argTokens.removeAll(keepingCapacity: true)
                    }
                } else {
                    argTokens.append(t)
                }
                index += 1
            }
            if !argTokens.isEmpty {
                let parser = ExpressionParser(tokens: argTokens, interner: interner, astArena: astArena)
                if let exprID = parser.parse() {
                    args.append(CallArgument(expr: exprID))
                }
            }
        }

        return ConstructorDelegationCall(kind: kind, args: args, range: range)
    }

    func setterParameterName(
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

    func accessorBody(
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


    func declarationBody(
        from nodeID: NodeID,
        in arena: SyntaxArena,
        interner: StringInterner,
        astArena: ASTArena
    ) -> FunctionBody {
        let directTokens = collectDirectTokens(from: nodeID, in: arena)
        let hasExpressionBody = directTokens.contains(where: { token in
            token.kind == .symbol(.assign)
        })

        if !hasExpressionBody {
            for child in arena.children(of: nodeID) {
                if case .node(let childID) = child, arena.node(childID).kind == .block {
                    let exprs = blockExpressions(from: childID, in: arena, interner: interner, astArena: astArena)
                    return .block(exprs, arena.node(childID).range)
                }
            }
        }

        let tokens = collectTokens(from: nodeID, in: arena)
        var assignIndex: Int?
        var depth = BracketDepth()
        for (index, token) in tokens.enumerated() {
            if token.kind == .symbol(.assign) && depth.isAtTopLevel {
                assignIndex = index
                break
            }
            depth.track(token.kind)
        }
        guard let assignIndex else {
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

    func blockExpressions(
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
            guard isStatementLikeKind(node.kind) else {
                continue
            }
            let rawTokens = collectTokens(from: nodeID, in: arena)
            let statementTokens = rawTokens.filter { token in
                token.kind != .symbol(.semicolon)
            }
            guard !statementTokens.isEmpty else {
                continue
            }
            if let localFunDeclExpr = parseLocalFunDeclExpr(
                from: rawTokens,
                interner: interner,
                astArena: astArena
            ) {
                result.append(localFunDeclExpr)
                continue
            }
            if let localDeclExpr = parseLocalDeclarationExpr(
                from: statementTokens,
                interner: interner,
                astArena: astArena
            ) {
                result.append(localDeclExpr)
                continue
            }
            if let localAssignExpr = parseLocalAssignmentExpr(
                from: statementTokens,
                interner: interner,
                astArena: astArena
            ) {
                result.append(localAssignExpr)
                continue
            }
            let parser = ExpressionParser(tokens: statementTokens, interner: interner, astArena: astArena)
            if let exprID = parser.parse() {
                result.append(exprID)
            }
        }
        return result
    }

    func parseLocalDeclarationExpr(
        from statementTokens: [Token],
        interner: StringInterner,
        astArena: ASTArena
    ) -> ExprID? {
        guard let head = statementTokens.first else {
            return nil
        }
        let isMutable: Bool
        switch head.kind {
        case .keyword(.val):
            isMutable = false
        case .keyword(.var):
            isMutable = true
        default:
            return nil
        }

        guard let nameToken = statementTokens.dropFirst().first(where: { token in
            isTypeLikeNameToken(token.kind)
        }),
              let name = internedIdentifier(from: nameToken, interner: interner) else {
            return nil
        }

        var assignIndex: Int?
        var depth = BracketDepth()
        for (index, token) in statementTokens.enumerated() {
            if token.kind == .symbol(.assign) && depth.isAtTopLevel {
                assignIndex = index
                break
            }
            depth.track(token.kind)
        }
        guard let assignIndex else {
            return nil
        }
        let initializerTokens = statementTokens[(assignIndex + 1)...].filter { token in
            token.kind != .symbol(.semicolon)
        }
        guard !initializerTokens.isEmpty else {
            return nil
        }
        let parser = ExpressionParser(tokens: Array(initializerTokens), interner: interner, astArena: astArena)
        guard let initializerExpr = parser.parse() else {
            return nil
        }
        let end = astArena.exprRange(initializerExpr)?.end ?? statementTokens.last?.range.end ?? head.range.end
        let range = SourceRange(start: head.range.start, end: end)
        return astArena.appendExpr(.localDecl(
            name: name,
            isMutable: isMutable,
            initializer: initializerExpr,
            range: range
        ))
    }

    func parseLocalAssignmentExpr(
        from statementTokens: [Token],
        interner: StringInterner,
        astArena: ASTArena
    ) -> ExprID? {
        if let compoundExpr = parseCompoundAssignmentExpr(
            from: statementTokens, interner: interner, astArena: astArena
        ) {
            return compoundExpr
        }

        var assignIndex: Int?
        var depth = BracketDepth()
        for (index, token) in statementTokens.enumerated() {
            if token.kind == .symbol(.assign) && depth.isAtTopLevel {
                assignIndex = index
                break
            }
            depth.track(token.kind)
        }
        guard let assignIndex, assignIndex > 0 else {
            return nil
        }

        let lhsTokens = statementTokens[..<assignIndex].filter { token in
            token.kind != .symbol(.semicolon)
        }
        guard !lhsTokens.isEmpty else {
            return nil
        }

        let valueTokens = statementTokens[(assignIndex + 1)...].filter { token in
            token.kind != .symbol(.semicolon)
        }
        guard !valueTokens.isEmpty else {
            return nil
        }

        let lhsParser = ExpressionParser(tokens: Array(lhsTokens), interner: interner, astArena: astArena)
        guard let lhsExpr = lhsParser.parse() else {
            return nil
        }
        let parser = ExpressionParser(tokens: Array(valueTokens), interner: interner, astArena: astArena)
        guard let valueExpr = parser.parse() else {
            return nil
        }
        guard let lhs = astArena.expr(lhsExpr),
              let lhsRange = astArena.exprRange(lhsExpr) else {
            return nil
        }
        let end = astArena.exprRange(valueExpr)?.end ?? statementTokens.last?.range.end ?? lhsRange.end
        let range = SourceRange(start: lhsRange.start, end: end)

        switch lhs {
        case .nameRef(let name, _):
            let nameText = interner.resolve(name)
            if nameText == "val" || nameText == "var" {
                return nil
            }
            return astArena.appendExpr(.localAssign(name: name, value: valueExpr, range: range))

        case .arrayAccess(let array, let index, _):
            return astArena.appendExpr(.arrayAssign(array: array, index: index, value: valueExpr, range: range))

        default:
            return nil
        }
    }

    func parseCompoundAssignmentExpr(
        from statementTokens: [Token],
        interner: StringInterner,
        astArena: ASTArena
    ) -> ExprID? {
        let compoundOps: [(TokenKind, CompoundAssignOp)] = [
            (.symbol(.plusAssign), .plusAssign),
            (.symbol(.minusAssign), .minusAssign),
            (.symbol(.starAssign), .timesAssign),
            (.symbol(.slashAssign), .divAssign),
            (.symbol(.percentAssign), .modAssign),
        ]

        var foundIndex: Int?
        var foundOp: CompoundAssignOp?
        var depth = BracketDepth()
        for (index, token) in statementTokens.enumerated() {
            for (kind, op) in compoundOps {
                if token.kind == kind && depth.isAtTopLevel {
                    foundIndex = index
                    foundOp = op
                    break
                }
            }
            if foundIndex != nil { break }
            depth.track(token.kind)
        }

        guard let assignIndex = foundIndex, let op = foundOp, assignIndex > 0 else {
            return nil
        }

        let lhsTokens = statementTokens[..<assignIndex].filter { $0.kind != .symbol(.semicolon) }
        guard !lhsTokens.isEmpty else { return nil }

        let valueTokens = statementTokens[(assignIndex + 1)...].filter { $0.kind != .symbol(.semicolon) }
        guard !valueTokens.isEmpty else { return nil }

        let lhsParser = ExpressionParser(tokens: Array(lhsTokens), interner: interner, astArena: astArena)
        guard let lhsExpr = lhsParser.parse(),
              let lhs = astArena.expr(lhsExpr),
              case .nameRef(let name, _) = lhs,
              let lhsRange = astArena.exprRange(lhsExpr) else {
            return nil
        }

        let parser = ExpressionParser(tokens: Array(valueTokens), interner: interner, astArena: astArena)
        guard let valueExpr = parser.parse() else { return nil }

        let end = astArena.exprRange(valueExpr)?.end ?? statementTokens.last?.range.end ?? lhsRange.end
        let range = SourceRange(start: lhsRange.start, end: end)
        return astArena.appendExpr(.compoundAssign(op: op, name: name, value: valueExpr, range: range))
    }

    func parseLocalFunDeclExpr(
        from statementTokens: [Token],
        interner: StringInterner,
        astArena: ASTArena
    ) -> ExprID? {
        guard let head = statementTokens.first,
              case .keyword(.fun) = head.kind else {
            return nil
        }

        guard let nameToken = statementTokens.dropFirst().first(where: { token in
            isTypeLikeNameToken(token.kind)
        }),
              let name = internedIdentifier(from: nameToken, interner: interner) else {
            return nil
        }

        guard let lParenIndex = statementTokens.firstIndex(where: { $0.kind == .symbol(.lParen) }) else {
            return nil
        }

        var valueParams: [ValueParamDecl] = []
        var depth = 0
        var paramTokens: [Token] = []
        var index = lParenIndex + 1
        while index < statementTokens.count {
            let token = statementTokens[index]
            if token.kind == .symbol(.lParen) {
                depth += 1
                paramTokens.append(token)
            } else if token.kind == .symbol(.rParen) {
                if depth == 0 {
                    break
                }
                depth -= 1
                paramTokens.append(token)
            } else if token.kind == .symbol(.comma) && depth == 0 {
                appendValueParameter(from: paramTokens, into: &valueParams, interner: interner, astArena: astArena)
                paramTokens.removeAll(keepingCapacity: true)
            } else {
                paramTokens.append(token)
            }
            index += 1
        }
        if !paramTokens.isEmpty {
            appendValueParameter(from: paramTokens, into: &valueParams, interner: interner, astArena: astArena)
        }

        guard index < statementTokens.count, statementTokens[index].kind == .symbol(.rParen) else {
            return nil
        }
        index += 1

        var returnType: TypeRefID?
        if index < statementTokens.count, statementTokens[index].kind == .symbol(.colon) {
            index += 1
            var typeTokens: [Token] = []
            var typeDepth = BracketDepth()
            while index < statementTokens.count {
                let token = statementTokens[index]
                if typeDepth.isAtTopLevel {
                    if token.kind == .symbol(.lBrace) || token.kind == .symbol(.assign) {
                        break
                    }
                }
                typeDepth.track(token.kind)
                typeTokens.append(token)
                index += 1
            }
            returnType = parseTypeRef(from: typeTokens, interner: interner, astArena: astArena)
        }

        let body: FunctionBody
        if index < statementTokens.count, statementTokens[index].kind == .symbol(.assign) {
            index += 1
            let exprTokens = Array(statementTokens[index...]).filter { $0.kind != .symbol(.semicolon) }
            let parser = ExpressionParser(tokens: exprTokens, interner: interner, astArena: astArena)
            if let exprID = parser.parse(), let exprRange = astArena.exprRange(exprID) {
                body = .expr(exprID, exprRange)
            } else {
                body = .unit
            }
        } else if index < statementTokens.count, statementTokens[index].kind == .symbol(.lBrace) {
            var braceDepth = 0
            var bodyTokens: [Token] = []
            let braceStart = index
            while index < statementTokens.count {
                let token = statementTokens[index]
                if token.kind == .symbol(.lBrace) {
                    braceDepth += 1
                } else if token.kind == .symbol(.rBrace) {
                    braceDepth -= 1
                    if braceDepth == 0 {
                        index += 1
                        break
                    }
                }
                if braceDepth >= 1 && !(braceDepth == 1 && token.kind == .symbol(.lBrace)) {
                    bodyTokens.append(token)
                }
                index += 1
            }
            if !bodyTokens.isEmpty {
                let stmtGroups = splitTokensIntoStatements(bodyTokens)
                var blockExprs: [ExprID] = []
                for stmtTokens in stmtGroups {
                    let filtered = stmtTokens.filter { $0.kind != .symbol(.semicolon) }
                    guard !filtered.isEmpty else { continue }
                    if let localFun = parseLocalFunDeclExpr(from: stmtTokens, interner: interner, astArena: astArena) {
                        blockExprs.append(localFun)
                    } else if let localDecl = parseLocalDeclarationExpr(from: filtered, interner: interner, astArena: astArena) {
                        blockExprs.append(localDecl)
                    } else if let localAssign = parseLocalAssignmentExpr(from: filtered, interner: interner, astArena: astArena) {
                        blockExprs.append(localAssign)
                    } else {
                        let parser = ExpressionParser(tokens: filtered, interner: interner, astArena: astArena)
                        if let exprID = parser.parse() {
                            blockExprs.append(exprID)
                        }
                    }
                }
                if !blockExprs.isEmpty,
                   let firstRange = astArena.exprRange(blockExprs.first!),
                   let lastRange = astArena.exprRange(blockExprs.last!) {
                    let bodyRange = SourceRange(start: firstRange.start, end: lastRange.end)
                    body = .block(blockExprs, bodyRange)
                } else {
                    let bodyRange = SourceRange(
                        start: statementTokens[braceStart].range.start,
                        end: statementTokens[min(index, statementTokens.count - 1)].range.end
                    )
                    body = .block([], bodyRange)
                }
            } else {
                let bodyRange = SourceRange(
                    start: statementTokens[braceStart].range.start,
                    end: statementTokens[min(index, statementTokens.count - 1)].range.end
                )
                body = .block([], bodyRange)
            }
        } else {
            body = .unit
        }

        let end: SourceLocation
        switch body {
        case .block(_, let range):
            end = range.end
        case .expr(_, let range):
            end = range.end
        case .unit:
            end = statementTokens.last?.range.end ?? head.range.end
        }
        let range = SourceRange(start: head.range.start, end: end)
        return astArena.appendExpr(.localFunDecl(
            name: name,
            valueParams: valueParams,
            returnType: returnType,
            body: body,
            range: range
        ))
    }

    func splitTokensIntoStatements(_ tokens: [Token]) -> [[Token]] {
        var groups: [[Token]] = []
        var current: [Token] = []
        var depth = BracketDepth()
        for token in tokens {
            if depth.isAtTopLevel {
                if token.kind == .symbol(.semicolon) {
                    if !current.isEmpty {
                        groups.append(current)
                        current = []
                    }
                    continue
                }
                let hasNewline = token.leadingTrivia.contains { piece in
                    if case .newline = piece { return true }
                    return false
                }
                if hasNewline && !current.isEmpty {
                    let lastIsContinuation = current.last.map { isBinaryOperatorToken($0.kind) } ?? false
                    let nextIsContinuation = isBinaryOperatorToken(token.kind)
                    if !lastIsContinuation && !nextIsContinuation {
                        groups.append(current)
                        current = []
                    }
                }
            }
            depth.track(token.kind)
            current.append(token)
        }
        if !current.isEmpty {
            groups.append(current)
        }
        return groups
    }

    func isBinaryOperatorToken(_ kind: TokenKind) -> Bool {
        switch kind {
        case .symbol(.plus), .symbol(.minus), .symbol(.star), .symbol(.slash), .symbol(.percent),
             .symbol(.ampAmp), .symbol(.barBar),
             .symbol(.equalEqual), .symbol(.bangEqual),
             .symbol(.lessThan), .symbol(.lessOrEqual), .symbol(.greaterThan), .symbol(.greaterOrEqual),
             .symbol(.assign), .symbol(.plusAssign), .symbol(.minusAssign),
             .symbol(.starAssign), .symbol(.slashAssign), .symbol(.percentAssign),
             .symbol(.dotDot), .symbol(.dotDotLt),
             .symbol(.questionQuestion), .symbol(.questionColon),
             .symbol(.dot), .symbol(.questionDot),
             .symbol(.arrow), .symbol(.fatArrow),
             .keyword(.as), .keyword(.is), .keyword(.in),
             .keyword(.else), .keyword(.catch), .keyword(.finally):
            return true
        default:
            return false
        }
    }

    func skipBalancedBracket(
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

    func resolveToken(_ tokenID: TokenID, in arena: SyntaxArena) -> Token? {
        let index = Int(tokenID.rawValue)
        guard index >= 0 && index < arena.tokens.count else {
            return nil
        }
        return arena.tokens[index]
    }

    func collectTokens(from nodeID: NodeID, in arena: SyntaxArena) -> [Token] {
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

    func collectDirectTokens(from nodeID: NodeID, in arena: SyntaxArena) -> [Token] {
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

    func isStatementLikeKind(_ kind: SyntaxKind) -> Bool {
        switch kind {
        case .statement, .propertyDecl, .loopStmt,
             .ifExpr, .whenExpr, .tryExpr, .callExpr,
             .funDecl:
            return true
        default:
            return false
        }
    }

}

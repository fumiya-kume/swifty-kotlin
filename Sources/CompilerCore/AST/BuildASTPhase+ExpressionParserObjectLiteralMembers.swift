import Foundation

extension BuildASTPhase.ExpressionParser {
    func parseObjectLiteralDecl(
        superTypes: [TypeRefID],
        bodyTokens: [Token],
        range: SourceRange
    ) -> DeclID? {
        let statementRanges = objectLiteralMemberRanges(in: bodyTokens)
        guard !statementRanges.isEmpty else {
            return nil
        }

        var propertyDeclIDs: [DeclID] = []
        for (start, end) in statementRanges {
            let group = bodyTokens[start ..< end]
            guard !group.isEmpty else {
                continue
            }
            guard let propertyDecl = parseObjectLiteralPropertyDecl(from: group) else {
                return nil
            }
            propertyDeclIDs.append(astArena.appendDecl(.propertyDecl(propertyDecl)))
        }

        guard !propertyDeclIDs.isEmpty else {
            return nil
        }

        let syntheticName = interner.intern(
            "__ObjectLiteral_\(range.start.file.rawValue)_\(range.start.offset)_\(range.end.offset)"
        )
        let objectDecl = ObjectDecl(
            range: range,
            name: syntheticName,
            modifiers: [.private],
            superTypes: superTypes,
            memberProperties: propertyDeclIDs
        )
        return astArena.appendDecl(.objectDecl(objectDecl))
    }

    private func objectLiteralMemberRanges(in tokens: [Token]) -> [(Int, Int)] {
        let baseRanges = splitBlockTokensIntoStatementRanges(tokens)
        guard !baseRanges.isEmpty else {
            return []
        }

        var merged: [(Int, Int)] = []
        for (start, end) in baseRanges {
            guard start < end else {
                continue
            }
            let currentGroup = tokens[start ..< end]
            if !merged.isEmpty,
               objectLiteralRangeStartsWithAccessor(currentGroup)
               || (objectLiteralRangeStartsWithBlock(currentGroup)
                   && objectLiteralRangeNeedsBraceContinuation(tokens[merged[merged.count - 1].0 ..< merged[merged.count - 1].1]))
            {
                merged[merged.count - 1].1 = end
                continue
            }
            merged.append((start, end))
        }
        return merged
    }

    private func parseObjectLiteralPropertyDecl(from tokens: ArraySlice<Token>) -> PropertyDecl? {
        let sanitized = tokens.filter { $0.kind != .symbol(.semicolon) }
        guard let first = sanitized.first, let last = sanitized.last else {
            return nil
        }

        let propertyRange = SourceRange(start: first.range.start, end: last.range.end)
        guard let prefix = parseObjectLiteralPropertyPrefix(from: sanitized) else {
            return nil
        }

        let suffixTokens = Array(sanitized.dropFirst(prefix.endIndex))
        var getter: PropertyAccessorDecl?
        var setter: PropertyAccessorDecl?
        var delegateExpression: ExprID?
        var delegateBody: FunctionBody?

        if !suffixTokens.isEmpty {
            switch suffixTokens[0].kind {
            case .softKeyword(.by):
                let delegateTokens = Array(suffixTokens.dropFirst()).filter { $0.kind != .symbol(.semicolon) }
                guard let parsedDelegateExpr = parseObjectLiteralExpression(from: delegateTokens) else {
                    return nil
                }
                delegateExpression = parsedDelegateExpr
                delegateBody = objectLiteralDelegateBody(from: parsedDelegateExpr)

            case .softKeyword(.get), .softKeyword(.set):
                guard let accessors = parseObjectLiteralAccessors(from: suffixTokens) else {
                    return nil
                }
                getter = accessors.getter
                setter = accessors.setter

            default:
                return nil
            }
        }

        return PropertyDecl(
            range: propertyRange,
            name: prefix.name,
            modifiers: [],
            type: prefix.typeAnnotation,
            isVar: prefix.isMutable,
            initializer: prefix.initializer,
            getter: getter,
            setter: setter,
            delegateExpression: delegateExpression,
            delegateBody: delegateBody
        )
    }

    private func parseObjectLiteralPropertyPrefix(
        from tokens: [Token]
    ) -> (name: InternedString, isMutable: Bool, typeAnnotation: TypeRefID?, initializer: ExprID?, endIndex: Int)? {
        var searchIndex = 0
        while let accessorIndex = topLevelAccessorStartIndex(in: tokens, from: searchIndex) {
            if let prefix = parseObjectLiteralLocalDeclPrefix(from: tokens[..<accessorIndex], endIndex: accessorIndex) {
                return prefix
            }
            searchIndex = accessorIndex + 1
        }

        if let delegateIndex = topLevelDelegateIndex(in: tokens) {
            if let prefix = parseObjectLiteralLocalDeclPrefix(from: tokens[..<delegateIndex], endIndex: delegateIndex) {
                return prefix
            }
            if let bareHeader = parseObjectLiteralBareHeader(from: Array(tokens[..<delegateIndex])) {
                return (bareHeader.name, bareHeader.isMutable, bareHeader.typeAnnotation, nil, delegateIndex)
            }
        }

        return parseObjectLiteralLocalDeclPrefix(from: tokens[...], endIndex: tokens.count)
    }

    private func parseObjectLiteralLocalDeclPrefix(
        from tokens: ArraySlice<Token>,
        endIndex: Int
    ) -> (name: InternedString, isMutable: Bool, typeAnnotation: TypeRefID?, initializer: ExprID?, endIndex: Int)? {
        guard !tokens.isEmpty,
              let localDeclExprID = parseLocalDeclFromSlice(tokens),
              let localDeclExpr = astArena.expr(localDeclExprID),
              case let .localDecl(name, isMutable, typeAnnotation, initializer, _, _) = localDeclExpr
        else {
            return nil
        }
        return (name, isMutable, typeAnnotation, initializer, endIndex)
    }

    private func parseObjectLiteralBareHeader(
        from tokens: [Token]
    ) -> (name: InternedString, isMutable: Bool, typeAnnotation: TypeRefID?)? {
        let sanitized = tokens.filter { $0.kind != .symbol(.semicolon) }
        guard sanitized.count >= 2 else {
            return nil
        }

        let isMutable: Bool
        switch sanitized[0].kind {
        case .keyword(.val):
            isMutable = false
        case .keyword(.var):
            isMutable = true
        default:
            return nil
        }

        guard let name = objectLiteralDeclarationName(from: sanitized[1]) else {
            return nil
        }

        guard sanitized.count > 2 else {
            return (name, isMutable, nil)
        }
        guard sanitized[2].kind == .symbol(.colon) else {
            return nil
        }

        let typeTokens = Array(sanitized.dropFirst(3))
        guard !typeTokens.isEmpty,
              let typeStart = typeTokens.first?.range,
              let typeRef = BuildASTPhase.ExpressionParser(
                  tokens: typeTokens[...],
                  interner: interner,
                  astArena: astArena
              ).parseTypeReference(typeStart)
        else {
            return nil
        }
        return (name, isMutable, typeRef)
    }

    private func parseObjectLiteralAccessors(
        from tokens: [Token]
    ) -> (getter: PropertyAccessorDecl?, setter: PropertyAccessorDecl?)? {
        var getter: PropertyAccessorDecl?
        var setter: PropertyAccessorDecl?
        var index = 0

        while index < tokens.count {
            guard let accessorStart = topLevelAccessorStartIndex(in: tokens, from: index),
                  accessorStart == index
            else {
                return nil
            }

            let kind: PropertyAccessorKind
            switch tokens[accessorStart].kind {
            case .softKeyword(.get):
                kind = .getter
            case .softKeyword(.set):
                kind = .setter
            default:
                return nil
            }

            let openParenIndex = accessorStart + 1
            guard openParenIndex < tokens.count,
                  tokens[openParenIndex].kind == .symbol(.lParen),
                  let closeParenIndex = matchingParenIndex(in: tokens, openIndex: openParenIndex)
            else {
                return nil
            }

            let parameterName: InternedString? = if kind == .setter {
                objectLiteralSetterParameterName(from: Array(tokens[openParenIndex ... closeParenIndex]))
            } else {
                nil
            }

            guard let body = parseObjectLiteralAccessorBody(in: tokens, startIndex: closeParenIndex + 1) else {
                return nil
            }
            let rangeEndIndex = body.nextIndex > accessorStart
                ? min(body.nextIndex - 1, tokens.count - 1)
                : closeParenIndex
            let accessorRange = SourceRange(
                start: tokens[accessorStart].range.start,
                end: tokens[rangeEndIndex].range.end
            )
            let accessor = PropertyAccessorDecl(
                range: accessorRange,
                kind: kind,
                parameterName: parameterName,
                body: body.functionBody
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
            index = body.nextIndex
        }

        return (getter, setter)
    }

    private func parseObjectLiteralAccessorBody(
        in tokens: [Token],
        startIndex: Int
    ) -> (functionBody: FunctionBody, nextIndex: Int)? {
        guard startIndex <= tokens.count else {
            return nil
        }
        if startIndex == tokens.count {
            return (.unit, startIndex)
        }

        switch tokens[startIndex].kind {
        case .symbol(.assign):
            let exprStart = startIndex + 1
            let nextAccessorIndex = topLevelAccessorStartIndex(in: tokens, from: exprStart) ?? tokens.count
            let exprTokens = Array(tokens[exprStart ..< nextAccessorIndex]).filter { $0.kind != .symbol(.semicolon) }
            guard let exprID = parseObjectLiteralExpression(from: exprTokens),
                  let range = astArena.exprRange(exprID)
            else {
                return nil
            }
            return (.expr(exprID, range), nextAccessorIndex)

        case .symbol(.lBrace):
            guard let blockEndIndex = matchingBraceIndex(in: tokens, openIndex: startIndex),
                  let blockBody = parseObjectLiteralBlockBody(from: Array(tokens[startIndex ... blockEndIndex]))
            else {
                return nil
            }
            return (blockBody, blockEndIndex + 1)

        default:
            if let nextAccessorIndex = topLevelAccessorStartIndex(in: tokens, from: startIndex),
               nextAccessorIndex == startIndex
            {
                return (.unit, startIndex)
            }
            return nil
        }
    }

    private func parseObjectLiteralExpression(from tokens: [Token]) -> ExprID? {
        guard !tokens.isEmpty else {
            return nil
        }
        return BuildASTPhase.ExpressionParser(
            tokens: tokens[...],
            interner: interner,
            astArena: astArena
        ).parse()
    }

    private func parseObjectLiteralBlockBody(from tokens: [Token]) -> FunctionBody? {
        guard !tokens.isEmpty,
              let blockExprID = BuildASTPhase.ExpressionParser(
                  tokens: tokens[...],
                  interner: interner,
                  astArena: astArena
              ).parseBlockExpression(),
              let blockExpr = astArena.expr(blockExprID),
              case let .blockExpr(statements, trailingExpr, range) = blockExpr
        else {
            return nil
        }

        var bodyExprs = statements
        if let trailingExpr {
            bodyExprs.append(trailingExpr)
        }
        return .block(bodyExprs, range)
    }

    private func objectLiteralDelegateBody(from exprID: ExprID) -> FunctionBody? {
        guard let expr = astArena.expr(exprID) else {
            return nil
        }

        let trailingLambdaExprID: ExprID? = switch expr {
        case let .call(_, _, args, _):
            args.last?.expr
        case let .memberCall(_, _, _, args, _):
            args.last?.expr
        default:
            nil
        }

        guard let trailingLambdaExprID,
              let lambdaExpr = astArena.expr(trailingLambdaExprID),
              case let .lambdaLiteral(_, bodyExprID, _, _) = lambdaExpr
        else {
            return nil
        }

        guard let bodyExpr = astArena.expr(bodyExprID) else {
            return nil
        }
        switch bodyExpr {
        case let .blockExpr(statements, trailingExpr, range):
            var exprs = statements
            if let trailingExpr {
                exprs.append(trailingExpr)
            }
            return .block(exprs, range)

        default:
            guard let range = astArena.exprRange(bodyExprID) else {
                return nil
            }
            return .expr(bodyExprID, range)
        }
    }

    private func objectLiteralRangeStartsWithAccessor(_ tokens: ArraySlice<Token>) -> Bool {
        guard let firstToken = tokens.first else {
            return false
        }
        return switch firstToken.kind {
        case .softKeyword(.get), .softKeyword(.set):
            true
        default:
            false
        }
    }

    private func objectLiteralRangeStartsWithBlock(_ tokens: ArraySlice<Token>) -> Bool {
        tokens.first?.kind == .symbol(.lBrace)
    }

    private func objectLiteralRangeNeedsBraceContinuation(_ tokens: ArraySlice<Token>) -> Bool {
        let combined = Array(tokens).filter { $0.kind != .symbol(.semicolon) }
        guard !combined.isEmpty else {
            return false
        }
        if topLevelDelegateIndex(in: combined) != nil {
            return true
        }

        guard let accessorStart = topLevelAccessorStartIndex(in: combined, from: 0) else {
            return false
        }
        let openParenIndex = accessorStart + 1
        guard openParenIndex < combined.count,
              combined[openParenIndex].kind == .symbol(.lParen),
              let closeParenIndex = matchingParenIndex(in: combined, openIndex: openParenIndex)
        else {
            return false
        }
        return closeParenIndex == combined.count - 1
    }

    private func topLevelDelegateIndex(in tokens: [Token]) -> Int? {
        var parenDepth = 0
        var bracketDepth = 0
        var braceDepth = 0
        for (index, token) in tokens.enumerated() {
            if case .softKeyword(.by) = token.kind,
               parenDepth == 0,
               bracketDepth == 0,
               braceDepth == 0
            {
                return index
            }
            switch token.kind {
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
            default:
                break
            }
        }
        return nil
    }

    private func topLevelAccessorStartIndex(in tokens: [Token], from startIndex: Int) -> Int? {
        guard startIndex < tokens.count else {
            return nil
        }

        var parenDepth = 0
        var bracketDepth = 0
        var braceDepth = 0
        if startIndex > 0 {
            for token in tokens[..<startIndex] {
                switch token.kind {
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
                default:
                    break
                }
            }
        }

        for index in startIndex ..< tokens.count {
            let token = tokens[index]
            let isAccessorKeyword = switch token.kind {
            case .softKeyword(.get), .softKeyword(.set):
                true
            default:
                false
            }
            if isAccessorKeyword,
               parenDepth == 0,
               bracketDepth == 0,
               braceDepth == 0,
               index + 1 < tokens.count,
               tokens[index + 1].kind == .symbol(.lParen)
            {
                return index
            }
            switch token.kind {
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
            default:
                break
            }
        }
        return nil
    }

    private func matchingParenIndex(in tokens: [Token], openIndex: Int) -> Int? {
        guard openIndex < tokens.count,
              tokens[openIndex].kind == .symbol(.lParen)
        else {
            return nil
        }

        var depth = 1
        for index in (openIndex + 1) ..< tokens.count {
            switch tokens[index].kind {
            case .symbol(.lParen):
                depth += 1
            case .symbol(.rParen):
                depth -= 1
                if depth == 0 {
                    return index
                }
            default:
                break
            }
        }
        return nil
    }

    private func matchingBraceIndex(in tokens: [Token], openIndex: Int) -> Int? {
        guard openIndex < tokens.count,
              tokens[openIndex].kind == .symbol(.lBrace)
        else {
            return nil
        }

        var depth = 1
        for index in (openIndex + 1) ..< tokens.count {
            switch tokens[index].kind {
            case .symbol(.lBrace):
                depth += 1
            case .symbol(.rBrace):
                depth -= 1
                if depth == 0 {
                    return index
                }
            default:
                break
            }
        }
        return nil
    }

    private func objectLiteralSetterParameterName(from tokens: [Token]) -> InternedString? {
        guard let openParenIndex = tokens.firstIndex(where: { $0.kind == .symbol(.lParen) }) else {
            return nil
        }
        for token in tokens[(openParenIndex + 1)...] {
            if token.kind == .symbol(.rParen) {
                break
            }
            if TypeRefParserCore.isTypeLikeNameToken(token.kind),
               let name = tokenText(token)
            {
                return name
            }
        }
        return nil
    }

    private func objectLiteralDeclarationName(from token: Token) -> InternedString? {
        switch token.kind {
        case let .identifier(name), let .backtickedIdentifier(name):
            name
        case let .keyword(keyword):
            interner.intern(keyword.rawValue)
        case let .softKeyword(keyword):
            interner.intern(keyword.rawValue)
        default:
            nil
        }
    }
}

import Foundation

enum TypeRefParserCore {
    struct Options {
        var allowQualifiedPath: Bool
        var allowFunctionType: Bool
        var allowKeywordIdentifiers: Bool
        var reserveVarianceKeywords: Bool

        static let declaration = Options(
            allowQualifiedPath: true,
            allowFunctionType: true,
            allowKeywordIdentifiers: true,
            reserveVarianceKeywords: true
        )

        static let expressionInline = Options(
            allowQualifiedPath: true,
            allowFunctionType: false,
            allowKeywordIdentifiers: true,
            reserveVarianceKeywords: false
        )
    }

    struct TypeRefParseResult {
        let ref: TypeRefID
        let consumed: Int
    }

    struct TypeArgsParseResult {
        let args: [TypeArgRef]
        let consumed: Int
    }

    static func isTypeLikeNameToken(_ kind: TokenKind) -> Bool {
        isTypeNameToken(kind, options: .declaration)
    }

    static func parseTypeRefPrefix(
        _ tokens: ArraySlice<Token>,
        interner: StringInterner,
        astArena: ASTArena,
        options: Options
    ) -> TypeRefParseResult? {
        guard !tokens.isEmpty else {
            return nil
        }
        let buffer = Array(tokens)
        guard let parsed = parseTypeRefPrefix(
            buffer,
            from: 0,
            interner: interner,
            astArena: astArena,
            options: options
        ) else {
            return nil
        }
        return TypeRefParseResult(ref: parsed.ref, consumed: parsed.next)
    }

    static func parseTypeArgRefsPrefix(
        _ tokens: ArraySlice<Token>,
        interner: StringInterner,
        astArena: ASTArena,
        options: Options
    ) -> TypeArgsParseResult? {
        guard !tokens.isEmpty else {
            return nil
        }
        let buffer = Array(tokens)
        guard let parsed = parseTypeArgRefsPrefix(
            buffer,
            from: 0,
            interner: interner,
            astArena: astArena,
            options: options
        ) else {
            return nil
        }
        return TypeArgsParseResult(args: parsed.args, consumed: parsed.next)
    }

    private static func parseTypeRefPrefix(
        _ tokens: [Token],
        from start: Int,
        interner: StringInterner,
        astArena: ASTArena,
        options: Options
    ) -> (ref: TypeRefID, next: Int)? {
        guard let first = parseSingleTypeRefPrefix(
            tokens,
            from: start,
            interner: interner,
            astArena: astArena,
            options: options
        ) else {
            return nil
        }

        var next = first.next
        var parts: [TypeRefID] = [first.ref]

        while next < tokens.count, tokens[next].kind == .symbol(.amp) {
            let saved = next
            next += 1
            guard let part = parseSingleTypeRefPrefix(
                tokens,
                from: next,
                interner: interner,
                astArena: astArena,
                options: options
            ) else {
                next = saved
                break
            }
            parts.append(part.ref)
            next = part.next
        }

        if parts.count == 1 {
            return (first.ref, next)
        }

        let intersection = astArena.appendTypeRef(.intersection(parts: parts))
        return (intersection, next)
    }

    private static func parseSingleTypeRefPrefix(
        _ tokens: [Token],
        from start: Int,
        interner: StringInterner,
        astArena: ASTArena,
        options: Options
    ) -> (ref: TypeRefID, next: Int)? {
        guard start < tokens.count else {
            return nil
        }

        if options.allowFunctionType,
           let functionType = parseFunctionTypeRefPrefix(
               tokens,
               from: start,
               interner: interner,
               astArena: astArena,
               options: options
           )
        {
            return functionType
        }

        guard let firstName = identifier(
            from: tokens[start],
            interner: interner,
            options: options
        ) else {
            return nil
        }

        var path: [InternedString] = [firstName]
        var typeArgs: [TypeArgRef] = []
        var next = start + 1

        if next < tokens.count,
           tokens[next].kind == .symbol(.lessThan),
           let parsedArgs = parseTypeArgRefsPrefix(
               tokens,
               from: next,
               interner: interner,
               astArena: astArena,
               options: options
           )
        {
            typeArgs = parsedArgs.args
            next = parsedArgs.next
        }

        if options.allowQualifiedPath {
            while next + 1 < tokens.count,
                  tokens[next].kind == .symbol(.dot),
                  let name = identifier(from: tokens[next + 1], interner: interner, options: options)
            {
                typeArgs = []
                path.append(name)
                next += 2

                if next < tokens.count,
                   tokens[next].kind == .symbol(.lessThan),
                   let parsedArgs = parseTypeArgRefsPrefix(
                       tokens,
                       from: next,
                       interner: interner,
                       astArena: astArena,
                       options: options
                   )
                {
                    typeArgs = parsedArgs.args
                    next = parsedArgs.next
                }
            }
        }

        var nullable = false
        if next < tokens.count, tokens[next].kind == .symbol(.question) {
            nullable = true
            next += 1
        }

        let named = astArena.appendTypeRef(.named(path: path, args: typeArgs, nullable: nullable))
        return (named, next)
    }

    private static func parseTypeArgRefsPrefix(
        _ tokens: [Token],
        from start: Int,
        interner: StringInterner,
        astArena: ASTArena,
        options: Options
    ) -> (args: [TypeArgRef], next: Int)? {
        guard start < tokens.count,
              tokens[start].kind == .symbol(.lessThan)
        else {
            return nil
        }

        var args: [TypeArgRef] = []
        var next = start + 1

        while true {
            guard next < tokens.count else {
                return nil
            }

            if tokens[next].kind == .symbol(.greaterThan) {
                return args.isEmpty ? nil : (args, next + 1)
            }

            if !args.isEmpty {
                guard tokens[next].kind == .symbol(.comma) else {
                    return nil
                }
                next += 1
                guard next < tokens.count else {
                    return nil
                }
                if tokens[next].kind == .symbol(.greaterThan) {
                    return (args, next + 1)
                }
            }

            if tokens[next].kind == .symbol(.star) {
                args.append(.star)
                next += 1
                continue
            }

            var variance: TypeVariance = .invariant
            if case .softKeyword(.out) = tokens[next].kind {
                variance = .out
                next += 1
            } else if case .keyword(.in) = tokens[next].kind {
                variance = .in
                next += 1
            }

            guard let inner = parseTypeRefPrefix(
                tokens,
                from: next,
                interner: interner,
                astArena: astArena,
                options: options
            ) else {
                return nil
            }
            next = inner.next

            switch variance {
            case .invariant:
                args.append(.invariant(inner.ref))
            case .out:
                args.append(.out(inner.ref))
            case .in:
                args.append(.in(inner.ref))
            }
        }
    }

    private static func parseFunctionTypeRefPrefix(
        _ tokens: [Token],
        from start: Int,
        interner: StringInterner,
        astArena: ASTArena,
        options: Options
    ) -> (ref: TypeRefID, next: Int)? {
        var next = start
        var isSuspend = false

        if next < tokens.count {
            if case .keyword(.suspend) = tokens[next].kind {
                isSuspend = true
                next += 1
            } else if case let .softKeyword(keyword) = tokens[next].kind,
                      keyword.rawValue == "suspend"
            {
                isSuspend = true
                next += 1
            }
        }

        guard next < tokens.count,
              tokens[next].kind == .symbol(.lParen)
        else {
            return nil
        }

        guard let closeParen = findMatchingCloseParen(in: tokens, from: next) else {
            return nil
        }

        guard closeParen + 1 < tokens.count,
              tokens[closeParen + 1].kind == .symbol(.arrow)
        else {
            return nil
        }

        guard let params = parseFunctionParamRefs(
            in: tokens,
            range: (next + 1) ..< closeParen,
            interner: interner,
            astArena: astArena,
            options: options
        ) else {
            return nil
        }

        let returnStart = closeParen + 2
        guard let returnRef = parseTypeRefPrefix(
            tokens,
            from: returnStart,
            interner: interner,
            astArena: astArena,
            options: options
        ) else {
            return nil
        }

        let ref = astArena.appendTypeRef(.functionType(
            params: params,
            returnType: returnRef.ref,
            isSuspend: isSuspend,
            nullable: false
        ))

        return (ref, returnRef.next)
    }

    private static func parseFunctionParamRefs(
        in tokens: [Token],
        range: Range<Int>,
        interner: StringInterner,
        astArena: ASTArena,
        options: Options
    ) -> [TypeRefID]? {
        guard !range.isEmpty else {
            return []
        }

        var refs: [TypeRefID] = []
        var segmentStart = range.lowerBound
        var depth = BuildASTPhase.BracketDepth()

        for index in range {
            let token = tokens[index]
            if token.kind == .symbol(.comma), depth.isAtTopLevel {
                guard segmentStart < index,
                      let parsed = parseTypeRefPrefix(
                          tokens,
                          from: segmentStart,
                          interner: interner,
                          astArena: astArena,
                          options: options
                      ),
                      parsed.next == index
                else {
                    return nil
                }
                refs.append(parsed.ref)
                segmentStart = index + 1
                continue
            }
            depth.track(token.kind)
        }

        if segmentStart < range.upperBound {
            guard let parsed = parseTypeRefPrefix(
                tokens,
                from: segmentStart,
                interner: interner,
                astArena: astArena,
                options: options
            ),
                parsed.next == range.upperBound
            else {
                return nil
            }
            refs.append(parsed.ref)
        }

        return refs
    }

    private static func findMatchingCloseParen(in tokens: [Token], from openIndex: Int) -> Int? {
        var depth = 0
        for index in openIndex ..< tokens.count {
            if tokens[index].kind == .symbol(.lParen) {
                depth += 1
            } else if tokens[index].kind == .symbol(.rParen) {
                depth -= 1
                if depth == 0 {
                    return index
                }
            }
        }
        return nil
    }

    private static func identifier(
        from token: Token,
        interner: StringInterner,
        options: Options
    ) -> InternedString? {
        guard isTypeNameToken(token.kind, options: options) else {
            return nil
        }

        switch token.kind {
        case let .identifier(name), let .backtickedIdentifier(name):
            return name
        case let .keyword(keyword):
            return interner.intern(keyword.rawValue)
        case let .softKeyword(keyword):
            return interner.intern(keyword.rawValue)
        default:
            return nil
        }
    }

    private static func isTypeNameToken(_ kind: TokenKind, options: Options) -> Bool {
        switch kind {
        case .identifier, .backtickedIdentifier:
            true
        case .keyword(.in):
            options.allowKeywordIdentifiers && !options.reserveVarianceKeywords
        case .keyword:
            options.allowKeywordIdentifiers
        case .softKeyword(.out):
            options.allowKeywordIdentifiers && !options.reserveVarianceKeywords
        case .softKeyword:
            options.allowKeywordIdentifiers
        default:
            false
        }
    }
}

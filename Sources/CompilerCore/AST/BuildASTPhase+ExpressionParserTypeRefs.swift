import Foundation

extension BuildASTPhase.ExpressionParser {
    internal func parseTypeReference(_ fallbackRange: SourceRange) -> TypeRefID? {
        guard let firstRef = parseSingleTypeReference() else { return nil }
        // Check for intersection type (T & U)
        var parts: [TypeRefID] = [firstRef]
        while true {
            let savedIndex = index
            guard consumeIf(.symbol(.amp)) != nil else { break }
            guard let nextRef = parseSingleTypeReference() else {
                index = savedIndex
                break
            }
            parts.append(nextRef)
        }
        if parts.count > 1 {
            return astArena.appendTypeRef(.intersection(parts: parts))
        }
        return firstRef
    }

    private func parseSingleTypeReference() -> TypeRefID? {
        guard let token = current() else { return nil }
        let name: InternedString
        switch token.kind {
        case .identifier(let n), .backtickedIdentifier(let n):
            _ = consume()
            name = n
        case .keyword(let kw):
            _ = consume()
            name = interner.intern(kw.rawValue)
        case .softKeyword(let kw):
            _ = consume()
            name = interner.intern(kw.rawValue)
        default:
            return nil
        }
        var typeArgs: [TypeArgRef] = []
        if matches(.symbol(.lessThan)) {
            let savedIndex = index
            if let parsedArgs = tryParseTypeArgRefs() {
                typeArgs = parsedArgs
            } else {
                index = savedIndex
            }
        }
        let isNullable = consumeIf(.symbol(.question)) != nil
        return astArena.appendTypeRef(.named(path: [name], args: typeArgs, nullable: isNullable))
    }

    internal func tryParseExplicitTypeArgs() -> [TypeRefID]? {
        guard matches(.symbol(.lessThan)) else { return nil }
        let savedIndex = index
        _ = consume()
        var refs: [TypeRefID] = []
        while true {
            guard let token = current() else {
                index = savedIndex
                return nil
            }
            if token.kind == .symbol(.greaterThan) {
                if refs.isEmpty {
                    index = savedIndex
                    return nil
                }
                _ = consume()
                return refs
            }
            if !refs.isEmpty {
                guard consumeIf(.symbol(.comma)) != nil else {
                    index = savedIndex
                    return nil
                }
            }
            guard let typeRef = parseInlineTypeRef() else {
                index = savedIndex
                return nil
            }
            refs.append(typeRef)
        }
    }

    internal func tryParseTypeArgRefs() -> [TypeArgRef]? {
        guard matches(.symbol(.lessThan)) else { return nil }
        let savedIndex = index
        _ = consume()
        var args: [TypeArgRef] = []
        while true {
            guard let token = current() else {
                index = savedIndex
                return nil
            }
            if token.kind == .symbol(.greaterThan) {
                _ = consume()
                return args
            }
            if !args.isEmpty {
                guard consumeIf(.symbol(.comma)) != nil else {
                    index = savedIndex
                    return nil
                }
                guard let freshToken = current() else {
                    index = savedIndex
                    return nil
                }
                if freshToken.kind == .symbol(.greaterThan) {
                    _ = consume()
                    return args
                }
                if freshToken.kind == .symbol(.star) {
                    _ = consume()
                    args.append(.star)
                    continue
                }
                var variance: TypeVariance = .invariant
                if case .softKeyword(.out) = freshToken.kind {
                    variance = .out
                    _ = consume()
                } else if case .keyword(.in) = freshToken.kind {
                    variance = .in
                    _ = consume()
                }
                guard let innerRef = parseInlineTypeRef() else {
                    index = savedIndex
                    return nil
                }
                switch variance {
                case .invariant: args.append(.invariant(innerRef))
                case .out: args.append(.out(innerRef))
                case .in: args.append(.in(innerRef))
                }
                continue
            }
            if token.kind == .symbol(.star) {
                _ = consume()
                args.append(.star)
                continue
            }
            var variance: TypeVariance = .invariant
            if case .softKeyword(.out) = token.kind {
                variance = .out
                _ = consume()
            } else if case .keyword(.in) = token.kind {
                variance = .in
                _ = consume()
            }
            guard let innerRef = parseInlineTypeRef() else {
                index = savedIndex
                return nil
            }
            switch variance {
            case .invariant: args.append(.invariant(innerRef))
            case .out: args.append(.out(innerRef))
            case .in: args.append(.in(innerRef))
            }
        }
    }

    internal func parseInlineTypeRef() -> TypeRefID? {
        guard let firstRef = parseSingleInlineTypeRef() else { return nil }
        // Check for intersection type (T & U) in inline context
        var parts: [TypeRefID] = [firstRef]
        while true {
            let savedIndex = index
            guard consumeIf(.symbol(.amp)) != nil else { break }
            guard let nextRef = parseSingleInlineTypeRef() else {
                index = savedIndex
                break
            }
            parts.append(nextRef)
        }
        if parts.count > 1 {
            return astArena.appendTypeRef(.intersection(parts: parts))
        }
        return firstRef
    }

    private func parseSingleInlineTypeRef() -> TypeRefID? {
        guard let token = current() else { return nil }
        let name: InternedString
        switch token.kind {
        case .identifier(let n), .backtickedIdentifier(let n):
            _ = consume()
            name = n
        case .keyword(let kw):
            _ = consume()
            name = interner.intern(kw.rawValue)
        case .softKeyword(let kw):
            _ = consume()
            name = interner.intern(kw.rawValue)
        default:
            return nil
        }
        var innerArgs: [TypeArgRef] = []
        if matches(.symbol(.lessThan)) {
            let saved = index
            if let parsed = tryParseTypeArgRefs() {
                innerArgs = parsed
            } else {
                index = saved
            }
        }
        let isNullable = consumeIf(.symbol(.question)) != nil
        return astArena.appendTypeRef(.named(path: [name], args: innerArgs, nullable: isNullable))
    }
}

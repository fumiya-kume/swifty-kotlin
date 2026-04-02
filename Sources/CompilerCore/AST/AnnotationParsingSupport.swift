import Foundation

enum AnnotationParsingSupport {
    struct ParsedAnnotation {
        let annotation: AnnotationNode
        let nextIndex: Int
        let hadInvalidUseSiteTarget: Bool
        let invalidUseSiteTargetRange: SourceRange?
    }

    static func parseAnnotation(
        from tokens: [Token],
        start: Int,
        interner: StringInterner,
        allowUseSiteTarget: Bool
    ) -> ParsedAnnotation? {
        guard start < tokens.count, tokens[start].kind == .symbol(.at) else {
            return nil
        }

        var index = start + 1
        guard index < tokens.count else {
            return nil
        }

        var useSiteTarget: String?
        var hadInvalidUseSiteTarget = false
        var invalidUseSiteTargetRange: SourceRange?
        if index + 1 < tokens.count, tokens[index + 1].kind == .symbol(.colon) {
            let candidate = tokens[index]
            if let candidateName = tokenText(candidate, interner: interner) {
                let knownTargets: Set<String> = [
                    "get", "set", "field", "param", "setparam",
                    "delegate", "property", "receiver", "file",
                ]
                if knownTargets.contains(candidateName) {
                    if allowUseSiteTarget {
                        useSiteTarget = candidateName
                    } else {
                        hadInvalidUseSiteTarget = true
                        invalidUseSiteTargetRange = candidate.range
                    }
                    index += 2
                }
            }
        }

        guard index < tokens.count else {
            return nil
        }

        var nameParts: [String] = []
        guard let firstPart = tokenText(tokens[index], interner: interner) else {
            return nil
        }
        nameParts.append(firstPart)
        index += 1
        while index + 1 < tokens.count,
              tokens[index].kind == .symbol(.dot),
              let nextPart = tokenText(tokens[index + 1], interner: interner)
        {
            nameParts.append(nextPart)
            index += 2
        }

        var arguments: [String] = []
        if index < tokens.count, tokens[index].kind == .symbol(.lParen) {
            index += 1
            var parenDepth = 1
            var bracketDepth = 0
            var braceDepth = 0
            var currentArg: [String] = []
            while index < tokens.count, parenDepth > 0 {
                let argToken = tokens[index]
                if argToken.kind == .symbol(.lParen) {
                    parenDepth += 1
                    currentArg.append("(")
                } else if argToken.kind == .symbol(.rParen) {
                    parenDepth -= 1
                    if parenDepth == 0 {
                        let trimmed = currentArg.joined().trimmingCharacters(in: .whitespaces)
                        if !trimmed.isEmpty {
                            arguments.append(trimmed)
                        }
                    } else {
                        currentArg.append(")")
                    }
                } else if argToken.kind == .symbol(.lBracket) {
                    bracketDepth += 1
                    currentArg.append("[")
                } else if argToken.kind == .symbol(.rBracket) {
                    bracketDepth = max(0, bracketDepth - 1)
                    currentArg.append("]")
                } else if argToken.kind == .symbol(.lBrace) {
                    braceDepth += 1
                    currentArg.append("{")
                } else if argToken.kind == .symbol(.rBrace) {
                    braceDepth = max(0, braceDepth - 1)
                    currentArg.append("}")
                } else if argToken.kind == .symbol(.comma), parenDepth == 1,
                          bracketDepth == 0, braceDepth == 0
                {
                    let trimmed = currentArg.joined().trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty {
                        arguments.append(trimmed)
                    }
                    currentArg = []
                } else if let text = tokenText(argToken, interner: interner) {
                    currentArg.append(text)
                } else {
                    currentArg.append(tokenRawText(argToken, interner: interner))
                }
                index += 1
            }
        }

        return ParsedAnnotation(
            annotation: AnnotationNode(
                name: nameParts.joined(separator: "."),
                arguments: arguments,
                useSiteTarget: useSiteTarget
            ),
            nextIndex: index,
            hadInvalidUseSiteTarget: hadInvalidUseSiteTarget,
            invalidUseSiteTargetRange: invalidUseSiteTargetRange
        )
    }

    private static func tokenText(_ token: Token, interner: StringInterner) -> String? {
        switch token.kind {
        case let .identifier(interned):
            interner.resolve(interned)
        case let .backtickedIdentifier(interned):
            interner.resolve(interned)
        case let .keyword(keyword):
            keyword.rawValue
        case let .softKeyword(soft):
            soft.rawValue
        default:
            nil
        }
    }

    private static func tokenRawText(_ token: Token, interner: StringInterner) -> String {
        switch token.kind {
        case let .identifier(interned), let .backtickedIdentifier(interned):
            interner.resolve(interned)
        case let .keyword(keyword):
            keyword.rawValue
        case let .softKeyword(soft):
            soft.rawValue
        case let .stringSegment(interned):
            "\"\(interner.resolve(interned))\""
        case .stringQuote:
            "\""
        case let .multiDollarStringQuote(dollarCount):
            String(repeating: "$", count: dollarCount) + "\""
        case let .multiDollarRawStringQuote(dollarCount):
            String(repeating: "$", count: dollarCount) + "\"\"\""
        case let .intLiteral(value):
            "\(value)"
        case let .longLiteral(value):
            "\(value)"
        case let .uintLiteral(value):
            "\(value)"
        case let .ulongLiteral(value):
            "\(value)"
        case let .floatLiteral(value):
            "\(value)"
        case let .doubleLiteral(value):
            "\(value)"
        case let .charLiteral(value):
            "'\(UnicodeScalar(value) ?? "?")'"
        case .rawStringQuote:
            "\"\"\""
        case .templateExprStart:
            "${"
        case .templateExprEnd:
            "}"
        case .templateSimpleNameStart:
            "$"
        case .eof:
            ""
        case let .missing(expected):
            "<missing:\(expected)>"
        case .symbol(let symbol):
            symbol.rawValue
        }
    }
}

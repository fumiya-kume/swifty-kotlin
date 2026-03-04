import Foundation

extension BuildASTPhase.ExpressionParser {
    // swiftlint:disable:next cyclomatic_complexity function_body_length
    func parsePrimary() -> ExprID? {
        guard let token = current() else {
            return nil
        }

        switch token.kind {
        case .intLiteral, .longLiteral, .uintLiteral, .ulongLiteral, .floatLiteral, .doubleLiteral, .charLiteral:
            return parsePrimaryNumericOrChar(token)
        case .keyword(.true):
            _ = consume()
            return astArena.appendExpr(.boolLiteral(true, token.range))
        case .keyword(.false):
            _ = consume()
            return astArena.appendExpr(.boolLiteral(false, token.range))
        case .identifier, .backtickedIdentifier:
            return parsePrimaryIdentifier(token)
        case .keyword(.for):
            return parseForExpression()
        case .keyword(.while):
            return parseWhileExpression()
        case .keyword(.do):
            return parseDoWhileExpression()
        case .keyword(.break):
            return parsePrimaryBreakOrContinue(token, isBreak: true)
        case .keyword(.continue):
            return parsePrimaryBreakOrContinue(token, isBreak: false)
        case .keyword(.return):
            return parseReturnExpression()
        case .keyword(.if):
            return parseIfExpression()
        case .keyword(.try):
            return parseTryExpression()
        case .keyword(.throw):
            return parseThrowExpression()
        case .keyword(.when):
            return parseWhenExpression()
        case .keyword(.super):
            return parsePrimarySuper(token)
        case .keyword(.this):
            return parsePrimaryThis(token)
        case .keyword(.object):
            return parseObjectLiteral()
        case let .keyword(keyword):
            _ = consume()
            return astArena.appendExpr(.nameRef(interner.intern(keyword.rawValue), token.range))
        case let .softKeyword(softKeyword):
            _ = consume()
            return astArena.appendExpr(.nameRef(interner.intern(softKeyword.rawValue), token.range))
        case .stringQuote, .rawStringQuote:
            return parseStringLiteral()
        case .symbol(.doubleColon):
            return parseCallableReferenceWithoutReceiver()
        case .symbol(.lParen):
            _ = consume()
            let expr = parseExpression(minPrecedence: 0)
            _ = consumeIf(.symbol(.rParen))
            return expr
        case .symbol(.lBrace):
            return parseLambdaLiteral() ?? parseBlockExpression()
        default:
            return nil
        }
    }

    private func parsePrimaryNumericOrChar(_ token: Token) -> ExprID? {
        switch token.kind {
        case let .intLiteral(text):
            _ = consume()
            let value = Int64(text.filter { $0.isNumber || $0 == "-" }) ?? 0
            return astArena.appendExpr(.intLiteral(value, token.range))
        case let .longLiteral(text):
            _ = consume()
            let stripped = text.filter { $0.isNumber || $0 == "-" }
            let value = Int64(stripped) ?? 0
            return astArena.appendExpr(.longLiteral(value, token.range))
        case let .uintLiteral(text):
            _ = consume()
            let value = parseUnsignedLiteral(text, range: token.range)
            if value > UInt32.max {
                return astArena.appendExpr(.ulongLiteral(value, token.range))
            }
            return astArena.appendExpr(.uintLiteral(value, token.range))
        case let .ulongLiteral(text):
            _ = consume()
            let value = parseUnsignedLiteral(text, range: token.range)
            return astArena.appendExpr(.ulongLiteral(value, token.range))
        case let .floatLiteral(text):
            _ = consume()
            let stripped = String(text.dropLast()).replacingOccurrences(of: "_", with: "")
            let value = Double(stripped) ?? 0.0
            return astArena.appendExpr(.floatLiteral(value, token.range))
        case let .doubleLiteral(text):
            _ = consume()
            let stripped: String = if text.last == "d" || text.last == "D" {
                String(text.dropLast()).replacingOccurrences(of: "_", with: "")
            } else {
                text.replacingOccurrences(of: "_", with: "")
            }
            let value = Double(stripped) ?? 0.0
            return astArena.appendExpr(.doubleLiteral(value, token.range))
        case let .charLiteral(scalar):
            _ = consume()
            return astArena.appendExpr(.charLiteral(scalar, token.range))
        default:
            return nil
        }
    }

    /// Parses unsigned literal text (e.g. "42u", "0xFFuL") to UInt64.
    private func parseUnsignedLiteral(_ text: String, range: SourceRange) -> UInt64 {
        var numPart = text.replacingOccurrences(of: "_", with: "")
        // Strip trailing u/U and uL/UL
        if numPart.uppercased().hasSuffix("UL") {
            numPart = String(numPart.dropLast(2))
        } else if numPart.last == "u" || numPart.last == "U" {
            numPart = String(numPart.dropLast())
        }
        let lower = numPart.lowercased()
        let result: UInt64? = if lower.hasPrefix("0x") {
            UInt64(numPart.dropFirst(2).filter(\.isHexDigit), radix: 16)
        } else if lower.hasPrefix("0b") {
            UInt64(numPart.dropFirst(2).filter { $0 == "0" || $0 == "1" }, radix: 2)
        } else {
            UInt64(numPart.filter(\.isNumber), radix: 10)
        }
        if let val = result {
            return val
        }
        diagnostics?.error(
            "KSWIFTK-LEX-0003",
            "Invalid unsigned literal format or overflow.",
            range: range
        )
        return 0
    }

    // swiftlint:disable:next cyclomatic_complexity
    private func parsePrimaryIdentifier(_ token: Token) -> ExprID? {
        let name: InternedString
        switch token.kind {
        case let .identifier(ident): name = ident
        case let .backtickedIdentifier(ident): name = ident
        default: return nil
        }

        let hasAt = peek(1).map { $0.kind == .symbol(.at) } ?? false
        if hasAt, let nextToken = peek(2) {
            switch nextToken.kind {
            case .keyword(.for), .keyword(.while), .keyword(.do), .symbol(.lBrace):
                let savedIndex = index
                _ = consume()
                _ = consume()
                let start = token.range.start

                if matches(.keyword(.for)) {
                    return parseForExpression(label: name, start: start)
                }
                if matches(.keyword(.while)) {
                    return parseWhileExpression(label: name, start: start)
                }
                if matches(.keyword(.do)) {
                    return parseDoWhileExpression(label: name, start: start)
                }
                if matches(.symbol(.lBrace)) {
                    if let lambda = parseLambdaLiteral(label: name, start: start) {
                        return lambda
                    }
                }

                index = savedIndex
            default:
                break
            }
        }

        _ = consume()
        return astArena.appendExpr(.nameRef(name, token.range))
    }

    private func parsePrimaryBreakOrContinue(_ token: Token, isBreak: Bool) -> ExprID {
        _ = consume()
        var label: InternedString?
        var end = token.range.end
        let isAtSymbol = current().map { $0.kind == .symbol(.at) } ?? false
        let labelToken = isAtSymbol ? peek(1) : nil
        let labelName = labelToken.flatMap { identifierFromToken($0) }
        if isAtSymbol, let resolvedToken = labelToken, labelName != nil {
            _ = consume()
            _ = consume()
            label = labelName
            end = resolvedToken.range.end
        }
        let range = SourceRange(start: token.range.start, end: end)
        if isBreak {
            return astArena.appendExpr(.breakExpr(label: label, range: range))
        }
        return astArena.appendExpr(.continueExpr(label: label, range: range))
    }

    private func parsePrimarySuper(_ token: Token) -> ExprID {
        _ = consume()
        // Parse optional interface qualifier: super<InterfaceName>
        var qualifier: InternedString?
        if let ltToken = current(), ltToken.kind == .symbol(.lessThan) {
            let savedIdx = index
            _ = consume() // consume '<'
            if let nameToken = current(), let name = identifierFromToken(nameToken) {
                _ = consume() // consume identifier
                if let gtToken = current(), gtToken.kind == .symbol(.greaterThan) {
                    _ = consume() // consume '>'
                    qualifier = name
                } else {
                    index = savedIdx
                }
            } else {
                index = savedIdx
            }
        }
        let endPos = qualifier != nil ? tokens[index - 1].range.end : token.range.end
        let superRange = SourceRange(start: token.range.start, end: endPos)
        return astArena.appendExpr(.superRef(interfaceQualifier: qualifier, superRange))
    }

    private func parsePrimaryThis(_ token: Token) -> ExprID {
        _ = consume()
        let isThisAtSymbol = current().map { $0.kind == .symbol(.at) } ?? false
        let thisLabelToken = isThisAtSymbol ? peek(1) : nil
        let thisLabelName = thisLabelToken.flatMap { identifierFromToken($0) }
        if isThisAtSymbol, let labelToken = thisLabelToken, let labelName = thisLabelName {
            _ = consume()
            _ = consume()
            let endRange = labelToken.range
            let range = SourceRange(start: token.range.start, end: endRange.end)
            return astArena.appendExpr(.thisRef(label: labelName, range))
        }
        return astArena.appendExpr(.thisRef(label: nil, token.range))
    }

    func parseStringLiteral() -> ExprID? {
        guard let open = consume() else { return nil }
        var end = open.range.end
        let closingKind = open.kind

        var hasTemplate = false
        var scanIdx = index
        while scanIdx < tokens.endIndex {
            let tk = tokens[scanIdx]
            if tk.kind == closingKind { break }
            if case .templateExprStart = tk.kind { hasTemplate = true; break }
            if case .templateSimpleNameStart = tk.kind { hasTemplate = true; break }
            scanIdx += 1
        }

        if !hasTemplate {
            var pieces: [String] = []
            while let token = current() {
                if token.kind == closingKind {
                    _ = consume()
                    end = token.range.end
                    break
                }
                if case let .stringSegment(segment) = token.kind {
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

        var parts: [StringTemplatePart] = []
        while let token = current() {
            if token.kind == closingKind {
                _ = consume()
                end = token.range.end
                break
            }

            if case let .stringSegment(segment) = token.kind {
                parts.append(.literal(segment))
                end = token.range.end
                _ = consume()
                continue
            }

            if case .templateSimpleNameStart = token.kind {
                _ = consume()
                if let nameToken = current(), let name = tokenText(nameToken) {
                    _ = consume()
                    let nameExprID = astArena.appendExpr(.nameRef(name, nameToken.range))
                    parts.append(.expression(nameExprID))
                    end = nameToken.range.end
                }
                continue
            }

            if case .templateExprStart = token.kind {
                _ = consume()
                if let exprID = parseExpression(minPrecedence: 0) {
                    parts.append(.expression(exprID))
                    if let exprRange = astArena.exprRange(exprID) {
                        end = exprRange.end
                    }
                }
                if let closeToken = current(), case .templateExprEnd = closeToken.kind {
                    end = closeToken.range.end
                    _ = consume()
                }
                continue
            }

            end = token.range.end
            _ = consume()
        }

        let range = SourceRange(start: open.range.start, end: end)
        return astArena.appendExpr(.stringTemplate(parts: parts, range: range))
    }
}

import Foundation

extension BuildASTPhase.ExpressionParser {
    internal func parsePrimary() -> ExprID? {
        guard let token = current() else {
            return nil
        }

        switch token.kind {
        case .intLiteral(let text):
            _ = consume()
            let value = Int64(text.filter { $0.isNumber || $0 == "-" }) ?? 0
            return astArena.appendExpr(.intLiteral(value, token.range))

        case .longLiteral(let text):
            _ = consume()
            let stripped = text.filter { $0.isNumber || $0 == "-" }
            let value = Int64(stripped) ?? 0
            return astArena.appendExpr(.longLiteral(value, token.range))

        case .floatLiteral(let text):
            _ = consume()
            let stripped = String(text.dropLast()).replacingOccurrences(of: "_", with: "")
            let value = Double(stripped) ?? 0.0
            return astArena.appendExpr(.floatLiteral(value, token.range))

        case .doubleLiteral(let text):
            _ = consume()
            let stripped: String
            if text.last == "d" || text.last == "D" {
                stripped = String(text.dropLast()).replacingOccurrences(of: "_", with: "")
            } else {
                stripped = text.replacingOccurrences(of: "_", with: "")
            }
            let value = Double(stripped) ?? 0.0
            return astArena.appendExpr(.doubleLiteral(value, token.range))

        case .charLiteral(let scalar):
            _ = consume()
            return astArena.appendExpr(.charLiteral(scalar, token.range))

        case .keyword(.true):
            _ = consume()
            return astArena.appendExpr(.boolLiteral(true, token.range))

        case .keyword(.false):
            _ = consume()
            return astArena.appendExpr(.boolLiteral(false, token.range))

        case .identifier(let name), .backtickedIdentifier(let name):
            if let atToken = peek(1), atToken.kind == .symbol(.at),
               let nextToken = peek(2) {
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

        case .keyword(.for):
            return parseForExpression()

        case .keyword(.while):
            return parseWhileExpression()

        case .keyword(.do):
            return parseDoWhileExpression()

        case .keyword(.break):
            _ = consume()
            var label: InternedString?
            var end = token.range.end
            if let atToken = current(), atToken.kind == .symbol(.at),
               let labelToken = peek(1),
               let labelName = identifierFromToken(labelToken) {
                _ = consume()
                _ = consume()
                label = labelName
                end = labelToken.range.end
            }
            let range = SourceRange(start: token.range.start, end: end)
            return astArena.appendExpr(.breakExpr(label: label, range: range))

        case .keyword(.continue):
            _ = consume()
            var label: InternedString?
            var end = token.range.end
            if let atToken = current(), atToken.kind == .symbol(.at),
               let labelToken = peek(1),
               let labelName = identifierFromToken(labelToken) {
                _ = consume()
                _ = consume()
                label = labelName
                end = labelToken.range.end
            }
            let range = SourceRange(start: token.range.start, end: end)
            return astArena.appendExpr(.continueExpr(label: label, range: range))

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
            _ = consume()
            return astArena.appendExpr(.superRef(token.range))

        case .keyword(.this):
            _ = consume()
            if let atToken = current(), atToken.kind == .symbol(.at),
               let labelToken = peek(1),
               let labelName = identifierFromToken(labelToken) {
                _ = consume()
                _ = consume()
                let endRange = labelToken.range
                let range = SourceRange(start: token.range.start, end: endRange.end)
                return astArena.appendExpr(.thisRef(label: labelName, range))
            }
            return astArena.appendExpr(.thisRef(label: nil, token.range))

        case .keyword(.object):
            return parseObjectLiteral()

        case .keyword(let keyword):
            _ = consume()
            return astArena.appendExpr(.nameRef(interner.intern(keyword.rawValue), token.range))

        case .softKeyword(let softKeyword):
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

    internal func parseStringLiteral() -> ExprID? {
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

        var parts: [StringTemplatePart] = []
        while let token = current() {
            if token.kind == closingKind {
                _ = consume()
                end = token.range.end
                break
            }

            if case .stringSegment(let segment) = token.kind {
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

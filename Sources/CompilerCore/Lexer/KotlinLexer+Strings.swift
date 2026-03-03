extension KotlinLexer {
    func scanString(leadingTrivia: [TriviaPiece], start: Int) -> [Token] {
        let openStart = offset
        offset += 1
        var tokens: [Token] = []
        tokens.append(Token(kind: .stringQuote, range: makeRange(start: openStart, end: openStart + 1), leadingTrivia: leadingTrivia))
        var segmentStart = offset

        while offset < bytes.count {
            let ch = bytes[offset]

            if ch == 0x22 {
                appendSegment(to: &tokens, from: segmentStart, to: offset, leadingTrivia: [])
                tokens.append(Token(kind: .stringQuote, range: makeRange(start: offset, end: offset + 1), leadingTrivia: []))
                offset += 1
                return tokens
            }

            if ch == 0x24, offset + 1 < bytes.count, bytes[offset + 1] == 0x7B {
                appendSegment(to: &tokens, from: segmentStart, to: offset, leadingTrivia: [])
                let templateStart = offset
                offset += 2
                tokens.append(Token(kind: .templateExprStart, range: makeRange(start: templateStart, end: templateStart + 2), leadingTrivia: []))
                let templateExpr = scanTemplateExpression()
                tokens.append(contentsOf: templateExpr.tokens)
                tokens.append(Token(kind: .templateExprEnd, range: templateExpr.closeRange, leadingTrivia: []))
                segmentStart = offset
                continue
            }

            if ch == 0x24, offset + 1 < bytes.count, isIdentifierStart(bytes[offset + 1]) {
                appendSegment(to: &tokens, from: segmentStart, to: offset, leadingTrivia: [])
                tokens.append(
                    Token(
                        kind: .templateSimpleNameStart,
                        range: makeRange(start: offset, end: offset + 1),
                        leadingTrivia: []
                    )
                )
                offset += 1
                if let templateName = scanTemplateName(leadingTrivia: [], start: offset) {
                    tokens.append(templateName)
                    segmentStart = offset
                    continue
                }
                segmentStart = offset
                continue
            }

            if ch == 0x5C {
                if offset + 1 >= bytes.count {
                    diagnostics.error(
                        "KSWIFTK-LEX-0002",
                        "Unterminated string escape.",
                        range: makeRange(start: offset, end: bytes.count)
                    )
                    break
                }
                let escaped = bytes[offset + 1]
                if escaped == 0x75 {
                    if let unicode = scanUnicodeEscape(escapeStart: offset + 1) {
                        offset += 1 + unicode.length
                        continue
                    } else {
                        let missingEnd = min(offset + 12, bytes.count)
                        diagnostics.error(
                            "KSWIFTK-LEX-0003",
                            "Invalid unicode escape sequence in string literal.",
                            range: makeRange(start: offset, end: missingEnd)
                        )
                        if offset + 6 <= bytes.count {
                            offset += 6
                        } else {
                            offset += 2
                        }
                        segmentStart = offset
                        continue
                    }
                }
                if scalarValue(forEscape: escaped) == nil {
                    diagnostics.error(
                        "KSWIFTK-LEX-0003",
                        "Invalid escape sequence in string literal.",
                        range: makeRange(start: offset, end: min(offset + 2, bytes.count))
                    )
                    offset += 2
                    segmentStart = offset
                    continue
                }
                offset += 2
                continue
            }

            if ch == 0x0A {
                diagnostics.warning(
                    "KSWIFTK-LEX-0004",
                    "Unescaped line break in string literal.",
                    range: makeRange(start: offset, end: offset + 1)
                )
                offset += 1
                continue
            }

            if ch == 0x0D {
                diagnostics.warning(
                    "KSWIFTK-LEX-0004",
                    "Unescaped line break in string literal.",
                    range: makeRange(start: offset, end: offset + 1)
                )
                offset += 1
                continue
            }

            offset += 1
        }

        diagnostics.error(
            "KSWIFTK-LEX-0002",
            "Unterminated string literal.",
            range: makeRange(start: start, end: bytes.count)
        )
        appendSegment(to: &tokens, from: segmentStart, to: bytes.count, leadingTrivia: [])
        return tokens
    }

    func scanRawString(leadingTrivia: [TriviaPiece], start: Int) -> [Token] {
        let quoteStart = offset
        offset += 3
        var tokens: [Token] = []
        tokens.append(
            Token(
                kind: .rawStringQuote,
                range: makeRange(start: quoteStart, end: quoteStart + 3),
                leadingTrivia: leadingTrivia
            )
        )

        var segmentStart = offset
        while offset + 2 < bytes.count {
            if starts(with: "\"\"\"", at: offset) {
                break
            }
            if bytes[offset] == 0x24, offset + 1 < bytes.count, bytes[offset + 1] == 0x7B {
                appendSegment(to: &tokens, from: segmentStart, to: offset, leadingTrivia: [])
                let templateStart = offset
                offset += 2
                tokens.append(Token(kind: .templateExprStart, range: makeRange(start: templateStart, end: templateStart + 2), leadingTrivia: []))
                let templateExpr = scanTemplateExpression()
                tokens.append(contentsOf: templateExpr.tokens)
                tokens.append(Token(kind: .templateExprEnd, range: templateExpr.closeRange, leadingTrivia: []))
                segmentStart = offset
                continue
            }
            offset += 1
        }

        if offset + 2 >= bytes.count {
            diagnostics.error(
                "KSWIFTK-LEX-0002",
                "Unterminated raw string literal.",
                range: makeRange(start: start, end: bytes.count)
            )
            appendSegment(to: &tokens, from: segmentStart, to: bytes.count, leadingTrivia: [])
            return tokens
        }

        appendSegment(to: &tokens, from: segmentStart, to: offset, leadingTrivia: [])
        tokens.append(
            Token(
                kind: .rawStringQuote,
                range: makeRange(start: offset, end: offset + 3),
                leadingTrivia: []
            )
        )
        offset += 3
        return tokens
    }

    func scanTemplateExpression() -> (tokens: [Token], closeRange: SourceRange) {
        let expressionStart = offset
        var depth = 1
        var tokens: [Token] = []

        while offset < bytes.count, depth > 0 {
            let leadingTrivia = consumeTrivia()
            if offset >= bytes.count {
                break
            }

            if bytes[offset] == 0x24, offset + 1 < bytes.count, bytes[offset + 1] == 0x7B {
                let templateStart = offset
                let templateRange = makeRange(start: templateStart, end: templateStart + 2)
                offset += 2
                var nestedTokens: [Token] = []
                nestedTokens.append(Token(kind: .templateExprStart, range: templateRange, leadingTrivia: leadingTrivia))
                let nested = scanTemplateExpression()
                nestedTokens.append(contentsOf: nested.tokens)
                nestedTokens.append(Token(kind: .templateExprEnd, range: nested.closeRange, leadingTrivia: []))
                tokens.append(contentsOf: nestedTokens)
                continue
            }

            if bytes[offset] == 0x22 {
                if starts(with: "\"\"\"", at: offset) {
                    tokens.append(contentsOf: scanRawString(leadingTrivia: leadingTrivia, start: offset))
                } else {
                    tokens.append(contentsOf: scanString(leadingTrivia: leadingTrivia, start: offset))
                }
                continue
            }

            if bytes[offset] == 0x27 {
                tokens.append(scanCharLiteral(leadingTrivia: leadingTrivia, start: offset))
                continue
            }

            if bytes[offset] == 0x7B {
                tokens.append(Token(
                    kind: .symbol(.lBrace),
                    range: makeRange(start: offset, end: offset + 1),
                    leadingTrivia: leadingTrivia
                ))
                offset += 1
                depth += 1
                continue
            }

            if bytes[offset] == 0x7D {
                if depth == 1 {
                    let closeRange = makeRange(start: offset, end: offset + 1)
                    offset += 1
                    return (tokens, closeRange)
                }
                tokens.append(Token(
                    kind: .symbol(.rBrace),
                    range: makeRange(start: offset, end: offset + 1),
                    leadingTrivia: leadingTrivia
                ))
                offset += 1
                depth -= 1
                continue
            }

            let scanned = scanNextTokens(leadingTrivia: leadingTrivia)
            if scanned.isEmpty {
                diagnostics.error(
                    "KSWIFTK-LEX-0001",
                    "Invalid character in template expression.",
                    range: makeRange(start: offset, end: min(offset + 1, bytes.count))
                )
                offset += 1
                continue
            }
            tokens.append(contentsOf: scanned)
            for token in scanned {
                switch token.kind {
                case .symbol(.lBrace):
                    depth += 1
                case .symbol(.rBrace):
                    if depth > 1 {
                        depth -= 1
                    }
                default:
                    break
                }
            }
        }

        diagnostics.error(
            "KSWIFTK-LEX-0002",
            "Unterminated template expression.",
            range: SourceRange(
                start: SourceLocation(file: file, offset: expressionStart),
                end: SourceLocation(file: file, offset: bytes.count)
            )
        )
        return (tokens, SourceRange(
            start: SourceLocation(file: file, offset: expressionStart),
            end: SourceLocation(file: file, offset: bytes.count)
        ))
    }

    func appendSegment(to tokens: inout [Token], from: Int, to: Int, leadingTrivia: [TriviaPiece]) {
        if from >= to {
            return
        }
        let segmentText = text(from: from ..< to)
        tokens.append(
            Token(
                kind: .stringSegment(interner.intern(segmentText)),
                range: makeRange(start: from, end: to),
                leadingTrivia: leadingTrivia
            )
        )
    }
}

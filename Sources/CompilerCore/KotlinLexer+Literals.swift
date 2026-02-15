extension KotlinLexer {
    func scanNumber(leadingTrivia: [TriviaPiece], start: Int) -> Token {
        var cursor = offset
        var hasDot = false
        var hasExponent = false
        var parsedPrefix = false

        if bytes[cursor] == 0x30 && cursor + 1 < bytes.count {
            let marker = bytes[cursor + 1]
            if marker == 0x78 || marker == 0x58 {
                parsedPrefix = true
                cursor += 2
                let startDigits = cursor
                while cursor < bytes.count {
                    let ch = bytes[cursor]
                    if isHexDigit(ch) {
                        cursor += 1
                        continue
                    }
                    if ch == 0x5F && cursor + 1 < bytes.count && isHexDigit(bytes[cursor + 1]) {
                        cursor += 1
                        continue
                    }
                    break
                }
                if cursor == startDigits {
                    diagnostics.error(
                        "KSWIFTK-LEX-0003",
                        "Invalid number format in numeric literal.",
                        range: makeRange(start: start, end: min(cursor + 1, bytes.count))
                    )
                }
            } else if marker == 0x62 || marker == 0x42 {
                parsedPrefix = true
                cursor += 2
                let startDigits = cursor
                while cursor < bytes.count {
                    let ch = bytes[cursor]
                    if isBinaryDigit(ch) {
                        cursor += 1
                        continue
                    }
                    if ch == 0x5F && cursor + 1 < bytes.count && isBinaryDigit(bytes[cursor + 1]) {
                        cursor += 1
                        continue
                    }
                    break
                }
                if cursor == startDigits {
                    diagnostics.error(
                        "KSWIFTK-LEX-0003",
                        "Invalid number format in numeric literal.",
                        range: makeRange(start: start, end: min(cursor + 1, bytes.count))
                    )
                }
            } else if marker == 0x6F || marker == 0x4F {
                parsedPrefix = true
                cursor += 2
                let startDigits = cursor
                while cursor < bytes.count {
                    let ch = bytes[cursor]
                    if isOctalDigit(ch) {
                        cursor += 1
                        continue
                    }
                    if ch == 0x5F && cursor + 1 < bytes.count && isOctalDigit(bytes[cursor + 1]) {
                        cursor += 1
                        continue
                    }
                    break
                }
                if cursor == startDigits {
                    diagnostics.error(
                        "KSWIFTK-LEX-0003",
                        "Invalid number format in numeric literal.",
                        range: makeRange(start: start, end: min(cursor + 1, bytes.count))
                    )
                }
            }
        }

        if !parsedPrefix {
            while cursor < bytes.count {
                let ch = bytes[cursor]
                if isDigit(ch) {
                    cursor += 1
                    continue
                }
                if ch == 0x5F {
                    if cursor + 1 >= bytes.count || !isDigit(bytes[cursor + 1]) {
                        diagnostics.warning(
                            "KSWIFTK-LEX-0006",
                            "Invalid underscore placement in numeric literal.",
                            range: makeRange(start: cursor, end: min(cursor + 1, bytes.count))
                        )
                        cursor += 1
                        continue
                    }
                    cursor += 1
                    continue
                }
                if ch == 0x2E && !hasDot {
                    hasDot = true
                    cursor += 1
                    if cursor >= bytes.count || !isDigit(bytes[cursor]) {
                        diagnostics.error(
                            "KSWIFTK-LEX-0003",
                            "Invalid number format in numeric literal.",
                            range: makeRange(start: start, end: min(cursor + 1, bytes.count))
                        )
                    }
                    continue
                }
                break
            }
        }

        if !parsedPrefix && cursor < bytes.count && (bytes[cursor] == 0x45 || bytes[cursor] == 0x65) {
            hasExponent = true
            cursor += 1
            if cursor < bytes.count && (bytes[cursor] == 0x2B || bytes[cursor] == 0x2D) {
                cursor += 1
            }
            let exponentStart = cursor
            while cursor < bytes.count && isDigit(bytes[cursor]) {
                cursor += 1
            }
            if exponentStart == cursor {
                diagnostics.error(
                    "KSWIFTK-LEX-0003",
                    "Invalid number format in numeric literal.",
                    range: makeRange(start: start, end: min(cursor + 1, bytes.count))
                )
            }
        }

        let suffix = cursor < bytes.count ? bytes[cursor] : nil
        var textEnd = cursor

        if suffix == 0x4C || suffix == 0x6C {
            textEnd = cursor + 1
            let literal = text(from: start..<textEnd)
            offset = textEnd
            return Token(kind: .longLiteral(literal), range: makeRange(start: start, end: textEnd), leadingTrivia: leadingTrivia)
        } else if suffix == 0x46 || suffix == 0x66 {
            textEnd = cursor + 1
            let literal = text(from: start..<textEnd)
            offset = textEnd
            return Token(kind: .floatLiteral(literal), range: makeRange(start: start, end: textEnd), leadingTrivia: leadingTrivia)
        } else if suffix == 0x44 || suffix == 0x64 {
            textEnd = cursor + 1
            let literal = text(from: start..<textEnd)
            offset = textEnd
            return Token(kind: .doubleLiteral(literal), range: makeRange(start: start, end: textEnd), leadingTrivia: leadingTrivia)
        }

        if (hasDot || hasExponent) && suffix == nil {
            diagnostics.error(
                "KSWIFTK-LEX-0003",
                "Invalid number format in numeric literal.",
                range: makeRange(start: start, end: textEnd)
            )
        }

        offset = textEnd
        let literal = text(from: start..<textEnd)
        if hasDot || hasExponent {
            return Token(kind: .doubleLiteral(literal), range: makeRange(start: start, end: textEnd), leadingTrivia: leadingTrivia)
        }
        return Token(kind: .intLiteral(literal), range: makeRange(start: start, end: textEnd), leadingTrivia: leadingTrivia)
    }

    func scanCharLiteral(leadingTrivia: [TriviaPiece], start: Int) -> Token {
        offset += 1
        if offset >= bytes.count {
            diagnostics.error(
                "KSWIFTK-LEX-0002",
                "Unterminated character literal.",
                range: makeRange(start: start, end: bytes.count)
            )
            return Token(kind: .charLiteral(0), range: makeRange(start: start, end: bytes.count), leadingTrivia: leadingTrivia)
        }

        var value: UInt32 = 0
        if bytes[offset] == 0x5C {
            if offset + 1 >= bytes.count {
                diagnostics.error(
                    "KSWIFTK-LEX-0002",
                    "Invalid escape sequence in character literal.",
                    range: makeRange(start: start, end: bytes.count)
                )
                return Token(kind: .charLiteral(0), range: makeRange(start: start, end: bytes.count), leadingTrivia: leadingTrivia)
            }
            let escape = bytes[offset + 1]
            if escape == 0x75 {
                if let unicode = scanUnicodeEscape(escapeStart: offset + 1) {
                    value = unicode.scalar
                    offset += 1 + unicode.length
                } else {
                    let missingEnd = min(offset + 12, bytes.count)
                    diagnostics.error(
                        "KSWIFTK-LEX-0003",
                        "Invalid unicode escape in character literal.",
                        range: makeRange(start: start, end: missingEnd)
                    )
                    offset += 2
                }
            } else if let scalar = scalarValue(forEscape: escape) {
                value = scalar
                offset += 2
            } else {
                diagnostics.error(
                    "KSWIFTK-LEX-0003",
                    "Invalid escape sequence in character literal.",
                    range: makeRange(start: offset, end: min(offset + 2, bytes.count))
                )
                offset += 2
            }
        } else {
            value = UInt32(bytes[offset])
            offset += 1
        }

        if offset >= bytes.count || bytes[offset] != 0x27 {
            diagnostics.error(
                "KSWIFTK-LEX-0002",
                "Unterminated character literal.",
                range: makeRange(start: start, end: min(offset + 1, bytes.count))
            )
            while offset < bytes.count && bytes[offset] != 0x27 {
                offset += 1
            }
            if offset < bytes.count {
                offset += 1
            }
            return Token(kind: .charLiteral(value), range: makeRange(start: start, end: min(offset, bytes.count)), leadingTrivia: leadingTrivia)
        }

        offset += 1
        return Token(kind: .charLiteral(value), range: makeRange(start: start, end: offset), leadingTrivia: leadingTrivia)
    }
}

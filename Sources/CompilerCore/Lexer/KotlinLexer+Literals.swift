extension KotlinLexer {
    func scanNumber(leadingTrivia: [TriviaPiece], start: Int) -> Token {
        var cursor = offset
        var hasDot = false
        var hasExponent = false
        var parsedPrefix = false
        var isHexOrBin = false

        (parsedPrefix, isHexOrBin) = scanNumberPrefix(cursor: &cursor, start: start)

        if !parsedPrefix {
            scanDecimalDigits(cursor: &cursor, start: start, hasDot: &hasDot)
        }

        if !parsedPrefix && cursor < bytes.count && (bytes[cursor] == 0x45 || bytes[cursor] == 0x65) {
            hasExponent = true
            cursor += 1
            if cursor < bytes.count, bytes[cursor] == 0x2B || bytes[cursor] == 0x2D {
                cursor += 1
            }
            let exponentStart = cursor
            if cursor < bytes.count, bytes[cursor] == 0x5F {
                diagnostics.error(
                    "KSWIFTK-LEX-0006",
                    "Invalid underscore placement in numeric literal.",
                    range: makeRange(start: cursor, end: min(cursor + 1, bytes.count))
                )
            }
            var exponentDigitCount = 0
            while cursor < bytes.count {
                let ch = bytes[cursor]
                if isDigit(ch) {
                    exponentDigitCount += 1
                    cursor += 1
                    continue
                }
                if ch == 0x5F {
                    cursor += 1
                    continue
                }
                break
            }
            if exponentDigitCount == 0 {
                diagnostics.error(
                    "KSWIFTK-LEX-0003",
                    "Invalid number format in numeric literal.",
                    range: makeRange(start: start, end: min(cursor + 1, bytes.count))
                )
            } else if cursor > exponentStart, bytes[cursor - 1] == 0x5F {
                diagnostics.error(
                    "KSWIFTK-LEX-0006",
                    "Trailing underscore in numeric literal.",
                    range: makeRange(start: cursor - 1, end: cursor)
                )
            }
        }

        let suffix = cursor < bytes.count ? bytes[cursor] : nil
        var textEnd = cursor

        // Unsigned suffixes: u/U (UInt) or uL/UL (ULong). Must be checked before L.
        if suffix == 0x75 || suffix == 0x55 {
            if hasDot || hasExponent {
                diagnostics.error(
                    "KSWIFTK-LEX-0003",
                    "Unsigned suffix 'u'/'U' is not allowed on floating-point literals.",
                    range: makeRange(start: cursor, end: cursor + 1)
                )
            }
            textEnd = cursor + 1
            let nextChar = textEnd < bytes.count ? bytes[textEnd] : nil
            if nextChar == 0x4C || nextChar == 0x6C {
                if nextChar == 0x6C {
                    diagnostics.error(
                        "KSWIFTK-LEX-0003",
                        "Use uppercase 'L' for ULong suffix; lowercase 'l' is not allowed.",
                        range: makeRange(start: textEnd, end: textEnd + 1)
                    )
                }
                textEnd += 1
                let literal = text(from: start ..< textEnd)
                offset = textEnd
                return Token(kind: .ulongLiteral(literal), range: makeRange(start: start, end: textEnd), leadingTrivia: leadingTrivia)
            }
            let literal = text(from: start ..< textEnd)
            offset = textEnd
            return Token(kind: .uintLiteral(literal), range: makeRange(start: start, end: textEnd), leadingTrivia: leadingTrivia)
        } else if suffix == 0x4C {
            if hasDot || hasExponent {
                diagnostics.error(
                    "KSWIFTK-LEX-0003",
                    "Long suffix 'L' is not allowed on floating-point literals.",
                    range: makeRange(start: cursor, end: cursor + 1)
                )
            }
            textEnd = cursor + 1
            let literal = text(from: start ..< textEnd)
            offset = textEnd
            return Token(kind: .longLiteral(literal), range: makeRange(start: start, end: textEnd), leadingTrivia: leadingTrivia)
        } else if suffix == 0x6C {
            diagnostics.error(
                "KSWIFTK-LEX-0003",
                "Use uppercase 'L' for Long suffix; lowercase 'l' is not allowed.",
                range: makeRange(start: cursor, end: cursor + 1)
            )
            if hasDot || hasExponent {
                diagnostics.error(
                    "KSWIFTK-LEX-0003",
                    "Long suffix 'L' is not allowed on floating-point literals.",
                    range: makeRange(start: cursor, end: cursor + 1)
                )
            }
            textEnd = cursor + 1
            let literal = text(from: start ..< textEnd)
            offset = textEnd
            return Token(kind: .longLiteral(literal), range: makeRange(start: start, end: textEnd), leadingTrivia: leadingTrivia)
        } else if suffix == 0x46 || suffix == 0x66 {
            if isHexOrBin {
                diagnostics.error(
                    "KSWIFTK-LEX-0003",
                    "Float suffix is not allowed on hex or binary literals.",
                    range: makeRange(start: cursor, end: cursor + 1)
                )
            }
            textEnd = cursor + 1
            let literal = text(from: start ..< textEnd)
            offset = textEnd
            return Token(kind: .floatLiteral(literal), range: makeRange(start: start, end: textEnd), leadingTrivia: leadingTrivia)
        } else if suffix == 0x44 || suffix == 0x64 {
            diagnostics.error(
                "KSWIFTK-LEX-0003",
                "Double suffix 'd'/'D' is not supported in Kotlin.",
                range: makeRange(start: cursor, end: cursor + 1)
            )
            textEnd = cursor + 1
            let literal = text(from: start ..< textEnd)
            offset = textEnd
            return Token(kind: .doubleLiteral(literal), range: makeRange(start: start, end: textEnd), leadingTrivia: leadingTrivia)
        }

        offset = textEnd
        let literal = text(from: start ..< textEnd)
        if hasDot || hasExponent {
            return Token(kind: .doubleLiteral(literal), range: makeRange(start: start, end: textEnd), leadingTrivia: leadingTrivia)
        }
        return Token(kind: .intLiteral(literal), range: makeRange(start: start, end: textEnd), leadingTrivia: leadingTrivia)
    }

    // MARK: - scanNumber helpers

    /// Scans hex/bin digits with underscore handling. Advances cursor past digits; emits diagnostics for invalid placement.
    private func scanPrefixedDigits(cursor: inout Int, isDigit: (UInt8) -> Bool, rangeStart: Int) -> Int {
        let startDigits = cursor
        if cursor < bytes.count, bytes[cursor] == 0x5F {
            diagnostics.error(
                "KSWIFTK-LEX-0006",
                "Invalid underscore placement in numeric literal.",
                range: makeRange(start: cursor, end: min(cursor + 1, bytes.count))
            )
        }
        var digitCount = 0
        while cursor < bytes.count {
            let ch = bytes[cursor]
            if isDigit(ch) {
                digitCount += 1
                cursor += 1
                continue
            }
            if ch == 0x5F {
                cursor += 1
                continue
            }
            break
        }
        if digitCount == 0 {
            diagnostics.error(
                "KSWIFTK-LEX-0003",
                "Invalid number format in numeric literal.",
                range: makeRange(start: rangeStart, end: min(cursor + 1, bytes.count))
            )
        } else if cursor > startDigits, bytes[cursor - 1] == 0x5F {
            diagnostics.error(
                "KSWIFTK-LEX-0006",
                "Trailing underscore in numeric literal.",
                range: makeRange(start: cursor - 1, end: cursor)
            )
        }
        return digitCount
    }

    /// Handles 0x, 0b, 0o prefixes. Returns (parsedPrefix, isHexOrBin).
    private func scanNumberPrefix(cursor: inout Int, start: Int) -> (Bool, Bool) {
        guard bytes[cursor] == 0x30 && cursor + 1 < bytes.count else {
            return (false, false)
        }
        let marker = bytes[cursor + 1]
        if marker == 0x78 || marker == 0x58 {
            cursor += 2
            _ = scanPrefixedDigits(cursor: &cursor, isDigit: isHexDigit, rangeStart: start)
            return (true, true)
        }
        if marker == 0x62 || marker == 0x42 {
            cursor += 2
            _ = scanPrefixedDigits(cursor: &cursor, isDigit: isBinaryDigit, rangeStart: start)
            return (true, true)
        }
        if marker == 0x6F || marker == 0x4F {
            cursor += 2
            diagnostics.error(
                "KSWIFTK-LEX-0003",
                "Octal literal prefix '0o' is not supported in Kotlin.",
                range: makeRange(start: start, end: cursor)
            )
            while cursor < bytes.count {
                let ch = bytes[cursor]
                if isOctalDigit(ch) || ch == 0x5F {
                    cursor += 1
                    continue
                }
                break
            }
            return (true, false)
        }
        return (false, false)
    }

    /// Scans decimal digits and optional decimal point. Advances cursor.
    private func scanDecimalDigits(cursor: inout Int, start: Int, hasDot: inout Bool) {
        while cursor < bytes.count {
            let ch = bytes[cursor]
            if isDigit(ch) {
                cursor += 1
                continue
            }
            if ch == 0x5F {
                cursor += 1
                continue
            }
            if ch == 0x2E, !hasDot {
                if cursor + 1 >= bytes.count || !isDigit(bytes[cursor + 1]) {
                    break
                }
                if cursor > start, bytes[cursor - 1] == 0x5F {
                    diagnostics.error(
                        "KSWIFTK-LEX-0006",
                        "Trailing underscore in numeric literal.",
                        range: makeRange(start: cursor - 1, end: cursor)
                    )
                }
                hasDot = true
                cursor += 1
                continue
            }
            break
        }
        if cursor > start, bytes[cursor - 1] == 0x5F {
            diagnostics.error(
                "KSWIFTK-LEX-0006",
                "Trailing underscore in numeric literal.",
                range: makeRange(start: cursor - 1, end: cursor)
            )
        }
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
        var emittedContentError = false
        if bytes[offset] == 0x27 {
            diagnostics.error(
                "KSWIFTK-LEX-0003",
                "Empty character literal.",
                range: makeRange(start: start, end: min(start + 2, bytes.count))
            )
            offset += 1
            return Token(kind: .charLiteral(0), range: makeRange(start: start, end: offset), leadingTrivia: leadingTrivia)
        }
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
                    let missingEnd = min(offset + 6, bytes.count)
                    diagnostics.error(
                        "KSWIFTK-LEX-0003",
                        "Invalid unicode escape in character literal.",
                        range: makeRange(start: offset, end: missingEnd)
                    )
                    offset += 2
                    emittedContentError = true
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
                emittedContentError = true
            }
        } else {
            if let decoded = decodeUTF8Scalar(at: offset) {
                value = decoded.scalar
                offset += decoded.length
            } else {
                diagnostics.error(
                    "KSWIFTK-LEX-0003",
                    "Invalid UTF-8 sequence in character literal.",
                    range: makeRange(start: offset, end: min(offset + 1, bytes.count))
                )
                offset += 1
                emittedContentError = true
            }
        }

        if offset >= bytes.count {
            diagnostics.error(
                "KSWIFTK-LEX-0002",
                "Unterminated character literal.",
                range: makeRange(start: start, end: bytes.count)
            )
            return Token(kind: .charLiteral(value), range: makeRange(start: start, end: bytes.count), leadingTrivia: leadingTrivia)
        }

        if bytes[offset] == 0x27 {
            offset += 1
            return Token(kind: .charLiteral(value), range: makeRange(start: start, end: offset), leadingTrivia: leadingTrivia)
        }

        if bytes[offset] == 0x0A || bytes[offset] == 0x0D {
            diagnostics.error(
                "KSWIFTK-LEX-0002",
                "Unterminated character literal.",
                range: makeRange(start: start, end: offset)
            )
            return Token(kind: .charLiteral(value), range: makeRange(start: start, end: offset), leadingTrivia: leadingTrivia)
        }

        if !emittedContentError {
            diagnostics.error(
                "KSWIFTK-LEX-0003",
                "Character literal must contain exactly one character.",
                range: makeRange(start: start, end: min(offset + 1, bytes.count))
            )
        }

        let closed = consumeUntilCharacterLiteralClosingQuote()
        if !closed {
            diagnostics.error(
                "KSWIFTK-LEX-0002",
                "Unterminated character literal.",
                range: makeRange(start: start, end: min(offset + 1, bytes.count))
            )
        }
        return Token(kind: .charLiteral(value), range: makeRange(start: start, end: offset), leadingTrivia: leadingTrivia)
    }

    private func consumeUntilCharacterLiteralClosingQuote() -> Bool {
        while offset < bytes.count {
            let current = bytes[offset]
            if current == 0x27 {
                offset += 1
                return true
            }
            if current == 0x0A || current == 0x0D {
                return false
            }
            offset += 1
        }
        return false
    }

    private func decodeUTF8Scalar(at start: Int) -> (scalar: UInt32, length: Int)? {
        guard start < bytes.count else {
            return nil
        }
        let leading = bytes[start]
        if leading < 0x80 {
            return (UInt32(leading), 1)
        }

        let length: Int
        var scalar: UInt32
        switch leading {
        case 0xC2 ... 0xDF:
            length = 2
            scalar = UInt32(leading & 0x1F)
        case 0xE0 ... 0xEF:
            length = 3
            scalar = UInt32(leading & 0x0F)
        case 0xF0 ... 0xF4:
            length = 4
            scalar = UInt32(leading & 0x07)
        default:
            return nil
        }

        guard start + length <= bytes.count else {
            return nil
        }

        for index in 1 ..< length {
            let next = bytes[start + index]
            guard (next & 0xC0) == 0x80 else {
                return nil
            }
            scalar = (scalar << 6) | UInt32(next & 0x3F)
        }

        if length == 2, scalar < 0x80 {
            return nil
        }
        if length == 3, scalar < 0x800 {
            return nil
        }
        if length == 4, scalar < 0x10000 {
            return nil
        }
        if scalar > 0x10FFFF || (0xD800 ... 0xDFFF).contains(scalar) {
            return nil
        }

        return (scalar, length)
    }
}

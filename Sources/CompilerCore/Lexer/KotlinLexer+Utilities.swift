extension KotlinLexer {
    func isIdentifierStart(_ ch: UInt8) -> Bool {
        ch == 0x5F || (0x41 ... 0x5A).contains(ch) || (0x61 ... 0x7A).contains(ch) || ch == 0x24 || ch >= 0x80
    }

    func isIdentifierContinue(_ ch: UInt8) -> Bool {
        isIdentifierStart(ch) || isDigit(ch)
    }

    func isDigit(_ ch: UInt8) -> Bool {
        (0x30 ... 0x39).contains(ch)
    }

    func isHexDigit(_ ch: UInt8) -> Bool {
        (0x30 ... 0x39).contains(ch) || (0x41 ... 0x46).contains(ch) || (0x61 ... 0x66).contains(ch)
    }

    func isOctalDigit(_ ch: UInt8) -> Bool {
        (0x30 ... 0x37).contains(ch)
    }

    func isBinaryDigit(_ ch: UInt8) -> Bool {
        ch == 0x30 || ch == 0x31
    }

    func makeRange(start: Int, end: Int) -> SourceRange {
        let safeStart = max(0, min(start, bytes.count))
        let safeEnd = max(safeStart, min(end, bytes.count))
        return SourceRange(
            start: SourceLocation(file: file, offset: safeStart),
            end: SourceLocation(file: file, offset: safeEnd)
        )
    }

    func starts(with literal: String) -> Bool {
        starts(with: literal, at: offset)
    }

    func starts(with literal: String, at position: Int) -> Bool {
        let utf8 = Array(literal.utf8)
        guard position + utf8.count <= bytes.count else {
            return false
        }
        for index in 0 ..< utf8.count where bytes[position + index] != utf8[index] {
            return false
        }
        return true
    }

    func text(from range: Range<Int>) -> String {
        guard range.lowerBound >= 0,
              range.upperBound >= range.lowerBound,
              range.upperBound <= bytes.count
        else {
            return ""
        }
        return String(decoding: bytes[range.lowerBound ..< range.upperBound], as: UTF8.self)
    }

    func scalarValue(forEscape escape: UInt8) -> UInt32? {
        switch escape {
        case 0x6E: 10
        case 0x74: 9
        case 0x72: 13
        case 0x22: 34
        case 0x27: 39
        case 0x5C: 92
        case 0x24: 36
        case 0x62: 8
        default: nil
        }
    }

    func scanUnicodeEscape(escapeStart: Int) -> (scalar: UInt32, length: Int)? {
        guard escapeStart < bytes.count, bytes[escapeStart] == 0x75 else {
            return nil
        }
        guard escapeStart + 4 < bytes.count else {
            return nil
        }
        let raw = Array(bytes[(escapeStart + 1) ... (escapeStart + 4)])
        let hex = raw.compactMap { hexValue(of: $0) }
        guard hex.count == 4 else {
            return nil
        }
        let scalar = UInt32((hex[0] << 12) + (hex[1] << 8) + (hex[2] << 4) + hex[3])
        return (scalar: scalar, length: 5)
    }

    func hexValue(of ascii: UInt8) -> Int? {
        switch ascii {
        case 0x30 ... 0x39:
            Int(ascii - 0x30)
        case 0x41 ... 0x46:
            Int(ascii - 0x37)
        case 0x61 ... 0x66:
            Int(ascii - 0x57)
        default:
            nil
        }
    }
}

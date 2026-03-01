extension KotlinLexer {
    func symbolKind() -> Symbol? {
        // Multi-character symbols: check longest first for correct greedy matching
        for (literal, sym) in Self.symbolTable {
            if starts(with: literal) {
                offset += literal.utf8.count
                return sym
            }
        }
        // Single-character symbols: check by byte
        guard offset < bytes.count else { return nil }
        let ch = bytes[offset]
        if let sym = Self.singleCharSymbols[ch] {
            offset += 1
            return sym
        }
        return nil
    }

    /// Multi-char symbols sorted by length descending (longest match first)
    private static let symbolTable: [(String, Symbol)] = [
        ("..<", .dotDotLt),
        ("??", .questionQuestion),
        ("?.", .questionDot),
        ("?:", .questionColon),
        ("!!", .bangBang),
        ("::", .doubleColon),
        ("=>", .fatArrow),
        ("->", .arrow),
        ("&&", .ampAmp),
        ("||", .barBar),
        ("==", .equalEqual),
        ("!=", .bangEqual),
        ("<=", .lessOrEqual),
        (">=", .greaterOrEqual),
        ("+=", .plusAssign),
        ("-=", .minusAssign),
        ("*=", .starAssign),
        ("/=", .slashAssign),
        ("%=", .percentAssign),
        ("++", .plusPlus),
        ("--", .minusMinus),
        ("..", .dotDot),
    ]

    private static let singleCharSymbols: [UInt8: Symbol] = [
        0x26: .amp,      // &
        0x2B: .plus,     // +
        0x2D: .minus,    // -
        0x2A: .star,     // *
        0x2F: .slash,    // /
        0x25: .percent,   // %
        0x21: .bang,     // !
        0x3D: .assign,    // =
        0x3C: .lessThan,  // <
        0x3E: .greaterThan, // >
        0x2E: .dot,       // .
        0x2C: .comma,    // ,
        0x3B: .semicolon, // ;
        0x3A: .colon,    // :
        0x28: .lParen,   // (
        0x29: .rParen,   // )
        0x5B: .lBracket, // [
        0x5D: .rBracket, // ]
        0x7B: .lBrace,   // {
        0x7D: .rBrace,    // }
        0x40: .at,       // @
        0x23: .hash,     // #
        0x3F: .question,  // ?
    ]
}

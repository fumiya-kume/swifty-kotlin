extension KotlinLexer {
    func symbolKind() -> Symbol? {
        if starts(with: "&&") {
            offset += 2
            return .ampAmp
        }
        if starts(with: "||") {
            offset += 2
            return .barBar
        }
        if starts(with: "==") {
            offset += 2
            return .equalEqual
        }
        if starts(with: "!=") {
            offset += 2
            return .bangEqual
        }
        if starts(with: "<=") {
            offset += 2
            return .lessOrEqual
        }
        if starts(with: ">=") {
            offset += 2
            return .greaterOrEqual
        }
        if starts(with: "+=") {
            offset += 2
            return .plusAssign
        }
        if starts(with: "-=") {
            offset += 2
            return .minusAssign
        }
        if starts(with: "*=") {
            offset += 2
            return .starAssign
        }
        if starts(with: "/=") {
            offset += 2
            return .slashAssign
        }
        if starts(with: "%=") {
            offset += 2
            return .percentAssign
        }
        if starts(with: "++") {
            offset += 2
            return .plusPlus
        }
        if starts(with: "--") {
            offset += 2
            return .minusMinus
        }
        if starts(with: "..<") {
            offset += 3
            return .dotDotLt
        }
        if starts(with: "?.") {
            offset += 2
            return .questionDot
        }
        if starts(with: "?:") {
            offset += 2
            return .questionColon
        }
        if starts(with: "?") {
            offset += 1
            return .question
        }
        if starts(with: "!!") {
            offset += 2
            return .bangBang
        }
        if starts(with: "::") {
            offset += 2
            return .doubleColon
        }
        if starts(with: "=>") {
            offset += 2
            return .fatArrow
        }
        if starts(with: "->") {
            offset += 2
            return .arrow
        }
        if starts(with: "..") {
            offset += 2
            return .dotDot
        }

        if bytes[offset] == 0x2B {
            offset += 1
            return .plus
        }
        if bytes[offset] == 0x2D {
            offset += 1
            return .minus
        }
        if bytes[offset] == 0x2A {
            offset += 1
            return .star
        }
        if bytes[offset] == 0x2F {
            offset += 1
            return .slash
        }
        if bytes[offset] == 0x25 {
            offset += 1
            return .percent
        }
        if bytes[offset] == 0x21 {
            offset += 1
            return .bang
        }
        if bytes[offset] == 0x3D {
            offset += 1
            return .assign
        }
        if bytes[offset] == 0x3C {
            offset += 1
            return .lessThan
        }
        if bytes[offset] == 0x3E {
            offset += 1
            return .greaterThan
        }
        if bytes[offset] == 0x2E {
            offset += 1
            return .dot
        }
        if bytes[offset] == 0x2C {
            offset += 1
            return .comma
        }
        if bytes[offset] == 0x3B {
            offset += 1
            return .semicolon
        }
        if bytes[offset] == 0x3A {
            offset += 1
            return .colon
        }
        if bytes[offset] == 0x28 {
            offset += 1
            return .lParen
        }
        if bytes[offset] == 0x29 {
            offset += 1
            return .rParen
        }
        if bytes[offset] == 0x5B {
            offset += 1
            return .lBracket
        }
        if bytes[offset] == 0x5D {
            offset += 1
            return .rBracket
        }
        if bytes[offset] == 0x7B {
            offset += 1
            return .lBrace
        }
        if bytes[offset] == 0x7D {
            offset += 1
            return .rBrace
        }
        if bytes[offset] == 0x40 {
            offset += 1
            return .at
        }
        if bytes[offset] == 0x23 {
            offset += 1
            return .hash
        }

        return nil
    }
}

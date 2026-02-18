import Foundation

extension BuildASTPhase {
    struct BracketDepth {
        var angle: Int = 0
        var paren: Int = 0
        var bracket: Int = 0
        var brace: Int = 0

        var isAtTopLevel: Bool {
            angle == 0 && paren == 0 && bracket == 0 && brace == 0
        }

        var isAngleParenTopLevel: Bool {
            angle == 0 && paren == 0
        }

        mutating func track(_ kind: TokenKind) {
            switch kind {
            case .symbol(.lessThan):    angle += 1
            case .symbol(.greaterThan): angle = max(0, angle - 1)
            case .symbol(.lParen):      paren += 1
            case .symbol(.rParen):      paren = max(0, paren - 1)
            case .symbol(.lBracket):    bracket += 1
            case .symbol(.rBracket):    bracket = max(0, bracket - 1)
            case .symbol(.lBrace):      brace += 1
            case .symbol(.rBrace):      brace = max(0, brace - 1)
            default: break
            }
        }
    }

    final class ExpressionParser {
        internal let tokens: [Token]
        internal let interner: StringInterner
        internal let astArena: ASTArena
        internal var index: Int = 0

        init(tokens: [Token], interner: StringInterner, astArena: ASTArena) {
            self.tokens = tokens
            self.interner = interner
            self.astArena = astArena
        }

        func parse() -> ExprID? {
            parseAssignmentOrExpression()
        }

        private func parseAssignmentOrExpression() -> ExprID? {
            parseExpression(minPrecedence: 0)
        }

        internal func parseExpression(minPrecedence: Int) -> ExprID? {
            guard var lhs = parsePrefixUnary() else {
                return nil
            }

            while true {
                if let token = current(), token.kind == .keyword(.is) {
                    let prec = 85
                    guard prec >= minPrecedence else { break }
                    _ = consume()
                    guard let typeRef = parseTypeReference(token.range) else { break }
                    let range = mergeRanges(astArena.exprRange(lhs), nil, fallback: token.range)
                    lhs = astArena.appendExpr(.isCheck(expr: lhs, type: typeRef, negated: false, range: range))
                    continue
                }

                if let token = current(), token.kind == .symbol(.bang),
                   let next = peek(1), next.kind == .keyword(.is) {
                    let prec = 85
                    guard prec >= minPrecedence else { break }
                    _ = consume()
                    _ = consume()
                    guard let typeRef = parseTypeReference(token.range) else { break }
                    let range = mergeRanges(astArena.exprRange(lhs), nil, fallback: token.range)
                    lhs = astArena.appendExpr(.isCheck(expr: lhs, type: typeRef, negated: true, range: range))
                    continue
                }

                if let token = current(), token.kind == .keyword(.as) {
                    let prec = 130
                    guard prec >= minPrecedence else { break }
                    _ = consume()
                    let isSafe = consumeIf(.symbol(.question)) != nil
                    guard let typeRef = parseTypeReference(token.range) else { break }
                    let range = mergeRanges(astArena.exprRange(lhs), nil, fallback: token.range)
                    lhs = astArena.appendExpr(.asCast(expr: lhs, type: typeRef, isSafe: isSafe, range: range))
                    continue
                }

                guard let op = binaryOperator(at: current()), precedence(of: op) >= minPrecedence else {
                    break
                }
                guard let opToken = consume() else { break }
                let assoc = associativity(of: op)
                let nextMin = assoc == .right ? precedence(of: op) : precedence(of: op) + 1
                guard let rhs = parseExpression(minPrecedence: nextMin) else { break }
                let range = mergeRanges(astArena.exprRange(lhs), astArena.exprRange(rhs), fallback: opToken.range)
                lhs = astArena.appendExpr(.binary(op: op, lhs: lhs, rhs: rhs, range: range))
            }
            return lhs
        }

        private func parsePrefixUnary() -> ExprID? {
            guard let token = current() else {
                return nil
            }
            switch token.kind {
            case .symbol(.bang):
                if let next = peek(1), next.kind == .keyword(.is) {
                    return parsePostfixOrPrimary()
                }
                _ = consume()
                guard let operand = parsePrefixUnary() else { return nil }
                let range = mergeRanges(token.range, astArena.exprRange(operand), fallback: token.range)
                return astArena.appendExpr(.unaryExpr(op: .not, operand: operand, range: range))
            case .symbol(.minus):
                _ = consume()
                guard let operand = parsePrefixUnary() else { return nil }
                let range = mergeRanges(token.range, astArena.exprRange(operand), fallback: token.range)
                return astArena.appendExpr(.unaryExpr(op: .unaryMinus, operand: operand, range: range))
            case .symbol(.plus):
                _ = consume()
                guard let operand = parsePrefixUnary() else { return nil }
                let range = mergeRanges(token.range, astArena.exprRange(operand), fallback: token.range)
                return astArena.appendExpr(.unaryExpr(op: .unaryPlus, operand: operand, range: range))
            default:
                return parsePostfixOrPrimary()
            }
        }

        private func isUnaryPrefix() -> Bool {
            if index == 0 { return true }
            guard index > 0, index - 1 < tokens.count else { return true }
            let prev = tokens[index - 1]
            switch prev.kind {
            case .intLiteral, .longLiteral, .floatLiteral, .doubleLiteral, .charLiteral,
                 .identifier, .backtickedIdentifier,
                 .symbol(.rParen), .symbol(.rBracket),
                 .symbol(.bangBang),
                 .keyword(.true), .keyword(.false):
                return false
            default:
                return true
            }
        }

        internal func mergeRanges(_ lhs: SourceRange?, _ rhs: SourceRange?, fallback: SourceRange) -> SourceRange {
            switch (lhs, rhs) {
            case let (lhs?, rhs?):
                return SourceRange(start: lhs.start, end: rhs.end)
            case let (lhs?, nil):
                return lhs
            case let (nil, rhs?):
                return rhs
            default:
                return fallback
            }
        }

        private func binaryOperator(at token: Token?) -> BinaryOp? {
            guard let token else { return nil }
            switch token.kind {
            case .symbol(.plus):
                return .add
            case .symbol(.minus):
                return .subtract
            case .symbol(.star):
                return .multiply
            case .symbol(.slash):
                return .divide
            case .symbol(.percent):
                return .modulo
            case .symbol(.equalEqual):
                return .equal
            case .symbol(.bangEqual):
                return .notEqual
            case .symbol(.lessThan):
                return .lessThan
            case .symbol(.lessOrEqual):
                return .lessOrEqual
            case .symbol(.greaterThan):
                return .greaterThan
            case .symbol(.greaterOrEqual):
                return .greaterOrEqual
            case .symbol(.ampAmp):
                return .logicalAnd
            case .symbol(.barBar):
                return .logicalOr
            case .symbol(.questionColon):
                return .elvis
            case .symbol(.dotDot):
                return .rangeTo
            default:
                return nil
            }
        }

        private enum Associativity {
            case left
            case right
        }

        private func precedence(of op: BinaryOp) -> Int {
            switch op {
            case .multiply, .divide, .modulo:
                return 120
            case .add, .subtract:
                return 110
            case .rangeTo:
                return 100
            case .elvis:
                return 90
            case .lessThan, .lessOrEqual, .greaterThan, .greaterOrEqual:
                return 80
            case .equal, .notEqual:
                return 70
            case .logicalAnd:
                return 60
            case .logicalOr:
                return 50
            }
        }

        private func associativity(of op: BinaryOp) -> Associativity {
            switch op {
            case .elvis:
                return .right
            default:
                return .left
            }
        }

        internal func tokenText(_ token: Token) -> InternedString? {
            switch token.kind {
            case .identifier(let name), .backtickedIdentifier(let name):
                return name
            case .keyword(let keyword):
                return interner.intern(keyword.rawValue)
            case .softKeyword(let keyword):
                return interner.intern(keyword.rawValue)
            default:
                return nil
            }
        }

        internal func identifierFromToken(_ token: Token) -> InternedString? {
            switch token.kind {
            case .identifier(let name), .backtickedIdentifier(let name):
                return name
            default:
                return nil
            }
        }

        @discardableResult
        internal func current() -> Token? {
            if index >= 0 && index < tokens.count {
                return tokens[index]
            }
            return nil
        }

        internal func peek(_ offset: Int) -> Token? {
            let target = index + offset
            if target >= 0 && target < tokens.count {
                return tokens[target]
            }
            return nil
        }

        @discardableResult
        internal func consume() -> Token? {
            guard let token = current() else {
                return nil
            }
            index += 1
            return token
        }

        internal func matches(_ kind: TokenKind) -> Bool {
            current()?.kind == kind
        }

        @discardableResult
        internal func consumeIf(_ kind: TokenKind) -> Token? {
            guard matches(kind) else {
                return nil
            }
            return consume()
        }
    }
}

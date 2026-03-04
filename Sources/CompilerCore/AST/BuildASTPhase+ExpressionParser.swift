// swiftlint:disable file_length
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
            case .symbol(.lessThan): angle += 1
            case .symbol(.greaterThan): angle = max(0, angle - 1)
            case .symbol(.lParen): paren += 1
            case .symbol(.rParen): paren = max(0, paren - 1)
            case .symbol(.lBracket): bracket += 1
            case .symbol(.rBracket): bracket = max(0, bracket - 1)
            case .symbol(.lBrace): brace += 1
            case .symbol(.rBrace): brace = max(0, brace - 1)
            default: break
            }
        }
    }

    // swiftlint:disable:next type_body_length
    final class ExpressionParser {
        let tokens: ArraySlice<Token>
        let interner: StringInterner
        let astArena: ASTArena
        let diagnostics: DiagnosticEngine?
        var index: Int

        init(
            tokens: ArraySlice<Token>,
            interner: StringInterner,
            astArena: ASTArena,
            diagnostics: DiagnosticEngine? = nil
        ) {
            self.tokens = tokens
            self.interner = interner
            self.astArena = astArena
            self.diagnostics = diagnostics
            index = tokens.startIndex
        }

        convenience init(
            tokens: [Token],
            interner: StringInterner,
            astArena: ASTArena,
            diagnostics: DiagnosticEngine? = nil
        ) {
            self.init(tokens: tokens[...], interner: interner, astArena: astArena, diagnostics: diagnostics)
        }

        func parse() -> ExprID? {
            parseAssignmentOrExpression()
        }

        private func parseAssignmentOrExpression() -> ExprID? {
            parseExpression(minPrecedence: 0)
        }

        func parseExpression(minPrecedence: Int) -> ExprID? {
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
                   let next = peek(1), next.kind == .keyword(.is)
                {
                    let prec = 85
                    guard prec >= minPrecedence else { break }
                    _ = consume()
                    _ = consume()
                    guard let typeRef = parseTypeReference(token.range) else { break }
                    let range = mergeRanges(astArena.exprRange(lhs), nil, fallback: token.range)
                    lhs = astArena.appendExpr(.isCheck(expr: lhs, type: typeRef, negated: true, range: range))
                    continue
                }

                if let token = current(), token.kind == .keyword(.in) {
                    let prec = 85
                    guard prec >= minPrecedence else { break }
                    _ = consume()
                    guard let rhs = parseExpression(minPrecedence: prec + 1) else { break }
                    let range = mergeRanges(astArena.exprRange(lhs), astArena.exprRange(rhs), fallback: token.range)
                    lhs = astArena.appendExpr(.inExpr(lhs: lhs, rhs: rhs, range: range))
                    continue
                }

                if let token = current(), token.kind == .symbol(.bang),
                   let next = peek(1), next.kind == .keyword(.in)
                {
                    let prec = 85
                    guard prec >= minPrecedence else { break }
                    _ = consume()
                    _ = consume()
                    guard let rhs = parseExpression(minPrecedence: prec + 1) else { break }
                    let range = mergeRanges(astArena.exprRange(lhs), astArena.exprRange(rhs), fallback: token.range)
                    lhs = astArena.appendExpr(.notInExpr(lhs: lhs, rhs: rhs, range: range))
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

                // Check for known binary operators (symbol-based and known infix identifiers)
                if let op = binaryOperator(at: current()), precedence(of: op) >= minPrecedence {
                    guard let opToken = consume() else { break }
                    let assoc = associativity(of: op)
                    let nextMin = assoc == .right ? precedence(of: op) : precedence(of: op) + 1
                    guard let rhs = parseExpression(minPrecedence: nextMin) else { break }
                    let range = mergeRanges(astArena.exprRange(lhs), astArena.exprRange(rhs), fallback: opToken.range)
                    lhs = astArena.appendExpr(.binary(op: op, lhs: lhs, rhs: rhs, range: range))
                    continue
                }

                // General infix function call: any identifier in infix position
                // Kotlin grammar: infixFunctionCall = rangeExpression (simpleIdentifier rangeExpression)*
                // All infix functions share the same precedence level as range operators (.downTo / .step)
                let infixPrecedence = precedence(of: .downTo)
                if infixPrecedence >= minPrecedence,
                   let token = current(),
                   isInfixIdentifierToken(token),
                   let nextToken = peek(1),
                   canStartExpression(nextToken)
                {
                    guard let calleeName = identifierFromToken(token) else { break }
                    _ = consume()
                    guard let rhs = parseExpression(minPrecedence: infixPrecedence + 1) else { break }
                    let range = mergeRanges(astArena.exprRange(lhs), astArena.exprRange(rhs), fallback: token.range)
                    lhs = astArena.appendExpr(.memberCall(
                        receiver: lhs,
                        callee: calleeName,
                        typeArgs: [],
                        args: [CallArgument(expr: rhs)],
                        range: range
                    ))
                    continue
                }

                break
            }
            return lhs
        }

        private func parsePrefixUnary() -> ExprID? {
            guard let token = current() else {
                return nil
            }
            switch token.kind {
            case .symbol(.bang):
                if let next = peek(1), next.kind == .keyword(.is) || next.kind == .keyword(.in) {
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
            if index == tokens.startIndex { return true }
            guard index > tokens.startIndex, index - 1 >= tokens.startIndex else { return true }
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

        func mergeRanges(_ lhs: SourceRange?, _ rhs: SourceRange?, fallback: SourceRange) -> SourceRange {
            switch (lhs, rhs) {
            case let (lhs?, rhs?):
                SourceRange(start: lhs.start, end: rhs.end)
            case let (lhs?, nil):
                lhs
            case let (nil, rhs?):
                rhs
            default:
                fallback
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
            case .symbol(.dotDotLt):
                return .rangeUntil
            case let .identifier(name):
                let resolved = interner.resolve(name)
                if resolved == "downTo" { return .downTo }
                if resolved == "step" { return .step }
                return nil
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
                120
            case .add, .subtract:
                110
            case .rangeTo, .rangeUntil:
                100
            case .downTo:
                95
            case .step:
                95
            case .shl, .shr, .ushr, .bitwiseAnd, .bitwiseXor, .bitwiseOr:
                95
            case .elvis:
                90
            case .lessThan, .lessOrEqual, .greaterThan, .greaterOrEqual:
                80
            case .equal, .notEqual:
                70
            case .logicalAnd:
                60
            case .logicalOr:
                50
            }
        }

        private func associativity(of op: BinaryOp) -> Associativity {
            switch op {
            case .elvis:
                .right
            default:
                .left
            }
        }

        func tokenText(_ token: Token) -> InternedString? {
            switch token.kind {
            case let .identifier(name), let .backtickedIdentifier(name):
                name
            case let .keyword(keyword):
                interner.intern(keyword.rawValue)
            case let .softKeyword(keyword):
                interner.intern(keyword.rawValue)
            default:
                nil
            }
        }

        func identifierFromToken(_ token: Token) -> InternedString? {
            switch token.kind {
            case let .identifier(name), let .backtickedIdentifier(name):
                name
            default:
                nil
            }
        }

        /// Returns true if the token is an identifier that can serve as an infix function name.
        /// Excludes identifiers already handled as known BinaryOp (downTo, step) by binaryOperator().
        private func isInfixIdentifierToken(_ token: Token) -> Bool {
            switch token.kind {
            case let .identifier(name):
                let resolved = interner.resolve(name)
                // Exclude names already handled by binaryOperator()
                if resolved == "downTo" || resolved == "step" {
                    return false
                }
                return true
            case .backtickedIdentifier:
                // Note: backticked identifiers intentionally bypass the special BinaryOp handling.
                // `downTo` and `step` written with backticks are treated as general infix function
                // calls (desugared to memberCall), not as BinaryOp.downTo/step.
                return true
            default:
                return false
            }
        }

        /// Returns true if a token can start an expression (used for infix call lookahead).
        private func canStartExpression(_ token: Token) -> Bool {
            switch token.kind {
            case .identifier, .backtickedIdentifier:
                true
            case .intLiteral, .longLiteral, .floatLiteral, .doubleLiteral, .charLiteral:
                true
            case .keyword(.true), .keyword(.false), .keyword(.null):
                true
            case .keyword(.if), .keyword(.when), .keyword(.try), .keyword(.throw), .keyword(.return):
                true
            case .keyword(.for), .keyword(.while), .keyword(.do):
                true
            case .keyword(.super), .keyword(.this), .keyword(.object):
                true
            case .symbol(.lParen), .symbol(.lBrace), .symbol(.lBracket):
                true
            case .symbol(.minus), .symbol(.plus), .symbol(.bang):
                true
            case .symbol(.doubleColon):
                true
            case .stringQuote, .rawStringQuote:
                true
            case .softKeyword:
                true
            default:
                false
            }
        }

        @discardableResult
        func current() -> Token? {
            if index >= tokens.startIndex, index < tokens.endIndex {
                return tokens[index]
            }
            return nil
        }

        func peek(_ offset: Int) -> Token? {
            let target = index + offset
            if target >= tokens.startIndex, target < tokens.endIndex {
                return tokens[target]
            }
            return nil
        }

        @discardableResult
        func consume() -> Token? {
            guard let token = current() else {
                return nil
            }
            index += 1
            return token
        }

        func matches(_ kind: TokenKind) -> Bool {
            current()?.kind == kind
        }

        @discardableResult
        func consumeIf(_ kind: TokenKind) -> Token? {
            guard matches(kind) else {
                return nil
            }
            return consume()
        }
    }
}

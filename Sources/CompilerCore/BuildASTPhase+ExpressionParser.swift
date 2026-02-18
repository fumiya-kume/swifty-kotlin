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

        private func parsePostfixOrPrimary() -> ExprID? {
            guard var expr = parsePrimary() else {
                return nil
            }
            while true {
                if matches(.symbol(.lessThan)) {
                    let savedIndex = index
                    if let typeArgs = tryParseExplicitTypeArgs() {
                        if matches(.symbol(.lParen)) {
                            guard let open = consume() else { break }
                            let args = parseCallArguments()
                            let close = consumeIf(.symbol(.rParen))
                            let fallbackEnd = close?.range.end ?? open.range.end
                            let endRange = SourceRange(start: fallbackEnd, end: fallbackEnd)
                            let range = mergeRanges(astArena.exprRange(expr), close?.range ?? endRange, fallback: open.range)
                            expr = astArena.appendExpr(.call(callee: expr, typeArgs: typeArgs, args: args, range: range))
                            continue
                        }
                    }
                    index = savedIndex
                }

                if matches(.symbol(.lParen)) {
                    guard let open = consume() else { break }
                    let args = parseCallArguments()
                    let close = consumeIf(.symbol(.rParen))
                    let fallbackEnd = close?.range.end ?? open.range.end
                    let endRange = SourceRange(start: fallbackEnd, end: fallbackEnd)
                    let range = mergeRanges(astArena.exprRange(expr), close?.range ?? endRange, fallback: open.range)
                    expr = astArena.appendExpr(.call(callee: expr, typeArgs: [], args: args, range: range))
                    continue
                }

                if matches(.symbol(.lBracket)) {
                    guard let open = consume() else { break }
                    let indexExpr = parseExpression(minPrecedence: 0)
                    let close = consumeIf(.symbol(.rBracket))
                    guard let indexExpr else {
                        break
                    }
                    let fallbackEnd = close?.range.end ?? open.range.end
                    let fallbackRange = SourceRange(start: fallbackEnd, end: fallbackEnd)
                    let range = mergeRanges(astArena.exprRange(expr), close?.range ?? fallbackRange, fallback: open.range)
                    expr = astArena.appendExpr(.arrayAccess(array: expr, index: indexExpr, range: range))
                    continue
                }

                if matches(.symbol(.bangBang)) {
                    guard let bangBang = consume() else { break }
                    let range = mergeRanges(astArena.exprRange(expr), bangBang.range, fallback: bangBang.range)
                    expr = astArena.appendExpr(.nullAssert(expr: expr, range: range))
                    continue
                }

                if matches(.symbol(.questionDot)) {
                    guard let qDot = consume(),
                          let memberToken = consume(),
                          let memberName = tokenText(memberToken) else {
                        break
                    }
                    var args: [CallArgument] = []
                    var typeArgs: [TypeRefID] = []
                    var memberEndRange = memberToken.range
                    if matches(.symbol(.lessThan)) {
                        let savedIndex = index
                        if let ta = tryParseExplicitTypeArgs() {
                            typeArgs = ta
                        } else {
                            index = savedIndex
                        }
                    }
                    if matches(.symbol(.lParen)),
                       let open = consume() {
                        args = parseCallArguments()
                        let close = consumeIf(.symbol(.rParen))
                        memberEndRange = close?.range ?? open.range
                    }
                    let range = mergeRanges(astArena.exprRange(expr), memberEndRange, fallback: qDot.range)
                    expr = astArena.appendExpr(.safeMemberCall(
                        receiver: expr,
                        callee: memberName,
                        typeArgs: typeArgs,
                        args: args,
                        range: range
                    ))
                    continue
                }

                guard matches(.symbol(.dot)) else {
                    break
                }
                guard let dot = consume(),
                      let memberToken = consume(),
                      let memberName = tokenText(memberToken) else {
                    break
                }
                var args: [CallArgument] = []
                var typeArgs: [TypeRefID] = []
                var memberEndRange = memberToken.range
                if matches(.symbol(.lessThan)) {
                    let savedIndex = index
                    if let ta = tryParseExplicitTypeArgs() {
                        typeArgs = ta
                    } else {
                        index = savedIndex
                    }
                }
                if matches(.symbol(.lParen)),
                   let open = consume() {
                    args = parseCallArguments()
                    let close = consumeIf(.symbol(.rParen))
                    memberEndRange = close?.range ?? open.range
                }
                let range = mergeRanges(astArena.exprRange(expr), memberEndRange, fallback: dot.range)
                expr = astArena.appendExpr(.memberCall(
                    receiver: expr,
                    callee: memberName,
                    typeArgs: typeArgs,
                    args: args,
                    range: range
                ))
            }
            return expr
        }

        private func parseCallArguments() -> [CallArgument] {
            var args: [CallArgument] = []
            if !matches(.symbol(.rParen)) {
                while true {
                    if let argument = parseCallArgument() {
                        args.append(argument)
                    }
                    if matches(.symbol(.comma)) {
                        _ = consume()
                        continue
                    }
                    break
                }
            }
            return args
        }

        private func parseCallArgument() -> CallArgument? {
            var isSpread = false
            if matches(.symbol(.star)) {
                _ = consume()
                isSpread = true
            }

            var label: InternedString?
            if let first = current(),
               let second = peek(1),
               isArgumentLabelToken(first.kind),
               second.kind == .symbol(.assign) {
                label = tokenText(first)
                _ = consume()
                _ = consume()
            }

            guard let expr = parseExpression(minPrecedence: 0) else {
                return nil
            }
            return CallArgument(label: label, isSpread: isSpread, expr: expr)
        }

        private func isArgumentLabelToken(_ kind: TokenKind) -> Bool {
            switch kind {
            case .identifier, .backtickedIdentifier, .keyword, .softKeyword:
                return true
            default:
                return false
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

        private func identifierFromToken(_ token: Token) -> InternedString? {
            switch token.kind {
            case .identifier(let name), .backtickedIdentifier(let name):
                return name
            default:
                return nil
            }
        }

        private func parsePrimary() -> ExprID? {
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
                return astArena.appendExpr(.breakExpr(range: token.range))

            case .keyword(.continue):
                _ = consume()
                return astArena.appendExpr(.continueExpr(range: token.range))

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

            case .keyword(let keyword):
                _ = consume()
                return astArena.appendExpr(.nameRef(interner.intern(keyword.rawValue), token.range))

            case .softKeyword(let keyword):
                _ = consume()
                return astArena.appendExpr(.nameRef(interner.intern(keyword.rawValue), token.range))

            case .stringQuote, .rawStringQuote:
                return parseStringLiteral()

            case .symbol(.lParen):
                _ = consume()
                let expr = parseExpression(minPrecedence: 0)
                _ = consumeIf(.symbol(.rParen))
                return expr

            case .symbol(.lBrace):
                return parseBlockExpression()

            default:
                return nil
            }
        }

        private func parseStringLiteral() -> ExprID? {
            guard let open = consume() else { return nil }
            var end = open.range.end
            let closingKind = open.kind

            var hasTemplate = false
            var scanIdx = index
            while scanIdx < tokens.count {
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

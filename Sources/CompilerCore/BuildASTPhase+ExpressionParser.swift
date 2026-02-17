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
        private let tokens: [Token]
        private let interner: StringInterner
        private let astArena: ASTArena
        private var index: Int = 0

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

        private func parseExpression(minPrecedence: Int) -> ExprID? {
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

        private func tokenText(_ token: Token) -> InternedString? {
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

        private func parseWhenExpression() -> ExprID? {
            guard let whenToken = consume() else {
                return nil
            }
            guard consumeIf(.symbol(.lParen)) != nil else {
                return nil
            }
            guard let subject = parseExpression(minPrecedence: 0) else {
                return nil
            }
            _ = consumeIf(.symbol(.rParen))
            guard consumeIf(.symbol(.lBrace)) != nil else {
                return nil
            }

            var branches: [WhenBranch] = []
            var elseExpr: ExprID?
            var end = whenToken.range.end

            while let token = current() {
                if token.kind == .symbol(.rBrace) {
                    end = token.range.end
                    _ = consume()
                    break
                }

                let branchStart = token.range.start
                var condition: ExprID?
                if token.kind == .keyword(.else) {
                    _ = consume()
                } else {
                    condition = parseExpression(minPrecedence: 0)
                }

                _ = consumeIf(.symbol(.arrow))
                let body = parseExpression(minPrecedence: 0)
                while matches(.symbol(.semicolon)) || matches(.symbol(.comma)) {
                    _ = consume()
                }

                if let body {
                    let branchRange = SourceRange(start: branchStart, end: astArena.exprRange(body)?.end ?? branchStart)
                    let branch = WhenBranch(condition: condition, body: body, range: branchRange)
                    if condition == nil {
                        elseExpr = body
                    } else {
                        branches.append(branch)
                    }
                    end = branchRange.end
                }
            }

            let range = SourceRange(start: whenToken.range.start, end: end)
            return astArena.appendExpr(.whenExpr(subject: subject, branches: branches, elseExpr: elseExpr, range: range))
        }

        private func parseReturnExpression() -> ExprID? {
            guard let returnToken = consume() else {
                return nil
            }
            let value = parseExpression(minPrecedence: 0)
            let end = value.flatMap { astArena.exprRange($0)?.end } ?? returnToken.range.end
            let range = SourceRange(start: returnToken.range.start, end: end)
            return astArena.appendExpr(.returnExpr(value: value, range: range))
        }

        private func parseThrowExpression() -> ExprID? {
            guard let throwToken = consume() else {
                return nil
            }
            guard let value = parseExpression(minPrecedence: 0) else {
                return nil
            }
            let end = astArena.exprRange(value)?.end ?? throwToken.range.end
            let range = SourceRange(start: throwToken.range.start, end: end)
            return astArena.appendExpr(.throwExpr(value: value, range: range))
        }

        private func parseForExpression() -> ExprID? {
            guard let forToken = consume() else {
                return nil
            }
            guard consumeIf(.symbol(.lParen)) != nil else {
                return nil
            }

            var loopVariable: InternedString?
            if let token = current(),
               token.kind != .keyword(.in),
               let name = tokenText(token) {
                loopVariable = name
                _ = consume()
            }

            while let token = current(),
                  token.kind != .keyword(.in),
                  token.kind != .symbol(.rParen) {
                _ = consume()
            }
            _ = consumeIf(.keyword(.in))

            guard let iterable = parseExpression(minPrecedence: 0) else {
                return nil
            }
            _ = consumeIf(.symbol(.rParen))

            guard let body = parseExpression(minPrecedence: 0) else {
                return nil
            }
            let end = astArena.exprRange(body)?.end ?? forToken.range.end
            let range = SourceRange(start: forToken.range.start, end: end)
            return astArena.appendExpr(.forExpr(loopVariable: loopVariable, iterable: iterable, body: body, range: range))
        }

        private func parseWhileExpression() -> ExprID? {
            guard let whileToken = consume() else {
                return nil
            }
            guard consumeIf(.symbol(.lParen)) != nil else {
                return nil
            }
            guard let condition = parseExpression(minPrecedence: 0) else {
                return nil
            }
            _ = consumeIf(.symbol(.rParen))
            guard let body = parseExpression(minPrecedence: 0) else {
                return nil
            }
            let end = astArena.exprRange(body)?.end ?? whileToken.range.end
            let range = SourceRange(start: whileToken.range.start, end: end)
            return astArena.appendExpr(.whileExpr(condition: condition, body: body, range: range))
        }

        private func parseDoWhileExpression() -> ExprID? {
            guard let doToken = consume() else {
                return nil
            }
            guard let body = parseExpression(minPrecedence: 0) else {
                return nil
            }
            guard matches(.keyword(.while)),
                  consume() != nil,
                  consumeIf(.symbol(.lParen)) != nil,
                  let condition = parseExpression(minPrecedence: 0) else {
                return nil
            }
            _ = consumeIf(.symbol(.rParen))
            let end = astArena.exprRange(condition)?.end ?? astArena.exprRange(body)?.end ?? doToken.range.end
            let range = SourceRange(start: doToken.range.start, end: end)
            return astArena.appendExpr(.doWhileExpr(body: body, condition: condition, range: range))
        }

        private func parseIfExpression() -> ExprID? {
            guard let ifToken = consume() else {
                return nil
            }
            guard consumeIf(.symbol(.lParen)) != nil else {
                return nil
            }
            guard let condition = parseExpression(minPrecedence: 0) else {
                return nil
            }
            _ = consumeIf(.symbol(.rParen))

            guard let thenExpr = parseExpression(minPrecedence: 0) else {
                return nil
            }

            var elseExpr: ExprID?
            if matches(.keyword(.else)) {
                _ = consume()
                elseExpr = parseExpression(minPrecedence: 0)
            }

            let end = elseExpr
                .flatMap { astArena.exprRange($0)?.end }
                ?? astArena.exprRange(thenExpr)?.end
                ?? ifToken.range.end
            let range = SourceRange(start: ifToken.range.start, end: end)
            return astArena.appendExpr(.ifExpr(condition: condition, thenExpr: thenExpr, elseExpr: elseExpr, range: range))
        }

        private func parseTryExpression() -> ExprID? {
            guard let tryToken = consume() else {
                return nil
            }
            guard let bodyExpr = parseExpression(minPrecedence: 0) else {
                return nil
            }

            var catchClauses: [CatchClause] = []
            while matches(.keyword(.catch)) {
                let catchToken = consume()!
                let (paramName, paramTypeName) = parseCatchParameter()
                if let catchExpr = parseExpression(minPrecedence: 0) {
                    let clauseEnd = astArena.exprRange(catchExpr)?.end ?? catchToken.range.end
                    let clauseRange = SourceRange(start: catchToken.range.start, end: clauseEnd)
                    catchClauses.append(CatchClause(paramName: paramName, paramTypeName: paramTypeName, body: catchExpr, range: clauseRange))
                } else {
                    break
                }
            }

            var finallyExpr: ExprID?
            if matches(.keyword(.finally)) {
                _ = consume()
                finallyExpr = parseExpression(minPrecedence: 0)
            }

            let tailEnd = finallyExpr
                .flatMap { astArena.exprRange($0)?.end }
                ?? catchClauses.last.flatMap { astArena.exprRange($0.body)?.end }
                ?? astArena.exprRange(bodyExpr)?.end
                ?? tryToken.range.end
            let range = SourceRange(start: tryToken.range.start, end: tailEnd)
            return astArena.appendExpr(.tryExpr(body: bodyExpr, catchClauses: catchClauses, finallyExpr: finallyExpr, range: range))
        }

        private func parseCatchParameter() -> (paramName: InternedString?, paramTypeName: InternedString?) {
            guard matches(.symbol(.lParen)) else {
                return (nil, nil)
            }
            _ = consume()
            var paramName: InternedString?
            var paramTypeName: InternedString?
            if case .identifier(let name) = current()?.kind {
                paramName = name
                _ = consume()
                if matches(.symbol(.colon)) {
                    _ = consume()
                    if case .identifier(let typeName) = current()?.kind {
                        paramTypeName = typeName
                        _ = consume()
                    }
                }
            }
            var depth = 1
            while let token = current(), depth > 0 {
                _ = consume()
                switch token.kind {
                case .symbol(.lParen):
                    depth += 1
                case .symbol(.rParen):
                    depth -= 1
                default:
                    continue
                }
            }
            return (paramName, paramTypeName)
        }

        private func parseBlockExpression() -> ExprID? {
            guard let openBrace = consume() else {
                return nil
            }
            var depth = 1
            var blockTokens: [Token] = []
            var end = openBrace.range.end

            while let token = current() {
                _ = consume()
                switch token.kind {
                case .symbol(.lBrace):
                    depth += 1
                    blockTokens.append(token)
                case .symbol(.rBrace):
                    depth -= 1
                    if depth == 0 {
                        end = token.range.end
                        break
                    }
                    blockTokens.append(token)
                default:
                    blockTokens.append(token)
                }
                if depth == 0 {
                    break
                }
            }

            let trimmed = blockTokens.filter { token in
                token.kind != .symbol(.semicolon)
            }
            if let nestedExpr = ExpressionParser(tokens: trimmed, interner: interner, astArena: astArena).parse() {
                return nestedExpr
            }
            let range = SourceRange(start: openBrace.range.start, end: end)
            return astArena.appendExpr(.nameRef(interner.intern("Unit"), range))
        }

        private func skipBalancedParenthesisIfNeeded() {
            guard matches(.symbol(.lParen)) else {
                return
            }
            _ = consume()
            var depth = 1
            while let token = current(), depth > 0 {
                _ = consume()
                switch token.kind {
                case .symbol(.lParen):
                    depth += 1
                case .symbol(.rParen):
                    depth -= 1
                default:
                    continue
                }
            }
        }

        private func mergeRanges(_ lhs: SourceRange?, _ rhs: SourceRange?, fallback: SourceRange) -> SourceRange {
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

        private func parseTypeReference(_ fallbackRange: SourceRange) -> TypeRefID? {
            guard let token = current() else { return nil }
            let name: InternedString
            switch token.kind {
            case .identifier(let n), .backtickedIdentifier(let n):
                _ = consume()
                name = n
            case .keyword(let kw):
                _ = consume()
                name = interner.intern(kw.rawValue)
            case .softKeyword(let kw):
                _ = consume()
                name = interner.intern(kw.rawValue)
            default:
                return nil
            }
            var typeArgs: [TypeArgRef] = []
            if matches(.symbol(.lessThan)) {
                let savedIndex = index
                if let parsedArgs = tryParseTypeArgRefs() {
                    typeArgs = parsedArgs
                } else {
                    index = savedIndex
                }
            }
            let isNullable = consumeIf(.symbol(.question)) != nil
            return astArena.appendTypeRef(.named(path: [name], args: typeArgs, nullable: isNullable))
        }

        private func tryParseExplicitTypeArgs() -> [TypeRefID]? {
            guard matches(.symbol(.lessThan)) else { return nil }
            let savedIndex = index
            _ = consume()
            var refs: [TypeRefID] = []
            while true {
                guard let token = current() else {
                    index = savedIndex
                    return nil
                }
                if token.kind == .symbol(.greaterThan) {
                    if refs.isEmpty {
                        index = savedIndex
                        return nil
                    }
                    _ = consume()
                    return refs
                }
                if !refs.isEmpty {
                    guard consumeIf(.symbol(.comma)) != nil else {
                        index = savedIndex
                        return nil
                    }
                }
                guard let typeRef = parseInlineTypeRef() else {
                    index = savedIndex
                    return nil
                }
                refs.append(typeRef)
            }
        }

        private func tryParseTypeArgRefs() -> [TypeArgRef]? {
            guard matches(.symbol(.lessThan)) else { return nil }
            let savedIndex = index
            _ = consume()
            var args: [TypeArgRef] = []
            while true {
                guard let token = current() else {
                    index = savedIndex
                    return nil
                }
                if token.kind == .symbol(.greaterThan) {
                    _ = consume()
                    return args
                }
                if !args.isEmpty {
                    guard consumeIf(.symbol(.comma)) != nil else {
                        index = savedIndex
                        return nil
                    }
                    guard let freshToken = current() else {
                        index = savedIndex
                        return nil
                    }
                    if freshToken.kind == .symbol(.greaterThan) {
                        _ = consume()
                        return args
                    }
                    if freshToken.kind == .symbol(.star) {
                        _ = consume()
                        args.append(.star)
                        continue
                    }
                    var variance: TypeVariance = .invariant
                    if case .softKeyword(.out) = freshToken.kind {
                        variance = .out
                        _ = consume()
                    } else if case .keyword(.in) = freshToken.kind {
                        variance = .in
                        _ = consume()
                    }
                    guard let innerRef = parseInlineTypeRef() else {
                        index = savedIndex
                        return nil
                    }
                    switch variance {
                    case .invariant: args.append(.invariant(innerRef))
                    case .out: args.append(.out(innerRef))
                    case .in: args.append(.in(innerRef))
                    }
                    continue
                }
                if token.kind == .symbol(.star) {
                    _ = consume()
                    args.append(.star)
                    continue
                }
                var variance: TypeVariance = .invariant
                if case .softKeyword(.out) = token.kind {
                    variance = .out
                    _ = consume()
                } else if case .keyword(.in) = token.kind {
                    variance = .in
                    _ = consume()
                }
                guard let innerRef = parseInlineTypeRef() else {
                    index = savedIndex
                    return nil
                }
                switch variance {
                case .invariant: args.append(.invariant(innerRef))
                case .out: args.append(.out(innerRef))
                case .in: args.append(.in(innerRef))
                }
            }
        }

        private func parseInlineTypeRef() -> TypeRefID? {
            guard let token = current() else { return nil }
            let name: InternedString
            switch token.kind {
            case .identifier(let n), .backtickedIdentifier(let n):
                _ = consume()
                name = n
            case .keyword(let kw):
                _ = consume()
                name = interner.intern(kw.rawValue)
            case .softKeyword(let kw):
                _ = consume()
                name = interner.intern(kw.rawValue)
            default:
                return nil
            }
            var innerArgs: [TypeArgRef] = []
            if matches(.symbol(.lessThan)) {
                let saved = index
                if let parsed = tryParseTypeArgRefs() {
                    innerArgs = parsed
                } else {
                    index = saved
                }
            }
            let isNullable = consumeIf(.symbol(.question)) != nil
            return astArena.appendTypeRef(.named(path: [name], args: innerArgs, nullable: isNullable))
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

        private func current() -> Token? {
            if index >= 0 && index < tokens.count {
                return tokens[index]
            }
            return nil
        }

        private func peek(_ offset: Int) -> Token? {
            let target = index + offset
            if target >= 0 && target < tokens.count {
                return tokens[target]
            }
            return nil
        }

        private func consume() -> Token? {
            guard let token = current() else {
                return nil
            }
            index += 1
            return token
        }

        private func matches(_ kind: TokenKind) -> Bool {
            current()?.kind == kind
        }

        private func consumeIf(_ kind: TokenKind) -> Token? {
            guard matches(kind) else {
                return nil
            }
            return consume()
        }
    }
}

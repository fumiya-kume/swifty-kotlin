import Foundation

extension BuildASTPhase.ExpressionParser {
    internal func parsePostfixOrPrimary() -> ExprID? {
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

            let isSafeDot = matches(.symbol(.questionDot))
            let isDot = isSafeDot || matches(.symbol(.dot))
            guard isDot else {
                break
            }
            guard let dotToken = consume(),
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
            let range = mergeRanges(astArena.exprRange(expr), memberEndRange, fallback: dotToken.range)
            if isSafeDot {
                expr = astArena.appendExpr(.safeMemberCall(
                    receiver: expr,
                    callee: memberName,
                    typeArgs: typeArgs,
                    args: args,
                    range: range
                ))
            } else {
                expr = astArena.appendExpr(.memberCall(
                    receiver: expr,
                    callee: memberName,
                    typeArgs: typeArgs,
                    args: args,
                    range: range
                ))
            }
        }
        return expr
    }

    internal func parseCallArguments() -> [CallArgument] {
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

    internal func parseCallArgument() -> CallArgument? {
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

    internal func isArgumentLabelToken(_ kind: TokenKind) -> Bool {
        switch kind {
        case .identifier, .backtickedIdentifier, .keyword, .softKeyword:
            return true
        default:
            return false
        }
    }
}

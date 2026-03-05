import Foundation

extension BuildASTPhase.ExpressionParser {
    func parsePostfixOrPrimary() -> ExprID? {
        guard var expr = parsePrimary() else {
            return nil
        }
        while true {
            if matches(.symbol(.lessThan)) {
                let savedIndex = index
                if let typeArgs = tryParseExplicitTypeArgs() {
                    if matches(.symbol(.lParen)) {
                        guard let open = consume() else { break }
                        var args = parseCallArguments()
                        let close = consumeIf(.symbol(.rParen))
                        var callEndRange = close?.range ?? open.range
                        // Trailing lambda without parentheses: foo<T> { ... }.
                        if matches(.symbol(.lBrace)),
                           let braceToken = current(),
                           let trailingLambda = parseLambdaLiteral(allowImplicitEmptyParams: true)
                        {
                            args.append(CallArgument(expr: trailingLambda))
                            callEndRange = astArena.exprRange(trailingLambda) ?? braceToken.range
                        }
                        let fallbackEnd = close?.range.end ?? open.range.end
                        let endRange = SourceRange(start: fallbackEnd, end: fallbackEnd)
                        let range = mergeRanges(astArena.exprRange(expr), callEndRange, fallback: endRange)
                        expr = astArena.appendExpr(.call(callee: expr, typeArgs: typeArgs, args: args, range: range))
                        continue
                    }
                    // Trailing lambda without parentheses: foo<T> { ... }.
                    if matches(.symbol(.lBrace)),
                       let braceToken = current(),
                       let trailingLambda = parseLambdaLiteral(allowImplicitEmptyParams: true)
                    {
                        let trailingRange = astArena.exprRange(trailingLambda) ?? braceToken.range
                        let range = mergeRanges(astArena.exprRange(expr), trailingRange, fallback: trailingRange)
                        expr = astArena.appendExpr(.call(
                            callee: expr,
                            typeArgs: typeArgs,
                            args: [CallArgument(expr: trailingLambda)],
                            range: range
                        ))
                        continue
                    }
                }
                index = savedIndex
            }

            if matches(.symbol(.lParen)) {
                guard let open = consume() else { break }
                var args = parseCallArguments()
                let close = consumeIf(.symbol(.rParen))
                var callEndRange = close?.range ?? open.range
                // Trailing lambda after a parenthesized call: foo(...) { ... }.
                if matches(.symbol(.lBrace)),
                   let braceToken = current(),
                   let trailingLambda = parseLambdaLiteral(allowImplicitEmptyParams: true)
                {
                    args.append(CallArgument(expr: trailingLambda))
                    callEndRange = astArena.exprRange(trailingLambda) ?? braceToken.range
                }
                let fallbackEnd = close?.range.end ?? open.range.end
                let endRange = SourceRange(start: fallbackEnd, end: fallbackEnd)
                let range = mergeRanges(astArena.exprRange(expr), callEndRange, fallback: endRange)
                expr = astArena.appendExpr(.call(callee: expr, typeArgs: [], args: args, range: range))
                continue
            }

            // Trailing lambda without parentheses: foo { ... }.
            if matches(.symbol(.lBrace)),
               let braceToken = current(),
               let trailingLambda = parseLambdaLiteral(allowImplicitEmptyParams: true)
            {
                let trailingRange = astArena.exprRange(trailingLambda) ?? braceToken.range
                let range = mergeRanges(astArena.exprRange(expr), trailingRange, fallback: trailingRange)
                expr = astArena.appendExpr(.call(
                    callee: expr,
                    typeArgs: [],
                    args: [CallArgument(expr: trailingLambda)],
                    range: range
                ))
                continue
            }

            if matches(.symbol(.lBracket)) {
                guard let open = consume() else { break }
                var indices: [ExprID] = []
                if !matches(.symbol(.rBracket)) {
                    while true {
                        guard let indexExpr = parseExpression(minPrecedence: 0) else { break }
                        indices.append(indexExpr)
                        if matches(.symbol(.comma)) {
                            _ = consume()
                            continue
                        }
                        break
                    }
                }
                let close = consumeIf(.symbol(.rBracket))
                guard !indices.isEmpty else {
                    break
                }
                let fallbackEnd = close?.range.end ?? open.range.end
                let fallbackRange = SourceRange(start: fallbackEnd, end: fallbackEnd)
                let range = mergeRanges(astArena.exprRange(expr), close?.range ?? fallbackRange, fallback: open.range)
                expr = astArena.appendExpr(.indexedAccess(receiver: expr, indices: indices, range: range))
                continue
            }

            if matches(.symbol(.bangBang)) {
                guard let bangBang = consume() else { break }
                let range = mergeRanges(astArena.exprRange(expr), bangBang.range, fallback: bangBang.range)
                expr = astArena.appendExpr(.nullAssert(expr: expr, range: range))
                continue
            }

            if matches(.symbol(.doubleColon)) {
                guard let opToken = consume(),
                      let memberToken = current(),
                      let memberName = tokenText(memberToken)
                else {
                    break
                }
                _ = consume()
                let range = mergeRanges(astArena.exprRange(expr), memberToken.range, fallback: opToken.range)
                expr = astArena.appendExpr(.callableRef(receiver: expr, member: memberName, range: range))
                continue
            }

            let isSafeDot = matches(.symbol(.questionDot))
            let isDot = isSafeDot || matches(.symbol(.dot))
            guard isDot else {
                break
            }
            guard let dotToken = consume(),
                  let memberToken = consume(),
                  let memberName = tokenText(memberToken)
            else {
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
               let open = consume()
            {
                args = parseCallArguments()
                let close = consumeIf(.symbol(.rParen))
                memberEndRange = close?.range ?? open.range
            }
            // Trailing lambda: attach `{ ... }` as the last argument (Kotlin grammar).
            if matches(.symbol(.lBrace)),
               let trailingLambda = parseLambdaLiteral(allowImplicitEmptyParams: true)
            {
                args.append(CallArgument(expr: trailingLambda))
                memberEndRange = astArena.exprRange(trailingLambda) ?? memberEndRange
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

    func parseCallArguments() -> [CallArgument] {
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

    func parseCallArgument() -> CallArgument? {
        var isSpread = false
        if matches(.symbol(.star)) {
            _ = consume()
            isSpread = true
        }

        var label: InternedString?
        if let first = current(),
           let second = peek(1),
           isArgumentLabelToken(first.kind),
           second.kind == .symbol(.assign)
        {
            label = tokenText(first)
            _ = consume()
            _ = consume()
        }

        guard let expr = parseExpression(minPrecedence: 0) else {
            return nil
        }
        return CallArgument(label: label, isSpread: isSpread, expr: expr)
    }

    func isArgumentLabelToken(_ kind: TokenKind) -> Bool {
        switch kind {
        case .identifier, .backtickedIdentifier, .keyword, .softKeyword:
            true
        default:
            false
        }
    }
}

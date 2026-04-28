import Foundation

extension BuildASTPhase.ExpressionParser {
    func parseTypeReference(_ fallbackRange: SourceRange) -> TypeRefID? {
        _ = fallbackRange
        let options = TypeRefParserCore.Options.expressionInline
        guard let parsed = TypeRefParserCore.parseTypeRefPrefix(
            tokens[index...],
            interner: interner,
            astArena: astArena,
            options: options,
            diagnostics: diagnostics
        ) else {
            return nil
        }
        index += parsed.consumed
        return parsed.ref
    }

    func tryParseExplicitTypeArgs() -> [TypeRefID]? {
        guard matches(.symbol(.lessThan)) else { return nil }
        let savedIndex = index
        var options = TypeRefParserCore.Options.expressionInline
        options.allowFunctionType = true
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
            guard let parsed = TypeRefParserCore.parseTypeRefPrefix(
                tokens[index...],
                interner: interner,
                astArena: astArena,
                options: options,
                diagnostics: diagnostics
            ) else {
                index = savedIndex
                return nil
            }
            index += parsed.consumed
            refs.append(parsed.ref)
        }
    }

}

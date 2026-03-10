import Foundation

extension BuildASTPhase.ExpressionParser {
    func parseLambdaBody(
        bodySlice: ArraySlice<Token>,
        fallbackStart: SourceLocation
    ) -> ExprID {
        if let blockExpr = parseLambdaBodyAsBlockExpression(
            bodySlice: bodySlice,
            fallbackStart: fallbackStart
        ) {
            return blockExpr
        }

        if let parsedExpr = BuildASTPhase.ExpressionParser(
            tokens: bodySlice,
            interner: interner,
            astArena: astArena
        ).parse() {
            return parsedExpr
        }

        return astArena.appendExpr(.blockExpr(
            statements: [],
            trailingExpr: nil,
            range: lambdaBodyRange(bodySlice: bodySlice, fallbackStart: fallbackStart)
        ))
    }

    private func parseLambdaBodyAsBlockExpression(
        bodySlice: ArraySlice<Token>,
        fallbackStart: SourceLocation
    ) -> ExprID? {
        let bodyTokens = Array(bodySlice)
        let ranges = splitBlockTokensIntoStatementRanges(bodyTokens)
        guard !ranges.isEmpty else {
            return nil
        }

        var statements = parseLambdaBodyStatements(ranges: ranges, tokens: bodyTokens)
        guard !statements.isEmpty else {
            return nil
        }

        let hasStatementOnlyBody = statements.contains { statementID in
            guard let statement = astArena.expr(statementID) else { return false }
            switch statement {
            case .localDecl, .localAssign, .memberAssign, .indexedAssign,
                 .compoundAssign, .indexedCompoundAssign, .localFunDecl:
                return true
            default:
                return false
            }
        }
        if ranges.count == 1, !hasStatementOnlyBody {
            return nil
        }

        let trailingExpr = lambdaTrailingExpression(from: &statements)
        return astArena.appendExpr(.blockExpr(
            statements: statements,
            trailingExpr: trailingExpr,
            range: lambdaBodyRange(bodySlice: bodySlice, fallbackStart: fallbackStart)
        ))
    }

    private func parseLambdaBodyStatements(
        ranges: [(Int, Int)],
        tokens: [Token]
    ) -> [ExprID] {
        var statements: [ExprID] = []
        for (start, end) in ranges {
            let group = ArraySlice(tokens[start ..< end])
            guard !group.isEmpty else {
                continue
            }
            if let statementExpr = parseLambdaBodyStatement(from: group) {
                statements.append(statementExpr)
            }
        }
        return statements
    }

    private func parseLambdaBodyStatement(from group: ArraySlice<Token>) -> ExprID? {
        if let localDecl = parseLocalDeclFromSlice(group) {
            return localDecl
        }
        if let localAssign = parseLocalAssignFromSlice(group) {
            return localAssign
        }
        return BuildASTPhase.ExpressionParser(
            tokens: group,
            interner: interner,
            astArena: astArena
        ).parse()
    }

    private func lambdaTrailingExpression(from statements: inout [ExprID]) -> ExprID? {
        guard let lastID = statements.last, let lastExpr = astArena.expr(lastID) else {
            return nil
        }

        switch lastExpr {
        case .localDecl, .localAssign, .memberAssign, .indexedAssign,
             .compoundAssign, .indexedCompoundAssign, .localFunDecl:
            return nil
        default:
            _ = statements.popLast()
            return lastID
        }
    }

    private func lambdaBodyRange(
        bodySlice: ArraySlice<Token>,
        fallbackStart: SourceLocation
    ) -> SourceRange {
        if let firstToken = bodySlice.first, let lastToken = bodySlice.last {
            return SourceRange(start: firstToken.range.start, end: lastToken.range.end)
        }
        return SourceRange(start: fallbackStart, end: fallbackStart)
    }
}

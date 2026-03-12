import Foundation

extension BuildASTPhase {
    struct LocalStatementCoreContext {
        let interner: StringInterner
        let astArena: ASTArena
        let parseExpression: (ArraySlice<Token>) -> ExprID?
        let parseTypeReference: ([Token]) -> TypeRefID?
        let resolveDeclarationName: (Token, StringInterner) -> InternedString?
    }

    struct LocalStatementCoreOptions {
        var allowMemberAssign: Bool
        var rejectValVarSimpleAssignLHS: Bool
        var strictInitializerWhenAssignPresent: Bool

        static let declaration = LocalStatementCoreOptions(
            allowMemberAssign: false,
            rejectValVarSimpleAssignLHS: true,
            strictInitializerWhenAssignPresent: true
        )

        static let blockExpression = LocalStatementCoreOptions(
            allowMemberAssign: true,
            rejectValVarSimpleAssignLHS: false,
            strictInitializerWhenAssignPresent: false
        )
    }

    enum LocalStatementCore {
        static func isLocalDeclarationTokens(_ tokens: [Token]) -> Bool {
            guard !tokens.isEmpty else {
                return false
            }
            var index = 0
            while index < tokens.count {
                if case let .keyword(keyword) = tokens[index].kind,
                   KotlinParser.isDeclarationModifierKeyword(keyword)
                {
                    index += 1
                    continue
                }
                break
            }
            guard index < tokens.count else {
                return false
            }
            switch tokens[index].kind {
            case .keyword(.val), .keyword(.var):
                return true
            default:
                return false
            }
        }

        static func isLocalAssignmentTokens(_ tokens: [Token]) -> Bool {
            guard tokens.count >= 3 else {
                return false
            }
            let assignmentOps: [TokenKind] = [
                .symbol(.assign),
                .symbol(.plusAssign), .symbol(.minusAssign),
                .symbol(.starAssign), .symbol(.slashAssign), .symbol(.percentAssign),
            ]
            var depth = BuildASTPhase.BracketDepth()
            for token in tokens {
                if assignmentOps.contains(token.kind), depth.isAtTopLevel {
                    return true
                }
                depth.track(token.kind)
            }
            return false
        }

        static func parseLocalDeclaration(
            from statementTokens: [Token],
            context: LocalStatementCoreContext,
            options: LocalStatementCoreOptions
        ) -> ExprID? {
            parseLocalDeclaration(from: statementTokens[...], context: context, options: options)
        }

        static func parseLocalDeclaration(
            from statementTokens: ArraySlice<Token>,
            context: LocalStatementCoreContext,
            options: LocalStatementCoreOptions
        ) -> ExprID? {
            guard !statementTokens.isEmpty else {
                return nil
            }

            var startIndex = statementTokens.startIndex
            while startIndex < statementTokens.endIndex,
                  case let .keyword(keyword) = statementTokens[startIndex].kind,
                  KotlinParser.isDeclarationModifierKeyword(keyword)
            {
                startIndex = statementTokens.index(after: startIndex)
            }
            guard startIndex < statementTokens.endIndex else {
                return nil
            }

            let head = statementTokens[startIndex]
            let isMutable: Bool
            switch head.kind {
            case .keyword(.val):
                isMutable = false
            case .keyword(.var):
                isMutable = true
            default:
                return nil
            }

            var nameIndex: Int?
            var name: InternedString?
            var lookup = statementTokens.index(after: startIndex)
            while lookup < statementTokens.endIndex {
                if let resolved = context.resolveDeclarationName(statementTokens[lookup], context.interner) {
                    nameIndex = lookup
                    name = resolved
                    break
                }
                lookup = statementTokens.index(after: lookup)
            }
            guard let nameIndex,
                  let name
            else {
                return nil
            }

            var typeAnnotation: TypeRefID?
            var colonIndex: Int?
            var colonDepth = BuildASTPhase.BracketDepth()
            var scan = statementTokens.index(after: nameIndex)
            while scan < statementTokens.endIndex {
                let token = statementTokens[scan]
                if colonDepth.isAtTopLevel {
                    if token.kind == .symbol(.colon) {
                        colonIndex = scan
                        break
                    }
                    if token.kind == .symbol(.assign) || token.kind == .symbol(.semicolon) {
                        break
                    }
                }
                colonDepth.track(token.kind)
                scan = statementTokens.index(after: scan)
            }

            if let colonIndex {
                var typeTokens: [Token] = []
                var typeDepth = BuildASTPhase.BracketDepth()
                var index = statementTokens.index(after: colonIndex)
                while index < statementTokens.endIndex {
                    let token = statementTokens[index]
                    if typeDepth.isAtTopLevel,
                       token.kind == .symbol(.assign) || token.kind == .symbol(.semicolon)
                    {
                        break
                    }
                    typeDepth.track(token.kind)
                    typeTokens.append(token)
                    index = statementTokens.index(after: index)
                }
                if !typeTokens.isEmpty {
                    typeAnnotation = context.parseTypeReference(typeTokens)
                }
            }

            var initializerStartIndex: Int?
            var isDelegated = false
            var assignDepth = BuildASTPhase.BracketDepth()
            var index = statementTokens.startIndex
            while index < statementTokens.endIndex {
                let token = statementTokens[index]
                if assignDepth.isAtTopLevel {
                    if token.kind == .symbol(.assign)
                        || token.kind == .softKeyword(.by)
                    {
                        isDelegated = token.kind == .softKeyword(.by)
                        initializerStartIndex = statementTokens.index(after: index)
                        break
                    }
                }
                assignDepth.track(token.kind)
                index = statementTokens.index(after: index)
            }

            var initializerExpr: ExprID?
            if let initializerStartIndex {
                let initTokens = stripSemicolons(statementTokens[initializerStartIndex ..< statementTokens.endIndex])
                guard !initTokens.isEmpty else {
                    return nil
                }
                let parsed = context.parseExpression(initTokens[...])
                if options.strictInitializerWhenAssignPresent, parsed == nil {
                    return nil
                }
                initializerExpr = parsed
            }

            if typeAnnotation == nil, initializerExpr == nil {
                return nil
            }

            let end: SourceLocation = if let initializerExpr {
                context.astArena.exprRange(initializerExpr)?.end
                    ?? statementTokens.last?.range.end
                    ?? head.range.end
            } else {
                statementTokens.last?.range.end ?? head.range.end
            }
            let range = SourceRange(start: statementTokens[statementTokens.startIndex].range.start, end: end)
            return context.astArena.appendExpr(.localDecl(
                name: name,
                isMutable: isMutable,
                typeAnnotation: typeAnnotation,
                initializer: initializerExpr,
                isDelegated: isDelegated,
                range: range
            ))
        }

        static func isLocalDelegateFactoryExpr(
            _ exprID: ExprID,
            ast: ASTModule,
            interner: StringInterner
        ) -> Bool {
            let knownNames = KnownCompilerNames(interner: interner)
            guard let expr = ast.arena.expr(exprID) else {
                return false
            }
            switch expr {
            case let .call(callee, _, _, _):
                guard let calleeExpr = ast.arena.expr(callee),
                      case let .nameRef(calleeName, _) = calleeExpr
                else {
                    return false
                }
                return calleeName == knownNames.lazy
            case let .memberCall(_, calleeName, _, _, _):
                return calleeName == knownNames.observable || calleeName == knownNames.vetoable
            default:
                return false
            }
        }

        static func parseLocalAssignment(
            from statementTokens: [Token],
            context: LocalStatementCoreContext,
            options: LocalStatementCoreOptions
        ) -> ExprID? {
            parseLocalAssignment(from: statementTokens[...], context: context, options: options)
        }

        static func parseLocalAssignment(
            from statementTokens: ArraySlice<Token>,
            context: LocalStatementCoreContext,
            options: LocalStatementCoreOptions
        ) -> ExprID? {
            guard statementTokens.count >= 3 else {
                return nil
            }

            if let compound = parseCompoundAssignment(
                from: statementTokens,
                context: context
            ) {
                return compound
            }

            var assignIndex: Int?
            var depth = BuildASTPhase.BracketDepth()
            var index = statementTokens.startIndex
            while index < statementTokens.endIndex {
                let token = statementTokens[index]
                if token.kind == .symbol(.assign), depth.isAtTopLevel {
                    assignIndex = index
                    break
                }
                depth.track(token.kind)
                index = statementTokens.index(after: index)
            }
            guard let assignIndex,
                  assignIndex > statementTokens.startIndex
            else {
                return nil
            }

            let lhsTokens = stripSemicolons(statementTokens[statementTokens.startIndex ..< assignIndex])
            guard !lhsTokens.isEmpty else {
                return nil
            }

            let valueStart = statementTokens.index(after: assignIndex)
            let valueTokens = stripSemicolons(statementTokens[valueStart ..< statementTokens.endIndex])
            guard !valueTokens.isEmpty else {
                return nil
            }

            guard let lhsExpr = context.parseExpression(lhsTokens[...]),
                  let lhs = context.astArena.expr(lhsExpr),
                  let lhsRange = context.astArena.exprRange(lhsExpr),
                  let valueExpr = context.parseExpression(valueTokens[...])
            else {
                return nil
            }

            let end = context.astArena.exprRange(valueExpr)?.end
                ?? statementTokens.last?.range.end
                ?? lhsRange.end
            let range = SourceRange(start: lhsRange.start, end: end)

            switch lhs {
            case let .nameRef(name, _):
                if options.rejectValVarSimpleAssignLHS {
                    let text = context.interner.resolve(name)
                    if text == "val" || text == "var" {
                        return nil
                    }
                }
                return context.astArena.appendExpr(.localAssign(name: name, value: valueExpr, range: range))

            case let .memberCall(receiver, callee, typeArgs, args, _):
                guard options.allowMemberAssign,
                      typeArgs.isEmpty,
                      args.isEmpty
                else {
                    return nil
                }
                return context.astArena.appendExpr(.memberAssign(
                    receiver: receiver,
                    callee: callee,
                    value: valueExpr,
                    range: range
                ))

            case let .indexedAccess(receiver, indices, _):
                return context.astArena.appendExpr(.indexedAssign(
                    receiver: receiver,
                    indices: indices,
                    value: valueExpr,
                    range: range
                ))

            default:
                return nil
            }
        }

        private static func parseCompoundAssignment(
            from statementTokens: ArraySlice<Token>,
            context: LocalStatementCoreContext
        ) -> ExprID? {
            let compoundOps: [(TokenKind, CompoundAssignOp)] = [
                (.symbol(.plusAssign), .plusAssign),
                (.symbol(.minusAssign), .minusAssign),
                (.symbol(.starAssign), .timesAssign),
                (.symbol(.slashAssign), .divAssign),
                (.symbol(.percentAssign), .modAssign),
            ]

            var foundIndex: Int?
            var foundOp: CompoundAssignOp?
            var depth = BuildASTPhase.BracketDepth()
            var index = statementTokens.startIndex
            while index < statementTokens.endIndex {
                let token = statementTokens[index]
                for (kind, op) in compoundOps where token.kind == kind && depth.isAtTopLevel {
                    foundIndex = index
                    foundOp = op
                    break
                }
                if foundIndex != nil {
                    break
                }
                depth.track(token.kind)
                index = statementTokens.index(after: index)
            }

            guard let assignIndex = foundIndex,
                  let op = foundOp,
                  assignIndex > statementTokens.startIndex
            else {
                return nil
            }

            let lhsTokens = stripSemicolons(statementTokens[statementTokens.startIndex ..< assignIndex])
            guard !lhsTokens.isEmpty else {
                return nil
            }

            let valueStart = statementTokens.index(after: assignIndex)
            let valueTokens = stripSemicolons(statementTokens[valueStart ..< statementTokens.endIndex])
            guard !valueTokens.isEmpty else {
                return nil
            }

            guard let lhsExpr = context.parseExpression(lhsTokens[...]),
                  let lhs = context.astArena.expr(lhsExpr),
                  let lhsRange = context.astArena.exprRange(lhsExpr),
                  let valueExpr = context.parseExpression(valueTokens[...])
            else {
                return nil
            }

            let end = context.astArena.exprRange(valueExpr)?.end
                ?? statementTokens.last?.range.end
                ?? lhsRange.end
            let range = SourceRange(start: lhsRange.start, end: end)

            switch lhs {
            case let .nameRef(name, _):
                return context.astArena.appendExpr(.compoundAssign(
                    op: op,
                    name: name,
                    value: valueExpr,
                    range: range
                ))
            case let .indexedAccess(receiver, indices, _):
                return context.astArena.appendExpr(.indexedCompoundAssign(
                    op: op,
                    receiver: receiver,
                    indices: indices,
                    value: valueExpr,
                    range: range
                ))
            default:
                return nil
            }
        }

        private static func stripSemicolons(_ tokens: ArraySlice<Token>) -> [Token] {
            tokens.filter { $0.kind != .symbol(.semicolon) }
        }
    }
}

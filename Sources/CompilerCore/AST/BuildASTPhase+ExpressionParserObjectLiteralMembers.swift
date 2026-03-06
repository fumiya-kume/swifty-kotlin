import Foundation

extension BuildASTPhase.ExpressionParser {
    func parseObjectLiteralDecl(
        superTypes: [TypeRefID],
        bodyTokens: [Token],
        range: SourceRange
    ) -> DeclID? {
        let statementRanges = splitBlockTokensIntoStatementRanges(bodyTokens)
        guard !statementRanges.isEmpty else {
            return nil
        }

        var propertyDeclIDs: [DeclID] = []
        for (start, end) in statementRanges {
            let group = bodyTokens[start ..< end]
            guard !group.isEmpty else {
                continue
            }
            guard let localDeclExprID = parseLocalDeclFromSlice(group),
                  let localDeclExpr = astArena.expr(localDeclExprID),
                  case let .localDecl(name, isMutable, typeAnnotation, initializer, declRange) = localDeclExpr
            else {
                return nil
            }
            let propertyDecl = PropertyDecl(
                range: declRange,
                name: name,
                modifiers: [],
                type: typeAnnotation,
                isVar: isMutable,
                initializer: initializer
            )
            propertyDeclIDs.append(astArena.appendDecl(.propertyDecl(propertyDecl)))
        }

        guard !propertyDeclIDs.isEmpty else {
            return nil
        }

        let syntheticName = interner.intern(
            "__ObjectLiteral_\(range.start.file.rawValue)_\(range.start.offset)_\(range.end.offset)"
        )
        let objectDecl = ObjectDecl(
            range: range,
            name: syntheticName,
            modifiers: [.private],
            superTypes: superTypes,
            memberProperties: propertyDeclIDs
        )
        return astArena.appendDecl(.objectDecl(objectDecl))
    }
}

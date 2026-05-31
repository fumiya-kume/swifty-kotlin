import CompilerCore

/// Resolves go-to-definition requests to the declaration site of the symbol
/// under the cursor.
public enum DefinitionFeature {
    public static func definition(
        for analysis: Analyzer.Analysis,
        line: Int,
        character: Int
    ) -> LSPLocation? {
        guard
            let fileID = analysis.fileID,
            let ast = analysis.context.ast,
            let sema = analysis.context.sema
        else {
            return nil
        }
        let sourceManager = analysis.context.sourceManager
        guard let offset = sourceManager.offset(ofLine: line, utf16Character: character, in: fileID) else {
            return nil
        }
        let resolver = PositionResolver(ast: ast, fileID: fileID)
        guard let exprID = resolver.innermostExpr(at: offset) else {
            return nil
        }
        guard
            let symbolID = SymbolResolution.symbol(for: exprID, sema: sema),
            let symbol = sema.symbols.symbol(symbolID),
            let declSite = symbol.declSite
        else {
            return nil
        }
        return LSPConvert.location(declSite, sourceManager)
    }
}

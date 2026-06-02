import CompilerCore

/// Computes hover information (type and symbol) for a position.
public enum HoverFeature {
    public static func hover(for analysis: Analyzer.Analysis, line: Int, character: Int) -> Hover? {
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

        let interner = analysis.context.interner
        let typeString = sema.bindings.exprType(for: exprID).map {
            sema.types.displayName(of: $0, symbols: sema.symbols, interner: interner)
        }

        var symbolName: String?
        var symbolKindLabel: String?
        if let symbolID = SymbolResolution.symbol(for: exprID, sema: sema),
           let symbol = sema.symbols.symbol(symbolID)
        {
            let resolved = interner.resolve(symbol.name)
            if !resolved.isEmpty {
                symbolName = resolved
                symbolKindLabel = SymbolResolution.label(for: symbol.kind)
            }
        }

        guard let markdown = renderMarkdown(
            symbolName: symbolName,
            kindLabel: symbolKindLabel,
            typeString: typeString
        ) else {
            return nil
        }

        let range = ast.arena.exprRange(exprID).map { LSPConvert.range($0, sourceManager) }
        return Hover(contents: MarkupContent(kind: "markdown", value: markdown), range: range)
    }

    private static func renderMarkdown(
        symbolName: String?,
        kindLabel: String?,
        typeString: String?
    ) -> String? {
        var signature: String?
        if let name = symbolName {
            if let type = typeString {
                signature = "\(name): \(type)"
            } else {
                signature = name
            }
        } else if let type = typeString {
            signature = type
        }

        guard let signature else { return nil }

        var value = "```kotlin\n\(signature)\n```"
        if let kindLabel {
            value += "\n\n\(kindLabel)"
        }
        return value
    }
}

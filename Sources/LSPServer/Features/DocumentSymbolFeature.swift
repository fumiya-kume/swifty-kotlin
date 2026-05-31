import CompilerCore

/// Builds a document outline (`textDocument/documentSymbol`) from the top-level
/// declarations of the analyzed file and their members.
public enum DocumentSymbolFeature {
    public static func documentSymbols(for analysis: Analyzer.Analysis) -> [DocumentSymbol] {
        guard
            let fileID = analysis.fileID,
            let ast = analysis.context.ast
        else {
            return []
        }
        guard let file = ast.files.first(where: { $0.fileID == fileID }) else {
            return []
        }
        let interner = analysis.context.interner
        let sourceManager = analysis.context.sourceManager

        return file.topLevelDecls.compactMap {
            symbol(forDecl: $0, ast: ast, interner: interner, sourceManager: sourceManager, isMember: false)
        }
    }

    private static func symbol(
        forDecl declID: DeclID,
        ast: ASTModule,
        interner: StringInterner,
        sourceManager: SourceManager,
        isMember: Bool
    ) -> DocumentSymbol? {
        guard let decl = ast.arena.decl(declID) else { return nil }

        switch decl {
        case let .classDecl(d):
            let kind: LSPSymbolKind = d.modifiers.contains(.enumModifier) ? .enum : .class
            return make(
                name: interner.resolve(d.name),
                kind: kind,
                range: d.range,
                children: classChildren(d, ast: ast, interner: interner, sourceManager: sourceManager),
                sourceManager: sourceManager
            )
        case let .interfaceDecl(d):
            return make(
                name: interner.resolve(d.name),
                kind: .interface,
                range: d.range,
                children: members(
                    properties: d.memberProperties,
                    functions: d.memberFunctions,
                    nestedClasses: d.nestedClasses,
                    nestedObjects: d.nestedObjects,
                    companion: d.companionObject,
                    ast: ast,
                    interner: interner,
                    sourceManager: sourceManager
                ),
                sourceManager: sourceManager
            )
        case let .objectDecl(d):
            return make(
                name: interner.resolve(d.name),
                kind: .object,
                range: d.range,
                children: members(
                    properties: d.memberProperties,
                    functions: d.memberFunctions,
                    nestedClasses: d.nestedClasses,
                    nestedObjects: d.nestedObjects,
                    companion: nil,
                    ast: ast,
                    interner: interner,
                    sourceManager: sourceManager
                ),
                sourceManager: sourceManager
            )
        case let .funDecl(d):
            return make(
                name: interner.resolve(d.name),
                kind: isMember ? .method : .function,
                range: d.range,
                children: [],
                sourceManager: sourceManager
            )
        case let .propertyDecl(d):
            let kind: LSPSymbolKind = isMember ? .property : (d.isVar ? .variable : .constant)
            return make(
                name: interner.resolve(d.name),
                kind: kind,
                range: d.range,
                children: [],
                sourceManager: sourceManager
            )
        case let .typeAliasDecl(d):
            return make(
                name: interner.resolve(d.name),
                kind: .class,
                range: d.range,
                children: [],
                sourceManager: sourceManager
            )
        case let .enumEntryDecl(d):
            return make(
                name: interner.resolve(d.name),
                kind: .enumMember,
                range: d.range,
                children: [],
                sourceManager: sourceManager
            )
        }
    }

    private static func classChildren(
        _ d: ClassDecl,
        ast: ASTModule,
        interner: StringInterner,
        sourceManager: SourceManager
    ) -> [DocumentSymbol] {
        var children: [DocumentSymbol] = []
        for entry in d.enumEntries {
            children.append(make(
                name: interner.resolve(entry.name),
                kind: .enumMember,
                range: entry.range,
                children: [],
                sourceManager: sourceManager
            ))
        }
        children.append(contentsOf: members(
            properties: d.memberProperties,
            functions: d.memberFunctions,
            nestedClasses: d.nestedClasses,
            nestedObjects: d.nestedObjects,
            companion: d.companionObject,
            ast: ast,
            interner: interner,
            sourceManager: sourceManager
        ))
        return children.sorted { lhs, rhs in
            (lhs.range.start.line, lhs.range.start.character) < (rhs.range.start.line, rhs.range.start.character)
        }
    }

    private static func members(
        properties: [DeclID],
        functions: [DeclID],
        nestedClasses: [DeclID],
        nestedObjects: [DeclID],
        companion: DeclID?,
        ast: ASTModule,
        interner: StringInterner,
        sourceManager: SourceManager
    ) -> [DocumentSymbol] {
        var result: [DocumentSymbol] = []
        for id in properties + functions {
            if let symbol = symbol(forDecl: id, ast: ast, interner: interner, sourceManager: sourceManager, isMember: true) {
                result.append(symbol)
            }
        }
        for id in nestedClasses + nestedObjects {
            if let symbol = symbol(forDecl: id, ast: ast, interner: interner, sourceManager: sourceManager, isMember: false) {
                result.append(symbol)
            }
        }
        if let companion,
           let symbol = symbol(forDecl: companion, ast: ast, interner: interner, sourceManager: sourceManager, isMember: false)
        {
            result.append(symbol)
        }
        return result.sorted { lhs, rhs in
            (lhs.range.start.line, lhs.range.start.character) < (rhs.range.start.line, rhs.range.start.character)
        }
    }

    private static func make(
        name: String,
        kind: LSPSymbolKind,
        range: SourceRange,
        children: [DocumentSymbol],
        sourceManager: SourceManager
    ) -> DocumentSymbol {
        let lspRange = LSPConvert.range(range, sourceManager)
        return DocumentSymbol(
            name: name.isEmpty ? "<anonymous>" : name,
            detail: nil,
            kind: kind.rawValue,
            range: lspRange,
            selectionRange: lspRange,
            children: children.isEmpty ? nil : children
        )
    }
}

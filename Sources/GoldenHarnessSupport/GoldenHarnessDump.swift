@testable import CompilerCore
import Foundation

/// Golden dumps are intended to run in a dedicated worker process.
/// Each dump uses a fresh `CompilationContext` from `makeCompilationContext`.

enum GoldenHarnessDumpError: Error, CustomStringConvertible {
    case missingSyntaxTree
    case missingAST
    case missingSema

    var description: String {
        switch self {
        case .missingSyntaxTree: "syntax tree not available after parse"
        case .missingAST: "AST not available after frontend"
        case .missingSema: "sema module not available"
        }
    }
}

enum GoldenHarnessDump {
    static func dumpLexer(sourcePath: String) throws -> String {
        let ctx = makeCompilationContext(inputs: [sourcePath], moduleName: "GoldenLexer", emit: .kirDump)
        try LoadSourcesPhase().run(ctx)
        try LexPhase().run(ctx)

        var lines: [String] = []
        for token in ctx.tokens {
            lines.append("\(GoldenHarnessSyntaxFormat.renderTokenKind(token.kind, interner: ctx.interner)) \(GoldenHarnessSyntaxFormat.renderRange(token.range))")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func dumpParser(sourcePath: String) throws -> String {
        let ctx = makeCompilationContext(inputs: [sourcePath], moduleName: "GoldenParser", emit: .kirDump)
        try LoadSourcesPhase().run(ctx)
        try LexPhase().run(ctx)
        try ParsePhase().run(ctx)

        guard let syntax = ctx.syntaxTree else {
            throw GoldenHarnessDumpError.missingSyntaxTree
        }
        var lines: [String] = []
        GoldenHarnessSyntaxFormat.dumpSyntaxNode(
            id: ctx.syntaxTreeRoot,
            syntax: syntax,
            interner: ctx.interner,
            indent: "",
            lines: &lines
        )
        return lines.joined(separator: "\n") + "\n"
    }

    static func dumpSema(sourcePath: String) throws -> String {
        let ctx = makeCompilationContext(inputs: [sourcePath], moduleName: "GoldenSema", emit: .kirDump)
        try runFrontend(ctx)
        try SemaPhase().run(ctx)

        guard let ast = ctx.ast else {
            throw GoldenHarnessDumpError.missingAST
        }
        guard let sema = ctx.sema else {
            throw GoldenHarnessDumpError.missingSema
        }
        
        return renderSemaOutput(ast: ast, sema: sema, interner: ctx.interner)
    }
    
    private static func renderSemaOutput(ast: ASTModule, sema: SemaModule, interner: StringInterner) -> String {
        var lines: [String] = []
        
        // Render symbols
        let symbols = sema.symbols.allSymbols().sorted { $0.id.rawValue < $1.id.rawValue }
        for symbol in symbols {
            lines.append(renderSymbol(symbol, sema: sema, interner: interner))
        }
        
        // Render files and declarations
        for file in ast.sortedFiles {
            lines.append(renderFile(file, ast: ast, sema: sema, interner: interner))
        }
        
        // Render expressions
        for raw in ast.arena.exprs.indices {
            let exprID = ExprID(rawValue: Int32(raw))
            guard let expr = ast.arena.expr(exprID) else { continue }
            lines.append(renderExpression(expr, id: exprID, sema: sema, interner: interner))
        }
        
        return lines.joined(separator: "\n") + "\n"
    }
    
    private static func renderSymbol(_ symbol: SemanticSymbol, sema: SemaModule, interner: StringInterner) -> String {
        var extra: [String] = []
        if let signature = sema.symbols.functionSignature(for: symbol.id) {
            extra.append("sig=\(GoldenHarnessSemaFormat.renderFunctionSignature(signature, types: sema.types))")
        }
        if let propertyType = sema.symbols.propertyType(for: symbol.id) {
            extra.append("type=\(sema.types.renderType(propertyType))")
        }
        let extras = extra.isEmpty ? "" : " " + extra.joined(separator: " ")
        let fq = GoldenHarnessSemaFormat.renderFQName(symbol.fqName, interner: interner)
        let flags = GoldenHarnessSemaFormat.renderSymbolFlags(symbol.flags)
        return "symbol s\(symbol.id.rawValue) kind=\(symbol.kind) fq=\(fq) vis=\(symbol.visibility) flags=\(flags)\(extras)"
    }
    
    private static func renderFile(_ file: ASTFile, ast: ASTModule, sema: SemaModule, interner: StringInterner) -> String {
        var fileLine = "file f\(file.fileID.rawValue) package=\(GoldenHarnessSemaFormat.renderFQName(file.packageFQName, interner: interner))"
        if !file.annotations.isEmpty {
            let renderedAnnotations = file.annotations.map { annotation in
                let targetPrefix = annotation.useSiteTarget.map { "@\($0):" } ?? "@"
                let arguments = if annotation.arguments.isEmpty {
                    ""
                } else {
                    "(\(annotation.arguments.map(GoldenHarnessSemaFormat.renderAnnotationArgument).joined(separator: ",")))"
                }
                return "\(targetPrefix)\(annotation.name)\(arguments)"
            }.joined(separator: ",")
            fileLine += " annotations=[\(renderedAnnotations)]"
        }
        
        var lines = [fileLine]
        for declID in file.topLevelDecls {
            guard let decl = ast.arena.decl(declID) else { continue }
            lines.append(
                "  decl d\(declID.rawValue) \(GoldenHarnessSemaFormat.renderDecl(decl, interner: interner)) sym=\(GoldenHarnessSemaFormat.renderDeclSymbol(declID, sema: sema))"
            )
        }
        return lines.joined(separator: "\n")
    }
    
    private static func renderExpression(_ expr: Expr, id: ExprID, sema: SemaModule, interner: StringInterner) -> String {
        var line = "expr e\(id.rawValue) \(GoldenHarnessExprFormat.renderExpr(expr, interner: interner))"
        
        if let exprType = sema.bindings.exprTypes[id] {
            line += " type=\(sema.types.renderType(exprType))"
        } else {
            line += " type=_"
        }
        
        if let refSymbol = sema.bindings.identifierSymbols[id] {
            line += " ref=s\(refSymbol.rawValue)"
        }
        
        if let callBinding = sema.bindings.callBindings[id] {
            let map = callBinding.parameterMapping.keys.sorted().map { key in
                "\(key)->\(callBinding.parameterMapping[key] ?? -1)"
            }.joined(separator: ",")
            let typeArgs = callBinding.substitutedTypeArguments.map { sema.types.renderType($0) }.joined(separator: ",")
            line += " call=s\(callBinding.chosenCallee.rawValue) map=[\(map)] targs=[\(typeArgs)]"
        }
        
        return line
    }

    static func dumpDiagnostics(sourcePath: String) throws -> String {
        let ctx = makeCompilationContext(inputs: [sourcePath], moduleName: "GoldenDiag", emit: .kirDump)
        do {
            try runFrontend(ctx)
            try SemaPhase().run(ctx)
        } catch {
            // Compilation errors are expected for diagnostic test cases.
        }
        let json = ctx.diagnostics.renderJSON(ctx.sourceManager)
        let normalized = json.replacingOccurrences(
            of: sourcePath,
            with: URL(fileURLWithPath: sourcePath).lastPathComponent
        )
        return normalized + "\n"
    }
}

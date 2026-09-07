@testable import CompilerCore
import Foundation

/// Golden dumps are intended to run in a dedicated worker process.
/// Each dump uses a fresh `CompilationContext` from `makeCompilationContext`.

enum GoldenHarnessDumpError: Error, CustomStringConvertible {
    case missingSourceFile
    case missingSyntaxTree
    case missingAST
    case missingSema

    var description: String {
        switch self {
        case .missingSourceFile: "source file not registered after loading"
        case .missingSyntaxTree: "syntax tree not available after parse"
        case .missingAST: "AST not available after frontend"
        case .missingSema: "sema module not available"
        }
    }
}

enum GoldenHarnessDump {
    static func dumpLexer(sourcePath: String, stdlibLibraryPath: String? = nil) throws -> String {
        let ctx = makeCompilationContext(
            inputs: [sourcePath],
            moduleName: "GoldenLexer",
            emit: .kirDump,
            stdlibLibraryPath: stdlibLibraryPath
        )
        try LoadSourcesPhase().run(ctx)
        try LexPhase().run(ctx)

        guard let sourceFileID = ctx.sourceManager.fileID(forPath: sourcePath) else {
            throw GoldenHarnessDumpError.missingSyntaxTree
        }

        var lines: [String] = []
        for token in ctx.tokens where token.range.start.file == sourceFileID {
            lines.append("\(GoldenHarnessSyntaxFormat.renderTokenKind(token.kind, interner: ctx.interner)) \(GoldenHarnessSyntaxFormat.renderRange(token.range))")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func dumpParser(sourcePath: String, stdlibLibraryPath: String? = nil) throws -> String {
        let ctx = makeCompilationContext(
            inputs: [sourcePath],
            moduleName: "GoldenParser",
            emit: .kirDump,
            stdlibLibraryPath: stdlibLibraryPath
        )
        try LoadSourcesPhase().run(ctx)
        try LexPhase().run(ctx)
        try ParsePhase().run(ctx)

        guard let sourceFileID = ctx.sourceManager.fileID(forPath: sourcePath) else {
            throw GoldenHarnessDumpError.missingSyntaxTree
        }
        guard let (_, syntax, root) = ctx.syntaxTrees.first(where: { $0.0 == sourceFileID }) else {
            throw GoldenHarnessDumpError.missingSyntaxTree
        }
        var lines: [String] = []
        GoldenHarnessSyntaxFormat.dumpSyntaxNode(
            id: root,
            syntax: syntax,
            interner: ctx.interner,
            indent: "",
            lines: &lines
        )
        return lines.joined(separator: "\n") + "\n"
    }

    static func dumpSema(
        sourcePath: String,
        preInjectedFiles: [(path: String, contents: Data)] = [],
        stdlibLibraryPath: String? = nil
    ) throws -> String {
        let ctx = makeCompilationContext(
            inputs: [sourcePath],
            moduleName: "GoldenSema",
            emit: .kirDump,
            stdlibLibraryPath: stdlibLibraryPath
        )
        for (path, contents) in preInjectedFiles {
            _ = ctx.sourceManager.addFile(path: path, contents: contents, origin: .bundledStdlib)
        }
        try runFrontend(ctx)
        try SemaPhase().run(ctx)

        guard let ast = ctx.ast else {
            throw GoldenHarnessDumpError.missingAST
        }
        guard let sema = ctx.sema else {
            throw GoldenHarnessDumpError.missingSema
        }
        guard let sourceFileID = ctx.sourceManager.fileID(forPath: sourcePath) else {
            throw GoldenHarnessDumpError.missingSourceFile
        }

        return renderSemaOutput(
            ast: ast,
            sema: sema,
            interner: ctx.interner,
            sourceManager: ctx.sourceManager,
            sourceFileID: sourceFileID,
            diagnostics: ctx.diagnostics
        )
    }

    // MARK: - Stable sema rendering

    private static func renderSemaOutput(
        ast: ASTModule,
        sema: SemaModule,
        interner: StringInterner,
        sourceManager: SourceManager,
        sourceFileID: FileID,
        diagnostics: DiagnosticEngine
    ) -> String {
        let ctx = StableRenderContext(sema: sema, interner: interner, ast: ast, sourceManager: sourceManager)

        // 1. Render body lines (files, decls, exprs) first to track referenced symbols
        var bodyLines: [String] = []

        for file in ast.sortedFiles where file.fileID == sourceFileID {
            bodyLines.append(renderFile(file, ast: ast, ctx: ctx))
        }

        for raw in ast.arena.exprs.indices {
            let exprID = ExprID(rawValue: Int32(raw))
            guard let expr = ast.arena.expr(exprID) else { continue }
            guard ast.arena.exprRange(exprID)?.start.file == sourceFileID else { continue }
            let hasType = sema.bindings.exprTypes[exprID] != nil
            let hasRef = sema.bindings.identifierSymbols[exprID] != nil
            let hasCall = sema.bindings.callBindings[exprID] != nil
            guard hasType || hasRef || hasCall else { continue }
            bodyLines.append(renderExpression(expr, id: exprID, ctx: ctx))
        }

        // 2. Transitively expand required symbols
        ctx.expandRequiredSymbols()

        // 3. Render only required symbol lines, sorted by FQ name for stability.
        // Synthetic scope names (__local_N, __for_N, .$classN, ...) embed a raw,
        // unpadded arena-ordinal suffix, so a plain string comparison sorts
        // "__local_10002" before "__local_9874" once the ordinal crosses a
        // power-of-ten digit-count boundary (lexicographic '1' < '9'). That
        // boundary shifts whenever unrelated bundled-stdlib edits change the
        // total expression count, which previously scrambled the printed
        // symbol order for cases whose ordinals happened to straddle it. Use
        // a numeric-aware comparison so embedded ordinals sort by value.
        let requiredSymbols = sema.symbols.allSymbols()
            .filter { ctx.requiredSymbols.contains($0.id.rawValue) }
            .filter { !isExcludedLibrarySymbol($0, sourceFileID: sourceFileID) }
            .sorted { ctx.stableKey(for: $0.id).compare(ctx.stableKey(for: $1.id), options: .numeric) == .orderedAscending }

        var symbolLines: [String] = []
        for symbol in requiredSymbols {
            symbolLines.append(renderSymbol(symbol, ctx: ctx))
        }

        let diagnosticLines = renderErrorDiagnostics(
            diagnostics,
            sourceManager: sourceManager,
            sourceFileID: sourceFileID
        )

        return (symbolLines + bodyLines + diagnosticLines).joined(separator: "\n") + "\n"
    }

    // A Sema golden case is expected to type-check cleanly; a case that's
    // deliberately ill-typed belongs in the Diagnostics suite instead. This
    // dump surfaces error-severity diagnostics anyway (rather than silently
    // dropping them, as SemaPhase.run's error-recovery would otherwise let
    // happen) so an accidentally ill-typed Sema fixture shows up as a golden
    // diff instead of looking identical to a clean one.
    private static func renderErrorDiagnostics(
        _ diagnostics: DiagnosticEngine,
        sourceManager: SourceManager,
        sourceFileID: FileID
    ) -> [String] {
        diagnostics.diagnostics
            .filter { $0.severity == .error }
            .compactMap { diagnostic -> (LineColumn, String)? in
                guard let range = diagnostic.primaryRange, range.start.file == sourceFileID else { return nil }
                let position = sourceManager.lineColumn(of: range.start)
                let line = "diagnostic severity=error code=\(diagnostic.code) at=\(position.line):\(position.column) msg=\(diagnostic.message)"
                return (position, line)
            }
            // Multiple diagnostics can land on the same position (e.g. several
            // unimplemented abstract members reported against one class decl,
            // collected from an unordered symbol set) — sort the rendered line
            // itself as a tiebreaker so process-to-process hash-seed variance
            // in the collector can't make this dump non-deterministic.
            .sorted { $0.0 != $1.0 ? ($0.0.line, $0.0.column) < ($1.0.line, $1.0.column) : $0.1 < $1.1 }
            .map(\.1)
    }


    /// `symbol` lines list only declarations authored inside the golden case
    /// file itself. Library-owned symbols — bundled-stdlib decls, imported
    /// `.kklib` decls, and synthetic stdlib stubs or compiler-internal
    /// helpers (all of which have no case-file `declSite`) — are internal
    /// topology that differs between the bundled-source and artifact loading
    /// paths; the expr-level `ref=`/`call=`/`type=` output already pins how
    /// they were resolved, so listing them here only adds noise.
    private static func isExcludedLibrarySymbol(_ symbol: SemanticSymbol, sourceFileID: FileID) -> Bool {
        guard let declSite = symbol.declSite else { return true }
        return declSite.start.file != sourceFileID
    }

    private static func renderSymbol(_ symbol: SemanticSymbol, ctx: StableRenderContext) -> String {
        var extra: [String] = []
        if let signature = ctx.sema.symbols.functionSignature(for: symbol.id) {
            extra.append("sig=\(ctx.renderSignature(signature))")
        }
        if let propertyType = ctx.sema.symbols.propertyType(for: symbol.id) {
            extra.append("type=\(ctx.renderType(propertyType))")
        }
        let extras = extra.isEmpty ? "" : " " + extra.joined(separator: " ")
        let key = ctx.stableKey(for: symbol.id)
        let flags = GoldenHarnessSemaFormat.renderSymbolFlags(symbol.flags)
        return "symbol fq=\(key) kind=\(symbol.kind) vis=\(symbol.visibility) flags=\(flags)\(extras)"
    }

    private static func renderFile(_ file: ASTFile, ast: ASTModule, ctx: StableRenderContext) -> String {
        var fileLine = "file f\(ctx.fileKey(file.fileID)) package=\(GoldenHarnessSemaFormat.renderFQName(file.packageFQName, interner: ctx.interner))"
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
            let symKey: String
            if let symbolID = ctx.sema.bindings.declSymbols[declID] {
                ctx.requireSymbol(symbolID)
                symKey = ctx.stableKey(for: symbolID)
            } else {
                symKey = "_"
            }
            lines.append(
                "  decl \(symKey) \(GoldenHarnessSemaFormat.renderDecl(decl, interner: ctx.interner)) sym=\(symKey)"
            )
        }
        return lines.joined(separator: "\n")
    }

    private static func renderExpression(_ expr: Expr, id: ExprID, ctx: StableRenderContext) -> String {
        var line = "expr \(ctx.exprKey(id)) \(GoldenHarnessExprFormat.renderExpr(expr, id: id, ctx: ctx))"

        if let exprType = ctx.sema.bindings.exprTypes[id] {
            line += " type=\(ctx.renderType(exprType))"
        } else {
            line += " type=_"
        }

        if let refSymbol = ctx.sema.bindings.identifierSymbols[id] {
            // Imported-library property reads bind both the property reference
            // and its accessor call, while the bundled-source path binds only
            // the accessor call. The ref is redundant there — drop it when the
            // call target is exactly the referenced property's accessor.
            let isAccessorPair = ctx.sema.bindings.callBindings[id].map {
                ctx.sema.symbols.accessorOwnerProperty(for: $0.chosenCallee) == refSymbol
            } ?? false
            if !isAccessorPair {
                if refSymbol.rawValue >= 0 {
                    ctx.requireSymbol(refSymbol)
                    line += " ref=\(ctx.stableKey(for: refSymbol))"
                } else {
                    line += " ref=s\(refSymbol.rawValue)"
                }
            }
        }

        if let callBinding = ctx.sema.bindings.callBindings[id] {
            ctx.requireSymbol(callBinding.chosenCallee)
            line += " call=\(ctx.stableKey(for: callBinding.chosenCallee))"
            if !callBinding.substitutedTypeArguments.isEmpty {
                let typeArgs = callBinding.substitutedTypeArguments.map { ctx.renderType($0) }.joined(separator: ",")
                line += " targs=[\(typeArgs)]"
            }
        }

        return line
    }

    static func dumpDiagnostics(sourcePath: String, stdlibLibraryPath: String? = nil) throws -> String {
        let ctx = makeCompilationContext(
            inputs: [sourcePath],
            moduleName: "GoldenDiag",
            emit: .kirDump,
            stdlibLibraryPath: stdlibLibraryPath
        )
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

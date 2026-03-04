import Foundation

public final class CompilerDriver {
    private struct PreparedRunContext {
        let context: CompilationContext
        let timePhasesEnabled: Bool
        let incrementalEnabled: Bool
    }

    private let version: CompilerVersion
    private let kotlinVersion: KotlinLanguageVersion

    public init(version: CompilerVersion, kotlinVersion: KotlinLanguageVersion) {
        self.version = version
        self.kotlinVersion = kotlinVersion
    }

    public func run(options: CompilerOptions) -> Int {
        let result = runInternal(options: options, printDiagnostics: true)
        return result.exitCode
    }

    func runForTesting(options: CompilerOptions) -> (exitCode: Int, diagnostics: [Diagnostic]) {
        runInternal(options: options, printDiagnostics: false)
    }

    static func fallbackDiagnostic(for error: Error) -> (code: String, message: String)? {
        guard let pipelineError = error as? CompilerPipelineError else {
            return nil
        }
        switch pipelineError {
        case .loadError:
            return (
                code: "KSWIFTK-PIPELINE-0001",
                message: "Compiler pipeline failed while loading input sources."
            )
        case let .invalidInput(detail):
            return (
                code: "KSWIFTK-PIPELINE-0002",
                message: "Compiler pipeline received invalid intermediate state: \(detail)"
            )
        case .outputUnavailable:
            return (
                code: "KSWIFTK-PIPELINE-0003",
                message: "Compiler pipeline could not produce requested output."
            )
        }
    }

    private func runInternal(
        options: CompilerOptions,
        printDiagnostics: Bool
    ) -> (exitCode: Int, diagnostics: [Diagnostic]) {
        let prepared = prepareContext(options: options)
        let ctx = prepared.context

        let phases: [CompilerPhase] = [
            LoadSourcesPhase(),
            LexPhase(),
            ParsePhase(),
            BuildASTPhase(),
            SemaPhase(),
            BuildKIRPhase(),
            LoweringPhase(),
            CodegenPhase(),
            LinkPhase(),
        ]

        executePhases(ctx: ctx, phases: phases, incrementalEnabled: prepared.incrementalEnabled)
        return finalizeRun(ctx: ctx, printDiagnostics: printDiagnostics, timePhasesEnabled: prepared.timePhasesEnabled)
    }

    // MARK: - Incremental compilation helpers

    /// Checks whether incremental compilation is enabled via frontend flags
    /// or cache path.
    private func isIncrementalEnabled(options: CompilerOptions) -> Bool {
        if options.incrementalCachePath != nil {
            return true
        }
        return options.frontendFlags.contains("incremental")
    }

    /// Resolves the cache directory path, falling back to a default derived
    /// from the output path.
    private func resolveIncrementalCachePath(options: CompilerOptions) -> String {
        if let explicit = options.incrementalCachePath {
            return explicit
        }
        // Default: place cache next to the output.
        let outputURL = URL(fileURLWithPath: options.outputPath)
        let parentDir = outputURL.deletingLastPathComponent().path
        return parentDir + "/.kswiftk-cache"
    }

    /// Computes fingerprints for loaded sources and determines the
    /// incremental recompilation set.
    private func setupIncrementalRecompileSet(ctx: CompilationContext) {
        guard let cache = ctx.incrementalCache else { return }

        let allPaths = ctx.options.inputs
        cache.computeCurrentFingerprints(for: allPaths, sourceManager: ctx.sourceManager)

        if let recompileSet = cache.recompilationSet(allPaths: allPaths) {
            if recompileSet.isEmpty {
                // Nothing changed — we still run the full pipeline to produce
                // a consistent output. In the future, we could short-circuit
                // here or reuse cached intermediate results more aggressively.
                ctx.incrementalRecompileSet = nil
            } else {
                ctx.incrementalRecompileSet = recompileSet
            }
        } else {
            // No previous cache — full build.
            ctx.incrementalRecompileSet = nil
        }
    }

    private func prepareContext(options: CompilerOptions) -> PreparedRunContext {
        let context = CompilationContext(
            options: options,
            sourceManager: SourceManager(),
            diagnostics: DiagnosticEngine(),
            interner: StringInterner()
        )

        let timePhasesEnabled = options.frontendFlags.contains("time-phases")
        if timePhasesEnabled {
            context.phaseTimer = PhaseTimer()
        }

        let incrementalEnabled = isIncrementalEnabled(options: options)
        if incrementalEnabled {
            let cachePath = resolveIncrementalCachePath(options: options)
            let cache = IncrementalCompilationCache(cachePath: cachePath)
            cache.loadPreviousState()
            context.incrementalCache = cache
        }

        return PreparedRunContext(
            context: context,
            timePhasesEnabled: timePhasesEnabled,
            incrementalEnabled: incrementalEnabled
        )
    }

    private func executePhases(
        ctx: CompilationContext,
        phases: [CompilerPhase],
        incrementalEnabled: Bool
    ) {
        do {
            for phase in phases {
                let phaseName = type(of: phase).name
                ctx.phaseTimer?.beginPhase(phaseName)
                defer { ctx.phaseTimer?.endPhase() }

                if phase is LoadSourcesPhase {
                    try phase.run(ctx)
                    if ctx.diagnostics.hasError { break }
                    if incrementalEnabled {
                        setupIncrementalRecompileSet(ctx: ctx)
                    }
                    continue
                }

                try phase.run(ctx)
                if ctx.diagnostics.hasError {
                    break
                }
            }
        } catch {
            if !ctx.diagnostics.hasError {
                if let fallback = Self.fallbackDiagnostic(for: error) {
                    ctx.diagnostics.error(fallback.code, fallback.message, range: nil)
                } else {
                    ctx.diagnostics.error("KSWIFTK-ICE-0001", "Compiler internal error: \(error)", range: nil)
                }
            }
        }
    }

    private func finalizeRun(
        ctx: CompilationContext,
        printDiagnostics: Bool,
        timePhasesEnabled: Bool
    ) -> (exitCode: Int, diagnostics: [Diagnostic]) {
        if !ctx.diagnostics.hasError, let cache = ctx.incrementalCache {
            let depGraph = buildDependencyGraph(ctx: ctx)
            cache.saveState(dependencyGraph: depGraph)
        }

        if printDiagnostics {
            ctx.diagnostics.printDiagnostics(format: ctx.options.diagnosticsFormat, from: ctx.sourceManager)
        }

        if timePhasesEnabled, let timer = ctx.phaseTimer {
            timer.printSummary()
        }

        return (ctx.diagnostics.hasError ? 1 : 0, ctx.diagnostics.diagnostics)
    }

    /// Builds a dependency graph from the current compilation state.
    private func buildDependencyGraph(ctx: CompilationContext) -> DependencyGraph {
        let graph = DependencyGraph()
        guard let sema = ctx.sema, let ast = ctx.ast else {
            return graph
        }

        let interner = ctx.interner
        let symbols = sema.symbols

        // Pre-build a map from FileID -> provided symbol names in one pass
        // over the symbol table, avoiding O(files * symbols) scanning.
        var symbolsByFile: [FileID: Set<String>] = [:]
        for sym in symbols.allSymbols() {
            guard let symFileID = symbols.sourceFileID(for: sym.id) else { continue }
            symbolsByFile[symFileID, default: []].insert(interner.resolve(sym.name))
        }

        // For each AST file, record which symbols it provides and depends on.
        for file in ast.files {
            let fileID = file.fileID
            let filePath = ctx.sourceManager.path(of: fileID)
            guard !filePath.isEmpty else { continue }

            var provided = Set<String>()
            var depended = Set<String>()

            // Collect provided symbols: top-level declarations in this file.
            for declID in file.topLevelDecls {
                guard let decl = ast.arena.decl(declID) else { continue }
                let declName = extractDeclName(decl, interner: interner)
                if let name = declName {
                    provided.insert(name)
                }
            }

            // Collect provided symbols from pre-built map.
            if let fileSymbols = symbolsByFile[fileID] {
                provided.formUnion(fileSymbols)
            }

            // Imports: use alias if present, otherwise the last path component
            // (simple name) to match provided symbol granularity.
            for imp in file.imports {
                if let alias = imp.alias {
                    depended.insert(interner.resolve(alias))
                } else if let last = imp.path.last {
                    depended.insert(interner.resolve(last))
                }
            }

            // Walk top-level declarations to find referenced names.
            for declID in file.topLevelDecls {
                collectDeclDependencies(
                    declID: declID,
                    ast: ast,
                    interner: interner,
                    depended: &depended
                )
            }

            graph.recordProvided(filePath: filePath, symbols: provided)
            graph.recordDepended(filePath: filePath, symbols: depended)
        }

        return graph
    }

    /// Extracts the declaration name as a String, if available.
    private func extractDeclName(_ decl: Decl, interner: StringInterner) -> String? {
        switch decl {
        case let .classDecl(d):
            interner.resolve(d.name)
        case let .interfaceDecl(d):
            interner.resolve(d.name)
        case let .funDecl(d):
            interner.resolve(d.name)
        case let .propertyDecl(d):
            interner.resolve(d.name)
        case let .typeAliasDecl(d):
            interner.resolve(d.name)
        case let .objectDecl(d):
            interner.resolve(d.name)
        case let .enumEntryDecl(d):
            interner.resolve(d.name)
        }
    }

    /// Recursively collects symbol names referenced by a declaration.
    private func collectDeclDependencies(
        declID: DeclID,
        ast: ASTModule,
        interner: StringInterner,
        depended: inout Set<String>
    ) {
        guard let decl = ast.arena.decl(declID) else { return }

        switch decl {
        case let .classDecl(d):
            collectNominalDeclDependencies(
                superTypes: d.superTypeEntries.map(\.typeRef),
                memberIDs: d.memberFunctions + d.memberProperties + d.nestedClasses + d.nestedObjects,
                ast: ast,
                interner: interner,
                depended: &depended
            )
        case let .interfaceDecl(d):
            collectNominalDeclDependencies(
                superTypes: d.superTypes,
                memberIDs: d.memberFunctions + d.memberProperties + d.nestedClasses + d.nestedObjects,
                ast: ast,
                interner: interner,
                depended: &depended
            )
        case let .objectDecl(d):
            collectNominalDeclDependencies(
                superTypes: d.superTypes,
                memberIDs: d.memberFunctions + d.memberProperties + d.nestedClasses + d.nestedObjects,
                ast: ast,
                interner: interner,
                depended: &depended
            )
        case let .funDecl(d):
            for param in d.valueParams {
                if let typeRef = param.type {
                    collectTypeRefDependencies(typeRefID: typeRef, ast: ast, interner: interner, depended: &depended)
                }
            }
            if let retType = d.returnType {
                collectTypeRefDependencies(typeRefID: retType, ast: ast, interner: interner, depended: &depended)
            }
        case let .propertyDecl(d):
            if let typeRef = d.type {
                collectTypeRefDependencies(typeRefID: typeRef, ast: ast, interner: interner, depended: &depended)
            }
        case let .typeAliasDecl(d):
            if let underlyingType = d.underlyingType {
                collectTypeRefDependencies(typeRefID: underlyingType, ast: ast, interner: interner, depended: &depended)
            }
        case .enumEntryDecl:
            break
        }
    }

    private func collectNominalDeclDependencies(
        superTypes: [TypeRefID],
        memberIDs: [DeclID],
        ast: ASTModule,
        interner: StringInterner,
        depended: inout Set<String>
    ) {
        for superType in superTypes {
            collectTypeRefDependencies(typeRefID: superType, ast: ast, interner: interner, depended: &depended)
        }
        for memberID in memberIDs {
            collectDeclDependencies(
                declID: memberID,
                ast: ast,
                interner: interner,
                depended: &depended
            )
        }
    }

    /// Collects type reference dependencies.
    private func collectTypeRefDependencies(
        typeRefID: TypeRefID,
        ast: ASTModule,
        interner: StringInterner,
        depended: inout Set<String>
    ) {
        guard let typeRef = ast.arena.typeRef(typeRefID) else { return }

        switch typeRef {
        case let .named(path, _, _):
            // Use only the last path component (the simple type name) to match
            // provided symbol granularity. Earlier components are package/module
            // qualifiers that don't correspond to per-file provided symbols.
            if let last = path.last {
                depended.insert(interner.resolve(last))
            }
        case let .functionType(paramTypes, returnType, _, _):
            for paramType in paramTypes {
                collectTypeRefDependencies(typeRefID: paramType, ast: ast, interner: interner, depended: &depended)
            }
            collectTypeRefDependencies(typeRefID: returnType, ast: ast, interner: interner, depended: &depended)
        case let .intersection(parts):
            for part in parts {
                collectTypeRefDependencies(typeRefID: part, ast: ast, interner: interner, depended: &depended)
            }
        }
    }
}

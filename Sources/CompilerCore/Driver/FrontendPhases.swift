import Foundation

public final class LoadSourcesPhase: CompilerPhase {
    public static let name = "LoadSources"

    public init() {}

    public func run(_ ctx: CompilationContext) throws {
        if ctx.options.inputs.isEmpty {
            ctx.diagnostics.error(
                "KSWIFTK-SOURCE-0001",
                "No input files were specified.",
                range: nil
            )
            throw CompilerPipelineError.loadError
        }

        for path in ctx.options.inputs {
            if ctx.sourceManager.containsFile(path: path) { continue }
            do {
                _ = try ctx.sourceManager.addFile(path: path)
            } catch {
                ctx.diagnostics.error(
                    "KSWIFTK-SOURCE-0002",
                    "Cannot read input file: \(path)",
                    range: nil
                )
                throw CompilerPipelineError.loadError
            }
        }
    }
}

public final class LexPhase: CompilerPhase {
    public static let name = "Lex"

    public init() {}

    public func run(_ ctx: CompilationContext) throws {
        let fileIDs = ctx.sourceManager.fileIDs().sorted(by: { $0.rawValue < $1.rawValue })
        let interner = ctx.interner
        let diagnostics = ctx.diagnostics
        let sourceManager = ctx.sourceManager

        let semaphore = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var tokensByFile: [(FileID, [Token])] = []
        Task {
            tokensByFile = await withTaskGroup(of: (FileID, [Token]).self) { group in
                // Submit all file tasks up front so the Swift concurrency
                // runtime can schedule them freely (original pre-PR behaviour).
                for fileID in fileIDs {
                    group.addTask {
                        let contents = sourceManager.contents(of: fileID)
                        let lexer = KotlinLexer(
                            file: fileID,
                            source: contents,
                            interner: interner,
                            diagnostics: diagnostics
                        )
                        return (fileID, lexer.lexAll())
                    }
                }
                var results: [(FileID, [Token])] = []
                for await result in group {
                    results.append(result)
                }
                return results.sorted(by: { $0.0.rawValue < $1.0.rawValue })
            }
            semaphore.signal()
        }
        semaphore.wait()

        var allTokens: [Token] = []
        for (_, fileTokens) in tokensByFile {
            if let last = fileTokens.last, case .eof = last.kind {
                allTokens.append(contentsOf: fileTokens.dropLast())
            } else {
                allTokens.append(contentsOf: fileTokens)
            }
        }
        ctx.tokens = allTokens
        ctx.tokensByFile = tokensByFile

        // Populate per-file IR.
        for (fileID, fileTokens) in tokensByFile {
            ctx.fileIRs[fileID] = FileIR(fileID: fileID, tokens: fileTokens)
        }

        // Stabilize diagnostic order after parallel lexing.
        ctx.diagnostics.sortBySourceLocation()
    }
}

public final class ParsePhase: CompilerPhase {
    public static let name = "Parse"

    public init() {}

    public func run(_ ctx: CompilationContext) throws {
        let interner = ctx.interner
        let diagnostics = ctx.diagnostics
        let tokensByFile = ctx.tokensByFile

        let semaphore = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var syntaxTrees: [(FileID, SyntaxArena, NodeID)] = []
        Task {
            syntaxTrees = await withTaskGroup(of: (FileID, SyntaxArena, NodeID).self) { group in
                // Submit all file tasks up front so the Swift concurrency
                // runtime can schedule them freely (original pre-PR behaviour).
                for (fileID, fileTokens) in tokensByFile {
                    group.addTask {
                        let parser = KotlinParser(
                            tokens: fileTokens,
                            interner: interner,
                            diagnostics: diagnostics
                        )
                        let parsed = parser.parseFile()
                        return (fileID, parsed.arena, parsed.root)
                    }
                }
                var results: [(FileID, SyntaxArena, NodeID)] = []
                for await result in group {
                    results.append(result)
                }
                return results.sorted(by: { $0.0.rawValue < $1.0.rawValue })
            }
            semaphore.signal()
        }
        semaphore.wait()

        ctx.syntaxTrees = syntaxTrees
        if let first = syntaxTrees.first {
            ctx.syntaxTree = first.1
            ctx.syntaxTreeRoot = first.2
        }

        // Update per-file IR with parse results.
        for (fileID, cstArena, root) in syntaxTrees {
            ctx.fileIRs[fileID, default: FileIR(fileID: fileID)].syntaxArena = cstArena
            ctx.fileIRs[fileID, default: FileIR(fileID: fileID)].syntaxRoot = root
        }

        // Stabilize diagnostic order after parallel parsing.
        ctx.diagnostics.sortBySourceLocation()
    }
}

public final class BuildASTPhase: CompilerPhase {
    public static let name = "BuildAST"

    /// Per-arena cache for `collectTokens(from:in:)`.  Cleared between files
    /// because different `SyntaxArena`s reuse the same `NodeID` space.
    internal var tokenCache: [NodeID: [Token]] = [:]

    public init() {}

    public func run(_ ctx: CompilationContext) throws {
        if ctx.syntaxTrees.isEmpty {
            if let cst = ctx.syntaxTree {
                let fileID: FileID
                if let firstToken = ctx.tokens.first, firstToken.range.start.file != FileID.invalid {
                    fileID = firstToken.range.start.file
                } else {
                    fileID = FileID(rawValue: 0)
                }
                ctx.syntaxTrees = [(fileID, cst, ctx.syntaxTreeRoot)]
            } else {
                throw CompilerPipelineError.invalidInput("Parse phase did not run.")
            }
        }

        let jobs = ctx.frontendJobs
        if jobs > 1 {
            try runParallel(ctx, jobs: jobs)
        } else {
            runSequential(ctx)
        }
    }

    // MARK: - Sequential (legacy) path

    private func runSequential(_ ctx: CompilationContext) {
        let arena = ASTArena()
        var declarations: [DeclID] = []
        var packageByFile: [Int32: [InternedString]] = [:]
        var importsByFile: [Int32: [ImportDecl]] = [:]
        var declarationsByFile: [Int32: [DeclID]] = [:]
        var scriptExprsByFile: [Int32: [ExprID]] = [:]

        for (fileID, cst, root) in ctx.syntaxTrees {
            tokenCache.removeAll(keepingCapacity: true)
            buildFileAST(
                fileID: fileID,
                cst: cst,
                root: root,
                interner: ctx.interner,
                arena: arena,
                declarations: &declarations,
                packageByFile: &packageByFile,
                importsByFile: &importsByFile,
                declarationsByFile: &declarationsByFile,
                scriptExprsByFile: &scriptExprsByFile
            )
        }

        finalizeAST(
            ctx: ctx,
            arena: arena,
            declarations: declarations,
            packageByFile: packageByFile,
            importsByFile: importsByFile,
            declarationsByFile: declarationsByFile,
            scriptExprsByFile: scriptExprsByFile
        )
    }

    // MARK: - Parallel path

    private func runParallel(_ ctx: CompilationContext, jobs: Int) throws {
        let arena = ASTArena() // thread-safe with locks
        let interner = ctx.interner
        let syntaxTrees = ctx.syntaxTrees

        // Each file produces its own per-file results that we merge afterward.
        struct PerFileResult: Sendable {
            let fileID: FileID
            let fileRawID: Int32
            let packageFQName: [InternedString]
            let imports: [ImportDecl]
            let topLevelDecls: [DeclID]
            let scriptBody: [ExprID]
            let allDecls: [DeclID]
        }

        let semaphore = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var perFileResults: [PerFileResult] = []

        Task {
            let taskResults = await withTaskGroup(of: PerFileResult.self) { group in
                var activeCount = 0
                var fileIndex = 0
                var results: [PerFileResult] = []

                func addFileTask(at index: Int) {
                    let (fileID, cst, root) = syntaxTrees[index]
                    group.addTask {
                        // Each task gets its own BuildASTPhase so that
                        // `tokenCache` is not shared across concurrent tasks
                        // (different SyntaxArenas may reuse the same NodeID space).
                        let taskPhase = BuildASTPhase()
                        var declarations: [DeclID] = []
                        var packageByFile: [Int32: [InternedString]] = [:]
                        var importsByFile: [Int32: [ImportDecl]] = [:]
                        var declarationsByFile: [Int32: [DeclID]] = [:]
                        var scriptExprsByFile: [Int32: [ExprID]] = [:]

                        taskPhase.buildFileAST(
                            fileID: fileID,
                            cst: cst,
                            root: root,
                            interner: interner,
                            arena: arena,
                            declarations: &declarations,
                            packageByFile: &packageByFile,
                            importsByFile: &importsByFile,
                            declarationsByFile: &declarationsByFile,
                            scriptExprsByFile: &scriptExprsByFile
                        )

                        let fileRawID = fileID.rawValue
                        return PerFileResult(
                            fileID: fileID,
                            fileRawID: fileRawID,
                            packageFQName: packageByFile[fileRawID] ?? [],
                            imports: importsByFile[fileRawID] ?? [],
                            topLevelDecls: declarationsByFile[fileRawID] ?? [],
                            scriptBody: scriptExprsByFile[fileRawID] ?? [],
                            allDecls: declarations
                        )
                    }
                }

                // Seed initial batch up to jobs limit.
                while fileIndex < syntaxTrees.count && activeCount < jobs {
                    addFileTask(at: fileIndex)
                    activeCount += 1
                    fileIndex += 1
                }

                for await result in group {
                    results.append(result)
                    activeCount -= 1
                    if fileIndex < syntaxTrees.count {
                        addFileTask(at: fileIndex)
                        activeCount += 1
                        fileIndex += 1
                    }
                }

                return results
            }

            // Sort results by FileID for deterministic ordering.
            perFileResults = taskResults.sorted(by: { $0.fileRawID < $1.fileRawID })
            semaphore.signal()
        }
        semaphore.wait()

        // Build final merged structures.
        var declarations: [DeclID] = []
        var packageByFile: [Int32: [InternedString]] = [:]
        var importsByFile: [Int32: [ImportDecl]] = [:]
        var declarationsByFile: [Int32: [DeclID]] = [:]
        var scriptExprsByFile: [Int32: [ExprID]] = [:]

        for result in perFileResults {
            declarations.append(contentsOf: result.allDecls)
            packageByFile[result.fileRawID] = result.packageFQName
            importsByFile[result.fileRawID] = result.imports
            declarationsByFile[result.fileRawID] = result.topLevelDecls
            if !result.scriptBody.isEmpty {
                scriptExprsByFile[result.fileRawID] = result.scriptBody
            }
        }

        finalizeAST(
            ctx: ctx,
            arena: arena,
            declarations: declarations,
            packageByFile: packageByFile,
            importsByFile: importsByFile,
            declarationsByFile: declarationsByFile,
            scriptExprsByFile: scriptExprsByFile
        )
    }

    // MARK: - Per-file AST building (shared between sequential and parallel)

    func buildFileAST(
        fileID: FileID,
        cst: SyntaxArena,
        root: NodeID,
        interner: StringInterner,
        arena: ASTArena,
        declarations: inout [DeclID],
        packageByFile: inout [Int32: [InternedString]],
        importsByFile: inout [Int32: [ImportDecl]],
        declarationsByFile: inout [Int32: [DeclID]],
        scriptExprsByFile: inout [Int32: [ExprID]]
    ) {
        let isScript = cst.node(root).kind == .script
        let fileRawID = fileID.rawValue

        for child in cst.children(of: root) {
            guard case .node(let nodeID) = child else {
                continue
            }
            let node = cst.node(nodeID)

            switch node.kind {
            case .packageHeader:
                packageByFile[fileRawID] = extractQualifiedPath(from: nodeID, in: cst, interner: interner, isPackageHeader: true)

            case .importHeader:
                let path = extractQualifiedPath(from: nodeID, in: cst, interner: interner, isPackageHeader: false)
                let alias = extractImportAlias(from: nodeID, in: cst, interner: interner)
                importsByFile[fileRawID, default: []].append(ImportDecl(range: node.range, path: path, alias: alias))

            case .importList:
                for importChild in cst.children(of: nodeID) {
                    guard case .node(let importNodeID) = importChild else { continue }
                    let importNode = cst.node(importNodeID)
                    guard importNode.kind == .importHeader else { continue }
                    let path = extractQualifiedPath(from: importNodeID, in: cst, interner: interner, isPackageHeader: false)
                    let alias = extractImportAlias(from: importNodeID, in: cst, interner: interner)
                    importsByFile[fileRawID, default: []].append(ImportDecl(range: importNode.range, path: path, alias: alias))
                }

            case .classDecl:
                let decl = Decl.classDecl(makeClassDecl(from: nodeID, in: cst, interner: interner, astArena: arena))
                appendDecl(decl, to: arena, declarations: &declarations, fileDecls: &declarationsByFile, fileRawID: fileRawID)

            case .interfaceDecl:
                let decl = Decl.interfaceDecl(makeInterfaceDecl(from: nodeID, in: cst, interner: interner, astArena: arena))
                appendDecl(decl, to: arena, declarations: &declarations, fileDecls: &declarationsByFile, fileRawID: fileRawID)

            case .objectDecl:
                let decl = Decl.objectDecl(makeObjectDecl(from: nodeID, in: cst, interner: interner, astArena: arena))
                appendDecl(decl, to: arena, declarations: &declarations, fileDecls: &declarationsByFile, fileRawID: fileRawID)

            case .funDecl:
                let decl = Decl.funDecl(makeFunDecl(from: nodeID, in: cst, interner: interner, astArena: arena))
                appendDecl(decl, to: arena, declarations: &declarations, fileDecls: &declarationsByFile, fileRawID: fileRawID)

            case .propertyDecl where !isScript:
                let decl = Decl.propertyDecl(makePropertyDecl(from: nodeID, in: cst, interner: interner, astArena: arena))
                appendDecl(decl, to: arena, declarations: &declarations, fileDecls: &declarationsByFile, fileRawID: fileRawID)

            case .typeAliasDecl:
                let decl = Decl.typeAliasDecl(makeTypeAliasDecl(from: nodeID, in: cst, interner: interner, astArena: arena))
                appendDecl(decl, to: arena, declarations: &declarations, fileDecls: &declarationsByFile, fileRawID: fileRawID)

            case .enumEntry:
                let decl = Decl.enumEntryDecl(makeEnumEntryDecl(from: nodeID, in: cst, interner: interner))
                appendDecl(decl, to: arena, declarations: &declarations, fileDecls: &declarationsByFile, fileRawID: fileRawID)

            default:
                continue
            }
        }

        if isScript {
            let scriptExprs = blockExpressions(
                from: root,
                in: cst,
                interner: interner,
                astArena: arena
            )
            let rootNode = cst.node(root)
            scriptExprsByFile[fileRawID] = scriptExprs

            let mainName = interner.intern("main")
            let mainDecl = FunDecl(
                range: rootNode.range,
                name: mainName,
                modifiers: [],
                body: .block(scriptExprs, rootNode.range)
            )
            let declID = arena.appendDecl(.funDecl(mainDecl))
            declarations.append(declID)
            declarationsByFile[fileRawID, default: []].append(declID)
        }
    }

    // MARK: - Finalization (shared between sequential and parallel)

    private func finalizeAST(
        ctx: CompilationContext,
        arena: ASTArena,
        declarations: [DeclID],
        packageByFile: [Int32: [InternedString]],
        importsByFile: [Int32: [ImportDecl]],
        declarationsByFile: [Int32: [DeclID]],
        scriptExprsByFile: [Int32: [ExprID]]
    ) {
        let fileIDs = ctx.syntaxTrees.map { $0.0.rawValue }.filter { $0 != FileID.invalid.rawValue }
        let uniqueFileIDs = Array(Set(fileIDs)).sorted()
        let files: [ASTFile] = uniqueFileIDs.map { rawID in
            ASTFile(
                fileID: FileID(rawValue: rawID),
                packageFQName: packageByFile[rawID] ?? [],
                imports: importsByFile[rawID] ?? [],
                topLevelDecls: declarationsByFile[rawID] ?? [],
                scriptBody: scriptExprsByFile[rawID] ?? []
            )
        }

        // Compute total token count from per-file data.
        let totalTokenCount: Int
        if !ctx.tokensByFile.isEmpty {
            totalTokenCount = ctx.tokensByFile.reduce(0) { $0 + $1.1.count }
        } else {
            totalTokenCount = ctx.tokens.count
        }

        ctx.ast = ASTModule(files: files, arena: arena, declarationCount: declarations.count, tokenCount: totalTokenCount)

        // Update per-file IR with AST results.
        for file in files {
            ctx.fileIRs[file.fileID, default: FileIR(fileID: file.fileID)].astFile = file
            ctx.fileIRs[file.fileID, default: FileIR(fileID: file.fileID)].astArena = arena
        }
    }
}

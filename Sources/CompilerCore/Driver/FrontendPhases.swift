import Foundation

private func collectPerFileResultsInParallel<Result: Sendable>(
    fileIDs: [FileID],
    task: @escaping @Sendable (FileID) -> Result
) -> [(FileID, Result)] {
    let count = fileIDs.count
    guard count > 0 else { return [] }
    var results: [Result?] = Array(repeating: nil, count: count)
    DispatchQueue.concurrentPerform(iterations: count) { index in
        results[index] = task(fileIDs[index])
    }
    return fileIDs.enumerated().map { index, fileID in
        (fileID, results[index]!)
    }.sorted(by: { $0.0.rawValue < $1.0.rawValue })
}

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

        let tokensByFile = collectPerFileResultsInParallel(fileIDs: fileIDs) { fileID in
            let contents = sourceManager.contents(of: fileID)
            let lexer = KotlinLexer(
                file: fileID,
                source: contents,
                interner: interner,
                diagnostics: diagnostics
            )
            return lexer.lexAll()
        }

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
        let tokensByFile = Dictionary(uniqueKeysWithValues: ctx.tokensByFile.map { ($0.0, $0.1) })
        let fileIDs = tokensByFile.keys.sorted(by: { $0.rawValue < $1.rawValue })
        let parsedByFile = collectPerFileResultsInParallel(fileIDs: fileIDs) { fileID in
            let parser = KotlinParser(
                tokens: tokensByFile[fileID] ?? [],
                interner: interner,
                diagnostics: diagnostics
            )
            let parsed = parser.parseFile()
            return (parsed.arena, parsed.root)
        }
        let syntaxTrees = parsedByFile.map { (fileID, parsed) in
            (fileID, parsed.0, parsed.1)
        }

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

    internal struct PerFileASTResult: Sendable {
        let fileID: FileID
        let fileRawID: Int32
        let packageFQName: [InternedString]
        let imports: [ImportDecl]
        let topLevelDecls: [DeclID]
        let scriptBody: [ExprID]
        let allDecls: [DeclID]
    }

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

    // MARK: - Sequential path

    private func runSequential(_ ctx: CompilationContext) {
        let arena = ASTArena()
        let perFileResults: [PerFileASTResult] = ctx.syntaxTrees.map { fileID, cst, root in
            tokenCache.removeAll(keepingCapacity: true)
            return buildFileAST(
                fileID: fileID,
                cst: cst,
                root: root,
                interner: ctx.interner,
                arena: arena
            )
        }

        let merged = mergePerFileASTResults(perFileResults)

        finalizeAST(
            ctx: ctx,
            arena: arena,
            declarations: merged.declarations,
            packageByFile: merged.packageByFile,
            importsByFile: merged.importsByFile,
            declarationsByFile: merged.declarationsByFile,
            scriptExprsByFile: merged.scriptExprsByFile
        )
    }

    // MARK: - Parallel path

    private func runParallel(_ ctx: CompilationContext, jobs: Int) throws {
        let arena = ASTArena() // thread-safe with locks
        let interner = ctx.interner
        let syntaxTrees = ctx.syntaxTrees
        let count = syntaxTrees.count
        var perFileResults: [PerFileASTResult?] = Array(repeating: nil, count: count)
        let jobSemaphore = DispatchSemaphore(value: jobs)
        let completionGroup = DispatchGroup()

        for index in 0..<count {
            jobSemaphore.wait()
            completionGroup.enter()
            DispatchQueue.global().async {
                let (fileID, cst, root) = syntaxTrees[index]
                // Each task gets its own BuildASTPhase so that `tokenCache`
                // is not shared across concurrent tasks.
                let taskPhase = BuildASTPhase()
                perFileResults[index] = taskPhase.buildFileAST(
                    fileID: fileID,
                    cst: cst,
                    root: root,
                    interner: interner,
                    arena: arena
                )
                completionGroup.leave()
                jobSemaphore.signal()
            }
        }
        completionGroup.wait()
        let orderedResults = perFileResults.map { $0! }

        let merged = mergePerFileASTResults(orderedResults)

        finalizeAST(
            ctx: ctx,
            arena: arena,
            declarations: merged.declarations,
            packageByFile: merged.packageByFile,
            importsByFile: merged.importsByFile,
            declarationsByFile: merged.declarationsByFile,
            scriptExprsByFile: merged.scriptExprsByFile
        )
    }

    // MARK: - Per-file AST building (shared between sequential and parallel)

    func buildFileAST(
        fileID: FileID,
        cst: SyntaxArena,
        root: NodeID,
        interner: StringInterner,
        arena: ASTArena
    ) -> PerFileASTResult {
        let isScript = cst.node(root).kind == .script
        let fileRawID = fileID.rawValue
        var declarations: [DeclID] = []
        var packageFQName: [InternedString] = []
        var imports: [ImportDecl] = []
        var topLevelDecls: [DeclID] = []
        var scriptBody: [ExprID] = []

        for child in cst.children(of: root) {
            guard case .node(let nodeID) = child else {
                continue
            }
            let node = cst.node(nodeID)

            switch node.kind {
            case .packageHeader:
                packageFQName = extractQualifiedPath(from: nodeID, in: cst, interner: interner, isPackageHeader: true)

            case .importHeader:
                let path = extractQualifiedPath(from: nodeID, in: cst, interner: interner, isPackageHeader: false)
                let alias = extractImportAlias(from: nodeID, in: cst, interner: interner)
                imports.append(ImportDecl(range: node.range, path: path, alias: alias))

            case .importList:
                for importChild in cst.children(of: nodeID) {
                    guard case .node(let importNodeID) = importChild else { continue }
                    let importNode = cst.node(importNodeID)
                    guard importNode.kind == .importHeader else { continue }
                    let path = extractQualifiedPath(from: importNodeID, in: cst, interner: interner, isPackageHeader: false)
                    let alias = extractImportAlias(from: importNodeID, in: cst, interner: interner)
                    imports.append(ImportDecl(range: importNode.range, path: path, alias: alias))
                }

            case .classDecl:
                let decl = Decl.classDecl(makeClassDecl(from: nodeID, in: cst, interner: interner, astArena: arena))
                appendDecl(decl, to: arena, declarations: &declarations, fileDecls: &topLevelDecls)

            case .interfaceDecl:
                let decl = Decl.interfaceDecl(makeInterfaceDecl(from: nodeID, in: cst, interner: interner, astArena: arena))
                appendDecl(decl, to: arena, declarations: &declarations, fileDecls: &topLevelDecls)

            case .objectDecl:
                let decl = Decl.objectDecl(makeObjectDecl(from: nodeID, in: cst, interner: interner, astArena: arena))
                appendDecl(decl, to: arena, declarations: &declarations, fileDecls: &topLevelDecls)

            case .funDecl:
                let decl = Decl.funDecl(makeFunDecl(from: nodeID, in: cst, interner: interner, astArena: arena))
                appendDecl(decl, to: arena, declarations: &declarations, fileDecls: &topLevelDecls)

            case .propertyDecl where !isScript:
                let decl = Decl.propertyDecl(makePropertyDecl(from: nodeID, in: cst, interner: interner, astArena: arena))
                appendDecl(decl, to: arena, declarations: &declarations, fileDecls: &topLevelDecls)

            case .typeAliasDecl:
                let decl = Decl.typeAliasDecl(makeTypeAliasDecl(from: nodeID, in: cst, interner: interner, astArena: arena))
                appendDecl(decl, to: arena, declarations: &declarations, fileDecls: &topLevelDecls)

            case .enumEntry:
                let decl = Decl.enumEntryDecl(makeEnumEntryDecl(from: nodeID, in: cst, interner: interner))
                appendDecl(decl, to: arena, declarations: &declarations, fileDecls: &topLevelDecls)

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
            scriptBody = scriptExprs

            let mainName = interner.intern("main")
            let mainDecl = FunDecl(
                range: rootNode.range,
                name: mainName,
                modifiers: [],
                body: .block(scriptExprs, rootNode.range)
            )
            let declID = arena.appendDecl(.funDecl(mainDecl))
            declarations.append(declID)
            topLevelDecls.append(declID)
        }

        return PerFileASTResult(
            fileID: fileID,
            fileRawID: fileRawID,
            packageFQName: packageFQName,
            imports: imports,
            topLevelDecls: topLevelDecls,
            scriptBody: scriptBody,
            allDecls: declarations
        )
    }

    private func appendDecl(
        _ decl: Decl,
        to arena: ASTArena,
        declarations: inout [DeclID],
        fileDecls: inout [DeclID]
    ) {
        let declID = arena.appendDecl(decl)
        declarations.append(declID)
        fileDecls.append(declID)
    }

    private func mergePerFileASTResults(_ results: [PerFileASTResult]) -> (
        declarations: [DeclID],
        packageByFile: [Int32: [InternedString]],
        importsByFile: [Int32: [ImportDecl]],
        declarationsByFile: [Int32: [DeclID]],
        scriptExprsByFile: [Int32: [ExprID]]
    ) {
        var declarations: [DeclID] = []
        var packageByFile: [Int32: [InternedString]] = [:]
        var importsByFile: [Int32: [ImportDecl]] = [:]
        var declarationsByFile: [Int32: [DeclID]] = [:]
        var scriptExprsByFile: [Int32: [ExprID]] = [:]

        for result in results.sorted(by: { $0.fileRawID < $1.fileRawID }) {
            declarations.append(contentsOf: result.allDecls)
            packageByFile[result.fileRawID] = result.packageFQName
            importsByFile[result.fileRawID] = result.imports
            declarationsByFile[result.fileRawID] = result.topLevelDecls
            if !result.scriptBody.isEmpty {
                scriptExprsByFile[result.fileRawID] = result.scriptBody
            }
        }

        return (
            declarations: declarations,
            packageByFile: packageByFile,
            importsByFile: importsByFile,
            declarationsByFile: declarationsByFile,
            scriptExprsByFile: scriptExprsByFile
        )
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

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

        let arena = ASTArena()
        var declarations: [DeclID] = []
        var packageByFile: [Int32: [InternedString]] = [:]
        var importsByFile: [Int32: [ImportDecl]] = [:]
        var declarationsByFile: [Int32: [DeclID]] = [:]
        var scriptExprsByFile: [Int32: [ExprID]] = [:]

        for (fileID, cst, root) in ctx.syntaxTrees {
            tokenCache.removeAll(keepingCapacity: true)
            let isScript = cst.node(root).kind == .script
            let fileRawID = fileID.rawValue

            for child in cst.children(of: root) {
                guard case .node(let nodeID) = child else {
                    continue
                }
                let node = cst.node(nodeID)

                switch node.kind {
                case .packageHeader:
                    packageByFile[fileRawID] = extractQualifiedPath(from: nodeID, in: cst, interner: ctx.interner, isPackageHeader: true)

                case .importHeader:
                    let path = extractQualifiedPath(from: nodeID, in: cst, interner: ctx.interner, isPackageHeader: false)
                    let alias = extractImportAlias(from: nodeID, in: cst, interner: ctx.interner)
                    importsByFile[fileRawID, default: []].append(ImportDecl(range: node.range, path: path, alias: alias))

                case .importList:
                    for importChild in cst.children(of: nodeID) {
                        guard case .node(let importNodeID) = importChild else { continue }
                        let importNode = cst.node(importNodeID)
                        guard importNode.kind == .importHeader else { continue }
                        let path = extractQualifiedPath(from: importNodeID, in: cst, interner: ctx.interner, isPackageHeader: false)
                        let alias = extractImportAlias(from: importNodeID, in: cst, interner: ctx.interner)
                        importsByFile[fileRawID, default: []].append(ImportDecl(range: importNode.range, path: path, alias: alias))
                    }

                case .classDecl:
                    let decl = Decl.classDecl(makeClassDecl(from: nodeID, in: cst, interner: ctx.interner, astArena: arena))
                    appendDecl(decl, to: arena, declarations: &declarations, fileDecls: &declarationsByFile, fileRawID: fileRawID)

                case .interfaceDecl:
                    let decl = Decl.interfaceDecl(makeInterfaceDecl(from: nodeID, in: cst, interner: ctx.interner, astArena: arena))
                    appendDecl(decl, to: arena, declarations: &declarations, fileDecls: &declarationsByFile, fileRawID: fileRawID)

                case .objectDecl:
                    let decl = Decl.objectDecl(makeObjectDecl(from: nodeID, in: cst, interner: ctx.interner, astArena: arena))
                    appendDecl(decl, to: arena, declarations: &declarations, fileDecls: &declarationsByFile, fileRawID: fileRawID)

                case .funDecl:
                    let decl = Decl.funDecl(makeFunDecl(from: nodeID, in: cst, interner: ctx.interner, astArena: arena))
                    appendDecl(decl, to: arena, declarations: &declarations, fileDecls: &declarationsByFile, fileRawID: fileRawID)

                case .propertyDecl where !isScript:
                    let decl = Decl.propertyDecl(makePropertyDecl(from: nodeID, in: cst, interner: ctx.interner, astArena: arena))
                    appendDecl(decl, to: arena, declarations: &declarations, fileDecls: &declarationsByFile, fileRawID: fileRawID)

                case .typeAliasDecl:
                    let decl = Decl.typeAliasDecl(makeTypeAliasDecl(from: nodeID, in: cst, interner: ctx.interner, astArena: arena))
                    appendDecl(decl, to: arena, declarations: &declarations, fileDecls: &declarationsByFile, fileRawID: fileRawID)

                case .enumEntry:
                    let decl = Decl.enumEntryDecl(makeEnumEntryDecl(from: nodeID, in: cst, interner: ctx.interner))
                    appendDecl(decl, to: arena, declarations: &declarations, fileDecls: &declarationsByFile, fileRawID: fileRawID)

                default:
                    continue
                }
            }

            if isScript {
                let scriptExprs = blockExpressions(
                    from: root,
                    in: cst,
                    interner: ctx.interner,
                    astArena: arena
                )
                let rootNode = cst.node(root)
                scriptExprsByFile[fileRawID] = scriptExprs

                let mainName = ctx.interner.intern("main")
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

        ctx.ast = ASTModule(files: files, arena: arena, declarationCount: declarations.count, tokenCount: ctx.tokens.count)
    }

}

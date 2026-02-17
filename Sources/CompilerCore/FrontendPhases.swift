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
        var tokens: [Token] = []
        for fileID in ctx.sourceManager.fileIDs().sorted(by: { $0.rawValue < $1.rawValue }) {
            let contents = ctx.sourceManager.contents(of: fileID)
            let lexer = KotlinLexer(
                file: fileID,
                source: contents,
                interner: ctx.interner,
                diagnostics: ctx.diagnostics
            )
            let fileTokens = lexer.lexAll()
            if let last = fileTokens.last, case .eof = last.kind {
                tokens.append(contentsOf: fileTokens.dropLast())
            } else {
                tokens.append(contentsOf: fileTokens)
            }
        }
        ctx.tokens = tokens
    }
}

public final class ParsePhase: CompilerPhase {
    public static let name = "Parse"

    public init() {}

    public func run(_ ctx: CompilationContext) throws {
        let parser = KotlinParser(
            tokens: ctx.tokens,
            interner: ctx.interner,
            diagnostics: ctx.diagnostics
        )
        let parsed = parser.parseFile()
        ctx.syntaxTree = parsed.arena
        ctx.syntaxTreeRoot = parsed.root
    }
}

public final class BuildASTPhase: CompilerPhase {
    public static let name = "BuildAST"

    public init() {}

    public func run(_ ctx: CompilationContext) throws {
        guard let cst = ctx.syntaxTree else {
            throw CompilerPipelineError.invalidInput("Parse phase did not run.")
        }

        let arena = ASTArena()
        var declarations: [DeclID] = []
        var packageByFile: [Int32: [InternedString]] = [:]
        var importsByFile: [Int32: [ImportDecl]] = [:]
        var declarationsByFile: [Int32: [DeclID]] = [:]

        let isScript = cst.node(ctx.syntaxTreeRoot).kind == .script

        for child in cst.children(of: ctx.syntaxTreeRoot) {
            guard case .node(let nodeID) = child else {
                continue
            }
            let node = cst.node(nodeID)
            let fileRawID = node.range.start.file.rawValue

            switch node.kind {
            case .packageHeader:
                packageByFile[fileRawID] = extractQualifiedPath(from: nodeID, in: cst, interner: ctx.interner, isPackageHeader: true)

            case .importHeader:
                let path = extractQualifiedPath(from: nodeID, in: cst, interner: ctx.interner, isPackageHeader: false)
                importsByFile[fileRawID, default: []].append(ImportDecl(range: node.range, path: path))

            case .importList:
                for importChild in cst.children(of: nodeID) {
                    guard case .node(let importNodeID) = importChild else { continue }
                    let importNode = cst.node(importNodeID)
                    guard importNode.kind == .importHeader else { continue }
                    let path = extractQualifiedPath(from: importNodeID, in: cst, interner: ctx.interner, isPackageHeader: false)
                    importsByFile[fileRawID, default: []].append(ImportDecl(range: importNode.range, path: path))
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
                let decl = Decl.typeAliasDecl(makeTypeAliasDecl(from: nodeID, in: cst, interner: ctx.interner))
                appendDecl(decl, to: arena, declarations: &declarations, fileDecls: &declarationsByFile, fileRawID: fileRawID)

            case .enumEntry:
                let decl = Decl.enumEntryDecl(makeEnumEntryDecl(from: nodeID, in: cst, interner: ctx.interner))
                appendDecl(decl, to: arena, declarations: &declarations, fileDecls: &declarationsByFile, fileRawID: fileRawID)

            default:
                continue
            }
        }

        var scriptExprsByFile: [Int32: [ExprID]] = [:]
        if isScript {
            let scriptExprs = blockExpressions(
                from: ctx.syntaxTreeRoot,
                in: cst,
                interner: ctx.interner,
                astArena: arena
            )
            if !scriptExprs.isEmpty {
                let rootNode = cst.node(ctx.syntaxTreeRoot)
                let fileRawID = rootNode.range.start.file.rawValue
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

        let tokenFileIDs = Set(ctx.tokens.map { $0.range.start.file.rawValue })
        let fileIDs = tokenFileIDs.filter { $0 != FileID.invalid.rawValue }.sorted()
        let files: [ASTFile] = fileIDs.map { rawID in
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

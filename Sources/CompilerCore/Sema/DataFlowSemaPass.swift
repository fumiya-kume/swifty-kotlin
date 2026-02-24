import Foundation

public final class DataFlowSemaPassPhase: CompilerPhase {
    public static let name = "DataFlowSemaPass"

    public init() {}

    public func run(_ ctx: CompilationContext) throws {
        guard let ast = ctx.ast else {
            throw CompilerPipelineError.invalidInput("No AST available for semantic analysis.")
        }

        let symbols = SymbolTable()
        let types = TypeSystem()
        let bindings = BindingTable()
        let sema = SemaModule(
            symbols: symbols,
            types: types,
            bindings: bindings,
            diagnostics: ctx.diagnostics
        )

        let rootScope = PackageScope(parent: nil, symbols: symbols)
        var fileScopes: [Int32: FileScope] = [:]
        var importedInlineFunctions: [SymbolID: KIRFunction] = [:]

        for file in ast.sortedFiles {
            let packageSymbol = definePackageSymbol(for: file, symbols: symbols, interner: ctx.interner)
            let packageScope = PackageScope(parent: rootScope, symbols: symbols)
            packageScope.insert(packageSymbol)
            fileScopes[file.fileID.rawValue] = FileScope(parent: packageScope, symbols: symbols)
        }

        loadImportedLibrarySymbols(
            options: ctx.options,
            symbols: symbols,
            types: types,
            diagnostics: ctx.diagnostics,
            interner: ctx.interner,
            importedInlineFunctions: &importedInlineFunctions
        )
        registerSyntheticDelegateStubs(
            symbols: symbols,
            types: types,
            interner: ctx.interner
        )
        sema.importedInlineFunctions = importedInlineFunctions

        // Pass A: collect declaration headers and signatures.
        for file in ast.sortedFiles {
            guard let fileScope = fileScopes[file.fileID.rawValue] else { continue }
            for declID in file.topLevelDecls {
                collectHeader(
                    declID: declID,
                    file: file,
                    ast: ast,
                    symbols: symbols,
                    types: types,
                    bindings: bindings,
                    scope: fileScope,
                    diagnostics: ctx.diagnostics,
                    interner: ctx.interner
                )
            }
        }
        bindInheritanceEdges(
            ast: ast,
            symbols: symbols,
            bindings: bindings,
            types: types
        )
        validateSealedHierarchy(
            ast: ast,
            symbols: symbols,
            bindings: bindings,
            diagnostics: ctx.diagnostics,
            interner: ctx.interner
        )
        validateConstructorDelegation(
            ast: ast,
            symbols: symbols,
            diagnostics: ctx.diagnostics
        )
        synthesizeNominalLayouts(symbols: symbols)

        // Pass B: lightweight body checks.
        for file in ast.sortedFiles {
            for declID in file.topLevelDecls {
                analyzeBody(
                    declID: declID,
                    ast: ast,
                    symbols: symbols,
                    types: types,
                    bindings: bindings,
                    diagnostics: ctx.diagnostics,
                    interner: ctx.interner
                )
            }
        }

        ctx.sema = sema
    }
}

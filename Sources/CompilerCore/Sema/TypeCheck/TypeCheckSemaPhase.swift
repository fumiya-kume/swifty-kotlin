import Foundation

/// Semantic analysis pass that performs type checking and type inference.
///
/// This phase is a thin wrapper around ``TypeCheckDriver``, which dispatches
/// type-checking work to independent delegate classes (`ExprTypeChecker`,
/// `CallTypeChecker`, `ControlFlowTypeChecker`, etc.). Each delegate holds only
/// the context it needs, replacing the previous extension-based splitting
/// where a single monolithic class shared all state across multiple files.
public final class TypeCheckSemaPhase: CompilerPhase {
    public static let name = "TypeCheckSema"

    public init() {}

    public func run(_ ctx: CompilationContext) throws {
        guard let sema = ctx.sema else {
            throw CompilerPipelineError.invalidInput("Semantic model is unavailable.")
        }

        guard let ast = ctx.ast else {
            throw CompilerPipelineError.invalidInput("AST is unavailable during type check.")
        }

        let semaCacheEnabled = ctx.options.frontendFlags.contains("sema-cache")
        let semaCacheContext: SemaCacheContext? = semaCacheEnabled ? SemaCacheContext() : nil

        let solver = ConstraintSolver()
        let resolver = OverloadResolver()
        if let semaCacheContext {
            resolver.cacheContext = semaCacheContext
        }
        let dataFlow = DataFlowAnalyzer()
        let semaCtx = SemaModule(
            symbols: sema.symbols,
            types: sema.types,
            bindings: sema.bindings,
            diagnostics: ctx.diagnostics
        )

        let lazyBoundDecls = collectLazyBoundObjectLiteralDecls(ast: ast)

        // Run consistency checks: every declaration should have a symbol binding.
        for decl in 0 ..< ast.arena.declCount {
            let declID = DeclID(rawValue: Int32(decl))
            if lazyBoundDecls.contains(declID) {
                continue
            }
            if sema.bindings.declSymbols[declID] == nil {
                ctx.diagnostics.error(
                    "KSWIFTK-TYPE-0003",
                    "Unbound declaration found during type checking.",
                    range: nil
                )
            }
        }

        let driver = TypeCheckDriver(
            ast: ast,
            sema: sema,
            semaCtx: semaCtx,
            solver: solver,
            resolver: resolver,
            dataFlow: dataFlow,
            interner: ctx.interner,
            diagnostics: ctx.diagnostics,
            semaCacheContext: semaCacheContext
        )

        let fileScopes = driver.scopeBuilder.buildFileScopes(
            ast: ast,
            sema: sema,
            interner: ctx.interner
        )

        driver.typeCheckModule(fileScopes: fileScopes, files: ast.files)
        for declID in lazyBoundDecls where sema.bindings.declSymbols[declID] == nil {
            ctx.diagnostics.error(
                "KSWIFTK-TYPE-0003",
                "Unbound declaration found during type checking.",
                range: nil
            )
        }
    }

    private func collectLazyBoundObjectLiteralDecls(ast: ASTModule) -> Set<DeclID> {
        var declsToSkip: Set<DeclID> = []
        for expr in ast.arena.exprs {
            guard case let .objectLiteral(_, declID, _) = expr,
                  let declID
            else {
                continue
            }
            collectObjectLiteralDeclTree(declID, ast: ast, into: &declsToSkip)
        }
        return declsToSkip
    }

    private func collectObjectLiteralDeclTree(
        _ declID: DeclID,
        ast: ASTModule,
        into declsToSkip: inout Set<DeclID>
    ) {
        guard declsToSkip.insert(declID).inserted,
              let decl = ast.arena.decl(declID)
        else {
            return
        }
        guard case let .objectDecl(objectDecl) = decl else {
            return
        }
        for childDeclID in objectDecl.memberFunctions
            + objectDecl.memberProperties
            + objectDecl.nestedClasses
            + objectDecl.nestedObjects
        {
            collectObjectLiteralDeclTree(childDeclID, ast: ast, into: &declsToSkip)
        }
    }
}

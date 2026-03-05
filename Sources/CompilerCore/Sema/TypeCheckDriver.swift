import Foundation

/// Shared typealias for local variable bindings used across all type-checking delegates.
typealias LocalBindings = [InternedString: (type: TypeID, symbol: SymbolID, isMutable: Bool, isInitialized: Bool)]

/// Dispatch hub for type checking. Replaces the monolithic extension-based splitting
/// of `TypeCheckSemaPassPhase` with independent delegate classes.
///
/// Each delegate holds an `unowned` back-reference to this driver so that mutually
/// recursive calls (e.g. `inferExpr` → `inferCallExpr` → `inferExpr`) can be
/// dispatched through the driver rather than sharing a single fat class instance.
final class TypeCheckDriver {
    let ast: ASTModule
    let sema: SemaModule
    let semaCtx: SemaModule
    let solver: ConstraintSolver
    let resolver: OverloadResolver
    let dataFlow: DataFlowAnalyzer
    let interner: StringInterner
    let diagnostics: DiagnosticEngine
    /// Sema cache context for hot-path caching.  `nil` when caching is disabled.
    let semaCacheContext: SemaCacheContext?

    // Delegates (lazy to break initialization ordering; each holds unowned back-reference)
    private(set) lazy var exprChecker = ExprTypeChecker(driver: self)
    private(set) lazy var callChecker = CallTypeChecker(driver: self)
    private(set) lazy var controlFlowChecker = ControlFlowTypeChecker(driver: self)
    private(set) lazy var localDeclChecker = LocalDeclTypeChecker(driver: self)
    private(set) lazy var declChecker = DeclTypeChecker(driver: self)

    // Stateless utilities (no back-reference needed)
    let helpers = TypeCheckHelpers()
    let scopeBuilder = TypeCheckScopeBuilder()
    let captureAnalyzer = CaptureAnalyzer()

    init(
        ast: ASTModule,
        sema: SemaModule,
        semaCtx: SemaModule,
        solver: ConstraintSolver,
        resolver: OverloadResolver,
        dataFlow: DataFlowAnalyzer,
        interner: StringInterner,
        diagnostics: DiagnosticEngine,
        semaCacheContext: SemaCacheContext? = nil
    ) {
        self.ast = ast
        self.sema = sema
        self.semaCtx = semaCtx
        self.solver = solver
        self.resolver = resolver
        self.dataFlow = dataFlow
        self.interner = interner
        self.diagnostics = diagnostics
        self.semaCacheContext = semaCacheContext
    }

    // MARK: - Main Recursive Dispatch Entry Point

    func inferExpr(
        _ id: ExprID,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings,
        expectedType: TypeID? = nil
    ) -> TypeID {
        exprChecker.inferExpr(id, ctx: ctx, locals: &locals, expectedType: expectedType)
    }

    // MARK: - Module-Level Type Checking

    func typeCheckModule(fileScopes: [Int32: FileScope], files: [ASTFile]) {
        let checker = VisibilityChecker(symbols: sema.symbols)

        for file in files {
            guard let fileScope = fileScopes[file.fileID.rawValue] else {
                continue
            }
            let inferCtx = TypeInferenceContext(
                ast: ast, sema: sema, semaCtx: semaCtx,
                resolver: resolver, dataFlow: dataFlow,
                interner: interner, scope: fileScope,
                implicitReceiverType: nil,
                loopDepth: 0,
                loopLabelStack: [],
                lambdaLabelStack: [],
                exportBlockLocalsForExpr: nil,
                flowState: DataFlowState(),
                currentFileID: file.fileID,
                enclosingClassSymbol: nil,
                visibilityChecker: checker,
                outerReceiverTypes: [],
                semaCacheContext: semaCacheContext
            )
            for declID in file.topLevelDecls {
                guard let decl = ast.arena.decl(declID),
                      let declSymbol = sema.bindings.declSymbols[declID]
                else {
                    continue
                }
                switch decl {
                case let .funDecl(function):
                    declChecker.typeCheckFunctionDecl(
                        function,
                        symbol: declSymbol,
                        ctx: inferCtx,
                        solver: solver,
                        diagnostics: diagnostics
                    )

                case let .propertyDecl(property):
                    declChecker.typeCheckBoundPropertyDecl(
                        property,
                        declID: declID,
                        symbol: declSymbol,
                        ctx: inferCtx,
                        solver: solver,
                        diagnostics: diagnostics
                    )

                case let .classDecl(classDecl):
                    declChecker.typeCheckClassDecl(
                        classDecl,
                        symbol: declSymbol,
                        ctx: inferCtx,
                        solver: solver,
                        diagnostics: diagnostics
                    )

                case let .interfaceDecl(interfaceDecl):
                    declChecker.typeCheckInterfaceDecl(
                        interfaceDecl,
                        symbol: declSymbol,
                        ctx: inferCtx,
                        solver: solver,
                        diagnostics: diagnostics
                    )

                case let .objectDecl(objectDecl):
                    declChecker.typeCheckObjectDecl(
                        objectDecl,
                        symbol: declSymbol,
                        ctx: inferCtx,
                        solver: solver,
                        diagnostics: diagnostics
                    )

                case .typeAliasDecl, .enumEntryDecl:
                    continue
                }
            }
        }
    }

    // MARK: - Shared Utilities

    func emitSubtypeConstraint(
        left: TypeID,
        right: TypeID,
        range: SourceRange?,
        solver: ConstraintSolver,
        sema: SemaModule,
        diagnostics: DiagnosticEngine,
        suppressPlatformWarning: Bool = false
    ) {
        let solution = solver.solve(
            vars: [],
            constraints: [
                Constraint(
                    kind: .subtype,
                    left: left,
                    right: right,
                    blameRange: range
                ),
            ],
            typeSystem: sema.types
        )
        if !solution.isSuccess, let failure = solution.failure {
            diagnostics.emit(failure)
        } else if !suppressPlatformWarning,
                  let warningRange = range,
                  sema.types.nullability(of: left) == .platformType,
                  sema.types.nullability(of: right) == .nonNull
        {
            diagnostics.warning(
                "KSWIFTK-SEMA-PLATFORM",
                "Expression of platform type is used as non-null without a null check. " +
                    "This may cause a NullPointerException at runtime.",
                range: warningRange
            )
        }
    }
}

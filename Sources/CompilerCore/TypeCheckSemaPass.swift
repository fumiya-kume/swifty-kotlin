import Foundation

struct VisibilityChecker {
    let symbols: SymbolTable

    func isAccessible(
        _ symbol: SemanticSymbol,
        fromFile accessFileID: FileID,
        enclosingClass: SymbolID?
    ) -> Bool {
        switch symbol.visibility {
        case .public, .internal:
            return true
        case .private:
            if isLocalOrParameter(symbol.kind) {
                return true
            }
            if let parent = symbols.parentSymbol(for: symbol.id) {
                return enclosingClass == parent || isEnclosedBy(enclosingClass, ancestor: parent)
            }
            guard let declSite = symbol.declSite else {
                return true
            }
            return declSite.start.file == accessFileID
        case .protected:
            guard let ownerClass = symbols.parentSymbol(for: symbol.id) else {
                return false
            }
            guard let enclosingClass else {
                return false
            }
            if enclosingClass == ownerClass {
                return true
            }
            return isSubclass(enclosingClass, of: ownerClass)
        }
    }

    private func isLocalOrParameter(_ kind: SymbolKind) -> Bool {
        kind == .local || kind == .valueParameter || kind == .label || kind == .typeParameter
    }

    private func isSubclass(_ candidate: SymbolID, of ancestor: SymbolID) -> Bool {
        var visited: Set<Int32> = []
        var queue = symbols.directSupertypes(for: candidate)
        while !queue.isEmpty {
            let current = queue.removeFirst()
            if current == ancestor { return true }
            if visited.contains(current.rawValue) { continue }
            visited.insert(current.rawValue)
            queue.append(contentsOf: symbols.directSupertypes(for: current))
        }
        return false
    }

    private func isEnclosedBy(_ candidate: SymbolID?, ancestor: SymbolID) -> Bool {
        var current = candidate
        while let c = current {
            if c == ancestor { return true }
            current = symbols.parentSymbol(for: c)
        }
        return false
    }
}

// Internal visibility is required for cross-file extension decomposition.
struct TypeInferenceContext {
    let ast: ASTModule
    let sema: SemaModule
    let semaCtx: SemaModule
    let resolver: OverloadResolver
    let dataFlow: DataFlowAnalyzer
    let interner: StringInterner
    let scope: Scope
    let implicitReceiverType: TypeID?
    let loopDepth: Int
    let currentFileID: FileID
    let enclosingClassSymbol: SymbolID?
    let visibilityChecker: VisibilityChecker

    func with(scope: Scope) -> TypeInferenceContext {
        TypeInferenceContext(
            ast: ast,
            sema: sema,
            semaCtx: semaCtx,
            resolver: resolver,
            dataFlow: dataFlow,
            interner: interner,
            scope: scope,
            implicitReceiverType: implicitReceiverType,
            loopDepth: loopDepth,
            currentFileID: currentFileID,
            enclosingClassSymbol: enclosingClassSymbol,
            visibilityChecker: visibilityChecker
        )
    }

    func with(implicitReceiverType: TypeID?) -> TypeInferenceContext {
        TypeInferenceContext(
            ast: ast,
            sema: sema,
            semaCtx: semaCtx,
            resolver: resolver,
            dataFlow: dataFlow,
            interner: interner,
            scope: scope,
            implicitReceiverType: implicitReceiverType,
            loopDepth: loopDepth,
            currentFileID: currentFileID,
            enclosingClassSymbol: enclosingClassSymbol,
            visibilityChecker: visibilityChecker
        )
    }

    func with(loopDepth: Int) -> TypeInferenceContext {
        TypeInferenceContext(
            ast: ast,
            sema: sema,
            semaCtx: semaCtx,
            resolver: resolver,
            dataFlow: dataFlow,
            interner: interner,
            scope: scope,
            implicitReceiverType: implicitReceiverType,
            loopDepth: loopDepth,
            currentFileID: currentFileID,
            enclosingClassSymbol: enclosingClassSymbol,
            visibilityChecker: visibilityChecker
        )
    }

    func with(enclosingClassSymbol: SymbolID?) -> TypeInferenceContext {
        TypeInferenceContext(
            ast: ast,
            sema: sema,
            semaCtx: semaCtx,
            resolver: resolver,
            dataFlow: dataFlow,
            interner: interner,
            scope: scope,
            implicitReceiverType: implicitReceiverType,
            loopDepth: loopDepth,
            currentFileID: currentFileID,
            enclosingClassSymbol: enclosingClassSymbol,
            visibilityChecker: visibilityChecker
        )
    }

    func filterByVisibility(_ candidates: [SymbolID]) -> (visible: [SymbolID], invisible: [SemanticSymbol]) {
        var visible: [SymbolID] = []
        var invisible: [SemanticSymbol] = []
        for candidate in candidates {
            guard let symbol = sema.symbols.symbol(candidate) else { continue }
            if visibilityChecker.isAccessible(symbol, fromFile: currentFileID, enclosingClass: enclosingClassSymbol) {
                visible.append(candidate)
            } else {
                invisible.append(symbol)
            }
        }
        return (visible, invisible)
    }
}

public final class TypeCheckSemaPassPhase: CompilerPhase {
    public static let name = "TypeCheckSemaPass"

    public init() {}

    public func run(_ ctx: CompilationContext) throws {
        guard let sema = ctx.sema else {
            throw CompilerPipelineError.invalidInput("Semantic model is unavailable.")
        }

        guard let ast = ctx.ast else {
            throw CompilerPipelineError.invalidInput("AST is unavailable during type check.")
        }

        let solver = ConstraintSolver()
        let resolver = OverloadResolver()
        let dataFlow = DataFlowAnalyzer()
        let semaCtx = SemaModule(
            symbols: sema.symbols,
            types: sema.types,
            bindings: sema.bindings,
            diagnostics: ctx.diagnostics
        )

        // Run consistency checks: every declaration should have a symbol binding.
        for decl in ast.arena.decls.indices {
            let declID = DeclID(rawValue: Int32(decl))
            if sema.bindings.declSymbols[declID] == nil {
                ctx.diagnostics.error(
                    "KSWIFTK-TYPE-0003",
                    "Unbound declaration found during type checking.",
                    range: nil
                )
            }
        }

        let fileScopes = buildFileScopes(
            ast: ast,
            sema: sema,
            interner: ctx.interner
        )

        let checker = VisibilityChecker(symbols: sema.symbols)

        for file in ast.files {
            guard let fileScope = fileScopes[file.fileID.rawValue] else {
                continue
            }
            let inferCtx = TypeInferenceContext(
                ast: ast, sema: sema, semaCtx: semaCtx,
                resolver: resolver, dataFlow: dataFlow,
                interner: ctx.interner, scope: fileScope,
                implicitReceiverType: nil,
                loopDepth: 0,
                currentFileID: file.fileID,
                enclosingClassSymbol: nil,
                visibilityChecker: checker
            )
            for declID in file.topLevelDecls {
                guard let decl = ast.arena.decl(declID),
                      let declSymbol = sema.bindings.declSymbols[declID] else {
                    continue
                }
                switch decl {
                case .funDecl(let function):
                    guard let signature = sema.symbols.functionSignature(for: declSymbol) else {
                        continue
                    }

                    var locals: [InternedString: (type: TypeID, symbol: SymbolID, isMutable: Bool, isInitialized: Bool)] = [:]
                    for (index, paramSymbol) in signature.valueParameterSymbols.enumerated() {
                        guard let param = sema.symbols.symbol(paramSymbol) else {
                            continue
                        }
                        let type = index < signature.parameterTypes.count ? signature.parameterTypes[index] : sema.types.anyType
                        locals[param.name] = (type, paramSymbol, false, true)
                    }

                    let funCtx = inferCtx.with(implicitReceiverType: signature.receiverType)
                    let bodyType = inferFunctionBodyType(
                        function.body, ctx: funCtx, locals: &locals,
                        expectedType: signature.returnType
                    )
                    emitSubtypeConstraint(
                        left: bodyType, right: signature.returnType,
                        range: function.range, solver: solver,
                        sema: sema, diagnostics: ctx.diagnostics
                    )

                    if function.returnType == nil && bodyType != sema.types.errorType {
                        sema.symbols.setFunctionSignature(
                            FunctionSignature(
                                receiverType: signature.receiverType,
                                parameterTypes: signature.parameterTypes,
                                returnType: bodyType,
                                isSuspend: signature.isSuspend,
                                valueParameterSymbols: signature.valueParameterSymbols,
                                valueParameterHasDefaultValues: signature.valueParameterHasDefaultValues,
                                valueParameterIsVararg: signature.valueParameterIsVararg,
                                typeParameterSymbols: signature.typeParameterSymbols,
                                reifiedTypeParameterIndices: signature.reifiedTypeParameterIndices
                            ),
                            for: declSymbol
                        )
                    }

                case .propertyDecl(let property):
                    typeCheckPropertyDecl(
                        property, symbol: declSymbol,
                        ctx: inferCtx, solver: solver,
                        diagnostics: ctx.diagnostics
                    )
                    let expr = ExprID(rawValue: declID.rawValue)
                    sema.bindings.bindIdentifier(expr, symbol: declSymbol)
                    let propertyType = sema.symbols.propertyType(for: declSymbol) ?? sema.types.nullableAnyType
                    sema.bindings.bindExprType(expr, type: propertyType)

                case .classDecl(let classDecl):
                    let classCtx = inferCtx.with(enclosingClassSymbol: declSymbol)
                    typeCheckInitBlocks(classDecl.initBlocks, ctx: classCtx)
                    typeCheckSecondaryConstructors(classDecl.secondaryConstructors, ctx: classCtx)

                case .interfaceDecl:
                    break

                case .objectDecl(let objectDecl):
                    typeCheckInitBlocks(objectDecl.initBlocks, ctx: inferCtx)

                case .typeAliasDecl, .enumEntryDecl:
                    continue
                }
            }
        }
    }

    // Internal visibility is required because expression inference helpers live in sibling files.
    func emitSubtypeConstraint(
        left: TypeID,
        right: TypeID,
        range: SourceRange?,
        solver: ConstraintSolver,
        sema: SemaModule,
        diagnostics: DiagnosticEngine
    ) {
        let solution = solver.solve(
            vars: [],
            constraints: [
                Constraint(
                    kind: .subtype,
                    left: left,
                    right: right,
                    blameRange: range
                )
            ],
            typeSystem: sema.types
        )
        if !solution.isSuccess, let failure = solution.failure {
            diagnostics.emit(failure)
        }
    }
}

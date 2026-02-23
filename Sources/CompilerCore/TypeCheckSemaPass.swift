import Foundation

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
                flowState: DataFlowState(),
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
                    typeCheckFunctionDecl(
                        function,
                        symbol: declSymbol,
                        ctx: inferCtx,
                        solver: solver,
                        diagnostics: ctx.diagnostics
                    )

                case .propertyDecl(let property):
                    typeCheckBoundPropertyDecl(
                        property,
                        declID: declID,
                        symbol: declSymbol,
                        ctx: inferCtx,
                        solver: solver,
                        diagnostics: ctx.diagnostics
                    )

                case .classDecl(let classDecl):
                    typeCheckClassDecl(
                        classDecl,
                        symbol: declSymbol,
                        ctx: inferCtx,
                        solver: solver,
                        diagnostics: ctx.diagnostics
                    )

                case .interfaceDecl:
                    break

                case .objectDecl(let objectDecl):
                    typeCheckObjectDecl(
                        objectDecl,
                        symbol: declSymbol,
                        ctx: inferCtx,
                        solver: solver,
                        diagnostics: ctx.diagnostics
                    )

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

extension TypeCheckSemaPassPhase {
    private typealias LocalBindings = [InternedString: (
        type: TypeID,
        symbol: SymbolID,
        isMutable: Bool,
        isInitialized: Bool
    )]

    func typeCheckFunctionDecl(
        _ function: FunDecl,
        symbol: SymbolID,
        ctx: TypeInferenceContext,
        solver: ConstraintSolver,
        diagnostics: DiagnosticEngine
    ) {
        let sema = ctx.sema
        guard let signature = sema.symbols.functionSignature(for: symbol) else {
            return
        }

        var locals: LocalBindings = [:]
        for (index, paramSymbol) in signature.valueParameterSymbols.enumerated() {
            guard let param = sema.symbols.symbol(paramSymbol) else {
                continue
            }
            let type = index < signature.parameterTypes.count
                ? signature.parameterTypes[index]
                : sema.types.anyType
            locals[param.name] = (type, paramSymbol, false, true)
        }

        let functionCtx = ctx.with(implicitReceiverType: signature.receiverType)
        let bodyType = inferFunctionBodyType(
            function.body,
            ctx: functionCtx,
            locals: &locals,
            expectedType: signature.returnType
        )
        emitSubtypeConstraint(
            left: bodyType,
            right: signature.returnType,
            range: function.range,
            solver: solver,
            sema: sema,
            diagnostics: diagnostics
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
                for: symbol
            )
        }
    }

    func typeCheckBoundPropertyDecl(
        _ property: PropertyDecl,
        declID: DeclID,
        symbol: SymbolID,
        ctx: TypeInferenceContext,
        solver: ConstraintSolver,
        diagnostics: DiagnosticEngine
    ) {
        let sema = ctx.sema
        typeCheckPropertyDecl(
            property,
            symbol: symbol,
            ctx: ctx,
            solver: solver,
            diagnostics: diagnostics
        )
        let expr = ExprID(rawValue: declID.rawValue)
        sema.bindings.bindIdentifier(expr, symbol: symbol)
        let propertyType = sema.symbols.propertyType(for: symbol) ?? sema.types.nullableAnyType
        sema.bindings.bindExprType(expr, type: propertyType)
    }

    func typeCheckClassDecl(
        _ classDecl: ClassDecl,
        symbol: SymbolID,
        ctx: TypeInferenceContext,
        solver: ConstraintSolver,
        diagnostics: DiagnosticEngine
    ) {
        let sema = ctx.sema
        let classType = sema.types.make(.classType(ClassType(classSymbol: symbol, args: [], nullability: .nonNull)))
        let classScope = buildClassMemberScope(
            ownerSymbol: symbol,
            ownerType: classType,
            memberFunctions: classDecl.memberFunctions,
            memberProperties: classDecl.memberProperties,
            nestedClasses: classDecl.nestedClasses,
            nestedObjects: classDecl.nestedObjects,
            ctx: ctx
        )
        let classCtx = ctx
            .with(scope: classScope)
            .with(implicitReceiverType: classType)

        typeCheckInitBlocks(classDecl.initBlocks, ctx: classCtx)
        typeCheckSecondaryConstructors(classDecl.secondaryConstructors, ctx: classCtx)
        typeCheckClassLikeMembers(
            memberFunctions: classDecl.memberFunctions,
            memberProperties: classDecl.memberProperties,
            nestedClasses: classDecl.nestedClasses,
            nestedObjects: classDecl.nestedObjects,
            ctx: classCtx,
            solver: solver,
            diagnostics: diagnostics
        )
    }

    func typeCheckObjectDecl(
        _ objectDecl: ObjectDecl,
        symbol: SymbolID,
        ctx: TypeInferenceContext,
        solver: ConstraintSolver,
        diagnostics: DiagnosticEngine
    ) {
        let sema = ctx.sema
        let objectType = sema.types.make(.classType(ClassType(classSymbol: symbol, args: [], nullability: .nonNull)))
        let objectScope = buildClassMemberScope(
            ownerSymbol: symbol,
            ownerType: objectType,
            memberFunctions: objectDecl.memberFunctions,
            memberProperties: objectDecl.memberProperties,
            nestedClasses: objectDecl.nestedClasses,
            nestedObjects: objectDecl.nestedObjects,
            ctx: ctx
        )
        let objectCtx = ctx
            .with(scope: objectScope)
            .with(implicitReceiverType: objectType)

        typeCheckInitBlocks(objectDecl.initBlocks, ctx: objectCtx)
        typeCheckClassLikeMembers(
            memberFunctions: objectDecl.memberFunctions,
            memberProperties: objectDecl.memberProperties,
            nestedClasses: objectDecl.nestedClasses,
            nestedObjects: objectDecl.nestedObjects,
            ctx: objectCtx,
            solver: solver,
            diagnostics: diagnostics
        )
    }

    func typeCheckClassLikeMembers(
        memberFunctions: [DeclID],
        memberProperties: [DeclID],
        nestedClasses: [DeclID],
        nestedObjects: [DeclID],
        ctx: TypeInferenceContext,
        solver: ConstraintSolver,
        diagnostics: DiagnosticEngine
    ) {
        let ast = ctx.ast
        let sema = ctx.sema

        for declID in memberFunctions {
            guard let decl = ast.arena.decl(declID),
                  case .funDecl(let function) = decl,
                  let symbol = sema.bindings.declSymbols[declID] else {
                continue
            }
            typeCheckFunctionDecl(
                function,
                symbol: symbol,
                ctx: ctx,
                solver: solver,
                diagnostics: diagnostics
            )
        }

        for declID in memberProperties {
            guard let decl = ast.arena.decl(declID),
                  case .propertyDecl(let property) = decl,
                  let symbol = sema.bindings.declSymbols[declID] else {
                continue
            }
            typeCheckBoundPropertyDecl(
                property,
                declID: declID,
                symbol: symbol,
                ctx: ctx,
                solver: solver,
                diagnostics: diagnostics
            )
        }

        for declID in nestedClasses {
            guard let decl = ast.arena.decl(declID),
                  let symbol = sema.bindings.declSymbols[declID] else {
                continue
            }
            switch decl {
            case .classDecl(let classDecl):
                typeCheckClassDecl(
                    classDecl,
                    symbol: symbol,
                    ctx: ctx,
                    solver: solver,
                    diagnostics: diagnostics
                )
            case .interfaceDecl:
                continue
            default:
                continue
            }
        }

        for declID in nestedObjects {
            guard let decl = ast.arena.decl(declID),
                  case .objectDecl(let objectDecl) = decl,
                  let symbol = sema.bindings.declSymbols[declID] else {
                continue
            }
            typeCheckObjectDecl(
                objectDecl,
                symbol: symbol,
                ctx: ctx,
                solver: solver,
                diagnostics: diagnostics
            )
        }
    }

    func buildClassMemberScope(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        memberFunctions: [DeclID],
        memberProperties: [DeclID],
        nestedClasses: [DeclID],
        nestedObjects: [DeclID],
        ctx: TypeInferenceContext
    ) -> ClassMemberScope {
        let sema = ctx.sema
        let classScope = ClassMemberScope(
            parent: ctx.scope,
            symbols: sema.symbols,
            ownerSymbol: ownerSymbol,
            thisType: ownerType
        )

        for declID in memberFunctions + memberProperties + nestedClasses + nestedObjects {
            if let symbol = sema.bindings.declSymbols[declID] {
                classScope.insert(symbol)
            }
        }
        return classScope
    }
}

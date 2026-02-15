import Foundation

private struct TypeInferenceContext {
    let ast: ASTModule
    let sema: SemaModule
    let semaCtx: SemaModule
    let resolver: OverloadResolver
    let dataFlow: DataFlowAnalyzer
    let interner: StringInterner
    let scope: Scope
    let implicitReceiverType: TypeID?

    func with(scope: Scope) -> TypeInferenceContext {
        TypeInferenceContext(ast: ast, sema: sema, semaCtx: semaCtx, resolver: resolver, dataFlow: dataFlow, interner: interner, scope: scope, implicitReceiverType: implicitReceiverType)
    }

    func with(implicitReceiverType: TypeID?) -> TypeInferenceContext {
        TypeInferenceContext(ast: ast, sema: sema, semaCtx: semaCtx, resolver: resolver, dataFlow: dataFlow, interner: interner, scope: scope, implicitReceiverType: implicitReceiverType)
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

        for file in ast.files {
            guard let fileScope = fileScopes[file.fileID.rawValue] else {
                continue
            }
            let inferCtx = TypeInferenceContext(
                ast: ast, sema: sema, semaCtx: semaCtx,
                resolver: resolver, dataFlow: dataFlow,
                interner: ctx.interner, scope: fileScope,
                implicitReceiverType: nil
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

                    var locals: [InternedString: (type: TypeID, symbol: SymbolID)] = [:]
                    for (index, paramSymbol) in signature.valueParameterSymbols.enumerated() {
                        guard let param = sema.symbols.symbol(paramSymbol) else {
                            continue
                        }
                        let type = index < signature.parameterTypes.count ? signature.parameterTypes[index] : sema.types.anyType
                        locals[param.name] = (type, paramSymbol)
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
                                typeParameterSymbols: signature.typeParameterSymbols
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
                    typeCheckInitBlocks(classDecl.initBlocks, ctx: inferCtx)

                case .objectDecl(let objectDecl):
                    typeCheckInitBlocks(objectDecl.initBlocks, ctx: inferCtx)

                case .typeAliasDecl, .enumEntry:
                    continue
                }
            }
        }
    }

    private func inferFunctionBodyType(
        _ body: FunctionBody,
        ctx: TypeInferenceContext,
        locals: inout [InternedString: (type: TypeID, symbol: SymbolID)],
        expectedType: TypeID?
    ) -> TypeID {
        switch body {
        case .unit:
            return ctx.sema.types.unitType

        case .expr(let exprID, _):
            return inferExpr(exprID, ctx: ctx, locals: &locals, expectedType: expectedType)

        case .block(let exprIDs, _):
            var last = ctx.sema.types.unitType
            for (index, exprID) in exprIDs.enumerated() {
                let expectedTypeForExpr = index == exprIDs.count - 1 ? expectedType : nil
                last = inferExpr(exprID, ctx: ctx, locals: &locals, expectedType: expectedTypeForExpr)
            }
            return last
        }
    }

    private func emitSubtypeConstraint(
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

    private func typeCheckPropertyDecl(
        _ property: PropertyDecl,
        symbol: SymbolID,
        ctx: TypeInferenceContext,
        solver: ConstraintSolver,
        diagnostics: DiagnosticEngine
    ) {
        let sema = ctx.sema
        let interner = ctx.interner
        var inferredPropertyType: TypeID? = property.type != nil ? sema.symbols.propertyType(for: symbol) : nil

        if let initializer = property.initializer {
            var locals: [InternedString: (type: TypeID, symbol: SymbolID)] = [:]
            let initializerType = inferExpr(
                initializer, ctx: ctx, locals: &locals,
                expectedType: inferredPropertyType
            )
            if let declaredType = inferredPropertyType {
                emitSubtypeConstraint(
                    left: initializerType, right: declaredType,
                    range: property.range, solver: solver,
                    sema: sema, diagnostics: diagnostics
                )
            } else {
                inferredPropertyType = initializerType
            }
        }

        if let getter = property.getter {
            var getterLocals: [InternedString: (type: TypeID, symbol: SymbolID)] = [:]
            if let fieldType = inferredPropertyType {
                getterLocals[interner.intern("field")] = (fieldType, symbol)
            }
            let getterType = inferFunctionBodyType(
                getter.body, ctx: ctx, locals: &getterLocals,
                expectedType: inferredPropertyType
            )
            if let declaredType = inferredPropertyType {
                emitSubtypeConstraint(
                    left: getterType, right: declaredType,
                    range: getter.range, solver: solver,
                    sema: sema, diagnostics: diagnostics
                )
            } else {
                inferredPropertyType = getterType
            }
        }

        let finalPropertyType = inferredPropertyType ?? sema.types.nullableAnyType
        sema.symbols.setPropertyType(finalPropertyType, for: symbol)

        if let setter = property.setter {
            if !property.isVar {
                diagnostics.error(
                    "KSWIFTK-SEMA-0005",
                    "Setter is not allowed for read-only property.",
                    range: setter.range
                )
            }
            var setterLocals: [InternedString: (type: TypeID, symbol: SymbolID)] = [:]
            setterLocals[interner.intern("field")] = (finalPropertyType, symbol)
            let parameterName = setter.parameterName ?? interner.intern("value")
            setterLocals[parameterName] = (finalPropertyType, symbol)
            let setterType = inferFunctionBodyType(
                setter.body, ctx: ctx, locals: &setterLocals,
                expectedType: sema.types.unitType
            )
            emitSubtypeConstraint(
                left: setterType, right: sema.types.unitType,
                range: setter.range, solver: solver,
                sema: sema, diagnostics: diagnostics
            )
        }
    }

    private func typeCheckInitBlocks(
        _ blocks: [FunctionBody],
        ctx: TypeInferenceContext
    ) {
        for block in blocks {
            var locals: [InternedString: (type: TypeID, symbol: SymbolID)] = [:]
            _ = inferFunctionBodyType(block, ctx: ctx, locals: &locals, expectedType: nil)
        }
    }

    private func inferExpr(
        _ id: ExprID,
        ctx: TypeInferenceContext,
        locals: inout [InternedString: (type: TypeID, symbol: SymbolID)],
        expectedType: TypeID? = nil
    ) -> TypeID {
        let ast = ctx.ast
        let sema = ctx.sema
        let interner = ctx.interner
        let scope = ctx.scope

        guard let expr = ast.arena.expr(id) else {
            return sema.types.errorType
        }

        let boolType = sema.types.make(.primitive(.boolean, .nonNull))
        let intType = sema.types.make(.primitive(.int, .nonNull))
        let stringType = sema.types.make(.primitive(.string, .nonNull))

        switch expr {
        case .intLiteral:
            sema.bindings.bindExprType(id, type: intType)
            return intType

        case .boolLiteral:
            sema.bindings.bindExprType(id, type: boolType)
            return boolType

        case .stringLiteral:
            sema.bindings.bindExprType(id, type: stringType)
            return stringType

        case .nameRef(let name, _):
            if interner.resolve(name) == "null" {
                sema.bindings.bindExprType(id, type: sema.types.nullableAnyType)
                return sema.types.nullableAnyType
            }
            if let local = locals[name] {
                sema.bindings.bindIdentifier(id, symbol: local.symbol)
                sema.bindings.bindExprType(id, type: local.type)
                return local.type
            }
            let candidates = scope.lookup(name).compactMap { sema.symbols.symbol($0) }
            if let first = candidates.first {
                sema.bindings.bindIdentifier(id, symbol: first.id)
            }
            let resolvedType = candidates.first.flatMap { symbol in
                if let signature = sema.symbols.functionSignature(for: symbol.id) {
                    return signature.returnType
                }
                if symbol.kind == .property || symbol.kind == .field {
                    return sema.symbols.propertyType(for: symbol.id)
                }
                return nil
            } ?? sema.types.anyType
            sema.bindings.bindExprType(id, type: resolvedType)
            return resolvedType

        case .binary(let op, let lhsID, let rhsID, _):
            let lhs = inferExpr(lhsID, ctx: ctx, locals: &locals)
            let rhs = inferExpr(rhsID, ctx: ctx, locals: &locals)
            let type: TypeID
            switch op {
            case .add:
                type = (lhs == stringType || rhs == stringType) ? stringType : intType
            case .subtract, .multiply, .divide:
                type = intType
            case .equal:
                type = boolType
            }
            sema.bindings.bindExprType(id, type: type)
            return type

        case .call(let calleeID, let args, let range):
            let argTypes = args.map { argument in
                inferExpr(argument.expr, ctx: ctx, locals: &locals)
            }

            let calleeExpr = ast.arena.expr(calleeID)
            let calleeName: InternedString?
            if case .nameRef(let name, _) = calleeExpr {
                calleeName = name
            } else {
                calleeName = nil
            }

            let candidates: [SymbolID]
            if let calleeName {
                candidates = scope.lookup(calleeName).filter { candidate in
                    guard let symbol = sema.symbols.symbol(candidate) else { return false }
                    return symbol.kind == .function || symbol.kind == .constructor
                }
            } else {
                candidates = []
            }

            if candidates.isEmpty {
                sema.bindings.bindExprType(id, type: sema.types.errorType)
                return sema.types.errorType
            }

            let resolvedArgs: [CallArg] = zip(args, argTypes).map { argument, type in
                CallArg(label: argument.label, isSpread: argument.isSpread, type: type)
            }
            let resolved = ctx.resolver.resolveCall(
                candidates: candidates,
                call: CallExpr(
                    range: range,
                    calleeName: calleeName ?? InternedString(rawValue: invalidID),
                    args: resolvedArgs
                ),
                expectedType: expectedType,
                implicitReceiverType: ctx.implicitReceiverType,
                ctx: ctx.semaCtx
            )
            if let diagnostic = resolved.diagnostic {
                ctx.semaCtx.diagnostics.emit(diagnostic)
                sema.bindings.bindExprType(id, type: sema.types.errorType)
                return sema.types.errorType
            }
            guard let chosen = resolved.chosenCallee else {
                sema.bindings.bindExprType(id, type: sema.types.errorType)
                return sema.types.errorType
            }
            sema.bindings.bindCall(
                id,
                binding: CallBinding(
                    chosenCallee: chosen,
                    substitutedTypeArguments: resolved.substitutedTypeArguments
                        .sorted(by: { $0.key.rawValue < $1.key.rawValue })
                        .map(\.value),
                    parameterMapping: resolved.parameterMapping
                )
            )
            let returnType: TypeID
            if let signature = sema.symbols.functionSignature(for: chosen) {
                let typeVarBySymbol = sema.types.makeTypeVarBySymbol(signature.typeParameterSymbols)
                returnType = sema.types.substituteTypeParameters(
                    in: signature.returnType,
                    substitution: resolved.substitutedTypeArguments,
                    typeVarBySymbol: typeVarBySymbol
                )
            } else {
                returnType = sema.types.anyType
            }
            sema.bindings.bindExprType(id, type: returnType)
            return returnType

        case .whenExpr(let subjectID, let branches, let elseExpr, let range):
            let subjectType = inferExpr(subjectID, ctx: ctx, locals: &locals)
            let subjectLocalBinding: (name: InternedString, type: TypeID, symbol: SymbolID, isStable: Bool)? = {
                guard let subjectExpr = ast.arena.expr(subjectID),
                      case .nameRef(let subjectName, _) = subjectExpr,
                      let local = locals[subjectName] else {
                    return nil
                }
                return (
                    subjectName, local.type, local.symbol,
                    isStableLocalSymbol(local.symbol, sema: sema)
                )
            }()
            let hasExplicitNullBranch = branches.contains { branch in
                guard let condition = branch.condition,
                      let conditionExpr = ast.arena.expr(condition),
                      case .nameRef(let name, _) = conditionExpr else {
                    return false
                }
                return interner.resolve(name) == "null"
            }
            var branchTypes: [TypeID] = []
            var covered: Set<InternedString> = []
            var hasNullCase = false
            var hasTrueCase = false
            var hasFalseCase = false
            for branch in branches {
                var isNullBranch = false
                var branchSmartCastType: TypeID?
                if let cond = branch.condition {
                    let condType = inferExpr(cond, ctx: ctx, locals: &locals)
                    if let condExpr = ast.arena.expr(cond) {
                        switch condExpr {
                        case .boolLiteral(true, _):
                            if condType == boolType { hasTrueCase = true }
                            covered.insert(interner.intern("true"))
                        case .boolLiteral(false, _):
                            if condType == boolType { hasFalseCase = true }
                            covered.insert(interner.intern("false"))
                        case .nameRef(let name, _):
                            if interner.resolve(name) == "null" {
                                hasNullCase = true
                                isNullBranch = true
                            } else {
                                covered.insert(name)
                            }
                        default:
                            break
                        }
                    }
                    branchSmartCastType = smartCastTypeForWhenSubjectCase(
                        conditionID: cond, subjectType: subjectType,
                        ast: ast, sema: sema, interner: interner
                    )
                }
                var branchLocals = locals
                if let subjectLocalBinding, subjectLocalBinding.isStable {
                    if let branchSmartCastType {
                        branchLocals[subjectLocalBinding.name] = (
                            branchSmartCastType, subjectLocalBinding.symbol
                        )
                    } else if hasExplicitNullBranch && !isNullBranch {
                        branchLocals[subjectLocalBinding.name] = (
                            makeNonNullable(subjectLocalBinding.type, types: sema.types),
                            subjectLocalBinding.symbol
                        )
                    }
                }
                branchTypes.append(
                    inferExpr(branch.body, ctx: ctx, locals: &branchLocals, expectedType: expectedType)
                )
            }

            if let elseExpr {
                var elseLocals = locals
                if let subjectLocalBinding,
                   subjectLocalBinding.isStable,
                   hasExplicitNullBranch {
                    elseLocals[subjectLocalBinding.name] = (
                        makeNonNullable(subjectLocalBinding.type, types: sema.types),
                        subjectLocalBinding.symbol
                    )
                }
                branchTypes.append(
                    inferExpr(elseExpr, ctx: ctx, locals: &elseLocals, expectedType: expectedType)
                )
            }

            let summary = WhenBranchSummary(
                coveredSymbols: covered, hasElse: elseExpr != nil,
                hasNullCase: hasNullCase, hasTrueCase: hasTrueCase,
                hasFalseCase: hasFalseCase
            )
            if !ctx.dataFlow.isWhenExhaustive(subjectType: subjectType, branches: summary, sema: sema) {
                ctx.semaCtx.diagnostics.error(
                    "KSWIFTK-SEMA-0004",
                    "Non-exhaustive when expression.",
                    range: range
                )
            }

            let type = sema.types.lub(branchTypes)
            sema.bindings.bindExprType(id, type: type)
            return type
        }
    }

    private func makeNonNullable(_ type: TypeID, types: TypeSystem) -> TypeID {
        switch types.kind(of: type) {
        case .any(.nullable):
            return types.anyType

        case .primitive(let primitive, .nullable):
            return types.make(.primitive(primitive, .nonNull))

        case .classType(let classType):
            guard classType.nullability == .nullable else {
                return type
            }
            return types.make(.classType(ClassType(
                classSymbol: classType.classSymbol,
                args: classType.args,
                nullability: .nonNull
            )))

        case .typeParam(let typeParam):
            guard typeParam.nullability == .nullable else {
                return type
            }
            return types.make(.typeParam(TypeParamType(
                symbol: typeParam.symbol,
                nullability: .nonNull
            )))

        case .functionType(let functionType):
            guard functionType.nullability == .nullable else {
                return type
            }
            return types.make(.functionType(FunctionType(
                receiver: functionType.receiver,
                params: functionType.params,
                returnType: functionType.returnType,
                isSuspend: functionType.isSuspend,
                nullability: .nonNull
            )))

        default:
            return type
        }
    }

    private func isStableLocalSymbol(_ symbolID: SymbolID, sema: SemaModule) -> Bool {
        guard let symbol = sema.symbols.symbol(symbolID) else {
            return false
        }
        switch symbol.kind {
        case .valueParameter, .local:
            return !symbol.flags.contains(.mutable)
        default:
            return false
        }
    }

    private func smartCastTypeForWhenSubjectCase(
        conditionID: ExprID,
        subjectType: TypeID,
        ast: ASTModule,
        sema: SemaModule,
        interner: StringInterner
    ) -> TypeID? {
        guard let conditionExpr = ast.arena.expr(conditionID) else {
            return nil
        }
        switch conditionExpr {
        case .boolLiteral:
            switch sema.types.kind(of: subjectType) {
            case .primitive(.boolean, _):
                return sema.types.make(.primitive(.boolean, .nonNull))
            default:
                return nil
            }

        case .nameRef(let name, _):
            if interner.resolve(name) == "null" {
                return nil
            }
            guard let conditionSymbolID = sema.bindings.identifierSymbols[conditionID],
                  let conditionSymbol = sema.symbols.symbol(conditionSymbolID) else {
                return nil
            }
            switch conditionSymbol.kind {
            case .field:
                guard let enumOwner = enumOwnerSymbol(for: conditionSymbol, symbols: sema.symbols),
                      nominalSymbol(of: subjectType, types: sema.types) == enumOwner else {
                    return nil
                }
                return sema.types.make(.classType(ClassType(
                    classSymbol: enumOwner,
                    args: [],
                    nullability: .nonNull
                )))

            case .class, .interface, .object, .enumClass, .annotationClass, .typeAlias:
                guard let subjectNominal = nominalSymbol(of: subjectType, types: sema.types),
                      isNominalSubtype(conditionSymbolID, of: subjectNominal, symbols: sema.symbols) else {
                    return nil
                }
                return sema.types.make(.classType(ClassType(
                    classSymbol: conditionSymbolID,
                    args: [],
                    nullability: .nonNull
                )))

            default:
                return nil
            }

        default:
            return nil
        }
    }

    private func nominalSymbol(of type: TypeID, types: TypeSystem) -> SymbolID? {
        if case .classType(let classType) = types.kind(of: type) {
            return classType.classSymbol
        }
        return nil
    }

    private func enumOwnerSymbol(for entrySymbol: SemanticSymbol, symbols: SymbolTable) -> SymbolID? {
        guard entrySymbol.kind == .field,
              entrySymbol.fqName.count >= 2 else {
            return nil
        }
        let ownerFQName = Array(entrySymbol.fqName.dropLast())
        return symbols.lookupAll(fqName: ownerFQName).first(where: { symbolID in
            symbols.symbol(symbolID)?.kind == .enumClass
        })
    }

    private func isNominalSubtype(
        _ candidate: SymbolID,
        of base: SymbolID,
        symbols: SymbolTable
    ) -> Bool {
        if candidate == base {
            return true
        }
        var queue = symbols.directSupertypes(for: candidate)
        var visited: Set<SymbolID> = [candidate]
        while !queue.isEmpty {
            let next = queue.removeFirst()
            if next == base {
                return true
            }
            if visited.insert(next).inserted {
                queue.append(contentsOf: symbols.directSupertypes(for: next))
            }
        }
        return false
    }

    private func buildFileScopes(
        ast: ASTModule,
        sema: SemaModule,
        interner: StringInterner
    ) -> [Int32: FileScope] {
        let topLevelSymbolsByPackage = collectTopLevelSymbolsByPackage(ast: ast, sema: sema)
        let defaultImportPackages = makeDefaultImportPackages(interner: interner)
        var fileScopes: [Int32: FileScope] = [:]

        for file in ast.sortedFiles {
            let defaultImportScope = ImportScope(parent: nil, symbols: sema.symbols)
            for packagePath in defaultImportPackages {
                for importedSymbol in topLevelSymbolsByPackage[packagePath] ?? [] {
                    defaultImportScope.insert(importedSymbol)
                }
            }

            let wildcardImportScope = ImportScope(parent: defaultImportScope, symbols: sema.symbols)
            let explicitImportScope = ImportScope(parent: wildcardImportScope, symbols: sema.symbols)
            populateImportScopes(
                for: file,
                sema: sema,
                explicitImportScope: explicitImportScope,
                wildcardImportScope: wildcardImportScope,
                topLevelSymbolsByPackage: topLevelSymbolsByPackage
            )

            let packageScope = PackageScope(parent: explicitImportScope, symbols: sema.symbols)
            for packageSymbol in topLevelSymbolsByPackage[file.packageFQName] ?? [] {
                packageScope.insert(packageSymbol)
            }

            let fileScope = FileScope(parent: packageScope, symbols: sema.symbols)
            fileScopes[file.fileID.rawValue] = fileScope
        }

        return fileScopes
    }

    private func collectTopLevelSymbolsByPackage(
        ast: ASTModule,
        sema: SemaModule
    ) -> [[InternedString]: [SymbolID]] {
        var mapping: [[InternedString]: [SymbolID]] = [:]
        for file in ast.sortedFiles {
            for declID in file.topLevelDecls {
                guard let symbol = sema.bindings.declSymbols[declID] else {
                    continue
                }
                mapping[file.packageFQName, default: []].append(symbol)
            }
        }
        return mapping
    }

    private func populateImportScopes(
        for file: ASTFile,
        sema: SemaModule,
        explicitImportScope: ImportScope,
        wildcardImportScope: ImportScope,
        topLevelSymbolsByPackage: [[InternedString]: [SymbolID]]
    ) {
        for importDecl in file.imports {
            let resolved = sema.symbols.lookupAll(fqName: importDecl.path)
            if resolved.isEmpty {
                continue
            }

            let importedSymbols = resolved.filter { symbolID in
                guard let symbol = sema.symbols.symbol(symbolID) else {
                    return false
                }
                return symbol.kind != .package
            }
            if !importedSymbols.isEmpty {
                for importedSymbol in importedSymbols {
                    explicitImportScope.insert(importedSymbol)
                }
                continue
            }

            let hasPackageImport = resolved.contains { symbolID in
                sema.symbols.symbol(symbolID)?.kind == .package
            }
            if hasPackageImport {
                for importedSymbol in topLevelSymbolsByPackage[importDecl.path] ?? [] {
                    wildcardImportScope.insert(importedSymbol)
                }
            }
        }
    }

    private func makeDefaultImportPackages(interner: StringInterner) -> [[InternedString]] {
        let packages: [[String]] = [
            ["kotlin"],
            ["kotlin", "annotation"],
            ["kotlin", "collections"],
            ["kotlin", "comparisons"],
            ["kotlin", "io"],
            ["kotlin", "ranges"],
            ["kotlin", "sequences"],
            ["kotlin", "text"]
        ]
        return packages.map { segments in
            segments.map { interner.intern($0) }
        }
    }

}


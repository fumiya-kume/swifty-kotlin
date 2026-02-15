import Foundation

private extension ASTModule {
    var sortedFiles: [ASTFile] {
        files.sorted(by: { $0.fileID.rawValue < $1.fileID.rawValue })
    }
}

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

        for file in ast.sortedFiles {
            let packageSymbol = definePackageSymbol(for: file, symbols: symbols, interner: ctx.interner)
            let packageScope = PackageScope(parent: rootScope, symbols: symbols)
            packageScope.insert(packageSymbol)
            fileScopes[file.fileID.rawValue] = FileScope(parent: packageScope, symbols: symbols)
        }

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
            bindings: bindings
        )

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

    private func definePackageSymbol(for file: ASTFile, symbols: SymbolTable, interner: StringInterner) -> SymbolID {
        let package = file.packageFQName.isEmpty ? [interner.intern("_root_")] : file.packageFQName
        let name = package.last ?? interner.intern("_root_")
        if let existing = symbols.lookup(fqName: package) {
            return existing
        }
        return symbols.define(
            kind: .package,
            name: name,
            fqName: package,
            declSite: nil,
            visibility: .public
        )
    }

    private func collectHeader(
        declID: DeclID,
        file: ASTFile,
        ast: ASTModule,
        symbols: SymbolTable,
        types: TypeSystem,
        bindings: BindingTable,
        scope: Scope,
        diagnostics: DiagnosticEngine,
        interner: StringInterner
    ) {
        guard let decl = ast.arena.decl(declID) else { return }
        let package = file.packageFQName
        let anyType = types.anyType
        let unitType = types.unitType

        let declaration: (kind: SymbolKind, name: InternedString, range: SourceRange?, visibility: Visibility, flags: SymbolFlags)?
        switch decl {
        case .classDecl(let classDecl):
            declaration = (
                kind: classSymbolKind(for: classDecl),
                name: classDecl.name,
                range: classDecl.range,
                visibility: visibility(from: classDecl.modifiers),
                flags: flags(from: classDecl.modifiers)
            )
        case .objectDecl(let objectDecl):
            declaration = (
                kind: .object,
                name: objectDecl.name,
                range: objectDecl.range,
                visibility: visibility(from: objectDecl.modifiers),
                flags: flags(from: objectDecl.modifiers)
            )
        case .funDecl(let funDecl):
            declaration = (
                kind: .function,
                name: funDecl.name,
                range: funDecl.range,
                visibility: visibility(from: funDecl.modifiers),
                flags: flags(from: funDecl.modifiers)
            )
        case .propertyDecl(let propertyDecl):
            var propertyFlags = flags(from: propertyDecl.modifiers)
            if propertyDecl.isVar {
                propertyFlags.insert(.mutable)
            }
            declaration = (
                kind: .property,
                name: propertyDecl.name,
                range: propertyDecl.range,
                visibility: visibility(from: propertyDecl.modifiers),
                flags: propertyFlags
            )
        case .typeAliasDecl(let typeAliasDecl):
            declaration = (
                kind: .typeAlias,
                name: typeAliasDecl.name,
                range: typeAliasDecl.range,
                visibility: visibility(from: typeAliasDecl.modifiers),
                flags: flags(from: typeAliasDecl.modifiers)
            )
        case .enumEntry(let entry):
            declaration = (
                kind: .field,
                name: entry.name,
                range: entry.range,
                visibility: .public,
                flags: []
            )
        }

        guard let declaration else { return }
        let fqName = package + [declaration.name]
        let existingSymbols = symbols.lookupAll(fqName: fqName).compactMap { symbols.symbol($0) }
        if hasDeclarationConflict(newKind: declaration.kind, existing: existingSymbols) {
            diagnostics.error(
                "KSWIFTK-SEMA-0001",
                "Duplicate declaration in the same package scope.",
                range: declaration.range
            )
        }
        let symbol = symbols.define(
            kind: declaration.kind,
            name: declaration.name,
            fqName: fqName,
            declSite: declaration.range,
            visibility: declaration.visibility,
            flags: declaration.flags
        )
        scope.insert(symbol)
        bindings.bindDecl(declID, symbol: symbol)

        switch decl {
        case .classDecl(let classDecl):
            let classType = types.make(.classType(ClassType(classSymbol: symbol, args: [], nullability: .nonNull)))
            if declaration.kind == .enumClass {
                for entry in classDecl.enumEntries {
                    let entryFQName = fqName + [entry.name]
                    let existingEntrySymbols = symbols.lookupAll(fqName: entryFQName).compactMap { symbols.symbol($0) }
                    if hasDeclarationConflict(newKind: .field, existing: existingEntrySymbols) {
                        diagnostics.error(
                            "KSWIFTK-SEMA-0001",
                            "Duplicate declaration in the same package scope.",
                            range: entry.range
                        )
                    }
                    let entrySymbol = symbols.define(
                        kind: .field,
                        name: entry.name,
                        fqName: entryFQName,
                        declSite: entry.range,
                        visibility: .public,
                        flags: []
                    )
                    symbols.setPropertyType(classType, for: entrySymbol)
                    scope.insert(entrySymbol)
                }
            }

        case .objectDecl:
            _ = types.make(.classType(ClassType(classSymbol: symbol, args: [], nullability: .nonNull)))

        case .funDecl(let funDecl):
            var paramTypes: [TypeID] = []
            var paramSymbols: [SymbolID] = []
            var paramHasDefaultValues: [Bool] = []
            var paramIsVararg: [Bool] = []
            var typeParameterSymbols: [SymbolID] = []
            var localTypeParameters: [InternedString: SymbolID] = [:]
            let localNamespaceFQName = fqName + [interner.intern("$\(symbol.rawValue)")]
            for typeParam in funDecl.typeParams {
                let typeParamFQName = localNamespaceFQName + [typeParam.name]
                let typeParamSymbol = symbols.define(
                    kind: .typeParameter,
                    name: typeParam.name,
                    fqName: typeParamFQName,
                    declSite: funDecl.range,
                    visibility: .private,
                    flags: []
                )
                typeParameterSymbols.append(typeParamSymbol)
                localTypeParameters[typeParam.name] = typeParamSymbol
            }
            let receiverType = resolveTypeRef(
                funDecl.receiverType,
                ast: ast,
                symbols: symbols,
                types: types,
                interner: interner,
                localTypeParameters: localTypeParameters
            )
            for valueParam in funDecl.valueParams {
                let paramFQName = localNamespaceFQName + [valueParam.name]
                let paramSymbol = symbols.define(
                    kind: .valueParameter,
                    name: valueParam.name,
                    fqName: paramFQName,
                    declSite: funDecl.range,
                    visibility: .private,
                    flags: []
                )
                let resolvedType = resolveTypeRef(
                    valueParam.type,
                    ast: ast,
                    symbols: symbols,
                    types: types,
                    interner: interner,
                    localTypeParameters: localTypeParameters
                ) ?? anyType
                paramTypes.append(resolvedType)
                paramSymbols.append(paramSymbol)
                paramHasDefaultValues.append(valueParam.hasDefaultValue)
                paramIsVararg.append(valueParam.isVararg)
            }
            let returnType: TypeID
            if let explicit = resolveTypeRef(
                funDecl.returnType,
                ast: ast,
                symbols: symbols,
                types: types,
                interner: interner,
                localTypeParameters: localTypeParameters
            ) {
                returnType = explicit
            } else {
                switch funDecl.body {
                case .unit:
                    returnType = unitType
                case .block, .expr:
                    returnType = anyType
                }
            }
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: receiverType,
                    parameterTypes: paramTypes,
                    returnType: returnType,
                    isSuspend: funDecl.isSuspend,
                    valueParameterSymbols: paramSymbols,
                    valueParameterHasDefaultValues: paramHasDefaultValues,
                    valueParameterIsVararg: paramIsVararg,
                    typeParameterSymbols: typeParameterSymbols
                ),
                for: symbol
            )

        case .propertyDecl(let propertyDecl):
            let resolvedType = resolveTypeRef(
                propertyDecl.type,
                ast: ast,
                symbols: symbols,
                types: types,
                interner: interner
            ) ?? types.nullableAnyType
            symbols.setPropertyType(resolvedType, for: symbol)

        case .typeAliasDecl, .enumEntry:
            break
        }
    }

    private func bindInheritanceEdges(
        ast: ASTModule,
        symbols: SymbolTable,
        bindings: BindingTable
    ) {
        for file in ast.sortedFiles {
            for declID in file.topLevelDecls {
                guard let symbol = bindings.declSymbols[declID],
                      let decl = ast.arena.decl(declID) else {
                    continue
                }
                let superTypeRefs: [TypeRefID]
                switch decl {
                case .classDecl(let classDecl):
                    superTypeRefs = classDecl.superTypes
                case .objectDecl(let objectDecl):
                    superTypeRefs = objectDecl.superTypes
                default:
                    continue
                }

                var superSymbols: [SymbolID] = []
                for superTypeRef in superTypeRefs {
                    if let superSymbol = resolveNominalSymbolFromTypeRef(
                        superTypeRef,
                        currentPackage: file.packageFQName,
                        ast: ast,
                        symbols: symbols
                    ) {
                        superSymbols.append(superSymbol)
                    }
                }
                let uniqueSuperSymbols = Array(Set(superSymbols)).sorted(by: { $0.rawValue < $1.rawValue })
                symbols.setDirectSupertypes(uniqueSuperSymbols, for: symbol)
            }
        }
    }

    private func resolveNominalSymbolFromTypeRef(
        _ typeRefID: TypeRefID,
        currentPackage: [InternedString],
        ast: ASTModule,
        symbols: SymbolTable
    ) -> SymbolID? {
        guard let typeRef = ast.arena.typeRef(typeRefID) else {
            return nil
        }
        let path: [InternedString]
        switch typeRef {
        case .named(let refPath, _):
            path = refPath
        }
        guard !path.isEmpty else {
            return nil
        }

        var candidatePaths: [[InternedString]] = [path]
        if path.count == 1 && !currentPackage.isEmpty {
            candidatePaths.append(currentPackage + path)
        }

        for candidatePath in candidatePaths {
            if let symbol = symbols.lookupAll(fqName: candidatePath)
                .compactMap({ symbols.symbol($0) })
                .first(where: { isNominalTypeSymbol($0.kind) })?.id {
                return symbol
            }
        }
        return nil
    }

    private func classSymbolKind(for classDecl: ClassDecl) -> SymbolKind {
        if classDecl.modifiers.contains(.annotationClass) {
            return .annotationClass
        }
        if classDecl.modifiers.contains(.enumModifier) {
            return .enumClass
        }
        return .class
    }

    private func resolveTypeRef(
        _ typeRefID: TypeRefID?,
        ast: ASTModule,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        localTypeParameters: [InternedString: SymbolID] = [:]
    ) -> TypeID? {
        guard let typeRefID, let typeRef = ast.arena.typeRef(typeRefID) else {
            return nil
        }

        let nullability: Nullability
        let path: [InternedString]
        switch typeRef {
        case .named(let refPath, let nullable):
            path = refPath
            nullability = nullable ? .nullable : .nonNull
        }

        guard let shortName = path.last else {
            return nil
        }

        if path.count == 1, let typeParamSymbol = localTypeParameters[shortName] {
            return types.make(.typeParam(TypeParamType(symbol: typeParamSymbol, nullability: nullability)))
        }

        switch interner.resolve(shortName) {
        case "Int":
            return types.make(.primitive(.int, nullability))
        case "Boolean":
            return types.make(.primitive(.boolean, nullability))
        case "String":
            return types.make(.primitive(.string, nullability))
        case "Any":
            return nullability == .nullable ? types.nullableAnyType : types.anyType
        case "Unit":
            return nullability == .nullable ? types.nullableAnyType : types.unitType
        case "Nothing":
            return types.nothingType
        default:
            break
        }

        if let symbol = symbols.lookupAll(fqName: path)
            .compactMap({ symbols.symbol($0) })
            .first(where: { isNominalTypeSymbol($0.kind) })?.id {
            return types.make(.classType(ClassType(classSymbol: symbol, args: [], nullability: nullability)))
        }
        return nullability == .nullable ? types.nullableAnyType : types.anyType
    }

    private func hasDeclarationConflict(newKind: SymbolKind, existing: [SemanticSymbol]) -> Bool {
        guard !existing.isEmpty else {
            return false
        }
        if isOverloadableSymbol(newKind) {
            return existing.contains(where: { !isOverloadableSymbol($0.kind) })
        }
        return true
    }

    private func isOverloadableSymbol(_ kind: SymbolKind) -> Bool {
        kind == .function || kind == .constructor
    }

    private func isNominalTypeSymbol(_ kind: SymbolKind) -> Bool {
        switch kind {
        case .class, .interface, .object, .enumClass, .annotationClass, .typeAlias:
            return true
        default:
            return false
        }
    }

    private func analyzeBody(
        declID: DeclID,
        ast: ASTModule,
        symbols: SymbolTable,
        types: TypeSystem,
        bindings: BindingTable,
        diagnostics: DiagnosticEngine,
        interner: StringInterner
    ) {
        guard let decl = ast.arena.decl(declID) else { return }
        switch decl {
        case .funDecl(let funDecl):
            var seenNames: Set<InternedString> = []
            for valueParam in funDecl.valueParams {
                if seenNames.contains(valueParam.name) {
                    diagnostics.error(
                        "KSWIFTK-TYPE-0002",
                        "Duplicate function parameter name.",
                        range: funDecl.range
                    )
                }
                seenNames.insert(valueParam.name)
            }

            if let symbol = bindings.declSymbols[declID],
               let signature = symbols.functionSignature(for: symbol),
               case .expr = funDecl.body {
                // Bind a synthetic expression type for expression-body functions.
                let expr = ExprID(rawValue: declID.rawValue)
                bindings.bindExprType(expr, type: signature.returnType)
            }

        case .propertyDecl(let propertyDecl):
            if let symbol = bindings.declSymbols[declID] {
                let expr = ExprID(rawValue: declID.rawValue)
                bindings.bindIdentifier(expr, symbol: symbol)
                let boundType = resolveTypeRef(
                    propertyDecl.type,
                    ast: ast,
                    symbols: symbols,
                    types: types,
                    interner: interner
                ) ?? types.anyType
                bindings.bindExprType(expr, type: boundType)
            }

        case .classDecl, .objectDecl, .typeAliasDecl, .enumEntry:
            break
        }
    }

    private func visibility(from modifiers: Modifiers) -> Visibility {
        if modifiers.contains(.privateModifier) {
            return .private
        }
        if modifiers.contains(.internalModifier) {
            return .internal
        }
        if modifiers.contains(.protectedModifier) {
            return .protected
        }
        return .public
    }

    private func flags(from modifiers: Modifiers) -> SymbolFlags {
        var value: SymbolFlags = []
        if modifiers.contains(.suspend) {
            value.insert(.suspendFunction)
        }
        if modifiers.contains(.inline) {
            value.insert(.inlineFunction)
        }
        if modifiers.contains(.sealed) {
            value.insert(.sealedType)
        }
        if modifiers.contains(.data) {
            value.insert(.dataType)
        }
        return value
    }
}

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

public final class SemaPassesPhase: CompilerPhase {
    public static let name = "SemaPasses"

    private let passes: [CompilerPhase] = [
        DataFlowSemaPassPhase(),
        TypeCheckSemaPassPhase()
    ]

    public init() {}

    public func run(_ ctx: CompilationContext) throws {
        guard ctx.ast != nil else {
            throw CompilerPipelineError.invalidInput("AST phase did not run.")
        }
        for phase in passes {
            try phase.run(ctx)
        }
    }
}

public final class BuildKIRPhase: CompilerPhase {
    public static let name = "BuildKIR"

    public init() {}

    public func run(_ ctx: CompilationContext) throws {
        guard let ast = ctx.ast, let sema = ctx.sema else {
            throw CompilerPipelineError.invalidInput("Sema phase did not run.")
        }

        let arena = KIRArena()
        var files: [KIRFile] = []

        for file in ast.sortedFiles {
            var declIDs: [KIRDeclID] = []
            for declID in file.topLevelDecls {
                guard let decl = ast.arena.decl(declID),
                      let symbol = sema.bindings.declSymbols[declID] else {
                    continue
                }

                switch decl {
                case .classDecl, .objectDecl:
                    let kirID = arena.appendDecl(.nominalType(KIRNominalType(symbol: symbol)))
                    declIDs.append(kirID)

                case .funDecl(let function):
                    let signature = sema.symbols.functionSignature(for: symbol)
                    let params: [KIRParameter]
                    if let signature {
                        params = zip(signature.valueParameterSymbols, signature.parameterTypes).map { pair in
                            KIRParameter(symbol: pair.0, type: pair.1)
                        }
                    } else {
                        params = []
                    }
                    let returnType = signature?.returnType ?? sema.types.unitType
                    var body: [KIRInstruction] = [.beginBlock]
                    switch function.body {
                    case .block(let exprIDs, _):
                        var lastValue: KIRExprID?
                        for exprID in exprIDs {
                            lastValue = lowerExpr(exprID, ast: ast, sema: sema, arena: arena, interner: ctx.interner, instructions: &body)
                        }
                        if let lastValue {
                            body.append(.returnValue(lastValue))
                        } else {
                            body.append(.returnUnit)
                        }
                    case .expr(let exprID, _):
                        let value = lowerExpr(exprID, ast: ast, sema: sema, arena: arena, interner: ctx.interner, instructions: &body)
                        body.append(.returnValue(value))
                    case .unit:
                        body.append(.returnUnit)
                    }
                    body.append(.endBlock)
                    let kirID = arena.appendDecl(
                        .function(
                            KIRFunction(
                                symbol: symbol,
                                name: function.name,
                                params: params,
                                returnType: returnType,
                                body: body,
                                isSuspend: function.isSuspend,
                                isInline: function.isInline
                            )
                        )
                    )
                    declIDs.append(kirID)

                case .propertyDecl:
                    let kirID = arena.appendDecl(.global(KIRGlobal(symbol: symbol, type: sema.types.anyType)))
                    declIDs.append(kirID)

                case .typeAliasDecl:
                    let kirID = arena.appendDecl(.nominalType(KIRNominalType(symbol: symbol)))
                    declIDs.append(kirID)

                case .enumEntry:
                    let kirID = arena.appendDecl(.global(KIRGlobal(symbol: symbol, type: sema.types.anyType)))
                    declIDs.append(kirID)
                }
            }
            files.append(KIRFile(fileID: file.fileID, decls: declIDs))
        }

        let module = KIRModule(files: files, arena: arena)
        if module.functionCount == 0 && !ctx.diagnostics.hasError {
            ctx.diagnostics.warning(
                "KSWIFTK-KIR-0001",
                "No function declarations found.",
                range: nil
            )
        }
        ctx.kir = module
    }

    private func lowerExpr(
        _ exprID: ExprID,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        guard let expr = ast.arena.expr(exprID) else {
            let temp = arena.appendExpr(.temporary(Int32(arena.expressions.count)))
            instructions.append(.constValue(result: temp, value: .unit))
            return temp
        }

        switch expr {
        case .intLiteral(let value, _):
            let id = arena.appendExpr(.intLiteral(value))
            instructions.append(.constValue(result: id, value: .intLiteral(value)))
            return id

        case .boolLiteral(let value, _):
            let id = arena.appendExpr(.boolLiteral(value))
            instructions.append(.constValue(result: id, value: .boolLiteral(value)))
            return id

        case .stringLiteral(let value, _):
            let id = arena.appendExpr(.stringLiteral(value))
            instructions.append(.constValue(result: id, value: .stringLiteral(value)))
            return id

        case .nameRef(let name, _):
            if let symbol = sema.bindings.identifierSymbols[exprID] {
                let id = arena.appendExpr(.symbolRef(symbol))
                instructions.append(.constValue(result: id, value: .symbolRef(symbol)))
                return id
            }
            let id = arena.appendExpr(.temporary(Int32(arena.expressions.count)))
            instructions.append(.call(symbol: nil, callee: name, arguments: [], result: id, outThrown: false))
            return id

        case .binary(let op, let lhs, let rhs, _):
            let lhsID = lowerExpr(lhs, ast: ast, sema: sema, arena: arena, interner: interner, instructions: &instructions)
            let rhsID = lowerExpr(rhs, ast: ast, sema: sema, arena: arena, interner: interner, instructions: &instructions)
            let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)))
            let kirOp: KIRBinaryOp
            switch op {
            case .add:
                kirOp = .add
            case .subtract:
                kirOp = .subtract
            case .multiply:
                kirOp = .multiply
            case .divide:
                kirOp = .divide
            case .equal:
                kirOp = .equal
            }
            instructions.append(.binary(op: kirOp, lhs: lhsID, rhs: rhsID, result: result))
            return result

        case .call(let calleeExpr, let args, _):
            let calleeName: InternedString
            if let callee = ast.arena.expr(calleeExpr), case .nameRef(let name, _) = callee {
                calleeName = name
            } else {
                calleeName = sema.symbols.allSymbols().first?.name ?? InternedString(rawValue: invalidID)
            }
            let argIDs = args.map { argument in
                lowerExpr(argument.expr, ast: ast, sema: sema, arena: arena, interner: interner, instructions: &instructions)
            }
            let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)))
            let chosen = sema.bindings.callBindings[exprID]?.chosenCallee
            instructions.append(.call(symbol: chosen, callee: calleeName, arguments: argIDs, result: result, outThrown: false))
            return result

        case .whenExpr(let subject, let branches, let elseExpr, _):
            let subjectID = lowerExpr(subject, ast: ast, sema: sema, arena: arena, interner: interner, instructions: &instructions)
            var branchValues: [KIRExprID] = [subjectID]
            for branch in branches {
                branchValues.append(lowerExpr(branch.body, ast: ast, sema: sema, arena: arena, interner: interner, instructions: &instructions))
            }
            if let elseExpr {
                branchValues.append(lowerExpr(elseExpr, ast: ast, sema: sema, arena: arena, interner: interner, instructions: &instructions))
            }
            let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)))
            let callee = interner.intern("__when_expr__")
            instructions.append(.call(symbol: nil, callee: callee, arguments: branchValues, result: result, outThrown: false))
            return result
        }
    }
}

private protocol LoweringImpl: KIRPass {}

private final class NormalizeBlocksPass: LoweringImpl {
    static let name = "NormalizeBlocks"
    func run(module: KIRModule, ctx: KIRContext) throws {
        module.arena.transformFunctions { function in
            var updated = function
            updated.body = function.body.filter { instruction in
                switch instruction {
                case .beginBlock, .endBlock:
                    return false
                default:
                    return true
                }
            }
            if let last = updated.body.last {
                switch last {
                case .returnUnit, .returnValue:
                    break
                default:
                    updated.body.append(.returnUnit)
                }
            } else {
                updated.body = [.returnUnit]
            }
            return updated
        }
        module.recordLowering(Self.name)
    }
}

private final class OperatorLoweringPass: LoweringImpl {
    static let name = "OperatorLowering"
    func run(module: KIRModule, ctx: KIRContext) throws {
        module.arena.transformFunctions { function in
            var updated = function
            updated.body = function.body.map { instruction in
                guard case .binary(let op, let lhs, let rhs, let result) = instruction else {
                    return instruction
                }
                let callee: InternedString
                switch op {
                case .add:
                    callee = ctx.interner.intern("kk_op_add")
                case .subtract:
                    callee = ctx.interner.intern("kk_op_sub")
                case .multiply:
                    callee = ctx.interner.intern("kk_op_mul")
                case .divide:
                    callee = ctx.interner.intern("kk_op_div")
                case .equal:
                    callee = ctx.interner.intern("kk_op_eq")
                }
                return .call(symbol: nil, callee: callee, arguments: [lhs, rhs], result: result, outThrown: false)
            }
            return updated
        }
        module.recordLowering(Self.name)
    }
}

private final class ForLoweringPass: LoweringImpl {
    static let name = "ForLowering"

    func run(module: KIRModule, ctx: KIRContext) throws {
        let markerCallee = ctx.interner.intern("__for_expr__")
        let iteratorCallee = ctx.interner.intern("iterator")
        let loweredCallee = ctx.interner.intern("kk_for_lowered")

        module.arena.transformFunctions { function in
            var updated = function
            var loweredBody: [KIRInstruction] = []
            loweredBody.reserveCapacity(function.body.count)

            for instruction in function.body {
                guard case .call(let symbol, let callee, let arguments, let result, let outThrown) = instruction,
                      callee == markerCallee else {
                    loweredBody.append(instruction)
                    continue
                }

                if let iterable = arguments.first {
                    let iteratorTemp = module.arena.appendExpr(.temporary(Int32(module.arena.expressions.count)))
                    loweredBody.append(
                        .call(
                            symbol: nil,
                            callee: iteratorCallee,
                            arguments: [iterable],
                            result: iteratorTemp,
                            outThrown: outThrown
                        )
                    )
                    var loweredArguments: [KIRExprID] = [iteratorTemp]
                    loweredArguments.append(contentsOf: arguments.dropFirst())
                    loweredBody.append(
                        .call(
                            symbol: symbol,
                            callee: loweredCallee,
                            arguments: loweredArguments,
                            result: result,
                            outThrown: outThrown
                        )
                    )
                } else {
                    loweredBody.append(
                        .call(
                            symbol: symbol,
                            callee: loweredCallee,
                            arguments: [],
                            result: result,
                            outThrown: outThrown
                        )
                    )
                }
            }

            updated.body = loweredBody
            return updated
        }
        module.recordLowering(Self.name)
    }
}

private final class WhenLoweringPass: LoweringImpl {
    static let name = "WhenLowering"

    func run(module: KIRModule, ctx: KIRContext) throws {
        let markerCallee = ctx.interner.intern("__when_expr__")
        let loweredCallee = ctx.interner.intern("kk_when_select")

        module.arena.transformFunctions { function in
            var updated = function
            updated.body = function.body.map { instruction in
                guard case .call(let symbol, let callee, let arguments, let result, let outThrown) = instruction,
                      callee == markerCallee else {
                    return instruction
                }
                if arguments.isEmpty {
                    let unitValue = module.arena.appendExpr(.unit)
                    return .call(
                        symbol: symbol,
                        callee: loweredCallee,
                        arguments: [unitValue],
                        result: result,
                        outThrown: outThrown
                    )
                }
                return .call(
                    symbol: symbol,
                    callee: loweredCallee,
                    arguments: arguments,
                    result: result,
                    outThrown: outThrown
                )
            }
            return updated
        }
        module.recordLowering(Self.name)
    }
}

private final class PropertyLoweringPass: LoweringImpl {
    static let name = "PropertyLowering"

    func run(module: KIRModule, ctx: KIRContext) throws {
        let getterName = ctx.interner.intern("get")
        let setterName = ctx.interner.intern("set")
        let loweredCallee = ctx.interner.intern("kk_property_access")

        module.arena.transformFunctions { function in
            var updated = function
            var loweredBody: [KIRInstruction] = []
            loweredBody.reserveCapacity(function.body.count)

            for instruction in function.body {
                guard case .call(let symbol, let callee, let arguments, let result, let outThrown) = instruction else {
                    loweredBody.append(instruction)
                    continue
                }
                guard callee == getterName || callee == setterName else {
                    loweredBody.append(instruction)
                    continue
                }

                let isSetter = callee == setterName
                let accessorKind = module.arena.appendExpr(.temporary(Int32(module.arena.expressions.count)))
                loweredBody.append(
                    .constValue(
                        result: accessorKind,
                        value: .boolLiteral(isSetter)
                    )
                )
                var loweredArguments: [KIRExprID] = [accessorKind]
                loweredArguments.append(contentsOf: arguments)
                loweredBody.append(
                    .call(
                        symbol: symbol,
                        callee: loweredCallee,
                        arguments: loweredArguments,
                        result: result,
                        outThrown: outThrown
                    )
                )
            }

            updated.body = loweredBody
            return updated
        }
        module.recordLowering(Self.name)
    }
}

private final class DataEnumSealedSynthesisPass: LoweringImpl {
    static let name = "DataEnumSealedSynthesis"

    func run(module: KIRModule, ctx: KIRContext) throws {
        module.arena.transformFunctions { function in
            var updated = function
            if updated.body.isEmpty {
                updated.body = [.nop, .returnUnit]
            }
            return updated
        }

        guard let sema = ctx.sema else {
            module.recordLowering(Self.name)
            return
        }

        let intType = sema.types.make(.primitive(.int, .nonNull))
        let existingFunctionSymbols = Set(module.arena.declarations.compactMap { decl -> SymbolID? in
            guard case .function(let function) = decl else {
                return nil
            }
            return function.symbol
        })
        let nominalSymbols = module.arena.declarations.compactMap { decl -> SymbolID? in
            guard case .nominalType(let nominal) = decl else {
                return nil
            }
            return nominal.symbol
        }

        for nominalSymbolID in nominalSymbols {
            guard let nominalSymbol = sema.symbols.symbol(nominalSymbolID) else {
                continue
            }

            if nominalSymbol.kind == .enumClass {
                let entries = enumEntrySymbols(owner: nominalSymbol, symbols: sema.symbols)
                let valuesCount = Int64(entries.count)
                let helperName = ctx.interner.intern("\(ctx.interner.resolve(nominalSymbol.name))$enumValuesCount")
                appendSyntheticCountFunctionIfNeeded(
                    name: helperName,
                    owner: nominalSymbol,
                    value: valuesCount,
                    returnType: intType,
                    module: module,
                    sema: sema,
                    existingFunctionSymbols: existingFunctionSymbols
                )
            }

            if nominalSymbol.flags.contains(.sealedType) {
                let subtypeCount = Int64(sema.symbols.directSubtypes(of: nominalSymbol.id).count)
                let helperName = ctx.interner.intern("\(ctx.interner.resolve(nominalSymbol.name))$sealedSubtypeCount")
                appendSyntheticCountFunctionIfNeeded(
                    name: helperName,
                    owner: nominalSymbol,
                    value: subtypeCount,
                    returnType: intType,
                    module: module,
                    sema: sema,
                    existingFunctionSymbols: existingFunctionSymbols
                )
            }

            if nominalSymbol.flags.contains(.dataType) {
                let helperName = ctx.interner.intern("\(ctx.interner.resolve(nominalSymbol.name))$copy")
                appendSyntheticDataCopyIfNeeded(
                    name: helperName,
                    owner: nominalSymbol,
                    module: module,
                    sema: sema,
                    existingFunctionSymbols: existingFunctionSymbols,
                    interner: ctx.interner
                )
            }
        }

        module.recordLowering(Self.name)
    }

    private func enumEntrySymbols(owner: SemanticSymbol, symbols: SymbolTable) -> [SemanticSymbol] {
        let prefixLength = owner.fqName.count
        return symbols
            .allSymbols()
            .filter { symbol in
                guard symbol.kind == .field, symbol.fqName.count == prefixLength + 1 else {
                    return false
                }
                return Array(symbol.fqName.prefix(prefixLength)) == owner.fqName
            }
            .sorted(by: { $0.id.rawValue < $1.id.rawValue })
    }

    private func appendSyntheticCountFunctionIfNeeded(
        name: InternedString,
        owner: SemanticSymbol,
        value: Int64,
        returnType: TypeID,
        module: KIRModule,
        sema: SemaModule,
        existingFunctionSymbols: Set<SymbolID>
    ) {
        let signature = FunctionSignature(parameterTypes: [], returnType: returnType, isSuspend: false)
        let resultExpr = module.arena.appendExpr(.temporary(Int32(module.arena.expressions.count)))
        let body: [KIRInstruction] = [
            .constValue(result: resultExpr, value: .intLiteral(value)),
            .returnValue(resultExpr)
        ]
        appendSyntheticFunctionIfNeeded(
            name: name,
            owner: owner,
            module: module,
            sema: sema,
            signature: signature,
            params: [],
            body: body,
            existingFunctionSymbols: existingFunctionSymbols
        )
    }

    private func appendSyntheticDataCopyIfNeeded(
        name: InternedString,
        owner: SemanticSymbol,
        module: KIRModule,
        sema: SemaModule,
        existingFunctionSymbols: Set<SymbolID>,
        interner: StringInterner
    ) {
        guard owner.kind == .class || owner.kind == .enumClass || owner.kind == .object else {
            return
        }

        let receiverType = sema.types.make(.classType(ClassType(
            classSymbol: owner.id,
            args: [],
            nullability: .nonNull
        )))
        let parameterName = interner.intern("$self")
        let fqName = owner.fqName + [name]
        let parameterSymbol = sema.symbols.define(
            kind: .valueParameter,
            name: parameterName,
            fqName: fqName + [parameterName],
            declSite: owner.declSite,
            visibility: .private,
            flags: [.synthetic]
        )
        let parameter = KIRParameter(symbol: parameterSymbol, type: receiverType)
        let resultExpr = module.arena.appendExpr(.temporary(Int32(module.arena.expressions.count)))
        let body: [KIRInstruction] = [
            .constValue(result: resultExpr, value: .symbolRef(parameterSymbol)),
            .returnValue(resultExpr)
        ]
        let signature = FunctionSignature(
            parameterTypes: [receiverType],
            returnType: receiverType,
            isSuspend: false,
            valueParameterSymbols: [parameterSymbol],
            valueParameterHasDefaultValues: [false],
            valueParameterIsVararg: [false]
        )
        appendSyntheticFunctionIfNeeded(
            name: name,
            owner: owner,
            module: module,
            sema: sema,
            signature: signature,
            params: [parameter],
            body: body,
            existingFunctionSymbols: existingFunctionSymbols
        )
    }

    private func appendSyntheticFunctionIfNeeded(
        name: InternedString,
        owner: SemanticSymbol,
        module: KIRModule,
        sema: SemaModule,
        signature: FunctionSignature,
        params: [KIRParameter],
        body: [KIRInstruction],
        existingFunctionSymbols: Set<SymbolID>
    ) {
        let fqName = owner.fqName + [name]
        let nonSyntheticConflict = sema.symbols.lookupAll(fqName: fqName).contains { symbolID in
            guard let symbol = sema.symbols.symbol(symbolID) else {
                return false
            }
            return symbol.kind == .function && !symbol.flags.contains(.synthetic)
        }
        if nonSyntheticConflict {
            return
        }

        let functionSymbol = sema.symbols.define(
            kind: .function,
            name: name,
            fqName: fqName,
            declSite: owner.declSite,
            visibility: .public,
            flags: [.synthetic, .static]
        )
        if existingFunctionSymbols.contains(functionSymbol) {
            return
        }
        sema.symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: signature.receiverType,
                parameterTypes: signature.parameterTypes,
                returnType: signature.returnType,
                isSuspend: signature.isSuspend,
                valueParameterSymbols: params.map(\.symbol),
                valueParameterHasDefaultValues: params.map { _ in false },
                valueParameterIsVararg: params.map { _ in false },
                typeParameterSymbols: []
            ),
            for: functionSymbol
        )
        _ = module.arena.appendDecl(.function(
            KIRFunction(
                symbol: functionSymbol,
                name: name,
                params: params,
                returnType: signature.returnType,
                body: body,
                isSuspend: false,
                isInline: false
            )
        ))
    }
}

private struct InlineExpansion {
    let instructions: [KIRInstruction]
    let returnedExpr: KIRExprID?
}

private final class InlineLoweringPass: LoweringImpl {
    static let name = "InlineLowering"

    func run(module: KIRModule, ctx: KIRContext) throws {
        let inlineFunctionsBySymbol = Dictionary(uniqueKeysWithValues: module.arena.declarations.compactMap { decl -> (SymbolID, KIRFunction)? in
            guard case .function(let function) = decl, function.isInline else {
                return nil
            }
            return (function.symbol, function)
        })
        let inlineFunctionsByName = Dictionary(grouping: inlineFunctionsBySymbol.values, by: \.name)

        module.arena.transformFunctions { function in
            var updated = function
            var loweredBody: [KIRInstruction] = []
            loweredBody.reserveCapacity(function.body.count)
            var aliases: [KIRExprID: KIRExprID] = [:]

            for originalInstruction in function.body {
                let instruction = rewriteInstruction(originalInstruction, aliases: aliases)
                if let defined = definedResult(in: instruction) {
                    aliases.removeValue(forKey: defined)
                }

                guard case .call(let symbol, let callee, let arguments, let result, _) = instruction else {
                    loweredBody.append(instruction)
                    continue
                }

                let inlineTarget: KIRFunction?
                if let symbol, let target = inlineFunctionsBySymbol[symbol] {
                    inlineTarget = target
                } else if let byName = inlineFunctionsByName[callee], byName.count == 1 {
                    inlineTarget = byName[0]
                } else {
                    inlineTarget = nil
                }

                guard let inlineTarget, inlineTarget.symbol != function.symbol else {
                    loweredBody.append(instruction)
                    continue
                }
                let expansion = expandInlineCall(
                    inlineTarget: inlineTarget,
                    arguments: arguments,
                    module: module
                )
                guard let expansion else {
                    loweredBody.append(instruction)
                    continue
                }

                loweredBody.append(contentsOf: expansion.instructions)
                if let result {
                    if let returnedExpr = expansion.returnedExpr {
                        aliases[result] = resolveAlias(of: returnedExpr, aliases: aliases)
                    } else {
                        let unitExpr = module.arena.appendExpr(.unit)
                        aliases[result] = unitExpr
                    }
                }
            }

            updated.body = loweredBody
            if updated.body.isEmpty {
                updated.body = [.returnUnit]
            }
            return updated
        }
        module.recordLowering(Self.name)
    }

    private func expandInlineCall(
        inlineTarget: KIRFunction,
        arguments: [KIRExprID],
        module: KIRModule
    ) -> InlineExpansion? {
        guard arguments.count == inlineTarget.params.count else {
            return nil
        }

        let parameterValues = Dictionary(uniqueKeysWithValues: zip(inlineTarget.params.map(\.symbol), arguments))
        var localExprMap: [KIRExprID: KIRExprID] = [:]
        var lowered: [KIRInstruction] = []
        lowered.reserveCapacity(inlineTarget.body.count)
        var returnedExpr: KIRExprID?

        for instruction in inlineTarget.body {
            switch instruction {
            case .beginBlock, .endBlock:
                continue

            case .nop:
                lowered.append(.nop)

            case .returnUnit:
                returnedExpr = nil

            case .returnValue(let value):
                returnedExpr = resolveAlias(of: value, aliases: localExprMap)

            case .constValue(let result, let value):
                if case .symbolRef(let symbol) = value, let argument = parameterValues[symbol] {
                    localExprMap[result] = argument
                    continue
                }
                let loweredResult = cloneExpr(result, in: module.arena)
                localExprMap[result] = loweredResult
                lowered.append(.constValue(result: loweredResult, value: value))

            case .binary(let op, let lhs, let rhs, let result):
                let loweredResult = cloneExpr(result, in: module.arena)
                localExprMap[result] = loweredResult
                lowered.append(
                    .binary(
                        op: op,
                        lhs: resolveAlias(of: lhs, aliases: localExprMap),
                        rhs: resolveAlias(of: rhs, aliases: localExprMap),
                        result: loweredResult
                    )
                )

            case .call(let symbol, let callee, let args, let result, let outThrown):
                let loweredResult = result.map { expr -> KIRExprID in
                    let cloned = cloneExpr(expr, in: module.arena)
                    localExprMap[expr] = cloned
                    return cloned
                }
                lowered.append(
                    .call(
                        symbol: symbol,
                        callee: callee,
                        arguments: args.map { resolveAlias(of: $0, aliases: localExprMap) },
                        result: loweredResult,
                        outThrown: outThrown
                    )
                )
            }
        }

        return InlineExpansion(instructions: lowered, returnedExpr: returnedExpr)
    }

    private func rewriteInstruction(_ instruction: KIRInstruction, aliases: [KIRExprID: KIRExprID]) -> KIRInstruction {
        switch instruction {
        case .binary(let op, let lhs, let rhs, let result):
            return .binary(
                op: op,
                lhs: resolveAlias(of: lhs, aliases: aliases),
                rhs: resolveAlias(of: rhs, aliases: aliases),
                result: result
            )

        case .call(let symbol, let callee, let arguments, let result, let outThrown):
            return .call(
                symbol: symbol,
                callee: callee,
                arguments: arguments.map { resolveAlias(of: $0, aliases: aliases) },
                result: result,
                outThrown: outThrown
            )

        case .returnValue(let value):
            return .returnValue(resolveAlias(of: value, aliases: aliases))

        default:
            return instruction
        }
    }

    private func definedResult(in instruction: KIRInstruction) -> KIRExprID? {
        switch instruction {
        case .constValue(let result, _):
            return result
        case .binary(_, _, _, let result):
            return result
        case .call(_, _, _, let result, _):
            return result
        default:
            return nil
        }
    }

    private func resolveAlias(of expr: KIRExprID, aliases: [KIRExprID: KIRExprID]) -> KIRExprID {
        var current = expr
        var visited: Set<KIRExprID> = []
        while let next = aliases[current], visited.insert(current).inserted {
            if next == current {
                break
            }
            current = next
        }
        return current
    }

    private func cloneExpr(_ source: KIRExprID, in arena: KIRArena) -> KIRExprID {
        let fallback = KIRExprKind.temporary(Int32(arena.expressions.count))
        return arena.appendExpr(arena.expr(source) ?? fallback)
    }
}

private final class LambdaClosureConversionPass: LoweringImpl {
    static let name = "LambdaClosureConversion"

    func run(module: KIRModule, ctx: KIRContext) throws {
        let markerCallee = ctx.interner.intern("<lambda>")
        let loweredCallee = ctx.interner.intern("kk_lambda_invoke")

        module.arena.transformFunctions { function in
            var updated = function
            updated.body = function.body.map { instruction in
                guard case .call(let symbol, let callee, let arguments, let result, let outThrown) = instruction,
                      callee == markerCallee else {
                    return instruction
                }
                return .call(
                    symbol: symbol,
                    callee: loweredCallee,
                    arguments: arguments,
                    result: result,
                    outThrown: outThrown
                )
            }
            return updated
        }
        module.recordLowering(Self.name)
    }
}

private final class CoroutineLoweringPass: LoweringImpl {
    static let name = "CoroutineLowering"

    func run(module: KIRModule, ctx: KIRContext) throws {
        let suspendFunctions = module.arena.declarations.compactMap { decl -> KIRFunction? in
            guard case .function(let function) = decl, function.isSuspend else {
                return nil
            }
            return function
        }
        guard !suspendFunctions.isEmpty else {
            module.recordLowering(Self.name)
            return
        }

        var existingFunctionNames: Set<InternedString> = Set(module.arena.declarations.compactMap { decl in
            guard case .function(let function) = decl else {
                return nil
            }
            return function.name
        })

        var nextSyntheticSymbol = nextAvailableSyntheticSymbol(module: module, sema: ctx.sema)
        var loweredBySymbol: [SymbolID: (name: InternedString, symbol: SymbolID)] = [:]
        var loweredByNameBuckets: [InternedString: [(name: InternedString, symbol: SymbolID)]] = [:]

        for suspendFunction in suspendFunctions {
            let rawLowered = ctx.interner.intern("kk_suspend_" + ctx.interner.resolve(suspendFunction.name))
            let loweredName = uniqueFunctionName(
                preferred: rawLowered,
                existingFunctionNames: &existingFunctionNames,
                interner: ctx.interner
            )
            let loweredSymbol = defineSyntheticCoroutineFunctionSymbol(
                original: suspendFunction,
                loweredName: loweredName,
                nextSyntheticSymbol: &nextSyntheticSymbol,
                sema: ctx.sema
            )
            let continuationType = ctx.sema?.types.nullableAnyType ?? suspendFunction.returnType
            let continuationParameterSymbol = defineSyntheticContinuationParameterSymbol(
                owner: loweredSymbol,
                loweredName: loweredName,
                nextSyntheticSymbol: &nextSyntheticSymbol,
                sema: ctx.sema,
                interner: ctx.interner
            )
            let loweredBody = lowerSuspendBodyToStateMachineSkeleton(
                originalBody: suspendFunction.body,
                continuationParameterSymbol: continuationParameterSymbol,
                loweredSymbol: loweredSymbol,
                module: module,
                interner: ctx.interner
            )
            let loweredFunction = KIRFunction(
                symbol: loweredSymbol,
                name: loweredName,
                params: suspendFunction.params + [
                    KIRParameter(symbol: continuationParameterSymbol, type: continuationType)
                ],
                returnType: continuationType,
                body: loweredBody,
                isSuspend: false,
                isInline: false
            )
            _ = module.arena.appendDecl(.function(loweredFunction))

            let lowered = (name: loweredName, symbol: loweredSymbol)
            loweredBySymbol[suspendFunction.symbol] = lowered
            loweredByNameBuckets[suspendFunction.name, default: []].append(lowered)
            updateLoweredFunctionSignatureIfPossible(
                loweredSymbol: loweredSymbol,
                continuationParameterSymbol: continuationParameterSymbol,
                originalSymbol: suspendFunction.symbol,
                continuationType: continuationType,
                sema: ctx.sema
            )
        }

        let loweredByUniqueName = loweredByNameBuckets.reduce(into: [InternedString: (name: InternedString, symbol: SymbolID)]()) { partial, entry in
            guard entry.value.count == 1, let value = entry.value.first else {
                return
            }
            partial[entry.key] = value
        }
        let continuationProvider = ctx.interner.intern("kk_coroutine_suspended")

        module.arena.transformFunctions { function in
            var updated = function
            var loweredBody: [KIRInstruction] = []
            loweredBody.reserveCapacity(function.body.count)
            for instruction in function.body {
                guard case .call(let symbol, let callee, let arguments, let result, let outThrown) = instruction else {
                    loweredBody.append(instruction)
                    continue
                }

                let loweredTarget: (name: InternedString, symbol: SymbolID)?
                if let symbol, let bySymbol = loweredBySymbol[symbol] {
                    loweredTarget = bySymbol
                } else if let byName = loweredByUniqueName[callee] {
                    loweredTarget = byName
                } else {
                    loweredTarget = nil
                }

                guard let loweredTarget else {
                    loweredBody.append(instruction)
                    continue
                }

                let continuationTemp = module.arena.appendExpr(.temporary(Int32(module.arena.expressions.count)))
                loweredBody.append(
                    .call(
                        symbol: nil,
                        callee: continuationProvider,
                        arguments: [],
                        result: continuationTemp,
                        outThrown: false
                    )
                )
                var loweredArguments = arguments
                loweredArguments.append(continuationTemp)
                loweredBody.append(
                    .call(
                        symbol: loweredTarget.symbol,
                        callee: loweredTarget.name,
                        arguments: loweredArguments,
                        result: result,
                        outThrown: outThrown
                    )
                )
            }
            updated.body = loweredBody
            return updated
        }
        module.recordLowering(Self.name)
    }

    private func nextAvailableSyntheticSymbol(module: KIRModule, sema: SemaModule?) -> Int32 {
        var maxRaw: Int32 = 0
        for decl in module.arena.declarations {
            switch decl {
            case .function(let function):
                maxRaw = max(maxRaw, function.symbol.rawValue + 1)
            case .global(let global):
                maxRaw = max(maxRaw, global.symbol.rawValue + 1)
            case .nominalType(let nominal):
                maxRaw = max(maxRaw, nominal.symbol.rawValue + 1)
            }
        }
        if let sema {
            maxRaw = max(maxRaw, Int32(sema.symbols.count))
        }
        return maxRaw
    }

    private func allocateSyntheticSymbol(_ nextSyntheticSymbol: inout Int32) -> SymbolID {
        let id = SymbolID(rawValue: nextSyntheticSymbol)
        nextSyntheticSymbol += 1
        return id
    }

    private func uniqueFunctionName(
        preferred: InternedString,
        existingFunctionNames: inout Set<InternedString>,
        interner: StringInterner
    ) -> InternedString {
        if existingFunctionNames.insert(preferred).inserted {
            return preferred
        }
        let base = interner.resolve(preferred)
        var suffix = 1
        while true {
            let candidate = interner.intern("\(base)$\(suffix)")
            if existingFunctionNames.insert(candidate).inserted {
                return candidate
            }
            suffix += 1
        }
    }

    private func defineSyntheticCoroutineFunctionSymbol(
        original: KIRFunction,
        loweredName: InternedString,
        nextSyntheticSymbol: inout Int32,
        sema: SemaModule?
    ) -> SymbolID {
        guard let sema, let originalSymbol = sema.symbols.symbol(original.symbol) else {
            return allocateSyntheticSymbol(&nextSyntheticSymbol)
        }
        let loweredFQName = Array(originalSymbol.fqName.dropLast()) + [loweredName]
        return sema.symbols.define(
            kind: .function,
            name: loweredName,
            fqName: loweredFQName,
            declSite: originalSymbol.declSite,
            visibility: originalSymbol.visibility,
            flags: [.synthetic, .static]
        )
    }

    private func defineSyntheticContinuationParameterSymbol(
        owner: SymbolID,
        loweredName: InternedString,
        nextSyntheticSymbol: inout Int32,
        sema: SemaModule?,
        interner: StringInterner
    ) -> SymbolID {
        guard let sema, let loweredSymbol = sema.symbols.symbol(owner) else {
            return allocateSyntheticSymbol(&nextSyntheticSymbol)
        }
        let parameterName = interner.intern("$continuation")
        return sema.symbols.define(
            kind: .valueParameter,
            name: parameterName,
            fqName: loweredSymbol.fqName + [parameterName],
            declSite: loweredSymbol.declSite,
            visibility: .private,
            flags: [.synthetic]
        )
    }

    private func updateLoweredFunctionSignatureIfPossible(
        loweredSymbol: SymbolID,
        continuationParameterSymbol: SymbolID,
        originalSymbol: SymbolID,
        continuationType: TypeID,
        sema: SemaModule?
    ) {
        guard let sema else {
            return
        }
        let originalSignature = sema.symbols.functionSignature(for: originalSymbol)
        let loweredParameterTypes = (originalSignature?.parameterTypes ?? []) + [continuationType]
        let loweredValueSymbols = (originalSignature?.valueParameterSymbols ?? []) + [continuationParameterSymbol]
        let loweredDefaults = (originalSignature?.valueParameterHasDefaultValues ?? []) + [false]
        let loweredVararg = (originalSignature?.valueParameterIsVararg ?? []) + [false]
        sema.symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: originalSignature?.receiverType,
                parameterTypes: loweredParameterTypes,
                returnType: continuationType,
                isSuspend: false,
                valueParameterSymbols: loweredValueSymbols,
                valueParameterHasDefaultValues: loweredDefaults,
                valueParameterIsVararg: loweredVararg,
                typeParameterSymbols: originalSignature?.typeParameterSymbols ?? []
            ),
            for: loweredSymbol
        )
    }

    private func lowerSuspendBodyToStateMachineSkeleton(
        originalBody: [KIRInstruction],
        continuationParameterSymbol: SymbolID,
        loweredSymbol: SymbolID,
        module: KIRModule,
        interner: StringInterner
    ) -> [KIRInstruction] {
        let enterCallee = interner.intern("kk_coroutine_state_enter")
        let exitCallee = interner.intern("kk_coroutine_state_exit")

        var lowered: [KIRInstruction] = []
        lowered.reserveCapacity(originalBody.count + 4)

        let continuationExpr = module.arena.appendExpr(.temporary(Int32(module.arena.expressions.count)))
        lowered.append(.constValue(result: continuationExpr, value: .symbolRef(continuationParameterSymbol)))

        let functionIDExpr = module.arena.appendExpr(.temporary(Int32(module.arena.expressions.count)))
        lowered.append(.constValue(result: functionIDExpr, value: .intLiteral(Int64(loweredSymbol.rawValue))))

        let resumeLabelExpr = module.arena.appendExpr(.temporary(Int32(module.arena.expressions.count)))
        lowered.append(
            .call(
                symbol: nil,
                callee: enterCallee,
                arguments: [continuationExpr, functionIDExpr],
                result: resumeLabelExpr,
                outThrown: false
            )
        )

        for instruction in originalBody {
            switch instruction {
            case .returnValue(let value):
                let exitValueExpr = module.arena.appendExpr(.temporary(Int32(module.arena.expressions.count)))
                lowered.append(
                    .call(
                        symbol: nil,
                        callee: exitCallee,
                        arguments: [continuationExpr, value],
                        result: exitValueExpr,
                        outThrown: false
                    )
                )
                lowered.append(.returnValue(exitValueExpr))

            case .returnUnit:
                let unitExpr = module.arena.appendExpr(.unit)
                let exitValueExpr = module.arena.appendExpr(.temporary(Int32(module.arena.expressions.count)))
                lowered.append(
                    .call(
                        symbol: nil,
                        callee: exitCallee,
                        arguments: [continuationExpr, unitExpr],
                        result: exitValueExpr,
                        outThrown: false
                    )
                )
                lowered.append(.returnValue(exitValueExpr))

            default:
                lowered.append(instruction)
            }
        }

        return lowered
    }
}

private final class ABILoweringPass: LoweringImpl {
    static let name = "ABILowering"

    func run(module: KIRModule, ctx: KIRContext) throws {
        let nonThrowingCallees: Set<InternedString> = [
            ctx.interner.intern("kk_op_add"),
            ctx.interner.intern("kk_op_sub"),
            ctx.interner.intern("kk_op_mul"),
            ctx.interner.intern("kk_op_div"),
            ctx.interner.intern("kk_op_eq"),
            ctx.interner.intern("kk_when_select"),
            ctx.interner.intern("kk_for_lowered"),
            ctx.interner.intern("iterator"),
            ctx.interner.intern("kk_property_access"),
            ctx.interner.intern("kk_lambda_invoke"),
            ctx.interner.intern("kk_coroutine_suspended"),
            ctx.interner.intern("kk_coroutine_state_enter"),
            ctx.interner.intern("kk_coroutine_state_exit")
        ]
        module.arena.transformFunctions { function in
            var updated = function
            updated.body = function.body.map { instruction in
                guard case .call(let symbol, let callee, let arguments, let result, _) = instruction else {
                    return instruction
                }
                return .call(
                    symbol: symbol,
                    callee: callee,
                    arguments: arguments,
                    result: result,
                    outThrown: !nonThrowingCallees.contains(callee)
                )
            }
            return updated
        }
        module.recordLowering(Self.name)
    }
}

public final class LoweringPhase: CompilerPhase {
    public static let name = "Lowerings"

    private let passes: [any LoweringImpl] = [
        NormalizeBlocksPass(),
        OperatorLoweringPass(),
        ForLoweringPass(),
        WhenLoweringPass(),
        PropertyLoweringPass(),
        DataEnumSealedSynthesisPass(),
        LambdaClosureConversionPass(),
        InlineLoweringPass(),
        CoroutineLoweringPass(),
        ABILoweringPass()
    ]

    public init() {}

    public func run(_ ctx: CompilationContext) throws {
        guard let module = ctx.kir else {
            throw CompilerPipelineError.invalidInput("KIR not available for lowering.")
        }
        let kirCtx = KIRContext(
            diagnostics: ctx.diagnostics,
            options: ctx.options,
            interner: ctx.interner,
            sema: ctx.sema
        )
        for pass in passes {
            try pass.run(module: module, ctx: kirCtx)
        }
    }
}

public final class CodegenPhase: CompilerPhase {
    public static let name = "Codegen"

    public init() {}

    public func run(_ ctx: CompilationContext) throws {
        guard let kir = ctx.kir else {
            throw CompilerPipelineError.invalidInput("KIR not available for codegen.")
        }

        let runtime = RuntimeLinkInfo(
            libraryPaths: ctx.options.libraryPaths,
            libraries: ctx.options.linkLibraries,
            extraObjects: []
        )
        let backend = LLVMBackend(
            target: ctx.options.target,
            optLevel: ctx.options.optLevel,
            debugInfo: ctx.options.debugInfo,
            diagnostics: ctx.diagnostics
        )

        do {
            switch ctx.options.emit {
            case .kirDump:
                let path = outputPath(base: ctx.options.outputPath, defaultExtension: "kir")
                let dump = kir.dump(interner: ctx.interner, symbols: ctx.sema?.symbols)
                try dump.write(to: URL(fileURLWithPath: path), atomically: true, encoding: .utf8)

            case .llvmIR:
                let path = outputPath(base: ctx.options.outputPath, defaultExtension: "ll")
                try backend.emitLLVMIR(module: kir, runtime: runtime, outputIRPath: path, interner: ctx.interner)
                ctx.generatedLLVMIRPath = path

            case .object, .executable:
                let path = outputPath(base: ctx.options.outputPath, defaultExtension: "o")
                try backend.emitObject(module: kir, runtime: runtime, outputObjectPath: path, interner: ctx.interner)
                ctx.generatedObjectPath = path

            case .library:
                try emitLibrary(module: kir, backend: backend, runtime: runtime, ctx: ctx)
            }
        } catch {
            throw CompilerPipelineError.outputUnavailable
        }
    }

    private func outputPath(base: String, defaultExtension: String) -> String {
        let fileURL = URL(fileURLWithPath: base)
        if fileURL.pathExtension.isEmpty {
            return fileURL.appendingPathExtension(defaultExtension).path
        }
        return base
    }

    private func emitLibrary(
        module: KIRModule,
        backend: LLVMBackend,
        runtime: RuntimeLinkInfo,
        ctx: CompilationContext
    ) throws {
        let fm = FileManager.default
        let outputDir = libraryOutputPath(base: ctx.options.outputPath)
        let objectsDir = outputDir + "/objects"
        let inlineDir = outputDir + "/inline-kir"

        if fm.fileExists(atPath: outputDir) {
            try fm.removeItem(atPath: outputDir)
        }
        try fm.createDirectory(atPath: outputDir, withIntermediateDirectories: true)
        try fm.createDirectory(atPath: objectsDir, withIntermediateDirectories: true)
        try fm.createDirectory(atPath: inlineDir, withIntermediateDirectories: true)

        let objectPath = objectsDir + "/\(ctx.options.moduleName)_0.o"
        try backend.emitObject(module: module, runtime: runtime, outputObjectPath: objectPath, interner: ctx.interner)
        ctx.generatedObjectPath = objectPath

        try emitInlineKIRArtifacts(module: module, outputDir: inlineDir, ctx: ctx)

        let manifestPath = outputDir + "/manifest.json"
        let metadataPath = outputDir + "/metadata.bin"

        let targetString = "\(ctx.options.target.arch)-\(ctx.options.target.vendor)-\(ctx.options.target.os)"
        let manifest = """
        {
          "formatVersion": 1,
          "moduleName": "\(ctx.options.moduleName)",
          "kotlinLanguageVersion": "2.3.10",
          "compilerVersion": "0.1.0",
          "target": "\(targetString)",
          "objects": ["objects/\(ctx.options.moduleName)_0.o"],
          "metadata": "metadata.bin",
          "inlineKIRDir": "inline-kir"
        }
        """
        try manifest.write(to: URL(fileURLWithPath: manifestPath), atomically: true, encoding: .utf8)

        let metadata = makeMetadata(ctx: ctx)
        try metadata.write(to: URL(fileURLWithPath: metadataPath), atomically: true, encoding: .utf8)
    }

    private func emitInlineKIRArtifacts(
        module: KIRModule,
        outputDir: String,
        ctx: CompilationContext
    ) throws {
        guard let sema = ctx.sema else {
            return
        }
        let mangler = NameMangler()
        for decl in module.arena.declarations {
            guard case .function(let function) = decl, function.isInline else {
                continue
            }
            guard let symbol = sema.symbols.symbol(function.symbol) else {
                continue
            }
            let signature = "F$arity\(function.params.count)"
            let mangled = mangler.mangle(moduleName: ctx.options.moduleName, symbol: symbol, signature: signature)
            let filePath = outputDir + "/\(mangled).kirbin"
            let bodyLines = function.body.map { instruction in
                switch instruction {
                case .nop:
                    return "nop"
                case .beginBlock:
                    return "beginBlock"
                case .endBlock:
                    return "endBlock"
                case .constValue(let result, let value):
                    return "const result=\(result.rawValue) value=\(value)"
                case .binary(let op, let lhs, let rhs, let result):
                    return "binary op=\(op) lhs=\(lhs.rawValue) rhs=\(rhs.rawValue) result=\(result.rawValue)"
                case .returnUnit:
                    return "returnUnit"
                case .returnValue:
                    return "returnValue"
                case .call(let symbol, let callee, let arguments, let result, let outThrown):
                    let args = arguments.map { String($0.rawValue) }.joined(separator: ",")
                    let symbolValue = symbol.map { String($0.rawValue) } ?? "_"
                    let resultValue = result.map { String($0.rawValue) } ?? "_"
                    return "call symbol=\(symbolValue) callee=\(callee.rawValue) args=[\(args)] result=\(resultValue) outThrown=\(outThrown)"
                }
            }.joined(separator: "\n")
            let content = """
            name=\(ctx.interner.resolve(function.name))
            params=\(function.params.count)
            suspend=\(function.isSuspend)
            body:
            \(bodyLines)
            """
            try content.write(to: URL(fileURLWithPath: filePath), atomically: true, encoding: .utf8)
        }
    }

    private func libraryOutputPath(base: String) -> String {
        if base.hasSuffix(".kklib") {
            return base
        }
        return base + ".kklib"
    }

    private func makeMetadata(ctx: CompilationContext) -> String {
        guard let sema = ctx.sema else {
            return "symbols=0\n"
        }
        let exported = sema.symbols.allSymbols()
            .filter { $0.visibility == Visibility.public && $0.kind != .package }
            .sorted { lhs, rhs in
                if lhs.fqName.count != rhs.fqName.count {
                    return lhs.fqName.count < rhs.fqName.count
                }
                let lhsRaw = lhs.fqName.map { $0.rawValue }
                let rhsRaw = rhs.fqName.map { $0.rawValue }
                if lhsRaw != rhsRaw {
                    return lhsRaw.lexicographicallyPrecedes(rhsRaw)
                }
                return lhs.id.rawValue < rhs.id.rawValue
            }

        var lines: [String] = ["symbols=\(exported.count)"]
        let mangler = NameMangler()
        for symbol in exported {
            let mangled = mangler.mangle(moduleName: ctx.options.moduleName, symbol: symbol, signature: "_")
            let fqName = symbol.fqName.map { ctx.interner.resolve($0) }.joined(separator: ".")
            var fields = [
                "\(symbol.kind)",
                mangled,
                "fq=\(fqName)"
            ]
            if symbol.kind == .function, let signature = sema.symbols.functionSignature(for: symbol.id) {
                fields.append("arity=\(signature.parameterTypes.count)")
                fields.append("suspend=\(signature.isSuspend ? 1 : 0)")
            }
            lines.append(fields.joined(separator: " "))
        }
        return lines.joined(separator: "\n") + "\n"
    }
}

public final class LinkPhase: CompilerPhase {
    public static let name = "Link"

    public init() {}

    public func run(_ ctx: CompilationContext) throws {
        if ctx.options.emit != .executable {
            return
        }

        guard let objectPath = ctx.generatedObjectPath,
              FileManager.default.fileExists(atPath: objectPath) else {
            throw CompilerPipelineError.outputUnavailable
        }

        guard let kir = ctx.kir else {
            throw CompilerPipelineError.invalidInput("KIR not available during link.")
        }

        guard let entrySymbol = resolveEntrySymbol(kir: kir, interner: ctx.interner) else {
            ctx.diagnostics.error(
                "KSWIFTK-LINK-0002",
                "No entry point 'main' function found for executable emission.",
                range: nil
            )
            throw CompilerPipelineError.outputUnavailable
        }

        let wrapperSource = """
        #include <stdint.h>
        #include <stddef.h>
        extern intptr_t \(entrySymbol)(intptr_t* outThrown);
        int main(void) { return (int)\(entrySymbol)(NULL); }
        """
        let wrapperURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "_entry.c")
        defer { try? FileManager.default.removeItem(at: wrapperURL) }

        do {
            try wrapperSource.write(to: wrapperURL, atomically: true, encoding: .utf8)

            var args: [String] = [objectPath, wrapperURL.path, "-o", ctx.options.outputPath]
            args.append(contentsOf: clangTargetArgs(ctx.options.target))
            for path in ctx.options.libraryPaths {
                args.append("-L\(path)")
            }
            for library in ctx.options.linkLibraries {
                args.append("-l\(library)")
            }
            _ = try CommandRunner.run(executable: "/usr/bin/clang", arguments: args)
        } catch let error as CommandRunnerError {
            let message: String
            switch error {
            case .launchFailed(let reason):
                message = "Failed to launch linker: \(reason)"
            case .nonZeroExit(let result):
                let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                message = stderr.isEmpty ? "Linker failed with exit code \(result.exitCode)." : "Linker failed: \(stderr)"
            }
            ctx.diagnostics.error("KSWIFTK-LINK-0001", message, range: nil)
            throw CompilerPipelineError.outputUnavailable
        } catch {
            ctx.diagnostics.error("KSWIFTK-LINK-0001", "Link step failed: \(error)", range: nil)
            throw CompilerPipelineError.outputUnavailable
        }
    }

    private func resolveEntrySymbol(kir: KIRModule, interner: StringInterner) -> String? {
        for decl in kir.arena.declarations {
            guard case .function(let function) = decl else {
                continue
            }
            if interner.resolve(function.name) == "main" {
                return LLVMBackend.cFunctionSymbol(for: function, interner: interner)
            }
        }
        return nil
    }

    private func clangTargetArgs(_ target: TargetTriple) -> [String] {
        var triple = "\(target.arch)-\(target.vendor)-\(target.os)"
        if let version = target.osVersion, !version.isEmpty {
            triple += version
        }
        return ["-target", triple]
    }
}

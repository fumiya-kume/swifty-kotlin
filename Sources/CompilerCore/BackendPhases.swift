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

        for file in ast.files.sorted(by: { $0.fileID.rawValue < $1.fileID.rawValue }) {
            let packageSymbol = definePackageSymbol(for: file, symbols: symbols, interner: ctx.interner)
            let packageScope = PackageScope(parent: rootScope, symbols: symbols)
            packageScope.insert(packageSymbol)
            fileScopes[file.fileID.rawValue] = FileScope(parent: packageScope, symbols: symbols)
        }

        // Pass A: collect declaration headers and signatures.
        for file in ast.files.sorted(by: { $0.fileID.rawValue < $1.fileID.rawValue }) {
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
                    diagnostics: ctx.diagnostics
                )
            }
        }

        // Pass B: lightweight body checks.
        for file in ast.files.sorted(by: { $0.fileID.rawValue < $1.fileID.rawValue }) {
            for declID in file.topLevelDecls {
                analyzeBody(
                    declID: declID,
                    ast: ast,
                    symbols: symbols,
                    types: types,
                    bindings: bindings,
                    diagnostics: ctx.diagnostics
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
        diagnostics: DiagnosticEngine
    ) {
        guard let decl = ast.arena.decl(declID) else { return }
        let package = file.packageFQName
        let anyType = types.anyType
        let unitType = types.unitType

        let declaration: (kind: SymbolKind, name: InternedString, range: SourceRange?, visibility: Visibility, flags: SymbolFlags)?
        switch decl {
        case .classDecl(let classDecl):
            declaration = (
                kind: .class,
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
            declaration = (
                kind: .property,
                name: propertyDecl.name,
                range: propertyDecl.range,
                visibility: visibility(from: propertyDecl.modifiers),
                flags: flags(from: propertyDecl.modifiers)
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
        if symbols.lookup(fqName: fqName) != nil {
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
        case .classDecl:
            _ = types.make(.classType(ClassType(classSymbol: symbol, args: [], nullability: .nonNull)))

        case .objectDecl:
            _ = types.make(.classType(ClassType(classSymbol: symbol, args: [], nullability: .nonNull)))

        case .funDecl(let funDecl):
            var paramTypes: [TypeID] = []
            var paramSymbols: [SymbolID] = []
            for valueParam in funDecl.valueParams {
                let paramFQName = fqName + [valueParam.name]
                let paramSymbol = symbols.define(
                    kind: .valueParameter,
                    name: valueParam.name,
                    fqName: paramFQName,
                    declSite: funDecl.range,
                    visibility: .private,
                    flags: []
                )
                paramTypes.append(anyType)
                paramSymbols.append(paramSymbol)
            }
            let returnType: TypeID
            switch funDecl.body {
            case .unit:
                returnType = unitType
            case .block, .expr:
                returnType = anyType
            }
            symbols.setFunctionSignature(
                FunctionSignature(
                    parameterTypes: paramTypes,
                    returnType: returnType,
                    isSuspend: funDecl.isSuspend,
                    valueParameterSymbols: paramSymbols
                ),
                for: symbol
            )

        case .propertyDecl:
            _ = types.make(.any(.nullable))

        case .typeAliasDecl, .enumEntry:
            break
        }
    }

    private func analyzeBody(
        declID: DeclID,
        ast: ASTModule,
        symbols: SymbolTable,
        types: TypeSystem,
        bindings: BindingTable,
        diagnostics: DiagnosticEngine
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

        case .propertyDecl:
            if let symbol = bindings.declSymbols[declID] {
                let expr = ExprID(rawValue: declID.rawValue)
                bindings.bindIdentifier(expr, symbol: symbol)
                bindings.bindExprType(expr, type: types.anyType)
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
        return value
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
        let semaCtx = SemaContext(
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

        for file in ast.files {
            for declID in file.topLevelDecls {
                guard let decl = ast.arena.decl(declID),
                      let declSymbol = sema.bindings.declSymbols[declID] else {
                    continue
                }
                guard case .funDecl(let function) = decl else {
                    continue
                }
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

                let bodyType: TypeID
                switch function.body {
                case .unit:
                    bodyType = sema.types.unitType

                case .expr(let exprID, _):
                    bodyType = inferExpr(
                        exprID,
                        ast: ast,
                        sema: sema,
                        semaCtx: semaCtx,
                        locals: &locals,
                        resolver: resolver,
                        dataFlow: dataFlow
                    )

                case .block(let exprIDs, _):
                    var last = sema.types.unitType
                    for exprID in exprIDs {
                        last = inferExpr(
                            exprID,
                            ast: ast,
                            sema: sema,
                            semaCtx: semaCtx,
                            locals: &locals,
                            resolver: resolver,
                            dataFlow: dataFlow
                        )
                    }
                    bodyType = last
                }

                let solution = solver.solve(
                    vars: [],
                    constraints: [
                        Constraint(
                            kind: .subtype,
                            left: bodyType,
                            right: signature.returnType,
                            blameRange: function.range
                        )
                    ],
                    typeSystem: sema.types
                )
                if !solution.isSuccess, let failure = solution.failure {
                    ctx.diagnostics.emit(failure)
                }
            }
        }
    }

    private func inferExpr(
        _ id: ExprID,
        ast: ASTModule,
        sema: SemaModule,
        semaCtx: SemaContext,
        locals: inout [InternedString: (type: TypeID, symbol: SymbolID)],
        resolver: OverloadResolver,
        dataFlow: DataFlowAnalyzer
    ) -> TypeID {
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
            if let local = locals[name] {
                sema.bindings.bindIdentifier(id, symbol: local.symbol)
                sema.bindings.bindExprType(id, type: local.type)
                return local.type
            }
            let candidates = sema.symbols.allSymbols().filter { $0.name == name }
            if let first = candidates.first {
                sema.bindings.bindIdentifier(id, symbol: first.id)
            }
            let resolvedType = candidates.first.flatMap { sema.symbols.functionSignature(for: $0.id)?.returnType } ?? sema.types.anyType
            sema.bindings.bindExprType(id, type: resolvedType)
            return resolvedType

        case .binary(let op, let lhsID, let rhsID, _):
            let lhs = inferExpr(lhsID, ast: ast, sema: sema, semaCtx: semaCtx, locals: &locals, resolver: resolver, dataFlow: dataFlow)
            let rhs = inferExpr(rhsID, ast: ast, sema: sema, semaCtx: semaCtx, locals: &locals, resolver: resolver, dataFlow: dataFlow)
            let type: TypeID
            switch op {
            case .add:
                if lhs == stringType || rhs == stringType {
                    type = stringType
                } else {
                    type = intType
                }
            case .subtract, .multiply, .divide:
                type = intType
            case .equal:
                type = boolType
            }
            sema.bindings.bindExprType(id, type: type)
            return type

        case .call(let calleeID, let argIDs, let range):
            let argTypes = argIDs.map { argID in
                inferExpr(argID, ast: ast, sema: sema, semaCtx: semaCtx, locals: &locals, resolver: resolver, dataFlow: dataFlow)
            }

            let calleeExpr = ast.arena.expr(calleeID)
            let calleeName: InternedString?
            if case .nameRef(let name, _) = calleeExpr {
                calleeName = name
            } else {
                calleeName = nil
            }

            let candidates = sema.symbols.allSymbols().filter { symbol in
                guard symbol.kind == .function || symbol.kind == .constructor else {
                    return false
                }
                guard let calleeName else {
                    return false
                }
                return symbol.name == calleeName
            }.map(\.id)

            if candidates.isEmpty {
                sema.bindings.bindExprType(id, type: sema.types.errorType)
                return sema.types.errorType
            }

            let args = argTypes.map { CallArg(type: $0) }
            let resolved = resolver.resolveCall(
                candidates: candidates,
                call: CallExpr(range: range, calleeName: calleeName ?? InternedString(rawValue: invalidID), args: args),
                expectedType: nil,
                ctx: semaCtx
            )
            if let diagnostic = resolved.diagnostic {
                semaCtx.diagnostics.emit(diagnostic)
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
                    substitutedTypeArguments: [],
                    parameterMapping: resolved.parameterMapping
                )
            )
            let returnType = sema.symbols.functionSignature(for: chosen)?.returnType ?? sema.types.anyType
            sema.bindings.bindExprType(id, type: returnType)
            return returnType

        case .whenExpr(let subjectID, let branches, let elseExpr, let range):
            let subjectType = inferExpr(subjectID, ast: ast, sema: sema, semaCtx: semaCtx, locals: &locals, resolver: resolver, dataFlow: dataFlow)
            var branchTypes: [TypeID] = []
            var covered: Set<InternedString> = []
            for branch in branches {
                if let cond = branch.condition {
                    let condType = inferExpr(cond, ast: ast, sema: sema, semaCtx: semaCtx, locals: &locals, resolver: resolver, dataFlow: dataFlow)
                    if condType == boolType, let condExpr = ast.arena.expr(cond) {
                        switch condExpr {
                        case .boolLiteral(true, _):
                            covered.insert(InternedString(rawValue: 1))
                        case .boolLiteral(false, _):
                            covered.insert(InternedString(rawValue: 2))
                        default:
                            break
                        }
                    }
                }
                branchTypes.append(
                    inferExpr(branch.body, ast: ast, sema: sema, semaCtx: semaCtx, locals: &locals, resolver: resolver, dataFlow: dataFlow)
                )
            }

            if let elseExpr {
                branchTypes.append(
                    inferExpr(elseExpr, ast: ast, sema: sema, semaCtx: semaCtx, locals: &locals, resolver: resolver, dataFlow: dataFlow)
                )
            }

            let summary = WhenBranchSummary(coveredSymbols: covered, hasElse: elseExpr != nil)
            if !dataFlow.isWhenExhaustive(subjectType: subjectType, branches: summary, sema: sema) {
                semaCtx.diagnostics.error(
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

        for file in ast.files.sorted(by: { $0.fileID.rawValue < $1.fileID.rawValue }) {
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
            let argIDs = args.map { arg in
                lowerExpr(arg, ast: ast, sema: sema, arena: arena, interner: interner, instructions: &instructions)
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
        let marker = "__for_expr__"
        let lowered = "kk_for_lowered"
        module.arena.transformFunctions { function in
            var updated = function
            updated.body = function.body.map { instruction in
                guard case .call(let symbol, let callee, let arguments, let result, let outThrown) = instruction else {
                    return instruction
                }
                if ctx.interner.resolve(callee) == marker {
                    return .call(
                        symbol: symbol,
                        callee: ctx.interner.intern(lowered),
                        arguments: arguments,
                        result: result,
                        outThrown: outThrown
                    )
                }
                return instruction
            }
            return updated
        }
        module.recordLowering(Self.name)
    }
}

private final class WhenLoweringPass: LoweringImpl {
    static let name = "WhenLowering"
    func run(module: KIRModule, ctx: KIRContext) throws {
        module.arena.transformFunctions { function in
            var updated = function
            updated.body = function.body.map { instruction in
                guard case .call(let symbol, let callee, let arguments, let result, let outThrown) = instruction else {
                    return instruction
                }
                if ctx.interner.resolve(callee) == "__when_expr__" {
                    return .call(
                        symbol: symbol,
                        callee: ctx.interner.intern("kk_when_select"),
                        arguments: arguments,
                        result: result,
                        outThrown: outThrown
                    )
                }
                return instruction
            }
            return updated
        }
        module.recordLowering(Self.name)
    }
}

private final class PropertyLoweringPass: LoweringImpl {
    static let name = "PropertyLowering"
    func run(module: KIRModule, ctx: KIRContext) throws {
        module.arena.transformFunctions { function in
            var updated = function
            updated.body = function.body.map { instruction in
                guard case .call(let symbol, let callee, let arguments, let result, let outThrown) = instruction else {
                    return instruction
                }
                if ctx.interner.resolve(callee) == "get" || ctx.interner.resolve(callee) == "set" {
                    return .call(
                        symbol: symbol,
                        callee: ctx.interner.intern("kk_property_access"),
                        arguments: arguments,
                        result: result,
                        outThrown: outThrown
                    )
                }
                return instruction
            }
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
        module.recordLowering(Self.name)
    }
}

private final class LambdaClosureConversionPass: LoweringImpl {
    static let name = "LambdaClosureConversion"
    func run(module: KIRModule, ctx: KIRContext) throws {
        module.arena.transformFunctions { function in
            var updated = function
            updated.body = function.body.map { instruction in
                guard case .call(let symbol, let callee, let arguments, let result, let outThrown) = instruction else {
                    return instruction
                }
                if ctx.interner.resolve(callee) == "<lambda>" {
                    return .call(
                        symbol: symbol,
                        callee: ctx.interner.intern("kk_lambda_invoke"),
                        arguments: arguments,
                        result: result,
                        outThrown: outThrown
                    )
                }
                return instruction
            }
            return updated
        }
        module.recordLowering(Self.name)
    }
}

private final class InlineLoweringPass: LoweringImpl {
    static let name = "InlineLowering"
    func run(module: KIRModule, ctx: KIRContext) throws {
        let inlineNames: Set<InternedString> = Set(module.arena.declarations.compactMap { decl in
            guard case .function(let function) = decl, function.isInline else {
                return nil
            }
            return function.name
        })
        module.arena.transformFunctions { function in
            var updated = function
            updated.body = function.body.map { instruction in
                guard case .call(let symbol, let callee, let arguments, let result, let outThrown) = instruction else {
                    return instruction
                }
                if inlineNames.contains(callee) {
                    let renamed = ctx.interner.intern("inlined_" + ctx.interner.resolve(callee))
                    return .call(symbol: symbol, callee: renamed, arguments: arguments, result: result, outThrown: outThrown)
                }
                return instruction
            }
            return updated
        }
        module.recordLowering(Self.name)
    }
}

private final class CoroutineLoweringPass: LoweringImpl {
    static let name = "CoroutineLowering"
    func run(module: KIRModule, ctx: KIRContext) throws {
        let suspendNames: Set<InternedString> = Set(module.arena.declarations.compactMap { decl in
            guard case .function(let function) = decl, function.isSuspend else {
                return nil
            }
            return function.name
        })
        module.arena.transformFunctions { function in
            var updated = function
            updated.body = function.body.map { instruction in
                guard case .call(let symbol, let callee, let arguments, let result, let outThrown) = instruction else {
                    return instruction
                }
                if suspendNames.contains(callee) {
                    let renamed = ctx.interner.intern("kk_suspend_" + ctx.interner.resolve(callee))
                    return .call(symbol: symbol, callee: renamed, arguments: arguments, result: result, outThrown: outThrown)
                }
                return instruction
            }
            return updated
        }
        module.recordLowering(Self.name)
    }
}

private final class ABILoweringPass: LoweringImpl {
    static let name = "ABILowering"
    func run(module: KIRModule, ctx: KIRContext) throws {
        module.arena.transformFunctions { function in
            var updated = function
            updated.body = function.body.map { instruction in
                guard case .call(let symbol, let callee, let arguments, let result, _) = instruction else {
                    return instruction
                }
                return .call(symbol: symbol, callee: callee, arguments: arguments, result: result, outThrown: true)
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
        let kirCtx = KIRContext(diagnostics: ctx.diagnostics, options: ctx.options, interner: ctx.interner)
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

            case .object:
                let path = outputPath(base: ctx.options.outputPath, defaultExtension: "o")
                try backend.emitObject(module: kir, runtime: runtime, outputObjectPath: path, interner: ctx.interner)
                ctx.generatedObjectPath = path

            case .executable:
                let objectPath = outputPath(base: ctx.options.outputPath, defaultExtension: "o")
                try backend.emitObject(module: kir, runtime: runtime, outputObjectPath: objectPath, interner: ctx.interner)
                ctx.generatedObjectPath = objectPath

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
            .filter { $0.visibility == Visibility.public }
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
            lines.append("\(symbol.kind) \(mangled)")
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
        extern intptr_t \(entrySymbol)(void);
        int main(void) { return (int)\(entrySymbol)(); }
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
            switch error {
            case .launchFailed(let reason):
                ctx.diagnostics.error(
                    "KSWIFTK-LINK-0001",
                    "Failed to launch linker: \(reason)",
                    range: nil
                )
            case .nonZeroExit(let result):
                let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                if stderr.isEmpty {
                    ctx.diagnostics.error(
                        "KSWIFTK-LINK-0001",
                        "Linker failed with exit code \(result.exitCode).",
                        range: nil
                    )
                } else {
                    ctx.diagnostics.error(
                        "KSWIFTK-LINK-0001",
                        "Linker failed: \(stderr)",
                        range: nil
                    )
                }
            }
            throw CompilerPipelineError.outputUnavailable
        } catch {
            ctx.diagnostics.error(
                "KSWIFTK-LINK-0001",
                "Link step failed: \(error)",
                range: nil
            )
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

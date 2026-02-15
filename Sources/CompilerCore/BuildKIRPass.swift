import Foundation

public final class BuildKIRPhase: CompilerPhase {
    public static let name = "BuildKIR"

    public init() {}

    public func run(_ ctx: CompilationContext) throws {
        guard let ast = ctx.ast, let sema = ctx.sema else {
            throw CompilerPipelineError.invalidInput("Sema phase did not run.")
        }

        let arena = KIRArena()
        var files: [KIRFile] = []
        let propertyConstantInitializers = collectPropertyConstantInitializers(ast: ast, sema: sema)

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
                        var terminatedByReturn = false
                        for exprID in exprIDs {
                            if let expr = ast.arena.expr(exprID),
                               case .returnExpr(let value, _) = expr {
                                if let value {
                                    let lowered = lowerExpr(
                                        value,
                                        ast: ast,
                                        sema: sema,
                                        arena: arena,
                                        interner: ctx.interner,
                                        propertyConstantInitializers: propertyConstantInitializers,
                                        instructions: &body
                                    )
                                    body.append(.returnValue(lowered))
                                } else {
                                    body.append(.returnUnit)
                                }
                                terminatedByReturn = true
                                break
                            }
                            lastValue = lowerExpr(
                                exprID,
                                ast: ast,
                                sema: sema,
                                arena: arena,
                                interner: ctx.interner,
                                propertyConstantInitializers: propertyConstantInitializers,
                                instructions: &body
                            )
                        }
                        if !terminatedByReturn {
                            if let lastValue {
                                body.append(.returnValue(lastValue))
                            } else {
                                body.append(.returnUnit)
                            }
                        }
                    case .expr(let exprID, _):
                        let value = lowerExpr(
                            exprID,
                            ast: ast,
                            sema: sema,
                            arena: arena,
                            interner: ctx.interner,
                            propertyConstantInitializers: propertyConstantInitializers,
                            instructions: &body
                        )
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

                case .enumEntryDecl:
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
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        guard let expr = ast.arena.expr(exprID) else {
            let temp = arena.appendExpr(.temporary(Int32(arena.expressions.count)))
            instructions.append(.constValue(result: temp, value: .unit))
            return temp
        }
        let stringType = sema.types.make(.primitive(.string, .nonNull))

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
            if interner.resolve(name) == "null" {
                let id = arena.appendExpr(.unit)
                instructions.append(.constValue(result: id, value: .unit))
                return id
            }
            if let symbol = sema.bindings.identifierSymbols[exprID] {
                if let constant = propertyConstantInitializers[symbol] {
                    let id = arena.appendExpr(constant)
                    instructions.append(.constValue(result: id, value: constant))
                    return id
                }
                let id = arena.appendExpr(.symbolRef(symbol))
                instructions.append(.constValue(result: id, value: .symbolRef(symbol)))
                return id
            }
            let id = arena.appendExpr(.temporary(Int32(arena.expressions.count)))
            instructions.append(.call(symbol: nil, callee: name, arguments: [], result: id, canThrow: false))
            return id

        case .returnExpr(let value, _):
            if let value {
                return lowerExpr(
                    value,
                    ast: ast,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    propertyConstantInitializers: propertyConstantInitializers,
                    instructions: &instructions
                )
            }
            let unit = arena.appendExpr(.unit)
            instructions.append(.constValue(result: unit, value: .unit))
            return unit

        case .ifExpr(let condition, let thenExpr, let elseExpr, _):
            let conditionID = lowerExpr(
                condition,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            let thenID = lowerExpr(
                thenExpr,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            let elseID: KIRExprID
            if let elseExpr {
                elseID = lowerExpr(
                    elseExpr,
                    ast: ast,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    propertyConstantInitializers: propertyConstantInitializers,
                    instructions: &instructions
                )
            } else {
                elseID = arena.appendExpr(.unit)
                instructions.append(.constValue(result: elseID, value: .unit))
            }
            let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)))
            instructions.append(
                .call(
                    symbol: nil,
                    callee: interner.intern("kk_when_select"),
                    arguments: [conditionID, thenID, elseID],
                    result: result,
                    canThrow: false
                )
            )
            return result

        case .tryExpr(let bodyExpr, _, _, _):
            return lowerExpr(
                bodyExpr,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )

        case .binary(let op, let lhs, let rhs, _):
            let lhsID = lowerExpr(
                lhs,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            let rhsID = lowerExpr(
                rhs,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)))
            if case .add = op, sema.bindings.exprTypes[exprID] == stringType {
                instructions.append(
                    .call(
                        symbol: nil,
                        callee: interner.intern("kk_string_concat"),
                        arguments: [lhsID, rhsID],
                        result: result,
                        canThrow: false
                    )
                )
                return result
            }
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
                calleeName = sema.symbols.allSymbols().first?.name ?? InternedString()
            }
            let argIDs = args.map { argument in
                lowerExpr(
                    argument.expr,
                    ast: ast,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    propertyConstantInitializers: propertyConstantInitializers,
                    instructions: &instructions
                )
            }
            let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)))
            let chosen = sema.bindings.callBindings[exprID]?.chosenCallee
            instructions.append(.call(symbol: chosen, callee: calleeName, arguments: argIDs, result: result, canThrow: false))
            return result

        case .whenExpr(let subject, let branches, let elseExpr, _):
            let subjectID = lowerExpr(
                subject,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            let fallbackID: KIRExprID
            if let elseExpr {
                fallbackID = lowerExpr(
                    elseExpr,
                    ast: ast,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    propertyConstantInitializers: propertyConstantInitializers,
                    instructions: &instructions
                )
            } else {
                fallbackID = arena.appendExpr(.unit)
                instructions.append(.constValue(result: fallbackID, value: .unit))
            }

            var selectedID = fallbackID
            for branch in branches.reversed() {
                let bodyID = lowerExpr(
                    branch.body,
                    ast: ast,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    propertyConstantInitializers: propertyConstantInitializers,
                    instructions: &instructions
                )
                guard let conditionExprID = branch.condition else {
                    selectedID = bodyID
                    continue
                }

                let conditionValueID = lowerExpr(
                    conditionExprID,
                    ast: ast,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    propertyConstantInitializers: propertyConstantInitializers,
                    instructions: &instructions
                )

                let matchesID = arena.appendExpr(.temporary(Int32(arena.expressions.count)))
                instructions.append(.binary(
                    op: .equal,
                    lhs: subjectID,
                    rhs: conditionValueID,
                    result: matchesID
                ))

                let nextSelectedID = arena.appendExpr(.temporary(Int32(arena.expressions.count)))
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_when_select"),
                    arguments: [matchesID, bodyID, selectedID],
                    result: nextSelectedID,
                    canThrow: false
                ))
                selectedID = nextSelectedID
            }
            return selectedID
        }
    }

    private func collectPropertyConstantInitializers(
        ast: ASTModule,
        sema: SemaModule
    ) -> [SymbolID: KIRExprKind] {
        var mapping: [SymbolID: KIRExprKind] = [:]
        for file in ast.sortedFiles {
            for declID in file.topLevelDecls {
                guard let decl = ast.arena.decl(declID),
                      case .propertyDecl(let property) = decl,
                      let symbol = sema.bindings.declSymbols[declID],
                      let constant = literalConstantExpr(property: property, ast: ast) else {
                    continue
                }
                mapping[symbol] = constant
                if let propertySymbol = sema.symbols.symbol(symbol) {
                    let related = sema.symbols.lookupAll(fqName: propertySymbol.fqName)
                    for relatedID in related {
                        guard let relatedSymbol = sema.symbols.symbol(relatedID) else {
                            continue
                        }
                        if relatedSymbol.kind == .property || relatedSymbol.kind == .field {
                            mapping[relatedID] = constant
                        }
                    }
                }
            }
        }
        return mapping
    }

    private func literalConstantExpr(property: PropertyDecl, ast: ASTModule) -> KIRExprKind? {
        if let initializer = property.initializer,
           let literal = literalConstantExpr(initializer, ast: ast) {
            return literal
        }
        if let getter = property.getter {
            return literalConstantExpr(getterBody: getter.body, ast: ast)
        }
        return nil
    }

    private func literalConstantExpr(getterBody: FunctionBody, ast: ASTModule) -> KIRExprKind? {
        switch getterBody {
        case .expr(let exprID, _):
            return literalConstantExpr(exprID, ast: ast)
        case .block(let exprIDs, _):
            guard let lastExprID = exprIDs.last,
                  let lastExpr = ast.arena.expr(lastExprID) else {
                return nil
            }
            if case .returnExpr(let valueExprID, _) = lastExpr,
               let valueExprID {
                return literalConstantExpr(valueExprID, ast: ast)
            }
            return literalConstantExpr(lastExprID, ast: ast)
        case .unit:
            return nil
        }
    }

    private func literalConstantExpr(_ exprID: ExprID, ast: ASTModule) -> KIRExprKind? {
        guard let expr = ast.arena.expr(exprID) else {
            return nil
        }
        switch expr {
        case .intLiteral(let value, _):
            return .intLiteral(value)
        case .boolLiteral(let value, _):
            return .boolLiteral(value)
        case .stringLiteral(let value, _):
            return .stringLiteral(value)
        default:
            return nil
        }
    }
}

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

        case .returnExpr(let value, _):
            if let value {
                return lowerExpr(
                    value,
                    ast: ast,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    instructions: &instructions
                )
            }
            let unit = arena.appendExpr(.unit)
            instructions.append(.constValue(result: unit, value: .unit))
            return unit

        case .ifExpr(let condition, let thenExpr, let elseExpr, _):
            let conditionID = lowerExpr(condition, ast: ast, sema: sema, arena: arena, interner: interner, instructions: &instructions)
            let thenID = lowerExpr(thenExpr, ast: ast, sema: sema, arena: arena, interner: interner, instructions: &instructions)
            let elseID: KIRExprID
            if let elseExpr {
                elseID = lowerExpr(elseExpr, ast: ast, sema: sema, arena: arena, interner: interner, instructions: &instructions)
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
                    outThrown: false
                )
            )
            return result

        case .tryExpr(let bodyExpr, _, _, _):
            return lowerExpr(bodyExpr, ast: ast, sema: sema, arena: arena, interner: interner, instructions: &instructions)

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

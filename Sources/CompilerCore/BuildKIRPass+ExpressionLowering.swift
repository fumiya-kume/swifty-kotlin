import Foundation

// Internal visibility is required for cross-file extension decomposition
extension BuildKIRPhase {
    func lowerExpr(
        _ exprID: ExprID,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let boundType = sema.bindings.exprTypes[exprID]
        let intType = sema.types.make(.primitive(.int, .nonNull))
        let boolType = sema.types.make(.primitive(.boolean, .nonNull))
        guard let expr = ast.arena.expr(exprID) else {
            let temp = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: sema.types.errorType)
            instructions.append(.constValue(result: temp, value: .unit))
            return temp
        }
        let stringType = sema.types.make(.primitive(.string, .nonNull))

        switch expr {
        case .intLiteral(let value, _):
            let id = arena.appendExpr(.intLiteral(value), type: boundType ?? intType)
            instructions.append(.constValue(result: id, value: .intLiteral(value)))
            return id

        case .longLiteral(let value, _):
            let longType = sema.types.make(.primitive(.long, .nonNull))
            let id = arena.appendExpr(.longLiteral(value), type: boundType ?? longType)
            instructions.append(.constValue(result: id, value: .longLiteral(value)))
            return id

        case .floatLiteral(let value, _):
            let floatType = sema.types.make(.primitive(.float, .nonNull))
            let id = arena.appendExpr(.floatLiteral(value), type: boundType ?? floatType)
            instructions.append(.constValue(result: id, value: .floatLiteral(value)))
            return id

        case .doubleLiteral(let value, _):
            let doubleType = sema.types.make(.primitive(.double, .nonNull))
            let id = arena.appendExpr(.doubleLiteral(value), type: boundType ?? doubleType)
            instructions.append(.constValue(result: id, value: .doubleLiteral(value)))
            return id

        case .charLiteral(let value, _):
            let charType = sema.types.make(.primitive(.char, .nonNull))
            let id = arena.appendExpr(.charLiteral(value), type: boundType ?? charType)
            instructions.append(.constValue(result: id, value: .charLiteral(value)))
            return id

        case .boolLiteral(let value, _):
            let id = arena.appendExpr(.boolLiteral(value), type: boundType ?? boolType)
            instructions.append(.constValue(result: id, value: .boolLiteral(value)))
            return id

        case .stringLiteral(let value, _):
            let id = arena.appendExpr(.stringLiteral(value), type: boundType ?? stringType)
            instructions.append(.constValue(result: id, value: .stringLiteral(value)))
            return id

        case .stringTemplate(let parts, _):
            var partIDs: [KIRExprID] = []
            for part in parts {
                switch part {
                case .literal(let interned):
                    let partID = arena.appendExpr(.stringLiteral(interned), type: stringType)
                    instructions.append(.constValue(result: partID, value: .stringLiteral(interned)))
                    partIDs.append(partID)
                case .expression(let exprID):
                    let lowered = lowerExpr(
                        exprID,
                        ast: ast,
                        sema: sema,
                        arena: arena,
                        interner: interner,
                        propertyConstantInitializers: propertyConstantInitializers,
                        instructions: &instructions
                    )
                    let exprType = sema.bindings.exprTypes[exprID]
                    if let exprType, exprType != stringType {
                        let tag: Int64
                        switch sema.types.kind(of: exprType) {
                        case .primitive(.boolean, _):
                            tag = 2
                        case .primitive(.string, _):
                            tag = 3
                        default:
                            tag = 1
                        }
                        let tagID = arena.appendExpr(.intLiteral(tag), type: intType)
                        instructions.append(.constValue(result: tagID, value: .intLiteral(tag)))
                        let converted = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: stringType)
                        instructions.append(.call(
                            symbol: nil,
                            callee: interner.intern("kk_any_to_string"),
                            arguments: [lowered, tagID],
                            result: converted,
                            canThrow: false,
                            thrownResult: nil
                        ))
                        partIDs.append(converted)
                    } else {
                        partIDs.append(lowered)
                    }
                }
            }
            if partIDs.isEmpty {
                let emptyStr = interner.intern("")
                let id = arena.appendExpr(.stringLiteral(emptyStr), type: stringType)
                instructions.append(.constValue(result: id, value: .stringLiteral(emptyStr)))
                return id
            }
            var accumulated = partIDs[0]
            for i in 1..<partIDs.count {
                let concatResult = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: stringType)
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_string_concat"),
                    arguments: [accumulated, partIDs[i]],
                    result: concatResult,
                    canThrow: false,
                    thrownResult: nil
                ))
                accumulated = concatResult
            }
            return accumulated

        case .nameRef(let name, _):
            if interner.resolve(name) == "null" {
                let id = arena.appendExpr(.null, type: boundType ?? sema.types.nullableAnyType)
                instructions.append(.constValue(result: id, value: .null))
                return id
            }
            if interner.resolve(name) == "this",
               let currentImplicitReceiverExprID {
                return currentImplicitReceiverExprID
            }
            if let symbol = sema.bindings.identifierSymbols[exprID] {
                if let localValue = localValuesBySymbol[symbol] {
                    return localValue
                }
                if let constant = propertyConstantInitializers[symbol] {
                    let id = arena.appendExpr(constant, type: boundType)
                    instructions.append(.constValue(result: id, value: constant))
                    return id
                }
                let id = arena.appendExpr(.symbolRef(symbol), type: boundType)
                instructions.append(.constValue(result: id, value: .symbolRef(symbol)))
                return id
            }
            let id = arena.appendExpr(.unit, type: boundType ?? sema.types.errorType)
            instructions.append(.constValue(result: id, value: .unit))
            return id

        case .forExpr(_, let iterableExpr, let bodyExpr, _):
            return lowerForExpr(exprID, iterableExpr: iterableExpr, bodyExpr: bodyExpr, ast: ast, sema: sema, arena: arena, interner: interner, propertyConstantInitializers: propertyConstantInitializers, instructions: &instructions)

        case .whileExpr(let conditionExpr, let bodyExpr, _):
            return lowerWhileExpr(exprID, conditionExpr: conditionExpr, bodyExpr: bodyExpr, ast: ast, sema: sema, arena: arena, interner: interner, propertyConstantInitializers: propertyConstantInitializers, instructions: &instructions)

        case .doWhileExpr(let bodyExpr, let conditionExpr, _):
            return lowerDoWhileExpr(exprID, bodyExpr: bodyExpr, conditionExpr: conditionExpr, ast: ast, sema: sema, arena: arena, interner: interner, propertyConstantInitializers: propertyConstantInitializers, instructions: &instructions)

        case .breakExpr:
            if let breakLabel = loopControlStack.last?.breakLabel {
                instructions.append(.jump(breakLabel))
            }
            let unit = arena.appendExpr(.unit, type: sema.types.unitType)
            instructions.append(.constValue(result: unit, value: .unit))
            return unit

        case .continueExpr:
            if let continueLabel = loopControlStack.last?.continueLabel {
                instructions.append(.jump(continueLabel))
            }
            let unit = arena.appendExpr(.unit, type: sema.types.unitType)
            instructions.append(.constValue(result: unit, value: .unit))
            return unit

        case .localFunDecl(_, _, _, _, _):
            if let symbol = sema.bindings.identifierSymbols[exprID] {
                let funType: TypeID
                if let sig = sema.symbols.functionSignature(for: symbol) {
                    funType = sema.types.make(.functionType(FunctionType(
                        params: sig.parameterTypes,
                        returnType: sig.returnType,
                        isSuspend: sig.isSuspend,
                        nullability: .nonNull
                    )))
                } else {
                    funType = boundType ?? sema.types.anyType
                }
                let funRef = arena.appendExpr(.symbolRef(symbol), type: funType)
                instructions.append(.constValue(result: funRef, value: .symbolRef(symbol)))
                localValuesBySymbol[symbol] = funRef
                registerCallableValue(
                    funRef,
                    symbol: symbol,
                    callee: callableTargetName(for: symbol, sema: sema, interner: interner),
                    captureArguments: []
                )
            }
            let unit = arena.appendExpr(.unit, type: sema.types.unitType)
            instructions.append(.constValue(result: unit, value: .unit))
            return unit

        case .localDecl(_, _, _, let initializer, _):
            if let initializer {
                let initializerID = lowerExpr(
                    initializer,
                    ast: ast,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    propertyConstantInitializers: propertyConstantInitializers,
                    instructions: &instructions
                )
                if let symbol = sema.bindings.identifierSymbols[exprID] {
                    localValuesBySymbol[symbol] = initializerID
                }
            }
            let unit = arena.appendExpr(.unit, type: sema.types.unitType)
            instructions.append(.constValue(result: unit, value: .unit))
            return unit

        case .localAssign(_, let valueExpr, _):
            let valueID = lowerExpr(
                valueExpr,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            if let symbol = sema.bindings.identifierSymbols[exprID] {
                localValuesBySymbol[symbol] = valueID
            }
            let unit = arena.appendExpr(.unit, type: sema.types.unitType)
            instructions.append(.constValue(result: unit, value: .unit))
            return unit

        case .arrayAccess(let arrayExpr, let indexExpr, _):
            return lowerArrayAccessExpr(exprID, arrayExpr: arrayExpr, indexExpr: indexExpr, ast: ast, sema: sema, arena: arena, interner: interner, propertyConstantInitializers: propertyConstantInitializers, instructions: &instructions)

        case .arrayAssign(let arrayExpr, let indexExpr, let valueExpr, _):
            return lowerArrayAssignExpr(exprID, arrayExpr: arrayExpr, indexExpr: indexExpr, valueExpr: valueExpr, ast: ast, sema: sema, arena: arena, interner: interner, propertyConstantInitializers: propertyConstantInitializers, instructions: &instructions)

        case .returnExpr(let value, _):
            if let value {
                let lowered = lowerExpr(
                    value,
                    ast: ast,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    propertyConstantInitializers: propertyConstantInitializers,
                    instructions: &instructions
                )
                instructions.append(.returnValue(lowered))
            } else {
                instructions.append(.returnUnit)
            }
            let unit = arena.appendExpr(.unit, type: sema.types.nothingType)
            instructions.append(.constValue(result: unit, value: .unit))
            return unit

        case .ifExpr(let condition, let thenExpr, let elseExpr, _):
            return lowerIfExpr(exprID, condition: condition, thenExpr: thenExpr, elseExpr: elseExpr, ast: ast, sema: sema, arena: arena, interner: interner, propertyConstantInitializers: propertyConstantInitializers, instructions: &instructions)

        case .tryExpr(let bodyExpr, let catchClauses, let finallyExpr, _):
            return lowerTryExpr(exprID, bodyExpr: bodyExpr, catchClauses: catchClauses, finallyExpr: finallyExpr, ast: ast, sema: sema, arena: arena, interner: interner, propertyConstantInitializers: propertyConstantInitializers, instructions: &instructions)

        case .binary(let op, let lhs, let rhs, _):
            return lowerBinaryExpr(exprID, op: op, lhs: lhs, rhs: rhs, ast: ast, sema: sema, arena: arena, interner: interner, propertyConstantInitializers: propertyConstantInitializers, instructions: &instructions)

        case .call(let calleeExpr, _, let args, _):
            return lowerCallExpr(exprID, calleeExpr: calleeExpr, args: args, ast: ast, sema: sema, arena: arena, interner: interner, propertyConstantInitializers: propertyConstantInitializers, instructions: &instructions)

        case .memberCall(let receiverExpr, let calleeName, _, let args, _):
            return lowerMemberCallExpr(exprID, receiverExpr: receiverExpr, calleeName: calleeName, args: args, ast: ast, sema: sema, arena: arena, interner: interner, propertyConstantInitializers: propertyConstantInitializers, instructions: &instructions)

        case .unaryExpr(let op, let operandExpr, _):
            let operandID = lowerExpr(
                operandExpr,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            switch op {
            case .unaryPlus:
                return operandID
            case .unaryMinus:
                let zero = arena.appendExpr(.intLiteral(0), type: intType)
                instructions.append(.constValue(result: zero, value: .intLiteral(0)))
                let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: boundType ?? intType)
                instructions.append(.binary(op: .subtract, lhs: zero, rhs: operandID, result: result))
                return result
            case .not:
                let falseValue = arena.appendExpr(.boolLiteral(false), type: boolType)
                instructions.append(.constValue(result: falseValue, value: .boolLiteral(false)))
                let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: boundType ?? boolType)
                instructions.append(.binary(op: .equal, lhs: operandID, rhs: falseValue, result: result))
                return result
            }

        case .isCheck(let exprToCheck, _, _, _):
            let operandID = lowerExpr(
                exprToCheck,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: boundType ?? boolType)
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_op_is"),
                arguments: [operandID],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result

        case .asCast(let exprToCast, _, _, _):
            let operandID = lowerExpr(
                exprToCast,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: boundType ?? sema.types.anyType)
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_op_cast"),
                arguments: [operandID],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result

        case .nullAssert(let innerExpr, _):
            let operandID = lowerExpr(
                innerExpr,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: boundType ?? sema.types.anyType)
            instructions.append(.nullAssert(operand: operandID, result: result))
            return result

        case .safeMemberCall(let receiverExpr, let calleeName, _, let args, _):
            return lowerSafeMemberCallExpr(exprID, receiverExpr: receiverExpr, calleeName: calleeName, args: args, ast: ast, sema: sema, arena: arena, interner: interner, propertyConstantInitializers: propertyConstantInitializers, instructions: &instructions)

        case .compoundAssign(_, _, let valueExpr, _):
            let valueID = lowerExpr(
                valueExpr,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            if let symbol = sema.bindings.identifierSymbols[exprID] {
                localValuesBySymbol[symbol] = valueID
            }
            let unit = arena.appendExpr(.unit, type: sema.types.unitType)
            instructions.append(.constValue(result: unit, value: .unit))
            return unit

        case .throwExpr(let valueExpr, _):
            let thrownValue = lowerExpr(
                valueExpr,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            instructions.append(.rethrow(value: thrownValue))
            let unit = arena.appendExpr(.unit, type: sema.types.nothingType)
            instructions.append(.constValue(result: unit, value: .unit))
            return unit

        case .lambdaLiteral(let params, let bodyExpr, _):
            return lowerLambdaLiteralExpr(
                exprID,
                params: params,
                bodyExpr: bodyExpr,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )

        case .callableRef(let receiverExpr, let memberName, _):
            return lowerCallableRefExpr(
                exprID,
                receiverExpr: receiverExpr,
                memberName: memberName,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )

        case .objectLiteral(let superTypes, _):
            return lowerObjectLiteralExpr(
                exprID,
                superTypes: superTypes,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )

        case .whenExpr(let subject, let branches, let elseExpr, _):
            return lowerWhenExpr(exprID, subject: subject, branches: branches, elseExpr: elseExpr, ast: ast, sema: sema, arena: arena, interner: interner, propertyConstantInitializers: propertyConstantInitializers, instructions: &instructions)

        case .blockExpr(let statements, let trailingExpr, _):
            for stmt in statements {
                let loweredStmt = lowerExpr(
                    stmt,
                    ast: ast,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    propertyConstantInitializers: propertyConstantInitializers,
                    instructions: &instructions
                )
                // If the statement is a terminator (return/throw), stop lowering
                if isTerminatedExpr(loweredStmt, arena: arena, sema: sema) {
                    return loweredStmt
                }
            }
            if let trailingExpr {
                return lowerExpr(
                    trailingExpr,
                    ast: ast,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    propertyConstantInitializers: propertyConstantInitializers,
                    instructions: &instructions
                )
            }
            let unit = arena.appendExpr(.unit, type: sema.types.unitType)
            instructions.append(.constValue(result: unit, value: .unit))
            return unit

        case .superRef:
            if let currentImplicitReceiverExprID {
                return currentImplicitReceiverExprID
            }
            let unit = arena.appendExpr(.unit, type: boundType ?? sema.types.errorType)
            instructions.append(.constValue(result: unit, value: .unit))
            return unit

        case .thisRef:
            if let currentImplicitReceiverExprID {
                return currentImplicitReceiverExprID
            }
            let unit = arena.appendExpr(.unit, type: boundType ?? sema.types.errorType)
            instructions.append(.constValue(result: unit, value: .unit))
            return unit

        case .inExpr(let lhsExpr, let rhsExpr, _):
            let lhsID = lowerExpr(
                lhsExpr, ast: ast, sema: sema, arena: arena, interner: interner,
                propertyConstantInitializers: propertyConstantInitializers, instructions: &instructions
            )
            let rhsID = lowerExpr(
                rhsExpr, ast: ast, sema: sema, arena: arena, interner: interner,
                propertyConstantInitializers: propertyConstantInitializers, instructions: &instructions
            )
            let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: boundType ?? boolType)
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_op_contains"),
                arguments: [rhsID, lhsID],
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result

        case .notInExpr(let lhsExpr, let rhsExpr, _):
            let lhsID = lowerExpr(
                lhsExpr, ast: ast, sema: sema, arena: arena, interner: interner,
                propertyConstantInitializers: propertyConstantInitializers, instructions: &instructions
            )
            let rhsID = lowerExpr(
                rhsExpr, ast: ast, sema: sema, arena: arena, interner: interner,
                propertyConstantInitializers: propertyConstantInitializers, instructions: &instructions
            )
            let containsResult = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: boolType)
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_op_contains"),
                arguments: [rhsID, lhsID],
                result: containsResult,
                canThrow: false,
                thrownResult: nil
            ))
            let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: boundType ?? boolType)
            instructions.append(.unary(op: .not, operand: containsResult, result: result))
            return result
        }
    }
}
